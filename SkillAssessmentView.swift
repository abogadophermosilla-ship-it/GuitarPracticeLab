import SwiftUI
import SwiftData

struct SkillAssessmentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SkillTopic.name) private var topics: [SkillTopic]
    @Query(sort: \Song.title) private var songs: [Song]
    @Query private var books: [LibraryBook]
    @Query(sort: \Band.name) private var bands: [Band]
    @AppStorage("hasCompletedSkillAssessment") private var hasCompletedAssessment = false
    @AppStorage("musicalTastes") private var musicalTastes = ""
    @AppStorage("assessmentContext") private var assessmentContext = ""
    @AppStorage("overallGuitaristLevel") private var overallGuitaristLevel = ""
    @AppStorage("overallLevelBand") private var overallLevelBand = ""
    @AppStorage("overallLevelPercentage") private var overallLevelPercentage = 0.0
    @AppStorage("lastQuestionRefreshDate") private var lastQuestionRefreshDate: Double = 0
    @StateObject private var orchestrator = AIOrchestrator()

    @State private var domain: SkillDomain = .technique
    @State private var isAnalyzing = false
    @State private var errorMessage = ""
    @State private var finishedMessage = ""
    @State private var showingQuestionReview = false

    /// Vencido = nunca se generó, o ya pasó un mes desde la última sesión de revisión de preguntas
    /// nuevas (ver `SkillAssessmentQuestionReviewView`). También se muestra el acceso si quedaron
    /// candidatas sin revisar de una sesión anterior, aunque el mes todavía no se haya cumplido.
    private var isQuestionRefreshDue: Bool {
        guard lastQuestionRefreshDate > 0 else { return true }
        let lastDate = Date(timeIntervalSince1970: lastQuestionRefreshDate)
        guard let nextDue = Calendar.current.date(byAdding: .month, value: 1, to: lastDate) else { return true }
        return Date() >= nextDue
    }

    private var hasPendingCandidateQuestions: Bool {
        topics.contains { !$0.pendingCandidateQuestions.isEmpty }
    }

    private var questionCount: Int {
        topics.reduce(0) { $0 + $1.assessmentQuestions.count + $1.activeRotationQuestions.count }
    }

    private var answeredCount: Int {
        topics.reduce(0) { partial, topic in
            partial
                + topic.assessmentQuestions.filter { $0.selectedIndex != nil }.count
                + topic.activeRotationQuestions.filter { $0.selectedIndex != nil }.count
        }
    }

    private func topics(for band: DifficultyBand) -> [SkillTopic] {
        topics.filter {
            $0.domain == domain && DifficultyClassifier.assess(skillNamed: $0.name).rating.band == band
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Responde cada pregunta de opción múltiple. El resultado abre tu mapa inicial; la práctica, la aplicación y las revisiones en frío determinarán después el dominio demostrado.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 5) {
                        ProgressView(value: Double(answeredCount), total: Double(max(1, questionCount)))
                        Text("\(answeredCount) de \(questionCount) respuestas · puedes cerrar y continuar después")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Contexto para el asistente (opcional)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        TextField(
                            "Ej: llevo 8 años tocando, sé teoría básica pero no modos, vengo del bajo eléctrico...",
                            text: $assessmentContext,
                            axis: .vertical
                        )
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)
                        Text("Ajusta las sugerencias de repertorio y la lectura de nivel general a tu situación real.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if !finishedMessage.isEmpty {
                        Text(finishedMessage)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    if isQuestionRefreshDue || hasPendingCandidateQuestions {
                        Button {
                            showingQuestionReview = true
                        } label: {
                            HStack {
                                Image(systemName: "sparkles")
                                Text(hasPendingCandidateQuestions ? "Candidatas de este mes esperando revisión" : "Generar preguntas nuevas de este mes")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                            }
                            .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.plain)
                        .padding(10)
                        .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    if let studentRating = StudentLevelService.rating(forPercentage: overallLevelPercentage) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Estimación del Test Integral")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                DifficultyBadge(rating: studentRating)
                            }
                            if !overallGuitaristLevel.isEmpty {
                                Text(overallGuitaristLevel)
                                    .font(.callout)
                            }
                        }
                        .padding(10)
                        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    if !orchestrator.currentStatus.isEmpty {
                        Text(orchestrator.currentStatus)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding([.horizontal, .top], 20)

                Picker("Área", selection: $domain) {
                    ForEach(SkillDomain.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(20)

                List {
                    ForEach(DifficultyBand.allCases) { band in
                        let items = topics(for: band)
                        if !items.isEmpty {
                            Section("\(band.rawValue)★ · \(band.name)") {
                                ForEach(items) { topic in
                                    AssessmentRow(topic: topic)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Autoevaluación")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        showingQuestionReview = true
                    } label: {
                        Label("Preguntas nuevas", systemImage: "sparkles")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await analyzeAndFinish() }
                    } label: {
                        if isAnalyzing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Analizar y terminar")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAnalyzing || answeredCount == 0)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Continuar después") { dismiss() }
                }
            }
            .sheet(isPresented: $showingQuestionReview) {
                SkillAssessmentQuestionReviewView()
            }
        }
    }

    @MainActor
    private func analyzeAndFinish() async {
        errorMessage = ""
        finishedMessage = ""
        guard answeredCount > 0 else {
            errorMessage = "Responde al menos una pregunta antes de analizar."
            return
        }
        isAnalyzing = true
        defer { isAnalyzing = false }

        // El test se conserva como estimación separada. Sus respuestas crean evidencia de
        // reconocimiento/comprensión; el dominio demostrado se recalcula con todas las fuentes.
        let assessmentRunID = UUID()
        for topic in topics {
            let testStatus = SkillAssessmentCoachService.computeStatus(for: topic)
            if testStatus != nil {
                topic.statusIsManual = false
                topic.testStatus = testStatus
                SkillEvidenceService.recordAssessment(for: topic, runID: assessmentRunID, in: modelContext)
            }
        }
        BadgeEvaluator.evaluate(context: modelContext)

        // El número y la banda son locales y determinísticos: quedan guardados aunque el proveedor
        // generativo no esté configurado o no responda. La IA solo redacta la explicación y propone
        // repertorio, por lo que nunca debe impedir terminar el test.
        let overallResultAndSource: (SkillAssessmentCoachService.OverallLevelResult, SkillAssessmentCoachService.OverallLevelSource)? = {
            if let combined = SkillAssessmentCoachService.computeCombinedLevel(topics: topics) {
                return (combined, .combined)
            }
            if let technical = SkillAssessmentCoachService.computeTechnicalLevel(topics: topics) {
                return (technical, .technical)
            }
            if let theory = SkillAssessmentCoachService.computeTheoryLevel(topics: topics) {
                return (theory, .theory)
            }
            return nil
        }()
        if let (overall, _) = overallResultAndSource {
            overallLevelPercentage = overall.percentage
            overallLevelBand = overall.band.rawValue
            overallGuitaristLevel = "\(overall.band.rawValue) · \(Int(overall.percentage.rounded()))% en las preguntas respondidas"
        }

        do {
            try modelContext.save()
            _ = try PracticeCoachCoordinator.reevaluate(
                trigger: .assessmentCompleted,
                in: modelContext
            )
        } catch {
            errorMessage = "No se pudo guardar la autoevaluación: \(error.localizedDescription)"
            return
        }
        hasCompletedAssessment = true

        // Solo la sugerencia de repertorio necesita el catálogo: se pide acá y no al abrir el test.
        let exercises = LibraryLookup.allExercises(in: modelContext)

        do {
            // Gemini pagado aporta el conocimiento musical; si no responde, el orquestador intenta
            // el mejor modelo local que pueda ejecutarse con seguridad en ese momento.
            let backend = try await orchestrator.backend(for: .medium)
            let suggestions = try await SkillAssessmentCoachService.suggestRepertoire(
                topics: topics,
                exercises: exercises,
                songs: songs,
                favoriteBands: bands.filter(\.isFavorite),
                musicalTastes: musicalTastes,
                context: assessmentContext,
                pdfReferences: pdfReferences(forWeakest: topics),
                backend: backend
            )
            RepertoireSuggestionStore.replace(suggestions, in: modelContext)

            if let (overall, source) = overallResultAndSource {
                let songsWithEvidence = songs.filter { !$0.linkedSkillIDs.isEmpty && $0.status.progressWeight >= 3 }.count
                let evidenceSummary = songsWithEvidence > 0
                    ? "\(songsWithEvidence) canción\(songsWithEvidence == 1 ? "" : "es") de su repertorio, ya dominada\(songsWithEvidence == 1 ? "" : "s") o en buen nivel, refuerza\(songsWithEvidence == 1 ? "" : "n") habilidades concretas."
                    : ""
                overallGuitaristLevel = try await SkillAssessmentCoachService.summarizeOverallLevel(
                    topics: topics,
                    overall: overall,
                    source: source,
                    context: assessmentContext,
                    evidenceSummary: evidenceSummary,
                    backend: backend
                )
            }

            finishedMessage = suggestions.isEmpty
                ? "Niveles actualizados."
                : "Niveles actualizados. Revisa el repertorio sugerido en la pestaña Repertorio."
            try modelContext.save()
        } catch {
            finishedMessage = "La estimación del test quedó guardada."
            errorMessage = "No se actualizaron las sugerencias opcionales con IA: \(error.localizedDescription)"
        }
    }

    /// Busca en el texto real de los PDFs importados páginas relacionadas con las habilidades
    /// más débiles, para que el asistente pueda citar páginas concretas en vez de inventarlas.
    private func pdfReferences(forWeakest topics: [SkillTopic]) -> [String] {
        let weakest = topics
            .filter { $0.status != .consolidated }
            .prefix(10)
        guard !books.isEmpty else { return [] }

        var lines: [String] = []
        for topic in weakest {
            for book in books {
                for match in book.matchingPages(for: [topic.name]) {
                    lines.append("- \(book.title), página \(match.page): \"\(match.snippet)\" (relacionado con \(topic.name))")
                }
            }
        }
        return lines
    }
}

private struct AssessmentRow: View {
    @Bindable var topic: SkillTopic

    private var difficulty: DifficultyRating {
        DifficultyClassifier.assess(skillNamed: topic.name).rating
    }

    private var hasGuide: Bool {
        !topic.concept.isEmpty || !topic.correctExecution.isEmpty || !topic.commonErrors.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(topic.name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                DifficultyBadge(rating: difficulty)
                StatusPill(text: topic.status.rawValue, tint: .blue)
            }

            if hasGuide {
                DisclosureGroup("Ver guía") {
                    VStack(alignment: .leading, spacing: 6) {
                        if !topic.concept.isEmpty {
                            guideBlock(title: "Concepto", text: topic.concept)
                        }
                        if !topic.correctExecution.isEmpty {
                            guideBlock(title: "Ejecución correcta", text: topic.correctExecution)
                        }
                        if !topic.commonErrors.isEmpty {
                            guideBlock(title: "Errores frecuentes", text: topic.commonErrors)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
            }

            if topic.assessmentQuestions.isEmpty && topic.activeRotationQuestions.isEmpty {
                Text(topic.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(topic.assessmentQuestions.enumerated()), id: \.offset) { index, question in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(question.question)
                            .font(.caption.weight(.medium))
                        MultipleChoiceOptions(
                            options: question.options,
                            selectedIndex: Binding(
                                get: { topic.assessmentQuestions[index].selectedIndex },
                                set: { topic.assessmentQuestions[index].selectedIndex = $0 }
                            )
                        )
                    }
                    .padding(.vertical, 4)
                }
                if !topic.activeRotationQuestions.isEmpty {
                    Text("Preguntas nuevas de este mes")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.purple)
                        .padding(.top, 2)
                    ForEach(Array(topic.activeRotationQuestions.enumerated()), id: \.offset) { index, question in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(question.question)
                                .font(.caption.weight(.medium))
                            MultipleChoiceOptions(
                                options: question.options,
                                selectedIndex: Binding(
                                    get: { topic.activeRotationQuestions[index].selectedIndex },
                                    set: { topic.activeRotationQuestions[index].selectedIndex = $0 }
                                )
                            )
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func guideBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.bold())
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct MultipleChoiceOptions: View {
    let options: [AssessmentOption]
    @Binding var selectedIndex: Int?
    /// Cuando no es nil y `revealed` es true, colorea la opción correcta en verde y, si el usuario
    /// eligió otra, esa en rojo — usado por las flashcards de teoría para dar feedback inmediato.
    /// El resto de los usos (autoevaluación) no los pasan y se comportan como antes.
    var correctIndex: Int? = nil
    var revealed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    guard !revealed else { return }
                    selectedIndex = index
                } label: {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: iconName(for: index))
                            .foregroundStyle(iconColor(for: index))
                        Text(option.text)
                            .font(.caption)
                            .foregroundStyle(textColor(for: index))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func iconName(for index: Int) -> String {
        if revealed, let correctIndex {
            if index == correctIndex { return "checkmark.circle.fill" }
            if selectedIndex == index { return "xmark.circle.fill" }
        }
        return selectedIndex == index ? "largecircle.fill.circle" : "circle"
    }

    private func iconColor(for index: Int) -> Color {
        if revealed, let correctIndex {
            if index == correctIndex { return .green }
            if selectedIndex == index { return .red }
            return .secondary
        }
        return selectedIndex == index ? .blue : .secondary
    }

    private func textColor(for index: Int) -> Color {
        if revealed, let correctIndex {
            return (index == correctIndex || selectedIndex == index) ? .primary : .secondary
        }
        return selectedIndex == index ? .primary : .secondary
    }
}
