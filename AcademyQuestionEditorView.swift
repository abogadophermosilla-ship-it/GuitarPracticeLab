import SwiftUI
import SwiftData
import AppKit

struct AcademyQuestionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SkillTopic.name) private var topics: [SkillTopic]
    @Query(sort: \LibraryBook.title) private var books: [LibraryBook]
    @StateObject private var orchestrator = AIOrchestrator()

    var questionToEdit: AcademyQuestion?
    /// Concepto de Biblioteca a partir del cual generar un borrador apenas se abre la hoja, sin
    /// pasar por foto/OCR — reutiliza `AcademyQuestionDraftService` con el `summary` ya curado del
    /// concepto en vez de texto reconocido de una imagen.
    var prefillFromConcept: LibraryConcept?

    @State private var type = AcademyQuestionType.multipleChoice
    @State private var topicID: UUID?
    @State private var prompt = ""
    @State private var options = ["", "", "", ""]
    @State private var correctOptionIndex = 0
    @State private var trueFalseAnswer = true
    @State private var fillAnswer = ""
    @State private var explanation = ""
    @State private var imageData: Data?
    @State private var imageBookID: UUID?
    @State private var imageBookTitle = ""
    @State private var imagePage = 0
    @State private var selectedBookID: UUID?
    @State private var sourcePage = 1
    @State private var renderedPage: NSImage?
    @State private var showingCropper = false
    @State private var errorMessage = ""
    @State private var didLoad = false
    @State private var isGeneratingFromImage = false
    @State private var recognizedText = ""
    @State private var isGeneratingFromConcept = false

    private var theoryTopics: [SkillTopic] { topics.filter { $0.domain == .theory } }
    private var selectedBook: LibraryBook? { books.first { $0.id == selectedBookID } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pregunta") {
                    if let prefillFromConcept {
                        Label("Generando desde \"\(prefillFromConcept.title)\" (\(prefillFromConcept.bookTitle), p. \(prefillFromConcept.page))", systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if isGeneratingFromConcept {
                            ProgressView(orchestrator.currentStatus.isEmpty ? "Redactando la pregunta…" : orchestrator.currentStatus)
                        }
                    }
                    Picker("Tipo", selection: $type) {
                        ForEach(AcademyQuestionType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Módulo", selection: $topicID) {
                        Text("Teoría general").tag(nil as UUID?)
                        ForEach(theoryTopics) { Text($0.name).tag($0.id as UUID?) }
                    }
                    TextField("Enunciado", text: $prompt, axis: .vertical)
                        .lineLimit(2...5)
                    answerEditor
                    TextField("Explicación al responder (opcional)", text: $explanation, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Imagen desde Biblioteca (opcional)") {
                    Picker("Libro PDF", selection: $selectedBookID) {
                        Text("Sin imagen").tag(nil as UUID?)
                        ForEach(books) { Text($0.title).tag($0.id as UUID?) }
                    }
                    if let book = selectedBook {
                        Stepper(
                            "Página \(sourcePage) de \(max(book.pageCount, 1))",
                            value: $sourcePage,
                            in: 1...max(book.pageCount, 1)
                        )
                        Button("Ver página y recortar", systemImage: "crop") {
                            renderSelectedPage()
                        }
                    }
                    if let imageData, let image = NSImage(data: imageData) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: 360, maxHeight: 220)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Button("Quitar imagen", role: .destructive) {
                                    self.imageData = nil
                                    imageBookID = nil
                                    imageBookTitle = ""
                                    imagePage = 0
                                    recognizedText = ""
                                }
                            }
                            Button("Crear borrador desde el recorte", systemImage: "viewfinder.circle") {
                                Task { await generateDraftFromImage() }
                            }
                            .disabled(isGeneratingFromImage)
                            if isGeneratingFromImage {
                                ProgressView(orchestrator.currentStatus.isEmpty
                                             ? "Leyendo y preparando la pregunta…"
                                             : orchestrator.currentStatus)
                            }
                            if !recognizedText.isEmpty {
                                DisclosureGroup("Texto reconocido") {
                                    Text(recognizedText)
                                        .font(.caption)
                                        .textSelection(.enabled)
                                }
                            }
                            Text("Vision reconoce el texto en el Mac y el modelo prepara un borrador. Revisalo antes de guardar.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle(questionToEdit == nil ? "Nueva pregunta" : "Editar pregunta")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(minWidth: 540, idealWidth: 640, minHeight: 560)
        .onAppear {
            loadInitialValuesIfNeeded()
            if questionToEdit == nil, let prefillFromConcept {
                Task { await generateDraftFromConcept(prefillFromConcept) }
            }
        }
        .onChange(of: selectedBookID) { oldValue, _ in
            // Al cargar una pregunta existente el valor pasa de nil al libro guardado; no hay que
            // borrar su recorte. Solo se reinicia cuando el usuario cambia desde otro libro.
            guard oldValue != nil else { return }
            sourcePage = 1
            imageData = nil
        }
        .sheet(isPresented: $showingCropper) {
            if let renderedPage {
                PDFCropSelectionView(
                    image: renderedPage,
                    onCancel: { showingCropper = false },
                    onConfirm: { data in
                        imageData = data
                        imageBookID = selectedBook?.id
                        imageBookTitle = selectedBook?.title ?? ""
                        imagePage = sourcePage
                        showingCropper = false
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var answerEditor: some View {
        switch type {
        case .multipleChoice:
            optionRow(0)
            optionRow(1)
            optionRow(2)
            optionRow(3)
        case .trueFalse:
            Picker("Respuesta correcta", selection: $trueFalseAnswer) {
                Text("Verdadero").tag(true)
                Text("Falso").tag(false)
            }
            .pickerStyle(.segmented)
        case .fillBlank:
            TextField("Palabra o frase correcta", text: $fillAnswer)
            Text("La comparación ignora mayúsculas, tildes y espacios sobrantes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func optionRow(_ index: Int) -> some View {
        HStack {
            TextField("Opción \(index + 1)", text: $options[index])
            Button {
                correctOptionIndex = index
            } label: {
                Label(
                    "Correcta",
                    systemImage: correctOptionIndex == index ? "largecircle.fill.circle" : "circle"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func renderSelectedPage() {
        guard let book = selectedBook else { return }
        errorMessage = ""
        guard let image = PDFPageRenderer.render(book: book, pageNumber: sourcePage) else {
            errorMessage = "No se pudo abrir esa página. Verifica que el PDF siga disponible."
            return
        }
        renderedPage = image
        showingCropper = true
    }

    @MainActor
    private func generateDraftFromImage() async {
        guard let imageData else { return }
        isGeneratingFromImage = true
        errorMessage = ""
        defer { isGeneratingFromImage = false }
        do {
            recognizedText = try await VisionOCRService.recognizeText(in: imageData)
            // .light: convertir un texto ya reconocido en una pregunta es transformación de texto,
            // y el borrador lo revisa el usuario antes de guardarlo — mismo criterio que
            // `SkillAssessmentQuestionDraftService`.
            let backend = try await orchestrator.backend(for: .light)
            let source = imageBookTitle.isEmpty
                ? "recorte sin libro"
                : "\(imageBookTitle), página \(imagePage)"
            let draft = try await AcademyQuestionDraftService.generate(
                recognizedText: recognizedText,
                requestedType: type,
                source: source,
                backend: backend
            )
            applyDraft(draft)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Mismo servicio que el recorte de imagen, pero con el `summary` ya curado del concepto en vez
    /// de texto OCR — sin foto, sin recorte, sin pasar por Vision.
    @MainActor
    private func generateDraftFromConcept(_ concept: LibraryConcept) async {
        isGeneratingFromConcept = true
        errorMessage = ""
        defer { isGeneratingFromConcept = false }
        do {
            let backend = try await orchestrator.backend(for: .light)
            let draft = try await AcademyQuestionDraftService.generate(
                recognizedText: concept.summary,
                requestedType: type,
                source: "\(concept.bookTitle), página \(concept.page)",
                backend: backend
            )
            applyDraft(draft)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyDraft(_ draft: GeneratedAcademyQuestion) {
        prompt = draft.prompt
        explanation = draft.explanation
        type = draft.type
        switch draft.type {
        case .multipleChoice:
            options = Array((draft.options + ["", "", "", ""]).prefix(4))
            correctOptionIndex = options.firstIndex(of: draft.correctAnswer) ?? 0
        case .trueFalse:
            trueFalseAnswer = draft.correctAnswer == "Verdadero"
        case .fillBlank:
            fillAnswer = draft.correctAnswer
        }
    }

    private func save() {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            errorMessage = "Escribe el enunciado de la pregunta."
            return
        }

        let savedOptions: [String]
        let correctAnswer: String
        switch type {
        case .multipleChoice:
            savedOptions = options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard savedOptions.allSatisfy({ !$0.isEmpty }),
                  savedOptions.indices.contains(correctOptionIndex) else {
                errorMessage = "Completa las cuatro opciones y elige la correcta."
                return
            }
            correctAnswer = savedOptions[correctOptionIndex]
        case .trueFalse:
            savedOptions = ["Verdadero", "Falso"]
            correctAnswer = trueFalseAnswer ? "Verdadero" : "Falso"
        case .fillBlank:
            savedOptions = []
            correctAnswer = fillAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !correctAnswer.isEmpty else {
                errorMessage = "Escribe la palabra o frase correcta."
                return
            }
        }

        if let questionToEdit {
            questionToEdit.topicID = topicID
            questionToEdit.type = type
            questionToEdit.prompt = trimmedPrompt
            questionToEdit.options = savedOptions
            questionToEdit.correctAnswer = correctAnswer
            questionToEdit.explanation = explanation
            questionToEdit.imageData = imageData
            questionToEdit.sourceBookID = imageData == nil ? nil : imageBookID
            questionToEdit.sourceBookTitle = imageData == nil ? "" : imageBookTitle
            questionToEdit.sourcePage = imageData == nil ? 0 : imagePage
        } else {
            modelContext.insert(AcademyQuestion(
                topicID: topicID,
                type: type,
                prompt: trimmedPrompt,
                options: savedOptions,
                correctAnswer: correctAnswer,
                explanation: explanation,
                imageData: imageData,
                sourceBookID: imageData == nil ? nil : imageBookID,
                sourceBookTitle: imageData == nil ? "" : imageBookTitle,
                sourcePage: imageData == nil ? 0 : imagePage
            ))
        }
        dismiss()
    }

    private func loadInitialValuesIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let questionToEdit else { return }
        type = questionToEdit.type
        topicID = questionToEdit.topicID
        prompt = questionToEdit.prompt
        explanation = questionToEdit.explanation
        imageData = questionToEdit.imageData
        imageBookID = questionToEdit.sourceBookID
        imageBookTitle = questionToEdit.sourceBookTitle
        imagePage = questionToEdit.sourcePage
        selectedBookID = questionToEdit.sourceBookID
        sourcePage = max(questionToEdit.sourcePage, 1)
        switch questionToEdit.type {
        case .multipleChoice:
            options = Array((questionToEdit.options + ["", "", "", ""]).prefix(4))
            correctOptionIndex = questionToEdit.options.firstIndex(of: questionToEdit.correctAnswer) ?? 0
        case .trueFalse:
            trueFalseAnswer = questionToEdit.correctAnswer == "Verdadero"
        case .fillBlank:
            fillAnswer = questionToEdit.correctAnswer
        }
    }
}
