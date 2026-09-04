import SwiftUI
import SwiftData

/// Entrenamiento de oído: reconocimiento de intervalos y acordes por audio, mismo mecanismo de
/// repetición espaciada (caja Leitner) que `TheoryFlashcardsView`, aplicado a los 16 ítems fijos de
/// `EarTrainingItem.all` en vez de preguntas de texto. Síntesis 100% local
/// (`EarTrainingAudioEngine`, mismo patrón que `MetronomeEngine`), sin archivos de audio ni IA.
struct AcademyEarTrainingView: View {
    @Query private var progressRecords: [EarTrainingProgress]
    @Environment(\.modelContext) private var modelContext

    private enum SessionPhase { case notStarted, reviewing, finished }

    @State private var phase: SessionPhase = .notStarted
    @State private var session: [EarTrainingQuestion] = []
    @State private var currentIndex = 0
    @State private var selectedOption: EarTrainingItem?
    @State private var revealed = false
    @State private var sessionCorrect = 0
    @State private var audioEngine = EarTrainingAudioEngine()

    private let sessionSize = 12

    var body: some View {
        content
            .onDisappear { audioEngine.stop() }
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
        let ranked = EarTrainingScheduler.rankedItems(progress: progressRecords)
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "ear")
                        .font(.system(size: 44))
                        .foregroundStyle(.pink)
                    Text(ranked.dueCount > 0
                         ? "\(ranked.dueCount) ítems para repasar hoy"
                         : "No hay ítems vencidos — puedes practicar igual")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Comenzar sesión") { startSession(with: ranked.items) }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)

                accuracyOverview
            }
            .padding(24)
        }
    }

    private var accuracyOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Precisión por ítem")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(EarTrainingItem.all) { item in
                    let record = progressRecords.first { $0.id == item.id }
                    let total = (record?.correctCount ?? 0) + (record?.wrongCount ?? 0)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.label).font(.caption.weight(.medium)).lineLimit(1)
                        if total > 0, let record {
                            let accuracy = Double(record.correctCount) / Double(total)
                            ProgressView(value: accuracy).tint(accuracy >= 0.8 ? .green : .orange)
                            Text("\(Int(accuracy * 100))%").font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Text("Sin datos").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .background(PracticeTheme.softSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    @ViewBuilder
    private var reviewView: some View {
        if currentIndex < session.count {
            let question = session[currentIndex]
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        StatusPill(text: question.item.kindTitle, tint: .pink)
                        Spacer()
                        Text("\(currentIndex + 1) de \(session.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        play(question)
                    } label: {
                        Label("Repetir", systemImage: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.bordered)

                    Text("¿Qué \(question.item.kindTitle.lowercased()) escuchaste?")
                        .font(.title3.weight(.medium))

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                        ForEach(question.item.siblingOptions) { option in
                            answerButton(option, for: question)
                        }
                    }

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

    private func answerButton(_ option: EarTrainingItem, for question: EarTrainingQuestion) -> some View {
        let isCorrectOption = option.id == question.item.id
        return Button {
            guard !revealed else { return }
            select(option, for: question)
        } label: {
            HStack {
                Image(systemName: answerIcon(option: option, isCorrectOption: isCorrectOption))
                    .foregroundStyle(answerColor(option: option, isCorrectOption: isCorrectOption))
                Text(option.label)
                Spacer()
            }
            .padding(9)
            .background(answerColor(option: option, isCorrectOption: isCorrectOption).opacity(revealed ? 0.1 : 0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func answerIcon(option: EarTrainingItem, isCorrectOption: Bool) -> String {
        guard revealed else { return selectedOption?.id == option.id ? "circle.inset.filled" : "circle" }
        if isCorrectOption { return "checkmark.circle.fill" }
        if selectedOption?.id == option.id { return "xmark.circle.fill" }
        return "circle"
    }

    private func answerColor(option: EarTrainingItem, isCorrectOption: Bool) -> Color {
        guard revealed else { return selectedOption?.id == option.id ? .pink : .secondary }
        if isCorrectOption { return .green }
        if selectedOption?.id == option.id { return .red }
        return .secondary
    }

    private var summaryView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: sessionCorrect == session.count ? "star.fill" : "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(.pink)
            Text("\(sessionCorrect) de \(session.count) correctas")
                .font(.title2.bold())
            Button("Repasar de nuevo") { phase = .notStarted }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(30)
    }

    private func startSession(with items: [EarTrainingItem]) {
        session = Array(items.prefix(sessionSize)).map { EarTrainingQuestion.random(item: $0) }
        currentIndex = 0
        selectedOption = nil
        revealed = false
        sessionCorrect = 0
        phase = .reviewing
        if let first = session.first { play(first) }
    }

    private func play(_ question: EarTrainingQuestion) {
        switch question.item {
        case .interval(let interval):
            audioEngine.playInterval(rootMidi: question.rootMidi, semitones: interval.semitones)
        case .chord(let quality):
            audioEngine.playChord(rootMidi: question.rootMidi, semitoneOffsets: quality.semitoneOffsets)
        }
    }

    private func select(_ option: EarTrainingItem, for question: EarTrainingQuestion) {
        selectedOption = option
        revealed = true
        let isCorrect = option.id == question.item.id
        if isCorrect { sessionCorrect += 1 }

        let progress = progressRecords.first { $0.id == question.item.id } ?? {
            let created = EarTrainingProgress(id: question.item.id)
            modelContext.insert(created)
            return created
        }()
        let wasDue = progress.lastReviewedDate != nil && progress.nextReviewDate <= .now
        EarTrainingScheduler.record(progress, isCorrect: isCorrect)
        SkillEvidenceService.recordEarTraining(
            item: question.item,
            isCorrect: isCorrect,
            wasDue: wasDue,
            in: modelContext
        )

        let stats = EarTrainingStats.fetchOrCreate(in: modelContext)
        stats.record(isCorrect: isCorrect)
    }

    private func advance() {
        if currentIndex == session.count - 1 {
            phase = .finished
            BadgeEvaluator.evaluate(context: modelContext)
        } else {
            currentIndex += 1
            selectedOption = nil
            revealed = false
            play(session[currentIndex])
        }
    }
}
