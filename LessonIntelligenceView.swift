import SwiftUI
import SwiftData

struct LessonIntelligenceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AIArtifact.createdAt, order: .reverse) private var allArtifacts: [AIArtifact]

    let lesson: GuitarLesson

    @StateObject private var orchestrator = AIOrchestrator()
    @State private var selectedAttachmentID: UUID?
    @State private var transcript = ""
    @State private var proposedTopics = ""
    @State private var proposedNotes = ""
    @State private var proposedObjective = ""
    @State private var isTranscribing = false
    @State private var isSummarizing = false
    @State private var errorMessage = ""
    @State private var didLoad = false

    private var audioAttachments: [LessonAttachment] {
        lesson.attachments.filter { attachment in
            guard attachment.kind == .audio, attachment.bookmarkData != nil else { return false }
            return LocalAudioIntelligenceService.supportedAudioExtensions.contains(
                URL(fileURLWithPath: attachment.fileName).pathExtension.lowercased()
            )
        }
    }

    private var selectedAttachment: LessonAttachment? {
        audioAttachments.first { $0.id == selectedAttachmentID }
    }

    private var priorTranscriptions: [AIArtifact] {
        allArtifacts.filter {
            $0.sourceID == lesson.id && $0.kind == .lessonTranscription
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Audio de la clase") {
                    if audioAttachments.isEmpty {
                        ContentUnavailableView(
                            "Sin audio",
                            systemImage: "waveform.slash",
                            description: Text("Edita la clase y adjunta un WAV, AIFF, M4A o MP3 con tipo Audio.")
                        )
                    } else {
                        Picker("Archivo", selection: $selectedAttachmentID) {
                            ForEach(audioAttachments) { attachment in
                                Text(attachment.displayName).tag(attachment.id as UUID?)
                            }
                        }
                        Button("Transcribir localmente", systemImage: "captions.bubble") {
                            Task { await transcribeSelectedAudio() }
                        }
                        .disabled(isTranscribing || isSummarizing || selectedAttachment == nil)
                    }

                    if isTranscribing {
                        ProgressView("MLX Whisper está escuchando la clase…")
                    }
                }

                if !transcript.isEmpty {
                    Section("Transcripción") {
                        TextEditor(text: $transcript)
                            .font(.body)
                            .frame(minHeight: 150)
                        Button("Extraer indicaciones y objetivo", systemImage: "sparkles") {
                            Task { await summarizeTranscript() }
                        }
                        .disabled(isTranscribing || isSummarizing)
                        if isSummarizing {
                            ProgressView(orchestrator.currentStatus.isEmpty
                                         ? "Analizando…"
                                         : orchestrator.currentStatus)
                        }
                    }
                }

                if hasProposal {
                    Section("Propuesta editable") {
                        TextField("Temas", text: $proposedTopics, axis: .vertical)
                            .lineLimit(2...5)
                        TextField("Indicaciones del profesor", text: $proposedNotes, axis: .vertical)
                            .lineLimit(3...8)
                        TextField("Próximo objetivo", text: $proposedObjective, axis: .vertical)
                            .lineLimit(2...6)
                        Text("Nada se modifica hasta que confirmes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Aplicar a esta clase", systemImage: "checkmark.circle.fill") {
                            applyProposal()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if priorTranscriptions.count > 1 {
                    Section("Historial") {
                        ForEach(priorTranscriptions.dropFirst()) { artifact in
                            DisclosureGroup(artifact.createdAt.formatted(date: .abbreviated, time: .shortened)) {
                                Text(artifact.body)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }

                if !errorMessage.isEmpty {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("IA · \(lesson.date.formatted(date: .abbreviated, time: .omitted))")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .onAppear { loadInitialState() }
        }
    }

    private var hasProposal: Bool {
        !proposedTopics.isEmpty || !proposedNotes.isEmpty || !proposedObjective.isEmpty
    }

    @MainActor
    private func transcribeSelectedAudio() async {
        guard let attachment = selectedAttachment, let bookmarkData = attachment.bookmarkData else { return }
        isTranscribing = true
        errorMessage = ""
        defer { isTranscribing = false }
        do {
            let result = try await LocalAudioIntelligenceService.transcribe(bookmarkData: bookmarkData)
            transcript = result.timestampedText
            modelContext.insert(AIArtifact(
                kind: .lessonTranscription,
                title: "Transcripción · \(attachment.displayName)",
                body: result.timestampedText,
                sourceID: lesson.id,
                sourceName: attachment.displayName,
                metadataJSON: """
                {"language":"\(result.language)","segments":\(result.segmentCount)}
                """
            ))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func summarizeTranscript() async {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSummarizing = true
        errorMessage = ""
        defer { isSummarizing = false }
        do {
            // .light: resumir una transcripción que ya viene completa en el prompt es una tarea de
            // texto puro, sin conocimiento externo — el modelo chico la resuelve bien y sin espera.
            let backend = try await orchestrator.backend(for: .light)
            let proposal = try await LessonTranscriptionCoachService.summarize(
                transcript: trimmed,
                backend: backend
            )
            proposedTopics = proposal.topics
            proposedNotes = proposal.teacherNotes
            proposedObjective = proposal.nextObjective
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyProposal() {
        lesson.topics = proposedTopics
        lesson.teacherNotes = proposedNotes
        lesson.nextObjective = proposedObjective
        dismiss()
    }

    private func loadInitialState() {
        guard !didLoad else { return }
        didLoad = true
        selectedAttachmentID = audioAttachments.first?.id
        if let latest = priorTranscriptions.first {
            transcript = latest.body
        }
    }
}
