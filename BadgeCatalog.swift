import Foundation
import SwiftUI

enum BadgeCategory: String, CaseIterable, Identifiable {
    case constancia = "Constancia"
    case tecnica = "Técnica"
    case teoria = "Teoría"
    case repertorio = "Repertorio"
    case biblioteca = "Biblioteca"
    case sesiones = "Sesiones"
    case oido = "Oído"
    case meta = "Meta"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .constancia: "flame.fill"
        case .tecnica: "hand.raised.fingers.spread"
        case .teoria: "book.closed.fill"
        case .repertorio: "music.note.list"
        case .biblioteca: "books.vertical.fill"
        case .sesiones: "clock.fill"
        case .oido: "ear"
        case .meta: "trophy.fill"
        }
    }
}

enum BadgeLeague: Int, CaseIterable {
    case hierro, bronce, plata, oro, platino, esmeralda, diamante, maestro, granMaestro, challenger

    var label: String {
        switch self {
        case .hierro: "Hierro"
        case .bronce: "Bronce"
        case .plata: "Plata"
        case .oro: "Oro"
        case .platino: "Platino"
        case .esmeralda: "Esmeralda"
        case .diamante: "Diamante"
        case .maestro: "Maestro"
        case .granMaestro: "Gran Maestro"
        case .challenger: "Challenger"
        }
    }

    var hasDivisions: Bool {
        rawValue <= BadgeLeague.diamante.rawValue
    }

    var color: Color {
        switch self {
        case .hierro: Color(red: 0.40, green: 0.43, blue: 0.43)
        case .bronce: Color(red: 0.65, green: 0.40, blue: 0.22)
        case .plata: Color(red: 0.62, green: 0.70, blue: 0.75)
        case .oro: Color(red: 0.88, green: 0.66, blue: 0.16)
        case .platino: Color(red: 0.25, green: 0.72, blue: 0.68)
        case .esmeralda: Color(red: 0.10, green: 0.68, blue: 0.43)
        case .diamante: Color(red: 0.39, green: 0.59, blue: 0.95)
        case .maestro: Color(red: 0.64, green: 0.38, blue: 0.88)
        case .granMaestro: Color(red: 0.86, green: 0.25, blue: 0.29)
        case .challenger: Color(red: 0.18, green: 0.72, blue: 0.92)
        }
    }
}

/// Las divisiones se ordenan como se recorren en la escalera: IV es la entrada y I la más alta.
enum BadgeDivision: CaseIterable {
    case four, three, two, one

    var label: String {
        switch self {
        case .four: "IV"
        case .three: "III"
        case .two: "II"
        case .one: "I"
        }
    }
}

/// Rango actual de un logro. Hierro–Diamante tienen cuatro divisiones; los tres rangos superiores
/// no. El progreso se reparte uniformemente por las 31 posiciones y Challenger solo se alcanza al
/// completar el objetivo, nunca por redondeo antes de tiempo.
struct BadgeRank: Identifiable, Equatable, Comparable {
    let league: BadgeLeague
    let division: BadgeDivision?

    static let all: [BadgeRank] = BadgeLeague.allCases.flatMap { league in
        league.hasDivisions
            ? BadgeDivision.allCases.map { BadgeRank(league: league, division: $0) }
            : [BadgeRank(league: league, division: nil)]
    }

    static let lowest = all[0]
    static let challenger = all[all.count - 1]

    var id: String { label }
    var label: String {
        if let division { return "\(league.label) \(division.label)" }
        return league.label
    }
    var color: Color { league.color }

    static func forProgress(current: Int, target: Int) -> BadgeRank {
        guard target > 0 else { return .lowest }
        let fraction = min(max(Double(current) / Double(target), 0), 1)
        let index = min(Int((fraction * Double(all.count - 1)).rounded(.down)), all.count - 1)
        return all[index]
    }

    static func nextMilestone(current: Int, target: Int) -> (rank: BadgeRank, required: Int)? {
        guard target > 0, current < target else { return nil }
        let currentRank = forProgress(current: current, target: target)
        for required in max(current + 1, 0)...target {
            let candidate = forProgress(current: required, target: target)
            if candidate > currentRank { return (candidate, required) }
        }
        return nil
    }

    static func < (lhs: BadgeRank, rhs: BadgeRank) -> Bool {
        guard let left = all.firstIndex(of: lhs), let right = all.firstIndex(of: rhs) else {
            return false
        }
        return left < right
    }
}

