import Foundation

struct CategoryProgress: Identifiable {
    let id = UUID()
    let category: ProgressCategory
    let total: Int
    let masteredCount: Int
    /// Progreso promedio (0-1), usando el peso de cada estado, para representar visualmente
    /// cuánto camino queda incluso cuando nada está "Dominado"/"Consolidado" todavía.
    let averageProgress: Double
    /// Conteo por `progressWeight` (0-5), independiente de si viene de `ExerciseStatus` o
    /// `SkillMasteryLevel`, para poder dibujar la barra apilada sin conocer el enum de origen.
    let weightCounts: [Int: Int]
}

struct MonthlyLevelUpPoint: Identifiable {
    let id = UUID()
    let monthStart: Date
    let count: Int
}

struct ExerciseSuggestion: Identifiable {
    let id = UUID()
    let exercise: LibraryExercise
    let reason: String
}

struct SkillPracticePoint: Identifiable {
    let id: UUID
    let skill: SkillTopic
    let minutes: Int
    let sessionCount: Int
}

enum ProgressAnalytics {
    /// Máximo de `progressWeight` compartido por `ExerciseStatus` y `SkillMasteryLevel` (ambos
    /// enums de 6 bandas, 0-5) — evita tener que pasar el máximo por separado en cada llamada.
    private static let maxWeight = 5

    static func categoryProgress(
        skills: [SkillTopic],
        exercises: [LibraryExercise],
        songs: [Song]
    ) -> [CategoryProgress] {
        let technique = skills.filter { $0.domain == .technique }
        let theory = skills.filter { $0.domain == .theory }

        return [
            build(.technique, weights: technique.map { $0.status.progressWeight }),
            build(.theory, weights: theory.map { $0.status.progressWeight }),
            build(.exercise, weights: exercises.map { $0.status.progressWeight }),
            build(.repertoire, weights: songs.map { $0.status.progressWeight })
        ]
    }

    private static func build(_ category: ProgressCategory, weights: [Int]) -> CategoryProgress {
        var counts: [Int: Int] = [:]
        for weight in weights { counts[weight, default: 0] += 1 }
        let total = weights.count
        let sum = counts.reduce(0) { $0 + $1.key * $1.value }
        let average = total > 0 ? Double(sum) / Double(total * maxWeight) : 0
        return CategoryProgress(
            category: category,
            total: total,
            masteredCount: counts[maxWeight] ?? 0,
            averageProgress: average,
            weightCounts: counts
        )
    }

    static func monthlyLevelUps(_ milestones: [ProgressMilestone], calendar: Calendar = .current) -> [MonthlyLevelUpPoint] {
        guard !milestones.isEmpty else { return [] }
        let grouped = Dictionary(grouping: milestones) { milestone -> Date in
            calendar.dateInterval(of: .month, for: milestone.date)?.start ?? milestone.date
        }
        return grouped
            .map { MonthlyLevelUpPoint(monthStart: $0.key, count: $0.value.count) }
            .sorted { $0.monthStart < $1.monthStart }
    }

    /// Sugiere ejercicios reales de la biblioteca priorizando las habilidades más débiles del
    /// alumno (técnica y teoría). Si ninguna coincide por nombre, respalda con los ejercicios
    /// menos avanzados en general para no dejar la sección vacía.
    static func suggestedExercises(
        skills: [SkillTopic],
        exercises: [LibraryExercise],
        limit: Int = 4
    ) -> [ExerciseSuggestion] {
        let pendingExercises = exercises.filter { $0.status != .mastered }
        guard !pendingExercises.isEmpty else { return [] }

        let contexts = DifficultyClassifier.bookContexts(for: exercises)
        let studentLevel = StudentLevelService.currentRating
        let fitOrder: [DifficultyFit: Int] = [.onLevel: 0, .review: 1, .stretch: 2, .tooHard: 3, .mastered: 4]
        let evidenceTokensByExerciseID = Dictionary(uniqueKeysWithValues: pendingExercises.map {
            ($0.id, Set($0.technique.evidenceTokens))
        })
        var ratingsByExerciseID: [UUID: DifficultyRating] = [:]

        func rating(_ exercise: LibraryExercise) -> DifficultyRating {
            if let cached = ratingsByExerciseID[exercise.id] { return cached }
            let computed = DifficultyClassifier.rating(
                for: exercise,
                context: DifficultyClassifier.context(forBook: exercise.bookTitle, in: contexts)
            )
            ratingsByExerciseID[exercise.id] = computed
            return computed
        }

        func ranked(_ candidates: [LibraryExercise]) -> [LibraryExercise] {
            candidates.sorted { lhs, rhs in
                let left = rating(lhs)
                let right = rating(rhs)
                if let studentLevel {
                    let leftFit = fitOrder[left.fit(forStudentLevel: studentLevel), default: 5]
                    let rightFit = fitOrder[right.fit(forStudentLevel: studentLevel), default: 5]
                    if leftFit != rightFit { return leftFit < rightFit }
                    let leftDistance = abs(left.stars - studentLevel.stars)
                    let rightDistance = abs(right.stars - studentLevel.stars)
                    if leftDistance != rightDistance { return leftDistance < rightDistance }
                }
                if lhs.status.progressWeight != rhs.status.progressWeight {
                    return lhs.status.progressWeight < rhs.status.progressWeight
                }
                return left < right
            }
        }

        func reason(for exercise: LibraryExercise, skillName: String? = nil) -> String {
            let exerciseRating = rating(exercise)
            let fit = studentLevel.map { exerciseRating.fit(forStudentLevel: $0).name }
            return [skillName.map { "Refuerza: \($0)" }, exerciseRating.label, fit]
                .compactMap { $0 }
                .joined(separator: " · ")
        }

        let weakestSkills = skills
            .filter { $0.status.progressWeight < SkillMasteryLevel.consolidated.progressWeight }
            .sorted { $0.status.progressWeight < $1.status.progressWeight }

        var suggestions: [ExerciseSuggestion] = []
        var usedExerciseIDs: Set<UUID> = []

        for skill in weakestSkills {
            guard suggestions.count < limit else { break }
            let skillTokens = Set((skill.name + " " + skill.detail).evidenceTokens)
            guard !skillTokens.isEmpty else { continue }
            let candidates = pendingExercises.filter { exercise in
                !usedExerciseIDs.contains(exercise.id) &&
                !(evidenceTokensByExerciseID[exercise.id] ?? []).isDisjoint(with: skillTokens)
            }
            guard let match = ranked(candidates).first else { continue }
            usedExerciseIDs.insert(match.id)
            suggestions.append(ExerciseSuggestion(exercise: match, reason: reason(for: match, skillName: skill.name)))
        }

        if suggestions.count < limit {
            let fallback = ranked(pendingExercises.filter { !usedExerciseIDs.contains($0.id) })
            for exercise in fallback {
                guard suggestions.count < limit else { break }
                suggestions.append(ExerciseSuggestion(exercise: exercise, reason: reason(for: exercise)))
            }
        }

        return suggestions
    }

