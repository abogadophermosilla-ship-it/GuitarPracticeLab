import SwiftUI
import SwiftData
import AppKit

@main
struct GuitarPracticeLabApp: App {
    /// `nil` cuando el store no pudo abrirse. En ese caso la app no muere: muestra
    /// `DatabaseRecoveryView`, que es el único lugar desde donde tiene sentido restaurar un respaldo
    /// (nadie está usando el store todavía).
    private let container: ModelContainer?
    private let startupError: Error?
    private let isRunningTests: Bool
    @State private var navigator = AppNavigator()
    @State private var didRunPostLaunchMaintenance = false

    init() {
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.isRunningTests = isRunningTests
        // Antes de abrir nada: si toca respaldo semanal, que sea del estado previo a cualquier
        // migración que este arranque pueda disparar.
        if !isRunningTests {
            DataBackupService.backupIfDue(storeURL: DataBackupService.defaultStoreURL)
            DifficultyScaleMigration.migrateCachedAssessmentSummary()
        }

        let schema = Schema(versionedSchema: SchemaV7.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isRunningTests)

        var openedContainer: ModelContainer?
        var failure: Error?
        do {
            openedContainer = try ModelContainer(
                for: schema,
                migrationPlan: AppMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            // Red de seguridad para el estreno del esquema versionado: un store creado antes de que
            // existiera `SchemaV1` no tiene versión grabada, y si esa combinación llegara a
            // rechazarse, abrirlo sin plan de migración sigue siendo correcto — los modelos son los
            // mismos. Solo si esto también falla el store está realmente dañado.
            failure = error
            openedContainer = try? ModelContainer(for: schema, configurations: [configuration])
            if openedContainer != nil { failure = nil }
        }

        container = openedContainer
        startupError = failure

        if let openedContainer, !isRunningTests {
            SeedService.seedIfNeeded(in: openedContainer.mainContext)
        }
    }

    var body: some Scene {
        WindowGroup {
            if isRunningTests {
                // El test host solo necesita cargar el módulo. No monta `ContentView`, evitando
                // métricas, recordatorios y demás efectos de navegación de la app real.
                EmptyView()
            } else if let container {
                    ContentView()
                        .frame(minWidth: 820, minHeight: 560)
                        .environment(navigator)
                        .modelContainer(container)
                        .task {
                            guard !didRunPostLaunchMaintenance else { return }
                            didRunPostLaunchMaintenance = true
                            await Task.yield()
                            runPostLaunchMaintenance(in: container)
                        }
            } else {
                DatabaseRecoveryView(errorDescription: startupError?.localizedDescription ?? "")
                    .frame(minWidth: 640, minHeight: 480)
            }
        }
        .defaultSize(width: 1120, height: 760)
        .commands { appCommands }
    }

    /// Deja que la ventana aparezca antes de sincronizar catálogos, recalcular evidencias y renovar
    /// el coach. Son tareas idempotentes, pero pueden recorrer miles de registros en una instalación
    /// nueva y no deben retrasar el primer frame de la app.
    @MainActor
    private func runPostLaunchMaintenance(in container: ModelContainer) {
        LibraryIntegrationService.integrateIfAvailable(in: container.mainContext)
        SkillEvidenceBackfillService.runIfNeeded(in: container.mainContext)
        SkillEvidenceService.refreshAllStatuses(in: container.mainContext)
        _ = try? PracticeCoachCoordinator.reevaluate(trigger: .appLaunch, in: container.mainContext)
    }

    /// Reemplaza el "Nueva ventana" que `WindowGroup` pone en ⌘N por las acciones que se usan
    /// todos los días. La app es de una sola ventana, así que ese comando por defecto no aportaba
    /// nada y se quedaba con el mejor atajo del menú.
    @CommandsBuilder
    private var appCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Registrar sesión") { navigator.request(.newSession) }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(container == nil)
            Button("Iniciar práctica") { navigator.request(.startPractice) }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(container == nil)
            Divider()
            Button("Buscar en todo") { navigator.selection = .search }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(container == nil)
        }
        CommandGroup(after: .saveItem) {
            Button("Crear respaldo ahora") { makeManualBackup() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(container == nil)
            Button("Configuración de respaldos…") { navigator.selection = .settings }
                .disabled(container == nil)
        }
    }

    private func makeManualBackup() {
        guard let container, let storeURL = DataBackupService.storeURL(for: container) else { return }
        do {
            try container.mainContext.save()
            try DataBackupService.makeBackup(of: storeURL)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "No se pudo crear el respaldo"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
