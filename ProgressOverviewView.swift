import SwiftUI
import SwiftData
import Charts

struct ProgressOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigator.self) private var navigator
    @Query(sort: \SkillTopic.name) private var skills: [SkillTopic]
    @Query(sort: \Song.title) private var songs: [Song]
    @Query(sort: \ProgressMilestone.date, order: .reverse) private var milestones: [ProgressMilestone]
    @Query(sort: \PracticeSession.date, order: .reverse) private var sessions: [PracticeSession]
    @Query(sort: \AIArtifact.createdAt, order: .reverse) private var savedArtifacts: [AIArtifact]
    @Query(sort: \Band.name) private var bands: [Band]
    @Query private var flashcardProgress: [TheoryFlashcardProgress]
    @Query private var earProgress: [EarTrainingProgress]
    @Query private var earStatsRecords: [EarTrainingStats]
    @Query private var earnedBadges: [EarnedBadge]

    @StateObject private var orchestrator = AIOrchestrator()

    @State private var showingTimer = false
    @State private var timerTaskID: UUID?
    @State private var skillPracticePeriod: SkillPracticePeriod = .week
    @State private var weeklyNarrative = ""
    @State private var isNarratingWeek = false
    @State private var narrateWeekError = ""

    /// Progreso cruza catálogo, sesiones y habilidades en varias tarjetas; toma el catálogo del
    /// caché compartido en vez de traerlo entero por su cuenta.
    private var exercises: [LibraryExercise] {
        LibraryLookup.Catalog.shared.exercises(in: modelContext)
    }

    private var concepts: [LibraryConcept] {
        LibraryLookup.Catalog.shared.concepts(in: modelContext)
    }

    private var categoryProgress: [CategoryProgress] {
        ProgressAnalytics.categoryProgress(skills: skills, exercises: exercises, songs: songs)
    }

    private var monthlyPoints: [MonthlyLevelUpPoint] {
        ProgressAnalytics.monthlyLevelUps(milestones)
    }

    private var suggestions: [ExerciseSuggestion] {
        ProgressAnalytics.suggestedExercises(skills: skills, exercises: exercises)
    }

    private var skillPracticePoints: [SkillPracticePoint] {
        ProgressAnalytics.skillPracticePoints(
            sessions: sessions,
            exercises: exercises,
            concepts: concepts,
            skills: skills,
            period: skillPracticePeriod
        )
    }

    private var routineSignals: RoutineSignals {
        RoutineAnalytics.computeSignals(sessions: sessions, milestones: milestones)
    }

    private var lastRoutineReview: AIArtifact? {
        savedArtifacts.first { $0.kind == .routineReview }
    }

    /// Puro — no llama a `BadgeEvaluator.evaluate` (que inserta en el contexto) porque esto se
    /// recalcula dentro de `body`. Otorgar insignias nuevas pasa solo en los puntos de guardado real
    /// (sesión, subida de nivel, fin de una sesión de repaso), no al simplemente mostrar Progreso.
    private var badgeDefinitions: [BadgeDefinition] {
        let base = BadgeCatalog.baseDefinitions(
            topics: skills,
            exercises: exercises,
            songs: songs,
            bands: bands,
            sessions: sessions,
            flashcards: flashcardProgress,
            earProgress: earProgress,
            earStats: earStatsRecords.first ?? EarTrainingStats(),
            currentStreakDays: routineSignals.currentStreakDays,
            hadComeback: BadgeEvaluator.hadRecentComeback(sessions: sessions, now: .now)
        )
        return base + BadgeCatalog.metaDefinitions(base: base, milestones: milestones)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                categoryGrid
                skillBreakdownCard
                routineIndicator
                badgesCard

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        suggestionsCard
                            .frame(maxWidth: .infinity)
                        milestonesCard
                            .frame(width: 340)
                    }
                    VStack(spacing: 18) {
                        suggestionsCard
                        milestonesCard
                    }
                }

                if !monthlyPoints.isEmpty {
                    trendChart
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showingTimer) {
            PracticeTimerView(initialTaskID: timerTaskID)
                .frame(minWidth: 500, idealWidth: 580, minHeight: 540)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Progreso")
                .font(.largeTitle.bold())
            Text("Evolución en técnica, teoría, ejercicios y repertorio")
                .foregroundStyle(.secondary)
        }
    }

    /// Aritmética pura (racha + fecha de la última revisión guardada), sin IA — un recordatorio de
    /// texto, no una llamada a modelo, así que no dispara nada solo por mostrarse. El botón lleva a
    /// Profesor IA → Rutina para generar la revisión con Gemini cuando el usuario lo decida.
    private var routineIndicator: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Racha actual: \(routineSignals.currentStreakDays) día\(routineSignals.currentStreakDays == 1 ? "" : "s")")
                        .font(.subheadline.weight(.medium))
                    Text(lastRoutineReview.map {
                        "Última revisión de rutina: hace \(daysAgo($0.createdAt)) día\(daysAgo($0.createdAt) == 1 ? "" : "s")"
                    } ?? "Todavía no revisaste tu rutina con el Profesor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Revisar rutina") { navigator.go(to: .profesor, id: nil) }
                    .buttonStyle(.bordered)
            }
            if routineSignals.hasEnoughData {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Button("Resumen de la semana", systemImage: "sparkles") {
                            Task { await narrateWeek() }
                        }
                        .font(.caption)
                        .disabled(isNarratingWeek)
                        if isNarratingWeek { ProgressView().controlSize(.small) }
                    }
                    if !weeklyNarrative.isEmpty {
                        Text(weeklyNarrative)
                            .font(.callout)
                            .foregroundStyle(.primary)
                    }
                    if !narrateWeekError.isEmpty {
                        Text(narrateWeekError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.top, 8)
            }
            }
        }
    }

    @MainActor
    private func narrateWeek() async {
        narrateWeekError = ""
        isNarratingWeek = true
        defer { isNarratingWeek = false }
        do {
            let backend = try await orchestrator.backend(for: .light)
            weeklyNarrative = try await RoutineCoachService.narrateWeek(signals: routineSignals, backend: backend)
        } catch {
            narrateWeekError = error.localizedDescription
        }
    }

    private func daysAgo(_ date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date), to: Calendar.current.startOfDay(for: .now)).day ?? 0
    }

    private var badgesCard: some View {
        let definitions = badgeDefinitions
        let earnedIDs = Set(earnedBadges.map(\.id))
        return CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Logros", subtitle: "\(earnedIDs.count)/\(definitions.count) en Challenger")
                Text("Cada logro asciende de Hierro IV a Challenger según su progreso.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(BadgeCategory.allCases) { category in
                    let categoryDefinitions = definitions.filter { $0.category == category }
                    if !categoryDefinitions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(category.rawValue)
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                                ForEach(categoryDefinitions) { definition in
                                    BadgeTileView(
                                        definition: definition,
                                        isEarned: earnedIDs.contains(definition.id),
                                        dateEarned: earnedBadges.first { $0.id == definition.id }?.dateEarned,
                                        currentStreakDays: routineSignals.currentStreakDays
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
            ForEach(categoryProgress) { progress in
                CategoryProgressCard(progress: progress)
            }
        }
    }

    /// Desglose de minutos por habilidad puntual (ej. "Alternate picking", no solo "Técnica"),
    /// acotado a hoy/semana/mes con el picker. Solo cuenta sesiones vinculadas a un ejercicio o
    /// concepto de Biblioteca que matchea alguna habilidad del catálogo — ver
    /// `ProgressAnalytics.resolvedSkill`.
    private var skillBreakdownCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Minutos por habilidad", subtitle: "según ejercicios y conceptos de Biblioteca vinculados a tus sesiones")

                Picker("Período", selection: $skillPracticePeriod) {
                    ForEach(SkillPracticePeriod.allCases) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                let points = skillPracticePoints
                if points.isEmpty {
                    EmptyStateView(
                        icon: "chart.bar.xaxis",
                        title: "Sin datos todavía",
                        message: "Registra sesiones vinculadas a un ejercicio o concepto de Biblioteca para ver aquí cuánto practicaste cada habilidad."
                    )
                    .frame(height: 140)
                } else {
                    ForEach(points) { point in
                        SkillPracticeRow(point: point)
                        if point.id != points.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var suggestionsCard: some View {
        let items = suggestions
        return CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Sugerencias de práctica", subtitle: "según tus habilidades más débiles")
                if items.isEmpty {
                    EmptyStateView(icon: "sparkles", title: "Sin sugerencias", message: "Agrega ejercicios a tu biblioteca para recibir sugerencias.")
                        .frame(height: 160)
                } else {
                    ForEach(items) { suggestion in
                        SuggestionRow(suggestion: suggestion) { addToPlan(suggestion) }
                        if suggestion.id != items.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var milestonesCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Subidas de nivel recientes")
                let recent = Array(milestones.prefix(12))
                if recent.isEmpty {
                    EmptyStateView(icon: "arrow.up.circle", title: "Sin registros", message: "Aquí verás cada vez que subas de nivel en una habilidad, ejercicio o canción.")
                        .frame(height: 160)
                } else {
                    ForEach(recent) { milestone in
                        MilestoneRow(milestone: milestone)
                        if milestone.id != recent.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var trendChart: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Subidas de nivel por mes")
                Chart(monthlyPoints) { point in
                    BarMark(
                        x: .value("Mes", point.monthStart, unit: .month),
                        y: .value("Subidas", point.count)
                    )
                    .foregroundStyle(.purple.gradient)
                    .cornerRadius(5)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { value in
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
                .frame(height: 200)
            }
        }
    }

    private func addToPlan(_ suggestion: ExerciseSuggestion) {
        let exercise = suggestion.exercise
        let resolution = PracticeTaskDeduplication.resolve(
            candidateTitle: exercise.displayName, candidateSourceKind: .library,
            candidateSourceID: exercise.id, in: modelContext
        )
        if case .keepExisting(let existing) = resolution {
            timerTaskID = existing.id
        } else {
            PracticeTaskDeduplication.apply(resolution, in: modelContext)
            let task = PracticeTask(
                title: exercise.displayName,
                category: .technique,
                plannedMinutes: 15,
                sourceTitle: exercise.bookTitle,
                exerciseTitle: exercise.displayName,
                targetBPM: exercise.targetBPM,
                priority: 0,
                sourceKind: .library,
                sourceID: exercise.id
            )
            modelContext.insert(task)
            timerTaskID = task.id
        }
        showingTimer = true
    }
}

private struct BadgeTileView: View {
    let definition: BadgeDefinition
    let isEarned: Bool
    let dateEarned: Date?
    let currentStreakDays: Int
    @State private var showingDetail = false

    @StateObject private var orchestrator = AIOrchestrator()
    @State private var message = ""
    @State private var isGenerating = false
    @State private var generateError = ""

    var body: some View {
        let rank = isEarned ? BadgeRank.challenger : definition.rank
        Button { showingDetail = true } label: {
            VStack(spacing: 6) {
                Image(systemName: definition.icon)
                    .font(.title2)
                    .foregroundStyle(rank.color.opacity(isEarned ? 1 : 0.78))
                    .frame(width: 44, height: 44)
                    .background(rank.color.opacity(isEarned ? 0.18 : 0.1), in: Circle())
                Text(definition.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isEarned ? .primary : .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(rank.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(rank.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(rank.color.opacity(0.12), in: Capsule())
                if !isEarned, let progress = definition.progress() {
                    Text("\(progress.current)/\(progress.target)\(definition.progressUnit)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingDetail) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: definition.icon).foregroundStyle(rank.color)
                    Text(definition.title).font(.headline)
                }
                StatusPill(text: "Rango: \(rank.label)", tint: rank.color)
                Text(definition.subtitle).font(.callout).foregroundStyle(.secondary)
                if let dateEarned {
                    Text("Challenger alcanzado el \(dateEarned.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let progress = definition.progress() {
                    VStack(alignment: .leading, spacing: 5) {
                        ProgressView(value: min(Double(progress.current), Double(progress.target)), total: Double(progress.target))
                            .tint(rank.color)
                        HStack {
                            Text("Progreso: \(progress.current)/\(progress.target)\(definition.progressUnit)")
                            Spacer()
                            if let next = BadgeRank.nextMilestone(current: progress.current, target: progress.target) {
                                Text("\(next.rank.label) en \(next.required)/\(progress.target)\(definition.progressUnit)")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } else if !isEarned {
                    Text("Completa este desafío para alcanzar Challenger")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if isEarned, let dateEarned {
                    if !message.isEmpty {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.primary)
                    } else {
                        HStack {
                            Button("Generar mensaje", systemImage: "sparkles") {
                                Task { await generateMessage(dateEarned: dateEarned) }
                            }
                            .font(.caption)
                            .disabled(isGenerating)
                            if isGenerating { ProgressView().controlSize(.small) }
                        }
                    }
                    if !generateError.isEmpty {
                        Text(generateError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(16)
            .frame(width: 280)
        }
    }

    @MainActor
    private func generateMessage(dateEarned: Date) async {
        generateError = ""
        isGenerating = true
        defer { isGenerating = false }
        do {
            let backend = try await orchestrator.backend(for: .light)
            message = try await BadgeCoachService.congratulate(
                badge: definition,
                dateEarned: dateEarned,
                currentStreakDays: currentStreakDays,
                backend: backend
            )
        } catch {
            generateError = error.localizedDescription
        }
    }
}

private struct CategoryProgressCard: View {
    let progress: CategoryProgress

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: progress.category.icon)
                        .foregroundStyle(progress.category.color)
                    Text(progress.category.rawValue)
                        .font(.headline)
                    Spacer()
                    Text("\(progress.masteredCount)/\(progress.total)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                StackedWeightBar(weightCounts: progress.weightCounts, total: progress.total)
                    .frame(height: 10)

                Text(progress.total == 0 ? "Sin elementos registrados" : "\(Int(progress.averageProgress * 100))% de dominio promedio")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct StackedWeightBar: View {
    let weightCounts: [Int: Int]
    let total: Int

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(0...5, id: \.self) { weight in
                    let count = weightCounts[weight] ?? 0
                    if count > 0 {
                        Capsule()
                            .fill(color(for: weight))
                            .frame(width: max(4, geo.size.width * (Double(count) / Double(max(total, 1)))))
                    }
                }
            }
        }
        .background(Capsule().fill(.quaternary.opacity(0.3)))
        .clipShape(Capsule())
    }

    private func color(for weight: Int) -> Color {
        switch weight {
        case 5: .green
        case 3, 4: .blue
        case 1, 2: .orange
        default: .gray
        }
    }
}

private struct SuggestionRow: View {
    let suggestion: ExerciseSuggestion
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.exercise.displayName)
                    .font(.subheadline.weight(.medium))
                Text(suggestion.exercise.bookTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(suggestion.reason)
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            Spacer()
            Button("Practicar", systemImage: "play.fill") { onAdd() }
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

private struct SkillPracticeRow: View {
    let point: SkillPracticePoint

    private var domainIcon: String { point.skill.domain == .technique ? "metronome" : "book.closed" }
    private var domainColor: Color { point.skill.domain == .technique ? .blue : .indigo }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: domainIcon)
                .foregroundStyle(domainColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(point.skill.name)
                    .font(.subheadline.weight(.medium))
                Text("\(point.sessionCount) sesión\(point.sessionCount == 1 ? "" : "es")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(point.minutes) min")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct MilestoneRow: View {
    let milestone: ProgressMilestone

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(milestone.category.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(milestone.itemName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text("\(milestone.previousStatusLabel) → \(milestone.newStatusLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !milestone.contextDetail.isEmpty {
                    Text(milestone.contextDetail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(milestone.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}
