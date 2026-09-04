import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BacklogIdea.createdAt, order: .reverse) private var ideas: [BacklogIdea]
    @State private var newIdeaText = ""
    @AppStorage("weeklyGoalMinutes") private var weeklyGoal = 240
    @AppStorage("dailyPracticeGoalMinutes") private var dailyGoal = 45
    @AppStorage("practiceBreakRemindersEnabled") private var breakRemindersEnabled = true
    @AppStorage("geminiModel") private var geminiModel = AIOrchestrator.defaultPaidAPIModel
    @AppStorage(GeminiUsageLedger.budgetDefaultsKey) private var geminiMonthlyBudget = 0.0
    @AppStorage("musicalTastes") private var musicalTastes = ""
    @AppStorage("localGatewayHost") private var gatewayHost = LocalGatewayService.defaultHost
    @AppStorage("whisperModel") private var whisperModel = "mlx-community/whisper-large-v3-turbo"
    @AppStorage("allowHeavyAIWithLogic") private var allowHeavyAIWithLogic = false
    @AppStorage(LearningMaterialsService.rootPathKey)
    private var materialsRoot = LearningMaterialsService.defaultRootPath
    @State private var apiKey = ""
    @State private var savedMessage = ""
    @State private var geminiUsage = GeminiMonthlyUsageSnapshot.empty
    @State private var isTestingGemini = false
    @State private var geminiStatus = ""
    @State private var geminiTestFailed = false
    /// Fuerza recalcular el conteo de secciones tras reiniciarlo (vive en `UserDefaults`, que no es
    /// observable por sí solo).
    @State private var usageVersion = 0
    @State private var isTestingGateway = false
    @State private var gatewayStatus = ""
    @State private var gatewayIsReachable = false
    @State private var youtubeAPIKey = ""
    @State private var youtubeKeyMessage = ""
    @State private var keychainImportMessage = ""
    @State private var showingMaterialsPicker = false
    @State private var materialsMessage = ""
    @State private var showingExportPicker = false
    @State private var backups: [DataBackupService.Entry] = []
    @State private var backupMessage = ""
    @State private var backupFailed = false
    @State private var exportMessage = ""
    @State private var exportFailed = false
    @State private var exportedFolder: URL?
    @AppStorage(PracticeReminderService.enabledKey) private var remindersEnabled = false
    @Query(sort: \PracticeSession.date, order: .reverse) private var sessions: [PracticeSession]
    @State private var reminderSchedule: ReminderSchedule?
    @State private var reminderMessage = ""
    @StateObject private var enrichmentOrchestrator = AIOrchestrator()
    private let enrichment = LibraryCatalogEnrichmentService.shared

    var body: some View {
        Form {
            Section("Ideas / Backlog") {
                HStack {
                    TextField("Idea para una futura versión", text: $newIdeaText, axis: .vertical)
                        .lineLimit(1...3)
                    Button("Agregar") { addIdea() }
                        .disabled(newIdeaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if ideas.isEmpty {
                    Text("Anota aquí cosas que todavía no están en la app — manejo de software/amplificadores, trabajo rítmico de groove, etc. — para no perderlas entre sesiones.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(ideas) { idea in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(idea.text)
                                Text(idea.createdAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Eliminar", systemImage: "trash", role: .destructive) {
                                modelContext.delete(idea)
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                }
            }

            Section("Práctica") {
                Stepper("Objetivo semanal: \(weeklyGoal) minutos", value: $weeklyGoal, in: 30...2000, step: 30)
                Stepper("Presupuesto diario: \(dailyGoal) minutos", value: $dailyGoal, in: 15...180, step: 5)
                Text("El plan de Hoy reprograma el excedente en días futuros; el calentamiento cromático conserva siempre sus \(DailyPracticeRoutine.chromaticMinutes) minutos.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Sugerir una pausa cada 25 minutos", isOn: $breakRemindersEnabled)
                Text("Las pausas no descuentan tiempo practicado y ayudan a evitar que la fatiga convierta repeticiones tensas en hábito.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Recordarme practicar", isOn: $remindersEnabled)
                Text(reminderStatusLine)
                    .font(.caption)
                    .foregroundStyle(reminderMessage.isEmpty ? Color.secondary : Color.orange)
            }

            Section("Materiales de aprendizaje") {
                TextField("Carpeta raíz externa", text: $materialsRoot)
                HStack {
                    Button("Elegir carpeta", systemImage: "folder.badge.plus") {
                        showingMaterialsPicker = true
                    }
                    Button("Abrir en Finder", systemImage: "folder") {
                        LearningMaterialsService.open(LearningMaterialsService.rootURL)
                    }
                    .disabled(!LearningMaterialsService.isAvailable)
                    Button("Usar VST/Clases") {
                        LearningMaterialsService.useDefaultRoot()
                        materialsRoot = LearningMaterialsService.defaultRootPath
                        materialsMessage = "Se restauró la ubicación predeterminada."
                    }
                }
                Label(
                    LearningMaterialsService.isAvailable
                        ? "Conectado · Biblioteca usa \(LearningMaterialsService.booksURL.path)"
                        : "Disco o carpeta no disponible. La app conserva los datos ya importados.",
                    systemImage: LearningMaterialsService.isAvailable
                        ? "externaldrive.fill.badge.checkmark"
                        : "externaldrive.badge.xmark"
                )
                .font(.caption)
                .foregroundStyle(LearningMaterialsService.isAvailable ? .green : .orange)
                if !materialsMessage.isEmpty {
                    Text(materialsMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Materiales, Biblioteca y el buscador global comparten esta única raíz. Los archivos permanecen en el disco externo; la app no los copia.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Asistente local") {
                TextField("Dirección de Ollama", text: $gatewayHost)
                HStack {
                    Button("Probar conexión") { Task { await testGatewayConnection() } }
                        .disabled(isTestingGateway)
                    if isTestingGateway { ProgressView().controlSize(.small) }
                    Spacer()
                }
                if !gatewayStatus.isEmpty {
                    Text(gatewayStatus)
                        .font(.caption)
                        .foregroundStyle(gatewayIsReachable ? .green : .red)
                }
                Text(resourceStatusLine)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("Gemini pagado es el proveedor principal de las funciones generativas. Si una llamada falla, la app elige automáticamente el mejor modelo de este gateway que pueda ejecutarse sin poner en riesgo Logic Pro. Los motores de audio también continúan funcionando localmente.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Enriquecer catálogo de Biblioteca") {
                if enrichment.totalCount > 0 {
                    ProgressView(value: Double(enrichment.processedCount), total: Double(enrichment.totalCount))
                    Text("\(enrichment.processedCount) de \(enrichment.totalCount) ítems procesados")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button(enrichment.isActive ? "Pausar" : "Enriquecer con IA local") {
                        if enrichment.isActive {
                            enrichment.stop()
                        } else {
                            enrichment.start(modelContext: modelContext, orchestrator: enrichmentOrchestrator)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(enrichment.state == .finished)
                    if case .running = enrichment.state, !enrichment.currentLabel.isEmpty {
                        ProgressView().controlSize(.small)
                        Text(enrichment.currentLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                switch enrichment.state {
                case .paused(let reason):
                    Text(reason).font(.caption).foregroundStyle(.orange)
                case .finished:
                    Text("Catálogo enriquecido por completo.").font(.caption).foregroundStyle(.green)
                case .idle, .running:
                    EmptyView()
                }
                Text("Recorre los ejercicios y conceptos de Biblioteca con el modelo local \(LocalModelTier.qwen38_27b.displayName) y suma vínculos de habilidad al matching por texto actual — nunca usa Gemini. Es un proceso largo (puede tardar horas); se puede pausar en cualquier momento y retoma donde quedó, incluso si cierras y vuelves a abrir Configuración.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onAppear { enrichment.refreshCounts(modelContext: modelContext) }

            HermesSettingsSection()

            Section("Motores de audio local") {
                ForEach(LocalAudioIntelligenceService.statuses) { status in
                    HStack {
                        Label(status.tool.rawValue, systemImage: status.isAvailable
                              ? "checkmark.circle.fill"
                              : "xmark.circle")
                            .foregroundStyle(status.isAvailable ? .green : .secondary)
                        Spacer()
                        Text(status.isAvailable ? "Disponible" : "No instalado")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                TextField("Modelo de transcripción", text: $whisperModel)
                Toggle("Permitir procesamiento local mientras Logic Pro está abierto", isOn: $allowHeavyAIWithLogic)
                Text("MLX Whisper transcribe; Basic Pitch detecta notas y crea MIDI; Demucs separa stems. Los procesos corren con prioridad baja y se detienen si el Mac está caliente o muy cargado. Essentia es opcional; sin él el análisis conserva duración, notas, ataques y pitch bends.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(LocalAudioIntelligenceService.environmentRoot.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }

            Section("Búsqueda de videos") {
                SecureField("Clave de YouTube Data API", text: $youtubeAPIKey)
                HStack {
                    Button("Guardar clave en Llavero") { saveYouTubeKey() }
                        .buttonStyle(.borderedProminent)
                    Button("Eliminar del campo") { youtubeAPIKey = "" }
                    Spacer()
                    Text(youtubeKeyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Profesor IA usa la API oficial para obtener videos y enlaces reales. La IA solo diseña la consulta y el criterio de aprendizaje.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Gustos musicales") {
                TextField("Artistas, géneros o canciones que te gustan", text: $musicalTastes, axis: .vertical)
                    .lineLimit(2...4)
                Text("El asistente prioriza estos gustos al sugerirte repertorio nuevo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Llavero") {
                Text("Las claves API se guardan en el llavero del sistema y ya no piden contraseña al abrir esta pantalla.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Importar claves de versiones anteriores") { importLegacyKeys() }
                    Spacer()
                    Text(keychainImportMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Úsalo una sola vez si los campos de abajo aparecen vacíos pero antes tenías claves guardadas. macOS pedirá la contraseña del llavero una vez por clave; si no la acepta, simplemente pega las claves de nuevo en los campos y guárdalas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Asistente de práctica (Gemini)") {
                SecureField("Clave API de Gemini", text: $apiKey)
                if !apiKey.isEmpty {
                    Text("\(apiKey.count) caracteres · empieza con \"\(apiKey.prefix(7))\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Guardar en Llavero") { saveKey() }
                        .buttonStyle(.borderedProminent)
                    Button("Eliminar del campo") { apiKey = "" }
                    Spacer()
                    Text(savedMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TextField("Modelo", text: $geminiModel)
                HStack {
                    Button("Probar Gemini") { Task { await testGeminiConnection() } }
                        .disabled(isTestingGemini)
                    if isTestingGemini {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                }
                if !geminiStatus.isEmpty {
                    Text(geminiStatus)
                        .font(.caption)
                        .foregroundStyle(geminiTestFailed ? .red : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Proveedor principal de toda la IA generativa de la app, excepto Profesor IA Avanzado, que conserva Hermes. La clave debe pertenecer a un proyecto de Google AI Studio con facturación habilitada. Si Gemini falla, se intenta el gateway local configurado arriba.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Consumo de esta app · \(geminiUsage.month.isEmpty ? "mes actual" : geminiUsage.month)")
                            .font(.caption.bold())
                        if geminiUsage.requestCount == 0 {
                            Text("Aún no hay llamadas registradas con la versión nueva.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(geminiUsage.requestCount) llamadas · \(geminiUsage.inputTokens.formatted()) tokens de entrada · \(geminiUsage.billedOutputTokens.formatted()) de salida y razonamiento")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Estimado: US$ \(String(format: "%.4f", geminiUsage.estimatedUSD)) · ≈ $\(Int((geminiUsage.estimatedUSD * 950).rounded()).formatted()) CLP")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.green)
                        }
                    }
                    Spacer()
                    Button("Actualizar") { Task { await refreshGeminiUsage() } }
                        .font(.caption)
                }
                Text("Estimación local según los tokens informados por Gemini y sus tarifas estándar; usa $950 CLP/USD como referencia. La facturación de Google es la cifra definitiva.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Divider()
                geminiBudgetControls
            }

            Section("Uso de las secciones") {
                sectionUsageReport
            }

            Section("Respaldo y exportación") {
                HStack {
                    Button("Crear respaldo ahora", systemImage: "clock.arrow.circlepath") { makeBackup() }
                        .buttonStyle(.borderedProminent)
                    Button("Exportar a JSON y CSV…", systemImage: "square.and.arrow.up") {
                        showingExportPicker = true
                    }
                    Spacer()
                }
                if !backupMessage.isEmpty {
                    Text(backupMessage)
                        .font(.caption)
                        .foregroundStyle(backupFailed ? .red : .secondary)
                }
                if !exportMessage.isEmpty {
                    HStack(alignment: .top) {
                        Text(exportMessage)
                            .font(.caption)
                            .foregroundStyle(exportFailed ? .red : .secondary)
                        if let exportedFolder {
                            Button("Mostrar en Finder") { DataBackupService.revealInFinder(exportedFolder) }
                                .buttonStyle(.link)
                                .font(.caption)
                        }
                    }
                }

                Text("El respaldo copia la base completa —incluidos los textos de los PDFs y los recortes de Academia— y es lo que permite volver atrás si la base se daña. La exportación genera un JSON legible y un CSV de sesiones para abrir en una planilla; deja fuera esos archivos pesados a propósito.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(automaticBackupLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if backups.isEmpty {
                    Text("Todavía no hay respaldos guardados.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(backups) { backup in
                        HStack {
                            Label(backup.displayName, systemImage: "externaldrive.badge.timemachine")
                            Text(backup.displaySize)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Mostrar en Finder", systemImage: "folder") {
                                DataBackupService.revealInFinder(backup.url)
                            }
                            .labelStyle(.iconOnly)
                            Button("Eliminar", systemImage: "trash", role: .destructive) {
                                DataBackupService.delete(backup)
                                backups = DataBackupService.list()
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                    Text("Se conservan los \(DataBackupService.maxStoredBackups) más recientes. Para restaurar uno, la app tiene que estar cerrada: si la base no abre, al iniciar aparece la pantalla de recuperación con la lista de respaldos.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Datos") {
                Text("Las sesiones, clases, ejercicios, instrumentos y activos del estudio se almacenan localmente con SwiftData.")
                Text("Los registros de ejemplo se pueden eliminar desde cada lista.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Configuración")
        .padding(12)
        .onAppear {
            migrateGeminiDefaultIfNeeded()
            loadStoredKeys()
            Task { await refreshGeminiUsage() }
            keychainImportMessage = KeychainStore.accessError()?.localizedDescription ?? ""
            backups = DataBackupService.list()
            reminderSchedule = PracticeReminderPlanner.schedule(from: sessions.map(\.date))
        }
        .onChange(of: remindersEnabled) { _, newValue in
            Task { await updateReminders(enabled: newValue) }
        }
        .fileImporter(isPresented: $showingMaterialsPicker, allowedContentTypes: [.folder]) { result in
            configureMaterialsRoot(result)
        }
        .fileImporter(isPresented: $showingExportPicker, allowedContentTypes: [.folder]) { result in
            exportEverything(to: result)
        }
    }

    private var reminderStatusLine: String {
        if !reminderMessage.isEmpty { return reminderMessage }
        guard remindersEnabled else {
            return "La app deduce tu horario habitual del historial de sesiones y te avisa solo los días en que sueles practicar. No avisa si ya practicaste ese día."
        }
        guard let reminderSchedule else {
            return "Todavía no hay suficientes sesiones registradas para deducir tu horario (hacen falta al menos \(PracticeReminderPlanner.minimumSessions) en las últimas \(PracticeReminderPlanner.windowWeeks) semanas)."
        }
        let days = reminderSchedule.weekdayNames.joined(separator: ", ")
        return "Aviso los \(days) a las \(reminderSchedule.readableTime), según tu propio historial."
    }

    private func updateReminders(enabled: Bool) async {
        reminderMessage = ""
        guard enabled else {
            PracticeReminderService.cancelAll()
            reminderSchedule = nil
            return
        }
        guard await PracticeReminderService.requestAuthorization() else {
            remindersEnabled = false
            reminderMessage = "macOS no autorizó las notificaciones de esta app. Actívalas en Ajustes del Sistema → Notificaciones."
            return
        }
        reminderSchedule = await PracticeReminderService.refresh(sessionDates: sessions.map(\.date))
    }

    private var automaticBackupLine: String {
        guard let last = DataBackupService.lastAutomaticBackupDate else {
            return "El respaldo automático corre al abrir la app, como máximo una vez cada \(DataBackupService.automaticIntervalDays) días. Todavía no corrió ninguno."
        }
        return "Último respaldo automático: \(last.formatted(date: .abbreviated, time: .shortened)). Corre al abrir la app, como máximo una vez cada \(DataBackupService.automaticIntervalDays) días."
    }

    private func makeBackup() {
        guard let storeURL = DataBackupService.storeURL(for: modelContext.container) else {
            backupFailed = true
            backupMessage = "No se encontró el archivo de la base de datos."
            return
        }
        do {
            // Vacía primero los cambios del contexto principal. El servicio compara después el hash
            // de cada componente antes y después de copiarlo y rechazará la instantánea si SQLite
            // cambia en medio del proceso.
            try modelContext.save()
            let entry = try DataBackupService.makeBackup(of: storeURL)
            backupFailed = false
            backupMessage = "Respaldo creado (\(entry.displaySize))."
            backups = DataBackupService.list()
        } catch {
            backupFailed = true
            backupMessage = "No se pudo respaldar: \(error.localizedDescription)"
        }
    }

    private func exportEverything(to result: Result<URL, Error>) {
        guard case .success(let folder) = result else { return }
        let granted = folder.startAccessingSecurityScopedResource()
        defer { if granted { folder.stopAccessingSecurityScopedResource() } }
        do {
            let output = try DataExportService.export(from: modelContext, to: folder)
            exportFailed = false
            exportedFolder = output.jsonURL
            exportMessage = "Se exportaron \(output.totalRecords) registros (\(output.sessionCount) sesiones) a \(output.jsonURL.lastPathComponent) y \(output.csvURL.lastPathComponent)."
        } catch {
            exportFailed = true
            exportedFolder = nil
            exportMessage = "No se pudo exportar: \(error.localizedDescription)"
        }
    }

    private var resourceStatusLine: String {
        let snapshot = ResourceMonitor.snapshot()
        let freeGB = Double(snapshot.freeBytes) / 1_000_000_000
        let totalGB = Double(snapshot.totalBytes) / 1_000_000_000
        return "RAM libre: \(String(format: "%.0f", freeGB)) de \(String(format: "%.0f", totalGB)) GB · Carga: \(String(format: "%.1f", snapshot.loadAverage1m))"
    }

    private func testGatewayConnection() async {
        isTestingGateway = true
        defer { isTestingGateway = false }
        let trimmedHost = gatewayHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = await LocalGatewayService.reachabilityError(host: trimmedHost) {
            gatewayIsReachable = false
            gatewayStatus = error.localizedDescription
        } else {
            gatewayIsReachable = true
            gatewayStatus = "Conectado"
        }
    }

    private func testGeminiConnection() async {
        isTestingGemini = true
        geminiStatus = ""
        geminiTestFailed = false
        defer { isTestingGemini = false }

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = geminiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            geminiTestFailed = true
            geminiStatus = "Escribe o carga primero una clave."
            return
        }
        guard !model.isEmpty else {
            geminiTestFailed = true
            geminiStatus = "Escribe un modelo."
            return
        }

        do {
            let resolvedModel = try await GeminiService(apiKey: key, model: model).checkConnection()
            geminiStatus = "Conectado · \(resolvedModel)"
            await refreshGeminiUsage()
        } catch {
            geminiTestFailed = true
            geminiStatus = error.localizedDescription
        }
    }

    private func addIdea() {
        let trimmed = newIdeaText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        modelContext.insert(BacklogIdea(text: trimmed))
        newIdeaText = ""
    }

    private func saveYouTubeKey() {
        let trimmed = youtubeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try KeychainStore.save(trimmed, account: "youtube-data-api-key")
            youtubeAPIKey = trimmed
            youtubeKeyMessage = "Clave guardada"
        } catch {
            youtubeKeyMessage = "No se pudo guardar: \(error.localizedDescription)"
        }
    }

    private func saveKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try KeychainStore.save(trimmed, account: AIOrchestrator.paidAPIKeychainAccount)
            apiKey = trimmed
            savedMessage = "Clave guardada"
        } catch {
            savedMessage = "No se pudo guardar: \(error.localizedDescription)"
        }
    }

    private func importLegacyKeys() {
        let imported = KeychainStore.importLegacyItems()
        loadStoredKeys()
        if let error = KeychainStore.accessError() {
            keychainImportMessage = error.localizedDescription
            return
        }
        keychainImportMessage = imported.isEmpty
            ? "No se recuperó ninguna clave antigua"
            : "Se recuperaron \(imported.count) clave(s)"
    }

    private func loadStoredKeys() {
        apiKey = KeychainStore.read(account: AIOrchestrator.paidAPIKeychainAccount)
        youtubeAPIKey = KeychainStore.read(account: "youtube-data-api-key")
    }

    private func migrateGeminiDefaultIfNeeded() {
        geminiModel = AIOrchestrator.migratePaidAPIModelIfNeeded()
    }

    @MainActor
    private func refreshGeminiUsage() async {
        geminiUsage = await GeminiUsageLedger.shared.currentMonth()
    }

    /// Cuántas veces se abrió cada sección, de más a menos usada.
    ///
    /// Sirve para decidir con datos propios qué parte de la app merece trabajo y cuál sobra, en vez
    /// de suponerlo. Es conteo local: no sale del equipo y se puede reiniciar.
    @ViewBuilder
    private var sectionUsageReport: some View {
        let ranking = SectionUsageTracker.ranking(allSections: SidebarSection.allCases.map(\.rawValue))
        let total = SectionUsageTracker.totalOpens()

        if total == 0 {
            Text("Todavía no hay aperturas registradas. Navega por la app y vuelve acá en unas semanas.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(ranking, id: \.section) { entry in
                HStack {
                    Text(entry.section)
                        .font(.caption)
                        .foregroundStyle(entry.count == 0 ? .secondary : .primary)
                    Spacer()
                    Text("\(entry.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(entry.count == 0 ? .tertiary : .secondary)
                }
            }
            HStack {
                if let since = SectionUsageTracker.measuringSince() {
                    Text("\(total) aperturas desde el \(since.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Reiniciar conteo") {
                    SectionUsageTracker.reset()
                    usageVersion += 1
                }
                .font(.caption)
            }
        }
    }

    /// Tope mensual de gasto. Separado del `Section` porque el cuerpo completo excedía el tiempo de
    /// inferencia de tipos del compilador.
    @ViewBuilder
    private var geminiBudgetControls: some View {
        let spent = geminiUsage.estimatedUSD
        let budget = geminiMonthlyBudget
        let remaining = max(0, budget - spent)

        HStack {
            Text("Tope mensual (US$)")
            Spacer()
            TextField("0 = sin tope", value: $geminiMonthlyBudget, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
        }

        if budget > 0 {
            ProgressView(value: min(spent, budget), total: budget)
            if remaining > 0 {
                Text("Quedan US$ \(String(format: "%.2f", remaining)) del tope de este mes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Tope alcanzado: las funciones generativas están usando el gateway local.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }

        Text("Al alcanzar el tope, la app deja de llamar a la API pagada y sigue con el gateway local; si el gateway está apagado, la función avisa en vez de gastar. El tope usa la estimación de arriba, no la facturación real de Google.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private func configureMaterialsRoot(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        do {
            try LearningMaterialsService.configureRoot(url)
            materialsRoot = url.standardizedFileURL.path
            materialsMessage = "Ubicación guardada. La Biblioteca la usará en el próximo inicio."
        } catch {
            materialsMessage = "No se pudo guardar el acceso: \(error.localizedDescription)"
        }
    }
}