/// Una insignia posible: criterio 100% determinístico sobre datos ya existentes, sin IA — mismo
/// espíritu que el resto de la app. `isMet`/`progress` son closures (no un `struct` de contexto)
/// porque varias insignias son "una por habilidad"/"una por módulo" y se generan mapeando sobre los
/// datos vivos al momento de construir el catálogo, capturando directamente el `SkillTopic`/`Band`
/// que les corresponde — no todas encajan en un contexto agregado plano.
struct BadgeDefinition: Identifiable {
    let id: String
    let category: BadgeCategory
    let title: String
    let subtitle: String
    let icon: String
    let isMet: () -> Bool
    /// (actual, meta) para mostrar progreso en insignias no ganadas, ej. "18/30 días". `nil` cuando
    /// no hay una magnitud continua clara (insignias binarias).
    var progress: () -> (current: Int, target: Int)? = { nil }
    var progressUnit: String = ""

    /// Cada insignia recorre su propia escalera. Las binarias permanecen en Hierro IV hasta
    /// cumplirse; las que tienen una magnitud continua avanzan por las 31 posiciones.
    var rank: BadgeRank {
        if let progress = progress() {
            return BadgeRank.forProgress(current: progress.current, target: progress.target)
        }
        return isMet() ? .challenger : .lowest
    }
}

/// Catálogo completo. `baseDefinitions` es puro (no toca `ModelContext`) para poder usarse tanto en
/// la UI de Progreso (renderizar insignias ganadas/pendientes) como en `BadgeEvaluator` (otorgar) sin
/// duplicar criterios en dos lugares. Las de categoría `.meta` se generan aparte porque necesitan
/// conocer el resultado de las demás.
enum BadgeCatalog {
    static func baseDefinitions(
        topics: [SkillTopic],
        exercises: [LibraryExercise],
        songs: [Song],
        bands: [Band],
        sessions: [PracticeSession],
        flashcards: [TheoryFlashcardProgress],
        earProgress: [EarTrainingProgress],
        earStats: EarTrainingStats,
        currentStreakDays: Int,
        hadComeback: Bool
    ) -> [BadgeDefinition] {
        constancia(currentStreakDays: currentStreakDays, hadComeback: hadComeback) +
        tecnica(topics: topics) +
        teoria(topics: topics, flashcards: flashcards) +
        repertorio(songs: songs, bands: bands) +
        biblioteca(exercises: exercises) +
        sesiones(sessions: sessions) +
        oido(earProgress: earProgress, earStats: earStats)
    }

    static func metaDefinitions(base: [BadgeDefinition], milestones: [ProgressMilestone], calendar: Calendar = .current) -> [BadgeDefinition] {
        let categoriesToCheck = BadgeCategory.allCases.filter { $0 != .meta }
        let completedCategory = categoriesToCheck.first { category in
            let defs = base.filter { $0.category == category }
            return !defs.isEmpty && defs.allSatisfy { $0.isMet() }
        }

        let integralWeek: Bool = {
            let grouped = Dictionary(grouping: milestones) { milestone in
                calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: milestone.date)
            }
            return grouped.values.contains { weekMilestones in
                let categories = Set(weekMilestones.map(\.category))
                let hasExerciseOrRepertoire = categories.contains(.exercise) || categories.contains(.repertoire)
                return categories.contains(.technique) && categories.contains(.theory) && hasExerciseOrRepertoire
            }
        }()

