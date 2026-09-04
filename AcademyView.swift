import SwiftUI
import SwiftData
import AppKit

private enum AcademyMode: String, CaseIterable, Identifiable {
    case overview = "Resumen"
    case study = "Estudiar"
    case practice = "Practicar"
    case questions = "Preguntas"
    case earTraining = "Oído"
    case rhythm = "Ritmo"
    var id: String { rawValue }
}

struct AcademyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigator.self) private var navigator
    @Query(sort: \SkillTopic.name) private var topics: [SkillTopic]
    @Query(sort: \AcademyQuestion.createdAt, order: .reverse) private var authoredQuestions: [AcademyQuestion]
    @Query(sort: \LibraryBook.title) private var books: [LibraryBook]
    @Query private var legacyProgress: [TheoryFlashcardProgress]
    @Query private var authoredProgress: [AcademyQuestionProgress]

    /// Estudiar recorre los 963 conceptos, pero los toma del catálogo compartido.
    private var concepts: [LibraryConcept] {
        LibraryLookup.Catalog.shared.concepts(in: modelContext)
    }

    @State private var mode = AcademyMode.overview
    @State private var showingNewQuestion = false
    @State private var questionToEdit: AcademyQuestion?

    private var ranked: (cards: [AcademyCard], dueCount: Int) {
        AcademyScheduler.rankedCards(
            topics: topics,
            legacyProgress: legacyProgress,
            authoredQuestions: authoredQuestions,
            authoredProgress: authoredProgress
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    academyTitle
                    Spacer()
                    academyControls
                }
                VStack(alignment: .leading, spacing: 12) {
                    academyTitle
                    academyControls
                }
            }
            .padding(20)

            Divider()

            switch mode {
            case .overview:
                overview
            case .study:
                AcademyStudyView(concepts: concepts, books: books)
            case .practice:
                AcademyPracticeView(
                    cards: ranked.cards,
                    dueCount: ranked.dueCount,
                    legacyProgress: legacyProgress,
                    authoredProgress: authoredProgress
                )
            case .questions:
                questionsList
            case .earTraining:
                AcademyEarTrainingView()
            case .rhythm:
                RhythmTrainingView()
            }
        }
        .sheet(isPresented: $showingNewQuestion) {
            AcademyQuestionEditorView()
        }
        .sheet(item: $questionToEdit) { question in
            AcademyQuestionEditorView(questionToEdit: question)
        }
        .onAppear { applyPendingFocus() }
        .onChange(of: navigator.focusConceptID) { _, _ in applyPendingFocus() }
    }

    private func applyPendingFocus() {
        guard navigator.focusConceptID != nil else { return }
        mode = .study
    }

    private var academyTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Academia de teoría")
                .font(.largeTitle.bold())
            Text("Aprende, comprueba y retén teoría, oído y ritmo aplicado a la guitarra")
                .foregroundStyle(.secondary)
        }
    }

    private var academyControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Picker("Vista", selection: $mode) {
                    ForEach(AcademyMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 530)
                if mode == .questions {
                    Button("Nueva pregunta", systemImage: "plus") { showingNewQuestion = true }
                        .buttonStyle(.borderedProminent)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Picker("Vista", selection: $mode) {
                    ForEach(AcademyMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(minWidth: 360, idealWidth: 530, maxWidth: 560)
                if mode == .questions {
                    Button("Nueva pregunta", systemImage: "plus") { showingNewQuestion = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                    MetricCard(
                        title: "Para repasar hoy",
                        value: "\(ranked.dueCount)",
                        detail: "de \(ranked.cards.count) tarjetas",
                        icon: "calendar.badge.clock",
                        tint: .indigo
                    )
                    MetricCard(
                        title: "Preguntas propias",
                        value: "\(authoredQuestions.count)",
                        detail: "texto e imágenes de tus PDFs",
                        icon: "square.and.pencil",
                        tint: .purple
                    )
                    MetricCard(
                        title: "Conceptos para estudiar",
                        value: "\(concepts.count)",
                        detail: "del catálogo de tus libros",
                        icon: "books.vertical.fill",
                        tint: .blue
                    )
                    MetricCard(
                        title: "Retención consolidada",
                        value: "\(consolidatedCount)",
                        detail: "tarjetas en caja 5",
                        icon: "brain.head.profile",
                        tint: .green
                    )
                }

                HStack {
                    SectionHeader(
                        title: "Módulos",
                        subtitle: "acceso libre · el repaso prioriza lo que olvidas"
                    )
                    Spacer()
                    Button("Practicar ahora", systemImage: "play.fill") { mode = .practice }
                        .buttonStyle(.borderedProminent)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                    ForEach(theoryTopics) { topic in
                        CardContainer {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(topic.name)
                                        .font(.headline)
                                    Spacer()
                                    DifficultyBadge(rating: DifficultyClassifier.assess(skillNamed: topic.name).rating)
                                }
                                Text(topic.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                ProgressView(value: mastery(for: topic))
                                    .tint(.indigo)
                                Text("\(Int(mastery(for: topic) * 100))% de retención")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private var questionsList: some View {
        Group {
            if authoredQuestions.isEmpty {
                EmptyStateView(
                    icon: "square.and.pencil",
                    title: "Sin preguntas propias",
                    message: "Crea preguntas de alternativa, verdadero/falso o completar palabra, con recortes de tus PDFs."
                )
            } else {
                List(authoredQuestions) { question in
                    Button {
                        questionToEdit = question
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: question.imageData == nil ? "text.bubble" : "photo")
                                .foregroundStyle(.indigo)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(question.prompt).font(.headline).lineLimit(2)
                                HStack {
                                    Text(question.type.rawValue)
                                    if !question.sourceBookTitle.isEmpty {
                                        Text("· \(question.sourceBookTitle), pág. \(question.sourcePage)")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Eliminar", systemImage: "trash", role: .destructive) {
                            delete(question)
                        }
                    }
                }
            }
        }
    }

    private var theoryTopics: [SkillTopic] {
        topics.filter { $0.domain == .theory }
    }

    private var consolidatedCount: Int {
        legacyProgress.filter { $0.boxLevel == 5 }.count +
        authoredProgress.filter { $0.boxLevel == 5 }.count
    }

    private func mastery(for topic: SkillTopic) -> Double {
        let legacyIDs = topic.assessmentQuestions.indices.map {
            TheoryFlashcardProgress.makeID(topicID: topic.id, questionIndex: $0)
        }
        let boxes = legacyIDs.compactMap { id in legacyProgress.first { $0.id == id }?.boxLevel } +
            authoredQuestions
                .filter { $0.topicID == topic.id }
                .compactMap { question in authoredProgress.first { $0.questionID == question.id }?.boxLevel }
        let totalCards = legacyIDs.count + authoredQuestions.filter { $0.topicID == topic.id }.count
        guard totalCards > 0 else { return 0 }
        return Double(boxes.reduce(0, +)) / Double(totalCards * 5)
    }

    private func delete(_ question: AcademyQuestion) {
        if let progress = authoredProgress.first(where: { $0.questionID == question.id }) {
            modelContext.delete(progress)
        }
        modelContext.delete(question)
    }
}

private struct AcademyStudyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigator.self) private var navigator
    let concepts: [LibraryConcept]
    let books: [LibraryBook]
    @State private var searchText = ""
    @State private var selectedID: UUID?
    @State private var showingQuestionEditor = false

    private var filtered: [LibraryConcept] {
        guard !searchText.isEmpty else { return concepts }
        return concepts.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.category.localizedCaseInsensitiveContains(searchText) ||
            $0.bookTitle.localizedCaseInsensitiveContains(searchText) ||
            $0.summary.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selected: LibraryConcept? {
        concepts.first { $0.id == selectedID } ?? filtered.first
    }

    var body: some View {
        HStack(spacing: 0) {
            List(filtered, selection: $selectedID) { concept in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(concept.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                        Spacer()
                        if concept.isExercise {
                            Image(systemName: "pencil.and.list.clipboard")
                                .foregroundStyle(.orange)
                        }
                    }
                    Text("\(concept.category) · \(concept.bookTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 4)
                .tag(concept.id)
            }
            .searchable(text: $searchText, prompt: "Buscar concepto, categoría o libro")
            .frame(minWidth: 240, idealWidth: 320, maxWidth: 380)
            Divider()
            Group {
            if let selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            StatusPill(
                                text: selected.isExercise ? "Ejercicio teórico" : "Concepto",
                                tint: selected.isExercise ? .orange : .blue
                            )
                            DifficultyBadge(rating: DifficultyClassifier.assess(selected).rating)
                        }
                        Text(selected.title).font(.title2.bold())
                        Text(selected.summary)
                            .font(.body)
                            .textSelection(.enabled)
                        Divider()
                        LabeledContent("Categoría", value: selected.category)
                        LabeledContent("Fuente", value: selected.bookTitle)
                        LabeledContent("Página", value: "\(selected.page)")
                        HStack {
                            if let book = matchingBook(for: selected) {
                                Button("Abrir PDF", systemImage: "arrow.up.forward.square") {
                                    SecurityScopedFile.open(book.bookmarkData)
                                }
                            }
                            Button("Agregar a tareas", systemImage: "checklist") {
                                addToTasks(selected)
                            }
                            .buttonStyle(.bordered)
                            Button("Generar pregunta con IA", systemImage: "sparkles") {
                                showingQuestionEditor = true
                            }
                            .buttonStyle(.bordered)
                        }
                        if matchingBook(for: selected) == nil {
                            Text("Importa el PDF correspondiente en Biblioteca para poder abrir la fuente desde aquí.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 780, alignment: .leading)
                }
            } else {
                EmptyStateView(
                    icon: "books.vertical",
                    title: "Sin conceptos",
                    message: "Importa compiled_teoria_guitarra.json desde Biblioteca → Conceptos."
                )
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            selectedID = selectedID ?? filtered.first?.id
            applyPendingFocus()
        }
        .onChange(of: navigator.focusConceptID) { _, _ in applyPendingFocus() }
        .sheet(isPresented: $showingQuestionEditor) {
            if let selected {
                AcademyQuestionEditorView(prefillFromConcept: selected)
            }
        }
    }

    private func applyPendingFocus() {
        guard let focusID = navigator.focusConceptID else { return }
        selectedID = focusID
        navigator.focusConceptID = nil
    }

    private func addToTasks(_ concept: LibraryConcept) {
        let resolution = PracticeTaskDeduplication.resolve(
            candidateTitle: concept.title, candidateSourceKind: .academia,
            candidateSourceID: concept.id, in: modelContext
        )
        guard PracticeTaskDeduplication.apply(resolution, in: modelContext) else { return }
        modelContext.insert(PracticeTask(
            title: concept.title,
            category: .theory,
            plannedMinutes: 15,
            sourceTitle: concept.bookTitle,
            exerciseTitle: concept.title,
            priority: 1,
            instructions: "\(TheoryTaskMode.readAndExplain.defaultInstructions)\n\n\(concept.summary)",
            theoryTaskMode: .readAndExplain,
            sourceKind: .academia,
            sourceID: concept.id
        ))
    }

    private func matchingBook(for concept: LibraryConcept) -> LibraryBook? {
        let conceptTitle = normalized(concept.bookTitle)
        return books.first {
            let bookTitle = normalized($0.title)
            return bookTitle == conceptTitle ||
                bookTitle.contains(conceptTitle) ||
                conceptTitle.contains(bookTitle)
        }
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }
}

private struct AcademyPracticeView: View {
    @Environment(\.modelContext) private var modelContext
    let cards: [AcademyCard]
    let dueCount: Int
    let legacyProgress: [TheoryFlashcardProgress]
    let authoredProgress: [AcademyQuestionProgress]

    private enum Phase { case ready, reviewing, finished }
    @State private var phase = Phase.ready
    @State private var session: [AcademyCard] = []
    @State private var index = 0
    @State private var selectedAnswer = ""
    @State private var fillAnswer = ""
    @State private var revealed = false
    @State private var correctCount = 0
    private let sessionSize = 12

    var body: some View {
        switch phase {
        case .ready:
            readyView
        case .reviewing:
            reviewView
        case .finished:
            finishedView
        }
    }

    private var readyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "brain.head.profile")
                .font(.system(size: 52))
                .foregroundStyle(.indigo)
            Text(dueCount > 0 ? "\(dueCount) tarjetas para repasar hoy" : "Todo al día")
                .font(.title2.bold())
            Text("La sesión mezcla el Test Integral con tus preguntas propias y vuelve a comprobar periódicamente lo aprendido.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            if cards.isEmpty {
                Text("Todavía no hay tarjetas disponibles.").foregroundStyle(.secondary)
            } else {
                Button("Comenzar sesión") {
                    session = Array(cards.prefix(sessionSize))
                    index = 0
                    correctCount = 0
                    resetAnswer()
                    phase = .reviewing
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding(30)
    }

    @ViewBuilder
    private var reviewView: some View {
        if session.indices.contains(index) {
            let card = session[index]
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        StatusPill(text: card.topicName, tint: .indigo)
                        Spacer()
                        Text("\(index + 1) de \(session.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let data = card.imageData, let image = NSImage(data: data) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Text(card.prompt).font(.title3.weight(.medium))
                    answerView(for: card)

                    if revealed {
                        feedback(for: card)
                        Button(index == session.count - 1 ? "Terminar" : "Siguiente") {
                            if index == session.count - 1 {
                                phase = .finished
                            } else {
                                index += 1
                                resetAnswer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(24)
                .frame(maxWidth: 850, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func answerView(for card: AcademyCard) -> some View {
        switch card.source {
        case .legacy(let legacy):
            MultipleChoiceOptions(
                options: legacy.question.options,
                selectedIndex: Binding(
                    get: {
                        guard !selectedAnswer.isEmpty else { return nil }
                        return Int(selectedAnswer)
                    },
                    set: { selected in
                        guard let selected else { return }
                        selectedAnswer = String(selected)
                        reveal(card, isCorrect: selected == legacy.correctIndex)
                    }
                ),
                correctIndex: legacy.correctIndex,
                revealed: revealed
            )
        case .authored(let question):
            switch question.type {
            case .multipleChoice, .trueFalse:
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { _, option in
                        answerButton(
                            option,
                            isCorrect: normalized(option) == normalized(question.correctAnswer),
                            card: card
                        )
                    }
                }
            case .fillBlank:
                HStack {
                    TextField("Completa la palabra o frase", text: $fillAnswer)
                        .textFieldStyle(.roundedBorder)
                        .disabled(revealed)
                    Button("Comprobar") {
                        selectedAnswer = fillAnswer
                        reveal(card, isCorrect: normalized(fillAnswer) == normalized(question.correctAnswer))
                    }
                    .disabled(revealed || fillAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func answerButton(_ option: String, isCorrect: Bool, card: AcademyCard) -> some View {
        Button {
            guard !revealed else { return }
            selectedAnswer = option
            reveal(card, isCorrect: isCorrect)
        } label: {
            HStack {
                Image(systemName: answerIcon(option: option, correct: isCorrect))
                    .foregroundStyle(answerColor(option: option, correct: isCorrect))
                Text(option)
                Spacer()
            }
            .padding(9)
            .background(answerColor(option: option, correct: isCorrect).opacity(revealed ? 0.1 : 0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func feedback(for card: AcademyCard) -> some View {
        if case .authored(let question) = card.source {
            let correct = normalized(selectedAnswer) == normalized(question.correctAnswer)
            VStack(alignment: .leading, spacing: 5) {
                Text(correct ? "Correcto" : "Respuesta correcta: \(question.correctAnswer)")
                    .font(.headline)
                    .foregroundStyle(correct ? .green : .orange)
                if !question.explanation.isEmpty {
                    Text(question.explanation).foregroundStyle(.secondary)
                }
                if !question.sourceBookTitle.isEmpty {
                    Text("Fuente: \(question.sourceBookTitle), página \(question.sourcePage)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var finishedView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(.indigo)
            Text("\(correctCount) de \(session.count) correctas")
                .font(.title2.bold())
            Button("Nueva sesión") { phase = .ready }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private func reveal(_ card: AcademyCard, isCorrect: Bool) {
        guard !revealed else { return }
        revealed = true
        if isCorrect { correctCount += 1 }
        switch card.source {
        case .legacy(let legacy):
            let progress = legacyProgress.first { $0.id == legacy.id } ?? {
                let created = TheoryFlashcardProgress(topicID: legacy.topic.id, questionIndex: legacy.questionIndex)
                modelContext.insert(created)
                return created
            }()
            let wasDue = progress.lastReviewedDate != nil && progress.nextReviewDate <= .now
            TheoryFlashcardScheduler.record(progress, isCorrect: isCorrect)
            SkillEvidenceService.recordTheoryReview(
                topicID: legacy.topic.id,
                isCorrect: isCorrect,
                wasDue: wasDue,
                in: modelContext
            )
        case .authored(let question):
            let progress = authoredProgress.first { $0.questionID == question.id } ?? {
                let created = AcademyQuestionProgress(questionID: question.id)
                modelContext.insert(created)
                return created
            }()
            let wasDue = progress.lastReviewedDate != nil && progress.nextReviewDate <= .now
            AcademyScheduler.record(progress, isCorrect: isCorrect)
            if let topicID = question.topicID {
                SkillEvidenceService.recordTheoryReview(
                    topicID: topicID,
                    isCorrect: isCorrect,
                    wasDue: wasDue,
                    in: modelContext
                )
            }
        }
    }

    private func resetAnswer() {
        selectedAnswer = ""
        fillAnswer = ""
        revealed = false
    }

    private func normalized(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func answerIcon(option: String, correct: Bool) -> String {
        guard revealed else { return selectedAnswer == option ? "circle.inset.filled" : "circle" }
        if correct { return "checkmark.circle.fill" }
        if selectedAnswer == option { return "xmark.circle.fill" }
        return "circle"
    }

    private func answerColor(option: String, correct: Bool) -> Color {
        guard revealed else { return selectedAnswer == option ? .indigo : .secondary }
        if correct { return .green }
        if selectedAnswer == option { return .red }
        return .secondary
    }
}
