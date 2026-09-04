import Foundation

struct AssessmentAnalysis {
    struct RepertoireSuggestion {
        let title: String
        let artist: String
        let reason: String
        let targetSkill: String
    }

    let repertoire: [RepertoireSuggestion]
}

enum SkillAssessmentSummaryError: LocalizedError {
    case emptyResponse

    var errorDescription: String? {
        "El asistente no devolvió una lectura de nivel general válida."
    }
}

enum SkillAssessmentCoachService {
    /// Las 12 habilidades "fundamentos" del Test Integral (85% del nivel general) y las 6 de
    /// "especialización" (15%, se usan solo las 3 mejores) — nombres exactos tal como quedan
    /// sembrados en `SeedService`. Los nombres deben coincidir literalmente para que la fórmula
    /// encuentre cada habilidad.
    static let fundamentosSkillNames = [
        "Postura, relajación y mecánica general",
        "Sincronización entre ambas manos",
        "Ritmo, subdivisión y groove",
        "Acordes y guitarra rítmica",
        "Muting y palm muting",
        "Alternate picking",
        "Downpicking, tremolo picking y gallops",
        "Legato",
        "Slides y cambios de posición",
        "Bending",
        "Vibrato",
        "Aplicación musical, oído, teoría y repertorio"
    ]

    static let especializacionSkillNames = [
        "String skipping",
        "Economy picking",
        "Sweep picking",
        "Tapping",
        "Armónicos",
        "Hybrid picking, fingerstyle y palanca"
    ]

    struct OverallLevelResult {
        let percentage: Double
        let band: OverallLevelBand
    }

    /// Qué test(s) produjeron un `OverallLevelResult`, para que `summarizeOverallLevel` redacte la
    /// lectura hablando del test correcto en vez de asumir siempre técnica.
    enum OverallLevelSource {
        case technical
        case theory
        case combined
    }

    /// Calcula el nivel real de cada habilidad a partir del puntaje obtenido en sus preguntas de
    /// opción múltiple (fijas, no generadas), sin necesidad de IA — instantáneo y determinístico.
    /// El máximo posible sale de las propias opciones de cada pregunta, no de una escala fija. Las
    /// bandas difieren por dominio porque los dos tests del usuario usan escalas distintas: técnica
    /// reproduce sus rangos 0-3/4-7/8-11/12-15/16-18/19-20 sobre 20; teoría usa cada punto entero
    /// (0-5) como su propia banda.
    static func computeStatus(for topic: SkillTopic) -> SkillMasteryLevel? {
        guard let (earned, maxPossible) = pointsEarned(for: topic), maxPossible > 0 else { return nil }
        let ratio = Double(earned) / Double(maxPossible)
        switch topic.domain {
        case .theory:
            switch ratio {
            case 0.9...: return .consolidated
            case 0.7..<0.9: return .advanced
            case 0.5..<0.7: return .intermediate
            case 0.3..<0.5: return .basic
            case 0.1..<0.3: return .initial
            default: return .notStarted
            }
        case .technique:
            switch ratio {
            case 0.925...: return .consolidated
            case 0.775..<0.925: return .advanced
            case 0.575..<0.775: return .intermediate
            case 0.375..<0.575: return .basic
            case 0.175..<0.375: return .initial
            default: return .notStarted
            }
        }
    }

    /// Puntos obtenidos y máximo posible para una habilidad, contando solo preguntas respondidas.
    /// Suma tanto las preguntas fijas del banco (`assessmentQuestions`, nunca se tocan) como la
    /// muestra rotativa vigente (`activeRotationQuestions`, ver `SkillAssessmentQuestionReviewView`)
    /// — ambas cuentan igual para el puntaje, un array separado es solo para no romper los índices de
    /// `TheoryFlashcardProgress` sobre `assessmentQuestions`.
    private static func pointsEarned(for topic: SkillTopic) -> (earned: Int, max: Int)? {
        let answered: [(earned: Int, max: Int)] = (topic.assessmentQuestions + topic.activeRotationQuestions).compactMap { q in
            guard let index = q.selectedIndex, q.options.indices.contains(index) else { return nil }
            guard let maxPoints = q.options.map(\.points).max() else { return nil }
            return (q.options[index].points, maxPoints)
        }
        guard !answered.isEmpty else { return nil }
        return (answered.reduce(0) { $0 + $1.earned }, answered.reduce(0) { $0 + $1.max })
    }

