import Foundation

/// Un ajuste a la RUTINA (cadencia, día de la semana, mezcla de categorías) — no un ejercicio
/// puntual, para eso ya existen el Asistente de progreso del Dashboard y el plan semanal.
struct RoutineAdjustment: Codable, Identifiable {
    var id: UUID = UUID()
    var observation: String
    var adjustment: String
    /// "" = ajuste transversal a propósito (el modelo lo marcó explícitamente así); un string no
    /// vacío pero no parseable cae a `.technique`, mismo criterio que el resto del parseo JSON de
    /// la app (`PracticeCategory(rawValue:) ?? .technique`) — nunca el mismo `nil` para dos cosas
    /// distintas.
    var categoryRaw: String = ""
    /// Minutos semanales totales a repartir entre `suggestedDays`, NO minutos de una sola sesión —
    /// rango propio (15-300), distinto del clamp de minutos por sesión que usan
    /// `WeeklyPracticePlanItem`/`PracticeSuggestion` (5-120).
    var suggestedWeeklyMinutes: Int
    var suggestedDays: [String] = []
    /// Material concreto de Biblioteca o Repertorio con el que aterrizar el ajuste ("para esto, toca
    /// esto"). Queda vacío si el modelo no encontró nada adecuado, o si devolvió algo que no coincide
    /// con ningún ítem real del catálogo que se le pasó — nunca se muestra material inventado.
    var material: String = ""
    var isSelected: Bool = true

    var category: PracticeCategory? {
        guard !categoryRaw.isEmpty else { return nil }
        return PracticeCategory(rawValue: categoryRaw) ?? .technique
    }
}

struct GeneratedRoutineReview {
    let summary: String
    let adjustments: [RoutineAdjustment]
}