        return [
            BadgeDefinition(
                id: "meta-semana-integral",
                category: .meta,
                title: "Semana integral",
                subtitle: "Técnica, teoría y repertorio o ejercicios subieron de nivel la misma semana",
                icon: "calendar.badge.checkmark",
                isMet: { integralWeek },
                progress: { (integralWeek ? 1 : 0, 1) }
            ),
            BadgeDefinition(
                id: "meta-coleccionista",
                category: .meta,
                title: "Coleccionista",
                subtitle: "Todas las insignias de un área completas",
                icon: "trophy.fill",
                isMet: { completedCategory != nil },
                progress: { (completedCategory == nil ? 0 : 1, 1) }
            )
        ]
    }

    // MARK: - Constancia

    private static func constancia(currentStreakDays: Int, hadComeback: Bool) -> [BadgeDefinition] {
        let thresholds = [7, 30, 90, 365]
        let streakBadges = thresholds.map { days in
            BadgeDefinition(
                id: "constancia-racha-\(days)",
                category: .constancia,
                title: "Racha de \(days) días",
                subtitle: "\(days) días seguidos practicando",
                icon: "flame.fill",
                isMet: { currentStreakDays >= days },
                progress: { (min(currentStreakDays, days), days) }
            )
        }
        let comeback = BadgeDefinition(
            id: "constancia-vuelta-al-ruedo",
            category: .constancia,
            title: "Vuelta al ruedo",
            subtitle: "Retomaste la práctica después de una pausa de 14 días o más",
            icon: "arrow.counterclockwise.circle.fill",
            isMet: { hadComeback },
            progress: { (hadComeback ? 1 : 0, 1) }
        )
        return streakBadges + [comeback]
    }

    // MARK: - Técnica

    private static func tecnica(topics: [SkillTopic]) -> [BadgeDefinition] {
        let techniqueTopics = topics.filter { $0.domain == .technique }
        let perSkill = techniqueTopics.map { topic in
            BadgeDefinition(
                id: "tecnica-avanzado-\(topic.id.uuidString)",
                category: .tecnica,
                title: topic.name,
                subtitle: "Nivel Avanzado o superior en esta habilidad",
                icon: "hand.raised.fingers.spread",
                isMet: { topic.status.progressWeight >= SkillMasteryLevel.advanced.progressWeight },
                progress: {
                    (topic.status.progressWeight, SkillMasteryLevel.advanced.progressWeight)
                }
            )
        }
        let average: () -> Double = {
            guard !techniqueTopics.isEmpty else { return 0 }
            let total = techniqueTopics.reduce(0) { $0 + $1.status.progressWeight }
            return Double(total) / Double(techniqueTopics.count * SkillMasteryLevel.consolidated.progressWeight)
        }
        let percentThresholds = [50, 70, 90]
        let percentBadges = percentThresholds.map { percent in
            BadgeDefinition(
                id: "tecnica-nivel-\(percent)",
                category: .tecnica,
                title: "Técnica al \(percent)%",
                subtitle: "Nivel técnico promedio de \(percent)% o más",
                icon: "gauge.with.dots.needle.67percent",
                isMet: { average() >= Double(percent) / 100 },
                progress: { (Int((average() * 100).rounded()), percent) }
            )
        }
        let specialist = BadgeDefinition(
            id: "tecnica-especialista",
            category: .tecnica,
            title: "Especialista",
            subtitle: "3 o más habilidades técnicas en el nivel Consolidado",
            icon: "star.circle.fill",
            isMet: { techniqueTopics.filter { $0.status == .consolidated }.count >= 3 },
            progress: { (techniqueTopics.filter { $0.status == .consolidated }.count, 3) }
        )
        return perSkill + percentBadges + [specialist]
    }

    // MARK: - Teoría

    private static func teoria(topics: [SkillTopic], flashcards: [TheoryFlashcardProgress]) -> [BadgeDefinition] {
        let theoryTopics = topics.filter { $0.domain == .theory }
        let perModule = theoryTopics.map { topic in
            BadgeDefinition(
                id: "teoria-dominado-\(topic.id.uuidString)",
                category: .teoria,
                title: topic.name,
                subtitle: "Módulo de teoría dominado (Consolidado)",
                icon: "book.closed.fill",
                isMet: { topic.status == .consolidated },
                progress: {
                    (topic.status.progressWeight, SkillMasteryLevel.consolidated.progressWeight)
                }
            )
        }
        let masteredFlashcards: () -> Int = { flashcards.filter { $0.boxLevel == 5 }.count }
        let flashcardThresholds = [25, 50, 100]
        let flashcardBadges = flashcardThresholds.map { count in
            BadgeDefinition(
                id: "teoria-flashcards-\(count)",
                category: .teoria,
                title: "\(count) tarjetas dominadas",
                subtitle: "Flashcards de teoría en caja 5",
                icon: "rectangle.on.rectangle",
                isMet: { masteredFlashcards() >= count },
                progress: { (min(masteredFlashcards(), count), count) }
            )
        }
        let average: () -> Double = {
            guard !theoryTopics.isEmpty else { return 0 }
            let total = theoryTopics.reduce(0) { $0 + $1.status.progressWeight }
            return Double(total) / Double(theoryTopics.count * SkillMasteryLevel.consolidated.progressWeight)
        }
        let complete = BadgeDefinition(
            id: "teoria-completo",
            category: .teoria,
            title: "Teórico completo",
            subtitle: "Nivel de teoría promedio de 90% o más",
            icon: "graduationcap.fill",
            isMet: { average() >= 0.9 },
            progress: { (Int((average() * 100).rounded()), 90) }
        )
        return perModule + flashcardBadges + [complete]
    }

    // MARK: - Repertorio

    private static func repertorio(songs: [Song], bands: [Band]) -> [BadgeDefinition] {
        let mastered = songs.filter { $0.status == .mastered }
        let bandGrouped = Dictionary(grouping: mastered.filter { $0.band != nil }, by: { $0.band!.id })
        let bestSectionPercent: () -> Int = {
            songs.compactMap { song -> Int? in
                guard !song.sectionProgress.isEmpty else { return nil }
                let learned = song.sectionProgress.filter(\.isLearned).count
                return Int((Double(learned) / Double(song.sectionProgress.count) * 100).rounded(.down))
            }.max() ?? 0
        }
        let favoriteBandCount: () -> Int = { bandGrouped.values.map(\.count).max() ?? 0 }
        let tributeProgress: () -> (current: Int, target: Int)? = {
            guard let tribute = bands.first(where: { $0.isTributeProject }) else { return nil }
            let tributeSongs = songs.filter { $0.band?.id == tribute.id }
            guard !tributeSongs.isEmpty else { return nil }
            return (tributeSongs.filter { $0.status == .mastered }.count, tributeSongs.count)
        }

        let countThresholds = [1, 5, 10, 25]
        let countBadges = countThresholds.map { count in
            BadgeDefinition(
                id: "repertorio-canciones-\(count)",
                category: .repertorio,
                title: count == 1 ? "Primera canción dominada" : "\(count) canciones dominadas",
                subtitle: "Canciones del repertorio en estado Dominado",
                icon: "music.note.list",
                isMet: { mastered.count >= count },
                progress: { (min(mastered.count, count), count) }
            )
        }
        let completeSection = BadgeDefinition(
            id: "repertorio-cancion-completa",
            category: .repertorio,
            title: "Canción completa",
            subtitle: "Todas las secciones de una canción marcadas como aprendidas",
            icon: "checklist",
            isMet: { bestSectionPercent() == 100 },
            progress: { (bestSectionPercent(), 100) }
        )
        let favoriteBand = BadgeDefinition(
            id: "repertorio-banda-favorita",
            category: .repertorio,
            title: "A fondo con tu banda favorita",
            subtitle: "3 o más canciones dominadas de la misma banda",
            icon: "person.3.fill",
            isMet: { favoriteBandCount() >= 3 },
            progress: { (favoriteBandCount(), 3) }
        )
        let tributeSetlist = BadgeDefinition(
            id: "repertorio-setlist-tributo",
            category: .repertorio,
            title: "Setlist listo",
            subtitle: "Todas las canciones de tu banda tributo están dominadas",
            icon: "star.square.fill",
            isMet: {
                guard let progress = tributeProgress() else { return false }
                return progress.current == progress.target
            },
            progress: tributeProgress
        )
        return countBadges + [completeSection, favoriteBand, tributeSetlist]
    }

    // MARK: - Biblioteca

    private static func biblioteca(exercises: [LibraryExercise]) -> [BadgeDefinition] {
        let mastered = exercises.filter { $0.status == .mastered }
        let byBook = Dictionary(grouping: exercises, by: \.bookTitle)
        let masteredBookCount: () -> Int = { Set(mastered.map(\.bookTitle)).count }
        let bestBookPercent: () -> Int = {
            byBook.values.map { group in
                let completed = group.filter { $0.status == .mastered }.count
                return Int((Double(completed) / Double(group.count) * 100).rounded(.down))
            }.max() ?? 0
        }

        let countThresholds = [10, 50, 100, 250]
        let countBadges = countThresholds.map { count in
            BadgeDefinition(
                id: "biblioteca-ejercicios-\(count)",
                category: .biblioteca,
                title: "\(count) ejercicios dominados",
                subtitle: "Ejercicios de Biblioteca en estado Dominado",
                icon: "books.vertical.fill",
                isMet: { mastered.count >= count },
                progress: { (min(mastered.count, count), count) }
            )
        }
        let explorer = BadgeDefinition(
            id: "biblioteca-explorador",
            category: .biblioteca,
            title: "Explorador",
            subtitle: "Ejercicios dominados de 5 o más libros distintos",
            icon: "map.fill",
            isMet: { masteredBookCount() >= 5 },
            progress: { (masteredBookCount(), 5) }
        )
        let fullBook = BadgeDefinition(
            id: "biblioteca-libro-completo",
            category: .biblioteca,
            title: "Libro completo",
            subtitle: "Todos los ejercicios de un libro dominados",
            icon: "book.closed.fill",
            isMet: { bestBookPercent() == 100 },
            progress: { (bestBookPercent(), 100) }
        )
        return countBadges + [explorer, fullBook]
    }

    // MARK: - Sesiones

    private static func sesiones(sessions: [PracticeSession]) -> [BadgeDefinition] {
        let totalMinutes: () -> Int = { sessions.reduce(0) { $0 + $1.durationMinutes } }
        let hourThresholds = [10, 50, 100, 500]
        let hourBadges = hourThresholds.map { hours in
            BadgeDefinition(
                id: "sesiones-horas-\(hours)",
                category: .sesiones,
                title: "\(hours) horas practicadas",
                subtitle: "Suma total de tiempo de práctica registrado",
                icon: "clock.fill",
                isMet: { totalMinutes() >= hours * 60 },
                progress: { (min(totalMinutes(), hours * 60), hours * 60) },
                progressUnit: " min"
            )
        }
        let steady = BadgeDefinition(
            id: "sesiones-metronomo-firme",
            category: .sesiones,
            title: "Metrónomo firme",
            subtitle: "Una sesión terminada sin bajar el tempo con el que empezaste",
            icon: "metronome.fill",
            isMet: { sessions.contains { $0.startBPM > 0 && $0.endBPM >= $0.startBPM } },
            progress: { (sessions.contains { $0.startBPM > 0 && $0.endBPM >= $0.startBPM } ? 1 : 0, 1) }
        )
        return hourBadges + [steady]
    }

    // MARK: - Oído

    private static func oido(earProgress: [EarTrainingProgress], earStats: EarTrainingStats) -> [BadgeDefinition] {
        func accuracy(_ id: String) -> Double? {
            guard let item = earProgress.first(where: { $0.id == id }) else { return nil }
            let total = item.correctCount + item.wrongCount
            guard total >= 3 else { return nil }
            return Double(item.correctCount) / Double(total)
        }
        let masteredIntervalCount: () -> Int = {
            EarInterval.allCases.filter { (accuracy(EarTrainingItem.interval($0).id) ?? 0) > 0.8 }.count
        }
        let masteredChordCount: () -> Int = {
            EarChordQuality.allCases.filter { (accuracy(EarTrainingItem.chord($0).id) ?? 0) > 0.8 }.count
        }

        let first = BadgeDefinition(
            id: "oido-primer-ejercicio",
            category: .oido,
            title: "Primer oído",
            subtitle: "Completaste tu primera pregunta de Entrenamiento de oído",
            icon: "ear",
            isMet: { earStats.totalAnswered >= 1 },
            progress: { (min(earStats.totalAnswered, 1), 1) }
        )
        let streakThresholds = [10, 25]
        let streakBadges = streakThresholds.map { count in
            BadgeDefinition(
                id: "oido-racha-\(count)",
                category: .oido,
                title: "\(count) aciertos seguidos",
                subtitle: "Racha de respuestas correctas en Entrenamiento de oído",
                icon: "waveform",
                isMet: { earStats.bestStreak >= count },
                progress: { (min(earStats.bestStreak, count), count) }
            )
        }
        let intervalsMastered = BadgeDefinition(
            id: "oido-intervalos-dominados",
            category: .oido,
            title: "Intervalos dominados",
            subtitle: "Los 11 intervalos con más de 80% de acierto",
            icon: "arrow.left.and.right",
            isMet: { masteredIntervalCount() == EarInterval.allCases.count },
            progress: { (masteredIntervalCount(), EarInterval.allCases.count) }
        )
        let chordsMastered = BadgeDefinition(
            id: "oido-acordes-dominados",
            category: .oido,
            title: "Acordes dominados",
            subtitle: "Las 5 calidades de acorde con más de 80% de acierto",
            icon: "pianokeys",
            isMet: { masteredChordCount() == EarChordQuality.allCases.count },
            progress: { (masteredChordCount(), EarChordQuality.allCases.count) }
        )
        return [first] + streakBadges + [intervalsMastered, chordsMastered]
    }
}