    /// Resuelve a qué habilidad puntual del catálogo (no solo la categoría amplia) corresponde una
    /// sesión, con el mismo emparejamiento por texto que `suggestedExercises` ya usa para evidencia
    /// práctica: `technique`↔`skill.name` para ejercicios de Biblioteca, `category`↔`skill.name` para
    /// conceptos de teoría. Sesiones sin ejercicio/concepto vinculado (registro libre, repertorio,
    /// Academia, Profesor IA, Clases) no se resuelven a ninguna habilidad — ver
    /// `TaskSourceKind`/`PracticeSession.sourceKind`.
    static func resolvedSkill(
        for session: PracticeSession,
        exercises: [LibraryExercise],
        concepts: [LibraryConcept],
        skills: [SkillTopic]
    ) -> SkillTopic? {
        guard let sourceID = session.sourceID else { return nil }
        switch session.sourceKind {
        case .library:
            guard let exercise = exercises.first(where: { $0.id == sourceID }), !exercise.technique.isEmpty else { return nil }
            return skills.first {
                $0.domain == .technique &&
                ($0.name.localizedCaseInsensitiveContains(exercise.technique) ||
                 exercise.technique.localizedCaseInsensitiveContains($0.name))
            }
        case .libraryConcept:
            guard let concept = concepts.first(where: { $0.id == sourceID }), !concept.category.isEmpty else { return nil }
            return skills.first {
                $0.domain == .theory &&
                ($0.name.localizedCaseInsensitiveContains(concept.category) ||
                 concept.category.localizedCaseInsensitiveContains($0.name))
            }
        default:
            return nil
        }
    }

    /// Minutos y cantidad de sesiones por habilidad puntual, acotado al período elegido (hoy/semana/
    /// mes), ordenado de mayor a menor dedicación. Solo incluye habilidades con al menos una sesión
    /// resuelta en el período.
    static func skillPracticePoints(
        sessions: [PracticeSession],
        exercises: [LibraryExercise],
        concepts: [LibraryConcept],
        skills: [SkillTopic],
        period: SkillPracticePeriod
    ) -> [SkillPracticePoint] {
        let scoped = PracticeAnalytics.sessions(in: period, from: sessions)
        var minutesBySkillID: [UUID: Int] = [:]
        var countBySkillID: [UUID: Int] = [:]
        var skillsByID: [UUID: SkillTopic] = [:]

        for session in scoped {
            guard let skill = resolvedSkill(for: session, exercises: exercises, concepts: concepts, skills: skills) else { continue }
            minutesBySkillID[skill.id, default: 0] += session.durationMinutes
            countBySkillID[skill.id, default: 0] += 1
            skillsByID[skill.id] = skill
        }

        return skillsByID.values
            .map { skill in
                SkillPracticePoint(
                    id: skill.id,
                    skill: skill,
                    minutes: minutesBySkillID[skill.id] ?? 0,
                    sessionCount: countBySkillID[skill.id] ?? 0
                )
            }
            .sorted { $0.minutes > $1.minutes }
    }
}
