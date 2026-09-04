import Foundation
import SwiftData

/// Evalúa el catálogo completo de insignias (`BadgeCatalog`) contra los datos actuales y otorga
/// (`EarnedBadge`) las que se cumplen y todavía no estaban otorgadas. 100% determinístico, sin IA —
/// se puede llamar seguido sin costo ni efectos raros: no duplica insignias ya ganadas ni las revoca
/// aunque el dato que las originó cambie después. Se llama solo en respuesta a una acción del
/// usuario (guardar sesión, subir de nivel, terminar una sesión de repaso) — nunca desde el `body`
/// de una vista, porque inserta en el `ModelContext`.
enum BadgeEvaluator {
    @discardableResult
    static func evaluate(context: ModelContext, now: Date = .now) -> [BadgeDefinition] {
        let topics = (try? context.fetch(FetchDescriptor<SkillTopic>())) ?? []
        let exercises = (try? context.fetch(FetchDescriptor<LibraryExercise>())) ?? []
        let songs = (try? context.fetch(FetchDescriptor<Song>())) ?? []
        let bands = (try? context.fetch(FetchDescriptor<Band>())) ?? []
        let sessions = (try? context.fetch(FetchDescriptor<PracticeSession>())) ?? []
        let milestones = (try? context.fetch(FetchDescriptor<ProgressMilestone>())) ?? []
        let flashcards = (try? context.fetch(FetchDescriptor<TheoryFlashcardProgress>())) ?? []
        let earProgress = (try? context.fetch(FetchDescriptor<EarTrainingProgress>())) ?? []
        let earStats = EarTrainingStats.fetchOrCreate(in: context)
        let earned = (try? context.fetch(FetchDescriptor<EarnedBadge>())) ?? []
        let earnedIDs = Set(earned.map(\.id))

        let signals = RoutineAnalytics.computeSignals(sessions: sessions, milestones: milestones, now: now)
        let comeback = hadRecentComeback(sessions: sessions, now: now)

        let base = BadgeCatalog.baseDefinitions(
            topics: topics,
            exercises: exercises,
            songs: songs,
            bands: bands,
            sessions: sessions,
            flashcards: flashcards,
            earProgress: earProgress,
            earStats: earStats,
            currentStreakDays: signals.currentStreakDays,
            hadComeback: comeback
        )
        let meta = BadgeCatalog.metaDefinitions(base: base, milestones: milestones)
        let all = base + meta

        for definition in all where !earnedIDs.contains(definition.id) && definition.isMet() {
            context.insert(EarnedBadge(id: definition.id, dateEarned: now))
        }
        return all
    }

    /// `true` si la racha actual arrancó después de un hueco de 14 días o más sin practicar — pura,
    /// sin efectos, así que también la usa la UI de Progreso para mostrar insignias pendientes sin
    /// tener que reimplementar el cálculo.
    static func hadRecentComeback(sessions: [PracticeSession], calendar: Calendar = .current, now: Date) -> Bool {
        let days = Set(sessions.map { calendar.startOfDay(for: $0.date) }).sorted()
        guard days.count >= 2 else { return false }

        let today = calendar.startOfDay(for: now)
        let daysSinceLastPractice = calendar.dateComponents([.day], from: days[days.count - 1], to: today).day ?? .max
        guard daysSinceLastPractice <= 1 else { return false }

        var streakStart = days[days.count - 1]
        var index = days.count - 1
        while index > 0 {
            let diff = calendar.dateComponents([.day], from: days[index - 1], to: days[index]).day ?? 0
            if diff == 1 {
                streakStart = days[index - 1]
                index -= 1
            } else {
                break
            }
        }
        guard index > 0 else { return false }

        let previous = days[index - 1]
        let gap = calendar.dateComponents([.day], from: previous, to: streakStart).day ?? 0
        return gap >= 14
    }
}