    /// Proporción exacta respondida en el Test Integral para que el libro mayor pueda registrar la
    /// señal sin duplicar ni aproximar la fórmula privada de puntuación.
    static func assessmentRatio(for topic: SkillTopic) -> Double? {
        guard let points = pointsEarned(for: topic), points.max > 0 else { return nil }
        return Double(points.earned) / Double(points.max)
    }

    /// Los 2 módulos de Teoría cuyo puntaje bajo limita el nivel teórico general, y sus nombres
    /// exactos tal como quedan sembrados en `SeedService`.
    private static let theoryNotasModuleName = "Notas musicales y organización del diapasón"
    private static let theoryRitmoModuleName = "Ritmo, figuras y compás"

    /// Fórmula exacta del Test Integral de Técnica: fundamentos (12 habilidades) pesan 85%,
    /// especialización (las 3 mejores de 6) pesa 15%, y luego se aplican las reglas de tope que
    /// degradan el nivel si postura, ritmo o aplicación musical están débiles — todo
    /// determinístico, sin IA.
    static func computeTechnicalLevel(topics: [SkillTopic]) -> OverallLevelResult? {
        func topicPoints(_ name: String) -> (earned: Int, max: Int)? {
            guard let topic = topics.first(where: { $0.name == name }) else { return nil }
            return pointsEarned(for: topic)
        }

        // Promedio de las proporciones de cada habilidad, NO suma de puntos dividida por suma de
        // máximos. Con el banco fijo daba lo mismo (las 12 tenían máximo 20), pero con la rotación
        // mensual cada habilidad puede tener distinta cantidad de preguntas, y agrupar haría que la
        // que más preguntas tenga pese más en el nivel general — bastaba aprobar preguntas nuevas en
        // una habilidad débil para bajar de banda sin haber cambiado de nivel real.
        let fundamentosScores = fundamentosSkillNames.compactMap(topicPoints)
        guard !fundamentosScores.isEmpty else { return nil }
        let fundamentosRatio = fundamentosScores.map(ratio(of:)).reduce(0, +) / Double(fundamentosScores.count)

        let especializacionScores = especializacionSkillNames.compactMap(topicPoints)
        let bestThree = especializacionScores
            .sorted { ratio(of: $0) > ratio(of: $1) }
            .prefix(3)
        let especializacionRatio = bestThree.isEmpty
            ? 0
            : bestThree.map(ratio(of:)).reduce(0, +) / Double(bestThree.count)

        let overallRatio = fundamentosRatio * 0.85 + especializacionRatio * 0.15
        let band = applyTechnicalCappingRules(to: bandForOverallRatio(overallRatio), topics: topics)
        return OverallLevelResult(percentage: overallRatio * 100, band: band)
    }

    /// Fórmula exacta del Test Integral de Teoría: suma directa de los 20 módulos sobre 100 (sin
    /// ponderación por bloques), con las 2 reglas de tope explícitas del documento.
    static func computeTheoryLevel(topics: [SkillTopic]) -> OverallLevelResult? {
        // Promedio de proporciones por módulo, por el mismo motivo que en `computeTechnicalLevel`:
        // con la rotación mensual los módulos dejan de tener todos el mismo máximo.
        let scores = topics.filter { $0.domain == .theory }.compactMap(pointsEarned)
        guard !scores.isEmpty else { return nil }
        let averageRatio = scores.map(ratio(of:)).reduce(0, +) / Double(scores.count)
        let band = applyTheoryCappingRules(to: bandForOverallRatio(averageRatio), topics: topics)
        return OverallLevelResult(percentage: averageRatio * 100, band: band)
    }

    /// Nivel general combinado (Sección X del Test Integral de Teoría): técnica pesa 70%, teoría
    /// pesa 30%. Requiere que ambos tests tengan al menos una respuesta; si solo hay uno de los
    /// dos, el llamador debe usar `computeTechnicalLevel`/`computeTheoryLevel` directamente.
    static func computeCombinedLevel(topics: [SkillTopic]) -> OverallLevelResult? {
        guard let technical = computeTechnicalLevel(topics: topics),
              let theory = computeTheoryLevel(topics: topics) else { return nil }
        let combinedRatio = (technical.percentage / 100) * 0.70 + (theory.percentage / 100) * 0.30
        var band = bandForOverallRatio(combinedRatio)
        band = applyTechnicalCappingRules(to: band, topics: topics)
        band = applyTheoryCappingRules(to: band, topics: topics)
        return OverallLevelResult(percentage: combinedRatio * 100, band: band)
    }

