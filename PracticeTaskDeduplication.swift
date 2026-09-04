import Foundation
import SwiftData

/// Evita que la app termine mostrando el mismo ejercicio dos veces como tarea pendiente, sin
/// importar de qué lado vino (Biblioteca, Repertorio, Profesor IA, Academia...) — pedido explícito
/// del usuario tras encontrarse el calentamiento cromático duplicado entre Biblioteca y una
/// sugerencia vieja del Profesor IA con un título completamente distinto ("Calentamiento cromático
/// diario" vs "Cromático 1-2-3-4 / 4-3-2-1"). Por eso la coincidencia no es por texto exacto sino por
/// palabras significativas compartidas entre título/`exerciseTitle`.
///
/// Solo compara contra tareas NO completadas: repetir un ejercicio otro día no es un duplicado. Ante
/// una coincidencia, `resolve` decide cuál de las dos conservar en vez de quedarse siempre con la
/// existente: primero por coherencia de origen (Biblioteca/Repertorio/Academia/Clases, que siguen
/// progreso real, le ganan a una sugerencia suelta del Profesor IA o a una tarea manual) y, si ambas
/// comparten ese nivel, por la dificultad real de 10 estrellas (se queda la más accesible). Sin
/// ninguna de esas dos señales, no hay evidencia suficiente para reemplazar nada — se conserva la
/// existente.
enum PracticeTaskDeduplication {
    enum Resolution {
        case none
        case keepExisting(PracticeTask)
        case replaceExisting(PracticeTask)
    }

    /// Palabras genéricas de calentamiento/rutina que no identifican un ejercicio puntual — sin
    /// filtrarlas, "Calentamiento diario" empataría con cualquier otra tarea de calentamiento.
    private static let stopWords: Set<String> = [
        "para", "diario", "diaria", "diarios", "diarias", "todos", "toda", "todas", "cada",
        "dias", "dia", "practica", "practicar", "ejercicio", "ejercicios", "tarea", "sesion",
        "calentamiento", "calentamientos", "rutina"
    ]

    /// Coincide si comparten al menos la mitad de las palabras significativas del más corto de los
    /// dos títulos comparados — umbral relajado a propósito porque el caso real que motivó esto
    /// (mismo ejercicio, títulos casi sin palabras en común) necesita margen, no coincidencia exacta.
    private static let overlapThreshold = 0.5

    /// Punto de entrada que deben usar los sitios que crean tareas: además de detectar la coincidencia,
    /// decide si conviene reemplazar la existente por la candidata o dejar las cosas como están.
    static func resolve(
        candidateTitle: String,
        candidateExerciseTitle: String = "",
        candidateSourceKind: TaskSourceKind = .manual,
        candidateSourceID: UUID? = nil,
        candidateScheduledDate: Date? = nil,
        excluding excludedID: UUID? = nil,
        in context: ModelContext,
        calendar: Calendar = .current
    ) -> Resolution {
        guard let existing = existingPendingTask(
            matchingTitle: candidateTitle, exerciseTitle: candidateExerciseTitle,
            scheduledDate: candidateScheduledDate,
            excluding: excludedID, in: context, calendar: calendar
        ) else { return .none }

        let prefersCandidate = prefersCandidate(
            over: existing,
            candidateSourceKind: candidateSourceKind,
            candidateSourceID: candidateSourceID,
            in: context
        )
        return prefersCandidate ? .replaceExisting(existing) : .keepExisting(existing)
    }

    /// Azúcar para los sitios que llaman a `resolve` justo antes de insertar: borra la tarea vieja si
    /// corresponde reemplazarla y devuelve si hay que insertar la candidata (`false` en `.keepExisting`).
    @discardableResult
    static func apply(_ resolution: Resolution, in context: ModelContext) -> Bool {
        switch resolution {
        case .none:
            return true
        case .replaceExisting(let existing):
            context.delete(existing)
            return true
        case .keepExisting:
            return false
        }
    }

