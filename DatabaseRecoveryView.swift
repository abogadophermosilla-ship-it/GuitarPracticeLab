import SwiftUI
import AppKit

/// Pantalla que reemplaza a la app cuando el store de SwiftData no pudo abrirse.
///
/// Antes esto era un `fatalError`: la app se cerraba sola y no había forma de recuperar los datos
/// sin herramientas externas. Acá el usuario ve qué pasó, puede restaurar cualquiera de los
/// respaldos y reiniciar. El store dañado nunca se borra — `DataBackupService.restore` lo deja al
/// lado con sufijo `.danado-<fecha>` por si hay algo rescatable con herramientas de SQLite.
struct DatabaseRecoveryView: View {
    let errorDescription: String

    @State private var backups = DataBackupService.list()
    @State private var message = ""
    @State private var didRestore = false
    @State private var pendingRestore: DataBackupService.Entry?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("No se pudo abrir tu base de datos", systemImage: "exclamationmark.triangle.fill")
                .font(.title2.bold())
                .foregroundStyle(.orange)

            Text("Tus datos siguen en el disco. La app no los borró ni los va a borrar. Puedes restaurar un respaldo y reiniciar, o abrir la carpeta y revisarla a mano.")
                .foregroundStyle(.secondary)

            if !errorDescription.isEmpty {
                GroupBox("Detalle técnico") {
                    Text(errorDescription)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if didRestore {
                restoredState
            } else {
                backupList
            }

            if !message.isEmpty {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(didRestore ? .green : .red)
            }

            Spacer()

            HStack {
                Button("Abrir la carpeta de respaldos", systemImage: "folder") {
                    DataBackupService.revealInFinder(DataBackupService.backupsDirectory)
                }
                Button("Abrir la carpeta de la base", systemImage: "internaldrive") {
                    DataBackupService.revealInFinder(DataBackupService.defaultStoreURL)
                }
                Spacer()
                Button("Salir") { NSApp.terminate(nil) }
            }
        }
        .padding(24)
        .confirmationDialog(
            "¿Restaurar este respaldo?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible
        ) {
            Button("Restaurar y reiniciar", role: .destructive) {
                if let pendingRestore { restore(pendingRestore) }
            }
            Button("Cancelar", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("La base actual se conserva al lado con sufijo \".danado\" por si hay algo rescatable. La app se va a reiniciar.")
        }
    }

    @ViewBuilder
    private var backupList: some View {
        if backups.isEmpty {
            GroupBox {
                Text("No hay respaldos guardados todavía. Si es la primera vez que abres la app, esto es normal: puedes seguir sin restaurar nada, pero primero cierra la app y mueve a otra carpeta el archivo de la base para que se cree una nueva y vacía.")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Respaldos disponibles")
                    .font(.headline)
                ForEach(backups) { backup in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(backup.displayName)
                            Text(backup.displaySize)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restaurar") { pendingRestore = backup }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var restoredState: some View {
        GroupBox {
            Text("Respaldo restaurado. La app se está reiniciando; si no vuelve sola, ábrela de nuevo desde el Dock.")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func restore(_ entry: DataBackupService.Entry) {
        pendingRestore = nil
        do {
            try DataBackupService.restore(entry, toStoreAt: DataBackupService.defaultStoreURL)
            didRestore = true
            message = "Se restauró el respaldo del \(entry.displayName)."
            relaunch()
        } catch {
            didRestore = false
            message = "No se pudo restaurar: \(error.localizedDescription)"
        }
    }

    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