    private static func ratio(of score: (earned: Int, max: Int)) -> Double {
        score.max > 0 ? Double(score.earned) / Double(score.max) : 0
    }

    private static func bandForOverallRatio(_ ratio: Double) -> OverallLevelBand {
        switch ratio {
        case 0.95...: return .advancedConsolidated
        case 0.85..<0.95: return .advanced
        case 0.70..<0.85: return .intermediateHigh
        case 0.55..<0.70: return .intermediate
        case 0.40..<0.55: return .basic
        case 0.20..<0.40: return .beginner
        default: return .initial
        }
    }

    private static func cap(_ band: OverallLevelBand, at maxBand: OverallLevelBand) -> OverallLevelBand {
        let order = OverallLevelBand.allCases
        guard let currentIndex = order.firstIndex(of: band), let maxIndex = order.firstIndex(of: maxBand) else { return band }
        return currentIndex > maxIndex ? maxBand : band
    }

    /// Reglas de tope del Test Integral de Técnica: si postura, ritmo o aplicación musical están
    /// por debajo de cierto puntaje, el nivel no puede considerarse superior al tope indicado, sin
    /// importar cuánto haya dado la fórmula ponderada.
    ///
    /// Los umbrales van como PROPORCIÓN, no como puntaje absoluto: el documento original los definía
    /// sobre 20 puntos fijos (8/20 = 0.40 y 11/20 = 0.55) porque cada habilidad tenía exactamente 5
    /// preguntas. Con la rotación mensual el máximo por habilidad ya no es 20, así que comparar
    /// contra 8 y 11 haría que el tope se dejara de disparar solo por haber agregado preguntas —
    /// alguien con el mismo nivel real pasaría el corte por sumar un punto sobre un máximo mayor.
    /// Con proporciones el resultado es idéntico al original cuando no hay preguntas rotativas.
    private static func applyTechnicalCappingRules(to band: OverallLevelBand, topics: [SkillTopic]) -> OverallLevelBand {
        func ratio(_ name: String) -> Double? {
            guard let score = topics.first(where: { $0.name == name }).flatMap(pointsEarned), score.max > 0 else { return nil }
            return Double(score.earned) / Double(score.max)
        }

        var capped = band
        if let postura = ratio("Postura, relajación y mecánica general"), postura < 0.40 {
            capped = cap(capped, at: .basic)
        }
        if let ritmo = ratio("Ritmo, subdivisión y groove") {
            if ritmo < 0.40 { capped = cap(capped, at: .beginner) } else if ritmo <= 0.55 { capped = cap(capped, at: .basic) }
        }
        if let aplicacion = ratio("Aplicación musical, oído, teoría y repertorio") {
            if aplicacion < 0.40 { capped = cap(capped, at: .basic) } else if aplicacion <= 0.55 { capped = cap(capped, at: .intermediate) }
        }
        return capped
    }

    /// Reglas de tope del Test Integral de Teoría: notas/diapasón y ritmo débiles limitan el nivel
    /// teórico general a Básico, sin importar el puntaje total.
    /// Mismo criterio de proporción que `applyTechnicalCappingRules`: el umbral original era 3 sobre
    /// los 5 puntos fijos del módulo, o sea 0.60.
    private static func applyTheoryCappingRules(to band: OverallLevelBand, topics: [SkillTopic]) -> OverallLevelBand {
        func ratio(_ name: String) -> Double? {
            guard let score = topics.first(where: { $0.name == name }).flatMap(pointsEarned), score.max > 0 else { return nil }
            return Double(score.earned) / Double(score.max)
        }

        var capped = band
        if let notas = ratio(theoryNotasModuleName), notas < 0.60 {
            capped = cap(capped, at: .basic)
        }
        if let ritmo = ratio(theoryRitmoModuleName), ritmo < 0.60 {
            capped = cap(capped, at: .basic)
        }
        return capped
    }