    static func existingPendingTask(
        matchingTitle title: String,
        exerciseTitle: String = "",
        scheduledDate: Date? = nil,
        excluding excludedID: UUID? = nil,
        in context: ModelContext,
        calendar: Calendar = .current
    ) -> PracticeTask? {
        let candidateWordSets = [title, exerciseTitle].map(significantWords).filter { !$0.isEmpty }
        guard !candidateWordSets.isEmpty else { return nil }

        let pending = (try? context.fetch(FetchDescriptor<PracticeTask>(
            predicate: #Predicate { !$0.isCompleted }
        ))) ?? []

        return pending.first { task in
            guard task.id != excludedID else { return false }
            // Un plan semanal puede repetir de forma deliberada el mismo material en días
            // distintos. Cuando el llamador entrega fecha, solo evitamos la duplicación dentro del
            // mismo día; los flujos antiguos que no entregan fecha conservan su comportamiento.
            if let scheduledDate,
               !calendar.isDate(task.scheduledDate, inSameDayAs: scheduledDate) {
                return false
            }
            let existingWordSets = [significantWords(task.title), significantWords(task.exerciseTitle)]
                .filter { !$0.isEmpty }
            return candidateWordSets.contains { candidate in
                existingWordSets.contains { existing in
                    candidate == existing || overlapRatio(candidate, existing) >= overlapThreshold
                }
            }
        }
    }

    private static func prefersCandidate(
        over existing: PracticeTask,
        candidateSourceKind: TaskSourceKind,
        candidateSourceID: UUID?,
        in context: ModelContext
    ) -> Bool {
        let candidateTier = coherenceTier(candidateSourceKind)
        let existingTier = coherenceTier(existing.sourceKind)
        guard candidateTier == existingTier else { return candidateTier > existingTier }

        guard
            let candidateDifficulty = difficulty(sourceKind: candidateSourceKind, sourceID: candidateSourceID, in: context),
            let existingDifficulty = difficulty(sourceKind: existing.sourceKind, sourceID: existing.sourceID, in: context)
        else { return false }

        return candidateDifficulty < existingDifficulty
    }

    /// Prioridad de "coherencia con lo que ya se ha estudiado": material sistemático que sigue
    /// progreso real (Biblioteca, Repertorio, Academia, Clases) le gana a una sugerencia suelta del
    /// Profesor IA, que a su vez le gana a una tarea sin origen rastreable.
    private static func coherenceTier(_ kind: TaskSourceKind) -> Int {
        switch kind {
        case .fretboard, .library, .libraryConcept, .skillLadder, .repertoire, .academia, .clases: 2
        case .profesor: 1
        case .manual: 0
        }
    }

    private static func difficulty(
        sourceKind: TaskSourceKind,
        sourceID: UUID?,
        in context: ModelContext
    ) -> DifficultyRating? {
        guard let sourceID else { return nil }
        switch sourceKind {
        case .library:
            guard let exercise = LibraryLookup.exercise(id: sourceID, in: context) else { return nil }
            let all = LibraryLookup.allExercises(in: context)
            let contexts = DifficultyClassifier.bookContexts(for: all)
            return DifficultyClassifier.assess(
                exercise,
                context: DifficultyClassifier.context(forBook: exercise.bookTitle, in: contexts)
            ).rating
        case .libraryConcept, .academia:
            return LibraryLookup.concept(id: sourceID, in: context).map { DifficultyClassifier.assess($0).rating }
        case .repertoire:
            var descriptor = FetchDescriptor<Song>(predicate: #Predicate { $0.id == sourceID })
            descriptor.fetchLimit = 1
            guard let song = (try? context.fetch(descriptor))?.first else { return nil }
            return SongDifficultyCatalog.assess(song).rating
        case .fretboard, .skillLadder, .clases, .profesor, .manual:
            return nil
        }
    }

    private static func overlapRatio(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(min(a.count, b.count))
    }

    /// Palabras de 4+ letras, sin acentos ni mayúsculas y sin conectores de rutina — así "Calentamiento
    /// cromático diario" y "Cromático 1-2-3-4 / 4-3-2-1" comparten "cromatico" sin que "calentamiento"
    /// (genérico) ni "diario" (conector) generen falsos negativos ni positivos por su cuenta.
    private static func significantWords(_ text: String) -> Set<String> {
        let normalized = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let words = normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 && !stopWords.contains($0) }
        return Set(words)
    }
}
