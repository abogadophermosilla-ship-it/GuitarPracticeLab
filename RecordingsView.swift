import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RecordingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var roots: [RecordingsLibraryRoot]
    @Query(sort: \Recording.lastModifiedDate, order: .reverse) private var recordings: [Recording]

    @State private var showingFolderImporter = false
    @State private var isScanning = false
    @State private var scanMessage = ""
    @State private var scanError = ""
    @State private var selectedRecordingID: UUID?

    private var root: RecordingsLibraryRoot? { roots.first }

    private var groupedByCategory: [(category: String, items: [Recording])] {
        Dictionary(grouping: recordings) { $0.category }
            .map { (category: $0.key, items: $0.value.sorted { $0.lastModifiedDate > $1.lastModifiedDate }) }
            .sorted { $0.category.localizedCompare($1.category) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(24)

            if !scanError.isEmpty {
                Text(scanError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
            }
            if !scanMessage.isEmpty {
                Text(scanMessage)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 24)
            }

            if root == nil {
                EmptyStateView(
                    icon: "waveform",
                    title: "Sin carpeta configurada",
                    message: "Elige la carpeta raíz donde organizas tus grabaciones de Logic, con subcarpetas por tema o canción."
                )
            } else if recordings.isEmpty {
                EmptyStateView(icon: "waveform", title: "Sin grabaciones", message: "Rescaneá la carpeta para detectar tus archivos.")
            } else {
                List {
                    ForEach(groupedByCategory, id: \.category) { group in
                        Section(group.category) {
                            ForEach(group.items) { recording in
                                RecordingRow(recording: recording)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedRecordingID = recording.id }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .fileImporter(isPresented: $showingFolderImporter, allowedContentTypes: [.folder]) { result in
            handleFolderSelection(result)
        }
        .sheet(item: Binding(
            get: { recordings.first { $0.id == selectedRecordingID } },
            set: { selectedRecordingID = $0?.id }
        )) { recording in
            RecordingDetailView(recording: recording)
                .frame(minWidth: 560, idealWidth: 680, minHeight: 560)
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                recordingsTitle
                Spacer()
                recordingsActions
            }
            VStack(alignment: .leading, spacing: 10) {
                recordingsTitle
                recordingsActions
            }
        }
    }

    private var recordingsTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Grabaciones")
                .font(.largeTitle.bold())
            if let root {
                Text(statusLine(for: root))
                    .foregroundStyle(.secondary)
            } else {
                Text("Vincula la carpeta donde Logic guarda tus proyectos y exportaciones")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var recordingsActions: some View {
        HStack {
            if isScanning {
                ProgressView().controlSize(.small)
            } else if root != nil {
                Button("Rescanear", systemImage: "arrow.clockwise") { Task { await rescan() } }
                Button("Cambiar carpeta", systemImage: "folder") { showingFolderImporter = true }
            } else {
                if FileManager.default.fileExists(atPath: LearningMaterialsService.projectsURL.path) {
                    Button("Usar Proyectos", systemImage: "externaldrive.fill") {
                        useLearningProjectsFolder()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button("Elegir otra", systemImage: "folder.badge.plus") { showingFolderImporter = true }
            }
        }
    }

    private func statusLine(for root: RecordingsLibraryRoot) -> String {
        var line = "\(root.folderName) · \(recordings.count) archivos"
        if let lastScan = root.lastScanDate {
            line += " · último escaneo \(lastScan.formatted(date: .abbreviated, time: .shortened))"
        }
        return line
    }

    private func handleFolderSelection(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        scanError = ""
        scanMessage = ""
        do {
            let bookmark = try SecurityScopedFile.makeBookmark(for: url)
            let selectedRoot: RecordingsLibraryRoot
            if let existingRoot = root {
                existingRoot.bookmarkData = bookmark
                existingRoot.folderName = url.lastPathComponent
                existingRoot.lastScanDate = nil
                selectedRoot = existingRoot
            } else {
                let newRoot = RecordingsLibraryRoot(folderName: url.lastPathComponent, bookmarkData: bookmark)
                modelContext.insert(newRoot)
                selectedRoot = newRoot
            }
            Task { await rescan(using: selectedRoot) }
        } catch {
            scanError = "No se pudo vincular la carpeta: \(error.localizedDescription)"
        }
    }

    private func useLearningProjectsFolder() {
        let url = LearningMaterialsService.projectsURL
        do {
            let bookmark = try SecurityScopedFile.makeBookmark(for: url)
            let selectedRoot: RecordingsLibraryRoot
            if let existingRoot = root {
                existingRoot.bookmarkData = bookmark
                existingRoot.folderName = url.lastPathComponent
                existingRoot.lastScanDate = nil
                selectedRoot = existingRoot
            } else {
                let newRoot = RecordingsLibraryRoot(
                    folderName: url.lastPathComponent,
                    bookmarkData: bookmark
                )
                modelContext.insert(newRoot)
                selectedRoot = newRoot
            }
            Task { await rescan(using: selectedRoot) }
        } catch {
            scanError = "No se pudo vincular Proyectos: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func rescan(using explicitRoot: RecordingsLibraryRoot? = nil) async {
        guard let scanRoot = explicitRoot ?? root else { return }
        isScanning = true
        scanError = ""
        scanMessage = ""
        defer { isScanning = false }
        do {
            let summary = try RecordingScanService.scan(
                root: scanRoot,
                existingRecordings: recordings,
                modelContext: modelContext
            )
            scanMessage = "Agregadas: \(summary.added) · Con nueva modificación: \(summary.modified) · Revisadas: \(summary.scannedTotal)"
        } catch {
            scanError = error.localizedDescription
        }
    }
}

private struct RecordingRow: View {
    let recording: Recording

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .foregroundStyle(.teal)
                .frame(width: 34, height: 34)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(recording.fileName)
                    .font(.headline)
                Text("Modificado: \(recording.lastModifiedDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !recording.modificationLog.isEmpty {
                StatusPill(text: "\(recording.modificationLog.count) cambios", tint: .orange)
            }
            Button("Abrir", systemImage: "arrow.up.forward.square") {
                SecurityScopedFile.open(recording.bookmarkData)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
        .padding(.vertical, 6)
    }
}

private struct RecordingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AIArtifact.createdAt, order: .reverse) private var allArtifacts: [AIArtifact]
    @Query(sort: \SkillTopic.name) private var skills: [SkillTopic]
    @Query(sort: \Recording.lastModifiedDate, order: .reverse) private var allRecordings: [Recording]
    let recording: Recording
    @State private var targetBPM = 0
    @State private var evidenceSkillID: UUID?
    @State private var evidenceDimension = SkillEvidenceDimension.execution
    @State private var referenceRecordingID: UUID?
    @State private var runningAction = ""
    @State private var errorMessage = ""

    private var artifacts: [AIArtifact] {
        allArtifacts.filter { $0.sourceID == recording.id }
    }

    private var isAudio: Bool {
        LocalAudioIntelligenceService.supportedAudioExtensions.contains(
            URL(fileURLWithPath: recording.fileName).pathExtension.lowercased()
        )
    }

    private var referenceCandidates: [Recording] {
        allRecordings.filter {
            $0.id != recording.id && LocalAudioIntelligenceService.supportedAudioExtensions.contains(
                URL(fileURLWithPath: $0.fileName).pathExtension.lowercased()
            )
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Archivo") {
                    LabeledContent("Nombre", value: recording.fileName)
                    LabeledContent("Categoría", value: recording.category)
                    LabeledContent("Última modificación", value: recording.lastModifiedDate.formatted(date: .abbreviated, time: .shortened))
                }
                Section("Historial de modificaciones") {
                    if recording.modificationLog.isEmpty {
                        Text("Sin cambios detectados todavía.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recording.modificationLog.sorted { $0.detectedAt > $1.detectedAt }) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Detectado el \(entry.detectedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.subheadline.weight(.medium))
                                Text("Nueva fecha de modificación: \(entry.newModifiedDate.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if isAudio {
                    Section("Escuchar") {
                        RecordingPlayerView(bookmark: recording.bookmarkData)
                    }
                }
                Section("Inteligencia de audio local") {
                    if isAudio {
                        Stepper(
                            "Tempo objetivo: \(targetBPM == 0 ? "sin comparar" : "\(targetBPM) BPM")",
                            value: $targetBPM,
                            in: 0...300
                        )
                        Picker("Toma de referencia", selection: $referenceRecordingID) {
                            Text("Sin referencia").tag(nil as UUID?)
                            ForEach(referenceCandidates) { candidate in
                                Text(candidate.fileName).tag(candidate.id as UUID?)
                            }
                        }
                        Text(referenceRecordingID == nil
                             ? "Sin referencia se califican solo tempo y regularidad."
                             : "La comparación usa la secuencia de notas y las proporciones rítmicas de ambas tomas; pueden estar a distinto tempo.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Habilidad evaluada", selection: $evidenceSkillID) {
                            Text("Solo guardar el análisis").tag(nil as UUID?)
                            ForEach(skills) { skill in
                                Text(skill.name).tag(skill.id as UUID?)
                            }
                        }
                        if evidenceSkillID != nil {
                            Picker("Dimensión objetiva", selection: $evidenceDimension) {
                                Text(SkillEvidenceDimension.execution.rawValue).tag(SkillEvidenceDimension.execution)
                                Text(SkillEvidenceDimension.musicalApplication.rawValue).tag(SkillEvidenceDimension.musicalApplication)
                            }
                            Text(referenceRecordingID == nil
                                 ? "Solo tempo y regularidad de ataques cuentan como evidencia. Notas, bends y musicalidad se muestran, pero no se puntúan sin una referencia objetivo."
                                 : "Con la toma de referencia sí se puntúan coincidencia de notas, cobertura y proporciones rítmicas. Bends y musicalidad siguen siendo informativos.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ViewThatFits(in: .horizontal) {
                            HStack { audioButtons }
                            VStack(alignment: .leading) { audioButtons }
                        }
                        if !runningAction.isEmpty {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text(runningAction)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } else {
                        Text("Exporta este proyecto de Logic como WAV, AIFF, M4A o MP3 para transcribirlo, analizar notas o separar stems.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !artifacts.isEmpty {
                    Section("Resultados guardados") {
                        ForEach(artifacts) { artifact in
                            DisclosureGroup {
                                if !artifact.body.isEmpty {
                                    Text(artifact.body)
                                        .textSelection(.enabled)
                                }
                                ForEach(artifact.filePaths, id: \.self) { path in
                                    Button("Abrir \(URL(fileURLWithPath: path).lastPathComponent)") {
                                        LearningMaterialsService.open(URL(fileURLWithPath: path))
                                    }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(artifact.title)
                                        .font(.subheadline.weight(.medium))
                                    Text(artifact.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Detalle de grabación")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
                ToolbarItem {
                    Button("Abrir en Logic", systemImage: "arrow.up.forward.square") {
                        SecurityScopedFile.open(recording.bookmarkData)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var audioButtons: some View {
        Button("Transcribir", systemImage: "captions.bubble") {
            Task { await transcribe() }
        }
        .disabled(!runningAction.isEmpty)
        Button("Analizar toma", systemImage: "waveform.badge.magnifyingglass") {
            Task { await analyze() }
        }
        .disabled(!runningAction.isEmpty)
        Button("Separar stems", systemImage: "square.stack.3d.up") {
            Task { await separateStems() }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!runningAction.isEmpty)
    }

    @MainActor
    private func transcribe() async {
        runningAction = "Transcribiendo localmente…"
        errorMessage = ""
        defer { runningAction = "" }
        do {
            let result = try await LocalAudioIntelligenceService.transcribe(
                bookmarkData: recording.bookmarkData
            )
            modelContext.insert(AIArtifact(
                kind: .recordingTranscription,
                title: "Transcripción · \(recording.fileName)",
                body: result.timestampedText,
                sourceID: recording.id,
                sourceName: recording.fileName,
                metadataJSON: #"{"language":"\#(result.language)","segments":\#(result.segmentCount)}"#
            ))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func analyze() async {
        runningAction = referenceRecordingID == nil
            ? "Detectando notas, timing y tempo…"
            : "Analizando la toma y su referencia…"
        errorMessage = ""
        defer { runningAction = "" }
        do {
            let result = try await LocalAudioIntelligenceService.analyzePerformance(
                bookmarkData: recording.bookmarkData,
                targetBPM: targetBPM > 0 ? targetBPM : nil
            )
            let selectedReference = referenceRecordingID.flatMap { id in
                allRecordings.first { $0.id == id }
            }
            let referenceResult: PerformanceAnalysisResult?
            if let selectedReference {
                referenceResult = try await LocalAudioIntelligenceService.analyzePerformance(
                    bookmarkData: selectedReference.bookmarkData,
                    targetBPM: nil
                )
            } else {
                referenceResult = nil
            }
            let comparison = referenceResult.flatMap {
                ReferenceAudioEvidenceScorer.score(
                    performanceMetadataJSON: result.metadataJSON,
                    referenceMetadataJSON: $0.metadataJSON
                )
            }
            let comparisonText = comparison.map {
                "\nComparación con \(selectedReference?.fileName ?? "referencia"): \($0.summary)."
            } ?? ""
            let files = [result.midiURL, result.noteCSVURL].compactMap(\.self).map(\.path)
            let artifact = AIArtifact(
                kind: .performanceAnalysis,
                title: "Análisis · \(recording.fileName)",
                body: result.summary + comparisonText,
                sourceID: recording.id,
                sourceName: recording.fileName,
                filePaths: files,
                metadataJSON: result.metadataJSON
            )
            modelContext.insert(artifact)
            let genericScore = selectedReference == nil
                ? ObjectiveAudioEvidenceScorer.score(metadataJSON: result.metadataJSON, targetBPM: targetBPM)
                : nil
            if let evidenceSkillID, let score = comparison.map({ ($0.score, $0.reliability, $0.summary) })
                ?? genericScore.map({ ($0.score, $0.reliability, $0.summary) }) {
                SkillEvidenceService.recordObjectiveAudio(
                    artifactID: artifact.id,
                    skillID: evidenceSkillID,
                    dimension: evidenceDimension,
                    score: score.0,
                    reliability: score.1,
                    notes: "\(recording.fileName) · \(score.2)",
                    in: modelContext
                )
            } else if evidenceSkillID != nil {
                errorMessage = selectedReference == nil
                    ? "El análisis se guardó, pero no produjo métricas objetivas suficientes para actualizar la habilidad."
                    : "El análisis se guardó, pero una de las tomas no produjo suficientes notas para compararlas."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func separateStems() async {
        runningAction = "Separando batería, bajo, voz y acompañamiento…"
        errorMessage = ""
        defer { runningAction = "" }
        do {
            let result = try await LocalAudioIntelligenceService.separateStems(
                bookmarkData: recording.bookmarkData
            )
            modelContext.insert(AIArtifact(
                kind: .stems,
                title: "Stems · \(recording.fileName)",
                body: "Se crearon \(result.stemURLs.count) stems en \(result.outputFolder.path).",
                sourceID: recording.id,
                sourceName: recording.fileName,
                filePaths: [result.outputFolder.path] + result.stemURLs.map(\.path)
            ))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
