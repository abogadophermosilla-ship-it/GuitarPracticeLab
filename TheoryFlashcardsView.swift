import SwiftUI
import SwiftData

/// Sesión de flashcards de teoría con repetición espaciada simple (caja Leitner, "Fase C" del plan
/// de integración de Ollama) — reutiliza las preguntas del Test Integral de teoría ya existentes en
/// `SkillTopic.assessmentQuestions`, no agrega contenido nuevo. 100% determinístico, sin IA.
struct TheoryFlashcardsView: View {
    @Query private var topics: [SkillTopic]
    @Query private var progressRecords: [TheoryFlashcardProgress]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private enum SessionPhase { case notStarted, reviewing, finished }

    @State private var phase: SessionPhase = .notStarted
    @State private var session: [TheoryFlashcard] = []
    @State private var currentIndex = 0
    @State private var selectedOptionIndex: Int?
    @State private var revealed = false
    @State private var sessionCorrect = 0

    private let sessionSize = 12

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Flashcards de teoría")
                    .font(.title2.bold())
                if phase == .reviewing {
                    Text("Tarjeta \(currentIndex + 1) de \(session.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Cerrar") { dismiss() }
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .notStarted: startView
        case .reviewing: reviewView
        case .finished: summaryView
        }
    }

    private var startView: some View {
        let ranked = TheoryFlashcardScheduler.rankedCards(topics: topics, progress: progressRecords)
        return VStack(spacing: 16) {
            Spacer()
            if ranked.cards.isEmpty {
                EmptyStateView(
                    icon: "rectangle.on.rectangle",
                    title: "Sin tarjetas",
                    message: "Todavía no hay preguntas de teoría cargadas."
                )
            } else {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 44))
                    .foregroundStyle(.indigo)
                Text(ranked.dueCount > 0
                     ? "\(ranked.dueCount) tarjetas para repasar hoy"
                     : "No hay tarjetas vencidas — puedes practicar igual")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Comenzar sesión") { startSession(with: ranked.cards) }
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding(30)
    }

    @ViewBuilder
    private var reviewView: some View {
        if currentIndex < session.count {
            let card = session[currentIndex]
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    StatusPill(text: card.topic.name, tint: .indigo)
                    Text(card.question.question)
                        .font(.title3.weight(.medium))
                    MultipleChoiceOptions(
                        options: card.question.options,
                        selectedIndex: Binding(
                            get: { selectedOptionIndex },
                            set: { select($0, for: card) }
                        ),
                        correctIndex: card.correctIndex,
                        revealed: revealed
                    )
                    if revealed {
                        Button(currentIndex == session.count - 1 ? "Terminar" : "Siguiente") {
                            advance()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(24)
            }
        }
    }

    private var summaryView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: sessionCorrect == session.count ? "star.fill" : "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(.indigo)
            Text("\(sessionCorrect) de \(session.count) correctas")
                .font(.title2.bold())
            HStack(spacing: 12) {
                Button("Repasar de nuevo") { phase = .notStarted }
                    .buttonStyle(.bordered)
                Button("Cerrar") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding(30)
    }

    private func startSession(with cards: [TheoryFlashcard]) {
        session = Array(cards.prefix(sessionSize))
        currentIndex = 0
        selectedOptionIndex = nil
        revealed = false
        sessionCorrect = 0
        phase = .reviewing
    }

    private func select(_ index: Int?, for card: TheoryFlashcard) {
        guard !revealed, let index else { return }
        selectedOptionIndex = index
        revealed = true
        let isCorrect = index == card.correctIndex
        if isCorrect { sessionCorrect += 1 }
        let progress = progressRecords.first { $0.id == card.id } ?? {
            let created = TheoryFlashcardProgress(topicID: card.topic.id, questionIndex: card.questionIndex)
            modelContext.insert(created)
            return created
        }()
        let wasDue = progress.lastReviewedDate != nil && progress.nextReviewDate <= .now
        TheoryFlashcardScheduler.record(progress, isCorrect: isCorrect)
        SkillEvidenceService.recordTheoryReview(
            topicID: card.topic.id,
            isCorrect: isCorrect,
            wasDue: wasDue,
            in: modelContext
        )
    }

    private func advance() {
        if currentIndex == session.count - 1 {
            phase = .finished
            BadgeEvaluator.evaluate(context: modelContext)
        } else {
            currentIndex += 1
            selectedOptionIndex = nil
            revealed = false
        }
    }
}