    /// Resumen agregado (0-1) de canciones y ejercicios vinculados, usado solo para presentar el
    /// material que sustenta una habilidad. El dominio se calcula en `SkillMasteryEngine`, no acá.
    /// Canciones: enlace explícito por `linkedSkillIDs` (sugerido por IA, confirmado por el usuario).
    /// Ejercicios: coincidencia determinística por texto entre `technique` y el nombre/detalle de la
    /// habilidad — vincular a mano o por IA los 1561 ejercicios importados uno por uno no es viable.
    static func practiceEvidence(
        for topic: SkillTopic,
        songs: [Song],
        exercises: [LibraryExercise]
    ) -> (ratio: Double, count: Int)? {
        let linkedSongs = songs.filter { $0.linkedSkillIDs.contains(topic.id) }
        let linkedExercises = matchingExercises(for: topic, exercises: exercises)
        let weights = linkedSongs.map(\.status.progressWeight) + linkedExercises.map(\.status.progressWeight)
        guard !weights.isEmpty else { return nil }
        return (Double(weights.reduce(0, +)) / Double(weights.count * 5), weights.count)
    }

    /// Habilidades cuyo nombre/detalle coincide (por texto, sin IA) con la técnica de un ejercicio —
    /// usado para saber qué habilidades recalcular cuando cambia el estado de un ejercicio de
    /// Biblioteca, sin tener que recorrer las 38 habilidades por cada uno de los 1561 ejercicios.
    static func matchingSkills(forExerciseTechnique technique: String, topics: [SkillTopic]) -> [SkillTopic] {
        let techniqueTokens = Set(technique.evidenceTokens)
        guard !techniqueTokens.isEmpty else { return [] }
        return topics.filter { topic in
            let skillTokens = Set((topic.name + " " + topic.detail).evidenceTokens)
            return !skillTokens.isDisjoint(with: techniqueTokens)
        }
    }

    /// Igual que `matchingSkills(forExerciseTechnique:)` pero suma los vínculos que propuso
    /// `LibraryCatalogEnrichmentService` (`aiSkillIDs`) — necesario porque el matching por texto se
    /// pierde cuando el vocabulario del ejercicio no coincide literalmente con el nombre de la
    /// habilidad, aunque la practique.
    static func matchingSkills(for exercise: LibraryExercise, topics: [SkillTopic]) -> [SkillTopic] {
        var result = matchingSkills(forExerciseTechnique: exercise.technique, topics: topics)
        guard !exercise.aiSkillIDs.isEmpty else { return result }
        let alreadyIncluded = Set(result.map(\.id))
        result += topics.filter { exercise.aiSkillIDs.contains($0.id) && !alreadyIncluded.contains($0.id) }
        return result
    }

    /// Mismo criterio que `matchingSkills(for exercise:)` pero para un concepto de teoría: matching
    /// por categoría (solo dominio teoría) más los vínculos de `LibraryCatalogEnrichmentService`.
    static func matchingSkills(for concept: LibraryConcept, topics: [SkillTopic]) -> [SkillTopic] {
        topics.filter { topic in
            (topic.domain == .theory &&
             (topic.name.localizedCaseInsensitiveContains(concept.category) ||
              concept.category.localizedCaseInsensitiveContains(topic.name))) ||
            concept.aiSkillIDs.contains(topic.id)
        }
    }

    /// Inverso de `matchingSkills`: qué ejercicios de Biblioteca coinciden por texto (o por
    /// `aiSkillIDs`) con una habilidad puntual — usado para mostrar la evidencia práctica en el
    /// detalle de esa habilidad.
    static func matchingExercises(for topic: SkillTopic, exercises: [LibraryExercise]) -> [LibraryExercise] {
        let skillTokens = Set((topic.name + " " + topic.detail).evidenceTokens)
        return exercises.filter { exercise in
            exercise.aiSkillIDs.contains(topic.id) ||
            (!skillTokens.isEmpty && !Set(exercise.technique.evidenceTokens).isDisjoint(with: skillTokens))
        }
    }