/// Coach de RUTINA: a diferencia del resto de Profesor IA (que reacciona a una pregunta o arma un
/// plan de ejercicios puntuales), este es el único lugar de la app que razona sobre patrones de
/// comportamiento a lo largo de semanas — a partir de `RoutineAnalytics.computeSignals`, nunca de
/// sesiones crudas. Sigue el mismo patrón prompt→JSON que `WeeklyPracticePlannerService`/
/// `SkillLadderService`.
enum RoutineCoachService {
    static let validDays = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]

    /// Catálogo acotado de material real del alumno para que el modelo pueda aterrizar cada ajuste
    /// en algo concreto en vez de quedarse en generalidades. Acotado a propósito: la Biblioteca tiene
    /// más de dos mil ejercicios importados y mandarlos todos haría un prompt gigante. Se priorizan
    /// los favoritos y lo que está en curso, que es lo que el alumno realmente tiene a mano.
    static func materialCatalog(exercises: [LibraryExercise], songs: [Song], concepts: [LibraryConcept] = [], limit: Int = 45) -> [String] {
        let songLines = songs
            .filter { $0.status != .mastered }
            .prefix(15)
            .map { song in
                let artist = song.artist.isEmpty ? "" : " — \(song.artist)"
                return "Canción: \(song.title)\(artist) (\(song.status.rawValue))"
            }

        let conceptLines = concepts
            .prefix(10)
            .map { concept in "Teoría: \(concept.title) (\(concept.bookTitle))" }

        let favorites = exercises.filter { $0.isFavorite && $0.status != .mastered }
        let inProgress = exercises.filter { !$0.isFavorite && ($0.status == .learning || $0.status == .consolidating || $0.status == .reducedTempo) }
        let exerciseLines = (favorites + inProgress)
            .prefix(max(0, limit - songLines.count - conceptLines.count))
            .map { exercise in
                let technique = exercise.technique.isEmpty ? "" : " (técnica: \(exercise.technique))"
                return "Ejercicio: \(exercise.bookTitle), \(exercise.displayName)\(technique)"
            }

        return Array(songLines) + Array(conceptLines) + Array(exerciseLines)
    }

    static func review(
        signals: RoutineSignals,
        exercises: [LibraryExercise] = [],
        songs: [Song] = [],
        concepts: [LibraryConcept] = [],
        backend: JSONCompletionBackend
    ) async throws -> GeneratedRoutineReview {
        let catalog = materialCatalog(exercises: exercises, songs: songs, concepts: concepts)
        let catalogText = catalog.isEmpty
            ? "El alumno no tiene material registrado — devuelve \"material\": \"\" en todos los ajustes."
            : catalog.map { "- \($0)" }.joined(separator: "\n")

        let prompt = """
        Eres un coach de RUTINA de práctica de guitarra. Todo lo que sigue ya está calculado a partir \
        de datos reales del alumno — no inventes números nuevos, úsalos tal cual. Tu trabajo es \
        detectar entre 2 y 4 patrones de comportamiento sostenidos (no fallas de una habilidad \
        puntual) y proponer un AJUSTE A LA RUTINA para cada uno: un cambio de cadencia, de día de la \
        semana o de mezcla de categorías que se sostenga varias semanas.

        Presta especial atención a las categorías casi sin práctica registrada: Repertorio y Teoría \
        suelen quedar relegadas frente a Técnica y ejercicios sueltos. Si alguna aparece en "casi sin \
        práctica registrada" y hay material real de esa categoría en la lista de abajo, propón al \
        menos un ajuste que la reincorpore a la rutina.

        SEÑALES DE LAS ÚLTIMAS SEMANAS:
        \(RoutineAnalytics.promptSummary(signals))

        MATERIAL QUE EL ALUMNO YA TIENE (Biblioteca, Teoría y Repertorio):
        \(catalogText)

        Cada ajuste debe aterrizarse en material concreto: además del cambio de rutina, elige UN ítem \
        de la lista de arriba con el que llevarlo a la práctica, y cópialo EXACTAMENTE como aparece, \
        carácter por carácter, en el campo "material". No inventes ejercicios, libros ni canciones que \
        no estén en esa lista: si ninguno encaja con el ajuste, devuelve "material": "".

        Categorías válidas: \(PracticeCategory.allCases.map(\.rawValue).joined(separator: ", ")).
        Días válidos: \(validDays.joined(separator: ", ")).

        Responde solo JSON:
        {
          "summary": "diagnóstico general de la rutina en una oración",
          "adjustments": [
            {
              "observation": "qué patrón concreto viste, citando el número real de arriba",
              "adjustment": "cambio de rutina sugerido en prosa, no un ejercicio puntual",
              "material": "un ítem copiado exacto de la lista de material, o \\"\\" si ninguno encaja",
              "category": "una categoría válida, o \\"\\" si el ajuste es transversal",
              "suggestedWeeklyMinutes": 20,
              "suggestedDays": ["Martes", "Jueves"]
            }
          ]
        }
        Devuelve entre 2 y 4 ajustes. Cada "observation" tiene que citar un número real de arriba — si \
        no hay datos suficientes para una señal, no la uses como base de ningún ajuste.
        """

        let raw = try await backend.completeJSON(prompt: prompt)
        let object = try JSONAIParser.object(from: raw)
        let rawAdjustments = object["adjustments"] as? [[String: Any]] ?? []

        // Solo se acepta material que exista de verdad en el catálogo que se le pasó. Si el modelo
        // devolvió algo parecido pero no idéntico, o directamente inventado, se descarta y el ajuste
        // queda sin material — antes que mandar al alumno a buscar un ejercicio que no tiene.
        let catalogSet = Set(catalog)

        let adjustments: [RoutineAdjustment] = rawAdjustments.compactMap { item in
            guard let observation = item["observation"] as? String, !observation.isEmpty,
                  let adjustment = item["adjustment"] as? String, !adjustment.isEmpty else { return nil }

            let minutes = min(300, max(15, item["suggestedWeeklyMinutes"] as? Int ?? 30))
            let rawDays = item["suggestedDays"] as? [String] ?? []
            var seenDays = Set<String>()
            let days = rawDays.filter { validDays.contains($0) && seenDays.insert($0).inserted }

            let proposedMaterial = (item["material"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let material = catalogSet.contains(proposedMaterial) ? proposedMaterial : ""

            return RoutineAdjustment(
                observation: observation,
                adjustment: adjustment,
                categoryRaw: item["category"] as? String ?? "",
                suggestedWeeklyMinutes: minutes,
                suggestedDays: days,
                material: material
            )
        }
        guard !adjustments.isEmpty else { throw AIServiceError.invalidResponse }
        return GeneratedRoutineReview(summary: object["summary"] as? String ?? "", adjustments: adjustments)
    }

    /// Versión liviana de `review`: solo texto narrado a partir de las mismas señales ya calculadas,
    /// sin pedirle ajustes de rutina al modelo — para cuando el alumno solo quiere leer "cómo estuvo
    /// mi semana" sin llegar hasta el flujo completo de "Rutina".
    static func narrateWeek(signals: RoutineSignals, backend: JSONCompletionBackend) async throws -> String {
        let prompt = """
        Eres un coach de práctica de guitarra. A partir de las señales de las últimas semanas del \
        alumno (ya calculadas, no inventes números nuevos), escribe un resumen narrado en 2 a 4 \
        oraciones, en español, tono cercano pero objetivo — como si le contaras a la persona cómo \
        estuvo su semana de práctica.

        SEÑALES DE LAS ÚLTIMAS SEMANAS:
        \(RoutineAnalytics.promptSummary(signals))

        Responde solo JSON:
        { "narrative": "resumen narrado en 2 a 4 oraciones" }
        """

        let raw = try await backend.completeJSON(prompt: prompt)
        let object = try JSONAIParser.object(from: raw)
        guard let narrative = object["narrative"] as? String, !narrative.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return narrative
    }
}