    /// Una sola llamada corta a la IA que redacta una lectura en prosa del resultado YA CALCULADO
    /// (no inventa el número ni el nivel — esos ya son determinísticos) — no reemplaza el cálculo,
    /// solo lo explica.
    static func summarizeOverallLevel(
        topics: [SkillTopic],
        overall: OverallLevelResult,
        source: OverallLevelSource,
        context: String = "",
        evidenceSummary: String = "",
        backend: JSONCompletionBackend
    ) async throws -> String {
        // Si el resultado viene de un solo dominio (no combinado), listar solo esas habilidades:
        // mezclar las del otro dominio (casi todas "No iniciado" porque nunca se testeó) confundiría
        // al modelo sobre qué se evaluó realmente.
        let relevantTopics: [SkillTopic]
        let testDescription: String
        switch source {
        case .technical:
            relevantTopics = topics.filter { $0.domain == .technique }
            testDescription = "un test técnico"
        case .theory:
            relevantTopics = topics.filter { $0.domain == .theory }
            testDescription = "un test teórico"
        case .combined:
            relevantTopics = topics
            testDescription = "un test integral de técnica y teoría"
        }

        let skillLines = relevantTopics
            .filter { !$0.assessmentQuestions.isEmpty }
            .map { "- \($0.name): \($0.status.rawValue)" }
            .joined(separator: "\n")

        let starLevel = DifficultyRating(ratio: overall.percentage / 100)

        let prompt = """
        Eres un profesor de guitarra. Un alumno completó \(testDescription) y su nivel general ya fue \
        calculado matemáticamente: \(String(format: "%.1f", overall.percentage))% — \(starLevel.label).

        Resultado por habilidad:
        \(skillLines.isEmpty ? "Sin datos." : skillLines)
        \(context.isEmpty ? "" : "\nContexto adicional del alumno: \(context)\n")
        \(evidenceSummary.isEmpty ? "" : "Evidencia práctica reciente: \(evidenceSummary)\n")
        Escribe una lectura breve (2-4 frases) de este resultado, en español, mencionando fortalezas \
        y debilidades concretas. Usa la escala de 10 estrellas; no lo traduzcas a básico, intermedio
        ni avanzado. No cambies ni contradigas la nota ya indicada, solo explícalo.

        Responde ÚNICAMENTE con un objeto JSON con esta forma exacta, sin texto adicional:
        { "summary": "la lectura de 2-4 frases" }
        """

        let raw = try await backend.completeJSON(prompt: prompt)
        guard let object = try? JSONAIParser.object(from: raw),
              let summary = object["summary"] as? String, !summary.isEmpty else {
            throw SkillAssessmentSummaryError.emptyResponse
        }
        return summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func suggestRepertoire(
        topics: [SkillTopic],
        exercises: [LibraryExercise],
        songs: [Song],
        favoriteBands: [Band] = [],
        musicalTastes: String,
        context: String = "",
        pdfReferences: [String],
        backend: JSONCompletionBackend
    ) async throws -> [AssessmentAnalysis.RepertoireSuggestion] {
        let weakest = topics
            .sorted { statusWeight($0.status) < statusWeight($1.status) }
            .prefix(15)
            .map {
                let difficulty = DifficultyClassifier.assess(skillNamed: $0.name).rating
                return "- \($0.name) (dominio \($0.status.rawValue), dificultad \(difficulty.label))"
            }
            .joined(separator: "\n")

        guard !weakest.isEmpty else { return [] }

        // Muestra acotada, no la Biblioteca entera: con más de dos mil ejercicios importados, mandar
        // todos hacía un prompt enorme en cada llamada. Aunque ahora use Gemini pagado, un prompt
        // así aumenta costo, latencia y riesgo de capacidad (503). Para que el
        // modelo "sepa qué tiene el alumno" basta con los favoritos y lo que está en curso.
        let favorites = exercises.filter { $0.isFavorite && $0.status != .mastered }
        let inProgress = exercises.filter {
            !$0.isFavorite && ($0.status == .learning || $0.status == .consolidating || $0.status == .reducedTempo)
        }
        let sampledExercises = Array((favorites + inProgress).prefix(60))
        let omitted = exercises.count - sampledExercises.count
        let exerciseContexts = DifficultyClassifier.bookContexts(for: exercises)
        let exerciseLines = sampledExercises
            .map {
                let difficulty = DifficultyClassifier.assess(
                    $0,
                    context: DifficultyClassifier.context(forBook: $0.bookTitle, in: exerciseContexts)
                ).rating
                return "- \($0.bookTitle), \($0.displayName), \(difficulty.label)"
            }
            .joined(separator: "\n")
            + (omitted > 0 ? "\n(y \(omitted) ejercicios más en su biblioteca, no listados acá)" : "")
        let songLines = songs.map {
            let difficulty = SongDifficultyCatalog.assess($0).rating
            return "- \($0.title)\($0.artist.isEmpty ? "" : " (\($0.artist))"), \(difficulty.label)"
        }.joined(separator: "\n")
        let pdfLines = pdfReferences.joined(separator: "\n")
        let bandLines = favoriteBands.map { band -> String in
            var line = "- \(band.name)"
            if !band.likedSongTitles.isEmpty {
                line += " (canciones que le gustan: \(band.likedSongTitles.joined(separator: ", ")))"
            }
            return line
        }.joined(separator: "\n")
        let studentLevel = StudentLevelService.currentRating
        let levelLine = studentLevel.map { "Nivel actual del alumno: \($0.label)." } ?? "Nivel actual aún no medido."

        let prompt = """
        Eres un profesor de guitarra. Estas son las habilidades más débiles de un alumno:
        \(weakest)

        \(levelLine)

        Bandas favoritas del alumno:
        \(bandLines.isEmpty ? "Ninguna registrada." : bandLines)

        Gustos musicales del alumno: \(musicalTastes.isEmpty ? "no especificados" : musicalTastes)
        \(context.isEmpty ? "" : "Contexto adicional del alumno: \(context)\n")

        Ejercicios que ya tiene en su biblioteca:
        \(exerciseLines.isEmpty ? "Ninguno registrado." : exerciseLines)

        Páginas reales de sus libros en PDF relacionadas con estas habilidades:
        \(pdfLines.isEmpty ? "Ninguna encontrada." : pdfLines)

        Canciones que ya tiene en su repertorio:
        \(songLines.isEmpty ? "Ninguna registrada." : songLines)

        Elige entre 4 y 6 de esas habilidades débiles y para cada una sugiere UNA canción real y \
        conocida que ayude a desarrollarla en la práctica, priorizando las bandas favoritas y los \
        gustos musicales del alumno si se especificaron. No repitas canciones que el alumno ya tiene \
        en su repertorio. La canción debe quedar a su nivel o como desafío alcanzable (como máximo \
        2,5 estrellas por encima); no recomiendes repertorio que le quede grande todavía.

        Responde ÚNICAMENTE con un objeto JSON con esta forma exacta, sin texto adicional, en español:
        {
          "repertoire": [
            { "title": "título de la canción", "artist": "artista", "reason": "por qué ayuda, máximo 20 palabras", "targetSkill": "nombre de la habilidad que refuerza" }
          ]
        }
        """

        let raw = try await backend.completeJSON(prompt: prompt)
        let items = parseObjectArray(from: raw, key: "repertoire")

        let suggestions = items.compactMap { item -> AssessmentAnalysis.RepertoireSuggestion? in
            guard let title = item["title"] as? String, let targetSkill = item["targetSkill"] as? String else { return nil }
            let artist = item["artist"] as? String ?? ""
            let reason = item["reason"] as? String ?? ""
            return AssessmentAnalysis.RepertoireSuggestion(title: title, artist: artist, reason: reason, targetSkill: targetSkill)
        }
        guard let studentLevel else { return suggestions }
        return suggestions.filter {
            SongDifficultyCatalog.assess(title: $0.title, artist: $0.artist).rating
                .fit(forStudentLevel: studentLevel) != .tooHard
        }
    }

    private static func statusWeight(_ status: SkillMasteryLevel) -> Int {
        switch status {
        case .notStarted: 0
        case .initial: 1
        case .basic: 2
        case .intermediate: 3
        case .advanced: 4
        case .consolidated: 5
        }
    }

    /// Parsea de forma tolerante un array de objetos bajo `key` en la respuesta JSON del modelo.
    /// Si el JSON viene mal formado o incompleto, devuelve lo que se pueda rescatar (o vacío)
    /// en vez de lanzar un error críptico que tumbe toda la autoevaluación.
    private static func parseObjectArray(from raw: String, key: String) -> [[String: Any]] {
        guard let object = try? JSONAIParser.object(from: raw),
              let array = object[key] as? [[String: Any]] else {
            return []
        }
        return array
    }
}

private let evidenceStopWords: Set<String> = [
    "al", "como", "con", "cada", "de", "del", "el", "en", "entre", "la", "las", "lo", "los",
    "mas", "para", "por", "que", "se", "sin", "sobre", "su", "sus", "un", "una", "unos", "unas", "y",
    "and", "for", "from", "in", "of", "on", "or", "the", "to", "with"
]

extension String {
    /// Tokens normalizados (sin acentos, minúsculas) usados para el matching determinístico entre
    /// `LibraryExercise.technique` y el nombre/detalle de una habilidad, sin depender de la IA.
    var evidenceTokens: [String] {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .filter { $0.count > 1 }
            .map(String.init)
            .filter { !evidenceStopWords.contains($0) }
    }
}
