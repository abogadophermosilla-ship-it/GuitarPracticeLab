import Foundation

struct SongExerciseSuggestion {
    let title: String
    let source: String
    let reason: String
}

/// Entrada estable para una consulta de duración. El `id` nunca se envía a Gemini: el prompt usa
/// un índice corto y luego lo vuelve a asociar localmente, evitando que el modelo altere un UUID.
struct SongDurationQuery: Equatable {
    let id: UUID
    let title: String
    let artist: String
}

struct SongDurationResult: Equatable {
    let songID: UUID
    let durationSeconds: Int
    let version: String
}

enum SongCoachError: LocalizedError {
    case emptyResponse
    case noSections
    case noDurations

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "El asistente no devolvió sugerencias de ejercicios válidas."
        case .noSections:
            return "El asistente no devolvió una estructura de secciones válida."
        case .noDurations:
            return "Gemini no devolvió duraciones verificables para el repertorio."
        }
    }
}

/// Consulta en una sola llamada la duración de varias canciones. La validación local descarta
/// estimaciones, índices inexistentes y valores fuera de un rango musical razonable antes de tocar
/// los datos guardados.
enum SongDurationAIService {
    static func lookup(
        songs: [SongDurationQuery],
        backend: JSONCompletionBackend
    ) async throws -> [SongDurationResult] {
        guard !songs.isEmpty else { return [] }

        let catalog = songs.enumerated().map { index, song in
            let artist = song.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            return "- \(index): \(song.title) — \(artist.isEmpty ? "artista no especificado" : artist)"
        }.joined(separator: "\n")

        let prompt = """
        Actualiza la duración de estas canciones del repertorio de guitarra. Usa la versión oficial \
        de estudio o álbum más conocida del artista indicado, no una versión en vivo, remaster \
        extendido, cover ni videoclip con introducción adicional. No estimes: si no reconoces con \
        certeza el título y el artista, marca recognized como false y usa 0 segundos.

        REPERTORIO:
        \(catalog)

        Devuelve una entrada por cada índice recibido y conserva exactamente esos índices. La \
        duración debe ser el total entero en segundos. Responde ÚNICAMENTE con JSON:
        {
          "songs": [
            { "index": 0, "recognized": true, "durationSeconds": 243, "version": "versión de álbum" }
          ]
        }
        """

        let raw = try await backend.completeJSON(prompt: prompt)
        let object = try JSONAIParser.object(from: raw)
        guard let items = object["songs"] as? [[String: Any]] else {
            throw SongCoachError.noDurations
        }

        var seen = Set<Int>()
        return items.compactMap { item in
            guard let index = item["index"] as? Int,
                  songs.indices.contains(index),
                  !seen.contains(index),
                  item["recognized"] as? Bool == true,
                  let seconds = item["durationSeconds"] as? Int,
                  (30...3_600).contains(seconds)
            else { return nil }
            seen.insert(index)
            return SongDurationResult(
                songID: songs[index].id,
                durationSeconds: seconds,
                version: item["version"] as? String ?? ""
            )
        }
    }
}

/// Caché liviano de sincronización. Las duraciones viven en `Song`; este registro solo evita pagar
/// la misma consulta en cada apertura. Un tema nuevo, un cambio de título/artista o 30 días de
/// antigüedad lo vuelven elegible automáticamente.
enum SongDurationRefreshStore {
    private struct Record: Codable {
        let identity: String
        let checkedAt: Date
    }

    private static let storageKey = "geminiSongDurationRefreshV1"
    private static let refreshInterval: TimeInterval = 30 * 24 * 60 * 60

    static func pending(
        from songs: [SongDurationQuery],
        force: Bool,
        now: Date = .now,
        defaults: UserDefaults = .standard
    ) -> [SongDurationQuery] {
        guard !force else { return songs }
        let records = load(defaults: defaults)
        return songs.filter { song in
            guard let record = records[song.id.uuidString] else { return true }
            return record.identity != identity(for: song)
                || now.timeIntervalSince(record.checkedAt) >= refreshInterval
        }
    }

    static func markChecked(
        _ songs: [SongDurationQuery],
        at date: Date = .now,
        defaults: UserDefaults = .standard
    ) {
        var records = load(defaults: defaults)
        for song in songs {
            records[song.id.uuidString] = Record(identity: identity(for: song), checkedAt: date)
        }
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private static func load(defaults: UserDefaults) -> [String: Record] {
        guard let data = defaults.data(forKey: storageKey),
              let records = try? JSONDecoder().decode([String: Record].self, from: data)
        else { return [:] }
        return records
    }

    private static func identity(for song: SongDurationQuery) -> String {
        "\(song.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())\u{0}\(song.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }
}

/// Sugiere ejercicios concretos a partir de una debilidad anotada en una sección de una canción del
/// repertorio (ej. "falta el solo, no me sale el bending") — mismo patrón de prompt→JSON que
/// `SkillAssessmentCoachService.suggestRepertoire`.
enum SongCoachService {
    static func suggestExercises(
        forWeakness weaknessNotes: String,
        songTitle: String,
        sectionName: String,
        skills: [SkillTopic],
        exercises: [LibraryExercise],
        backend: JSONCompletionBackend
    ) async throws -> [SongExerciseSuggestion] {
        let trimmedWeakness = weaknessNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWeakness.isEmpty else { return [] }

        let studentLevel = StudentLevelService.currentRating
        let skillLines = skills.map {
            let difficulty = DifficultyClassifier.assess(skillNamed: $0.name).rating
            return "- \($0.name) (dominio \($0.status.rawValue), dificultad \(difficulty.label))"
        }.joined(separator: "\n")

        // El catálogo supera los dos mil ejercicios: primero se filtra por las palabras concretas
        // de la debilidad y después se ordena por adecuación al Test Integral. Así el modelo recibe
        // opciones pertinentes y realizables, no un bloque enorme donde gana cualquier coincidencia.
        let weaknessTokens = Set(trimmedWeakness.difficultySearchTokens)
        let contexts = DifficultyClassifier.bookContexts(for: exercises)
        let fitOrder: [DifficultyFit: Int] = [.onLevel: 0, .review: 1, .stretch: 2, .tooHard: 3, .mastered: 4]
        func rating(_ exercise: LibraryExercise) -> DifficultyRating {
            DifficultyClassifier.assess(
                exercise,
                context: DifficultyClassifier.context(forBook: exercise.bookTitle, in: contexts)
            ).rating
        }
        var candidates = exercises.filter { exercise in
            let tokens = Set((exercise.technique + " " + exercise.displayName + " " + exercise.notes).difficultySearchTokens)
            return !weaknessTokens.isDisjoint(with: tokens)
        }
        if candidates.isEmpty {
            candidates = exercises.filter { $0.isFavorite || $0.status == .learning || $0.status == .consolidating }
        }
        candidates.sort { lhs, rhs in
            let left = rating(lhs)
            let right = rating(rhs)
            if let studentLevel {
                let leftFit = fitOrder[left.fit(forStudentLevel: studentLevel), default: 5]
                let rightFit = fitOrder[right.fit(forStudentLevel: studentLevel), default: 5]
                if leftFit != rightFit { return leftFit < rightFit }
            }
            return left < right
        }
        let exerciseLines = candidates.prefix(80).map {
            let difficulty = rating($0)
            let fit = studentLevel.map { difficulty.fit(forStudentLevel: $0).name }
            return "- \($0.bookTitle), \($0.displayName), técnica: \($0.technique), \(difficulty.label)\(fit.map { ", \($0)" } ?? "")"
        }.joined(separator: "\n")

        let prompt = """
        Eres un profesor de guitarra. El alumno está tocando "\(songTitle)" y anotó esta debilidad \
        concreta en la sección "\(sectionName)":
        "\(trimmedWeakness)"

        Habilidades del alumno, para contexto de su nivel:
        \(skillLines.isEmpty ? "Sin registrar." : skillLines)

        Nivel general del Test Integral: \(studentLevel?.label ?? "sin medir").

        Ejercicios que ya tiene en su biblioteca:
        \(exerciseLines.isEmpty ? "Ninguno registrado." : exerciseLines)

        Sugiere entre 1 y 2 ejercicios o técnicas concretas para resolver esa debilidad puntual, \
        priorizando ejercicios reales de su biblioteca si alguno calza con el problema descrito.
        Elige material a su nivel o un desafío alcanzable; no material marcado como "Te queda grande".

        Responde ÚNICAMENTE con un objeto JSON con esta forma exacta, sin texto adicional, en español:
        {
          "suggestions": [
            { "title": "ejercicio o técnica concreta", "source": "libro/página si aplica, o vacío", "reason": "por qué ayuda con esta debilidad, máximo 25 palabras" }
          ]
        }
        No inventes ejercicios ni libros que no estén en la lista de arriba, salvo que sea una técnica \
        genérica sin fuente concreta que sugerir.
        """

        let raw = try await backend.completeJSON(prompt: prompt)
        let items = parseObjectArray(from: raw, key: "suggestions")
        guard !items.isEmpty else { throw SongCoachError.emptyResponse }

        return items.compactMap { item in
            guard let title = item["title"] as? String, !title.isEmpty else { return nil }
            return SongExerciseSuggestion(
                title: title,
                source: item["source"] as? String ?? "",
                reason: item["reason"] as? String ?? ""
            )
        }
    }

    /// Sugiere qué habilidades del catálogo refuerza una canción (a partir de título, artista y
    /// secciones) — el usuario confirma o edita el resultado antes de guardarlo como
    /// `Song.linkedSkillIDs`, nunca se aplica sin confirmar. Solo devuelve nombres que existen
    /// exactamente en `skills`, para evitar que la IA invente una habilidad que no está en el catálogo.
    static func suggestSkills(
        songTitle: String,
        artist: String,
        sections: String,
        skills: [SkillTopic],
        backend: JSONCompletionBackend
    ) async throws -> [SkillTopic] {
        let trimmedTitle = songTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return [] }

        let skillLines = skills.map { "- \($0.name) (\($0.domain.rawValue))" }.joined(separator: "\n")

        let prompt = """
        Eres un profesor de guitarra que conoce el repertorio real de esta canción, no solo su \
        título. El alumno tiene esta canción en su repertorio:
        Título: \(trimmedTitle)
        Artista: \(artist.isEmpty ? "no especificado" : artist)
        Secciones: \(sections.isEmpty ? "no especificadas" : sections)

        Este es el catálogo completo de habilidades del alumno (nombres exactos):
        \(skillLines)

        Primero piensa en serio qué género y estilo tiene ESTA canción en particular (blues lento, \
        rock, metal, funk, jazz, acústico, etc.) — no asumas un estilo genérico de "rock de guitarra" \
        por defecto. Después elige entre 2 y 5 nombres de la lista que esta canción refuerce \
        REALMENTE al tocarla, coherentes con ese género y estilo real (técnica exigida, ritmos, \
        recursos). Por ejemplo: una canción de blues lento en el estilo de Stevie Ray Vaughan no usa \
        downpicking agresivo, gallops ni tremolo picking (eso es propio de metal/thrash) — ahí \
        calzarían cosas como bending, vibrato, shuffle, double stops o dinámica. No elijas una \
        habilidad solo porque está en la lista si no tiene sentido para el género real de la canción. \
        Si no reconoces la canción con certeza, elige solo habilidades genéricas y ampliamente \
        aplicables, o devuelve una lista vacía antes que adivinar mal.

        Usa el nombre EXACTO tal como aparece en la lista, no lo parafrasees ni inventes uno nuevo.

        Responde ÚNICAMENTE con un objeto JSON con esta forma exacta, sin texto adicional:
        { "skills": ["nombre exacto 1", "nombre exacto 2"] }
        """

        let raw = try await backend.completeJSON(prompt: prompt)
        let object = (try? JSONAIParser.object(from: raw)) ?? [:]
        let names = object["skills"] as? [String] ?? []
        return names.compactMap { name in skills.first { $0.name == name } }
    }

    /// Sugiere la estructura de secciones de una canción (intro, verso, estribillo, solo...) a partir
    /// de título y artista, para que el alumno no tenga que describirla a mano. Si la IA no reconoce
    /// la canción, devuelve una estructura genérica razonable para ese estilo — nunca deja la lista
    /// vacía salvo error real. El resultado se usa para poblar `Song.sections`/`sectionProgress`, que
    /// el usuario sigue pudiendo editar, reordenar o borrar después (ver `NewSongView`).
    static func suggestSections(
        songTitle: String,
        artist: String,
        backend: JSONCompletionBackend
    ) async throws -> [String] {
        let trimmedTitle = songTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return [] }

        let prompt = """
        Eres un profesor de guitarra. Necesitas la estructura de secciones de esta canción para que el \
        alumno pueda marcar su progreso sección por sección en vez de describirla a mano:
        Título: \(trimmedTitle)
        Artista: \(artist.isEmpty ? "no especificado" : artist)

        Si conoces la canción, da su estructura real en el orden en que aparece (intro, verso, \
        preestribillo, estribillo, puente, solo, outro, etc., según corresponda). Si no la conoces con \
        certeza, da una estructura genérica razonable para una canción de ese estilo.

        Responde ÚNICAMENTE con un objeto JSON con esta forma exacta, sin texto adicional, en español, \
        entre 4 y 8 secciones, nombres cortos (1 a 3 palabras), en el orden en que aparecen:
        { "sections": ["Intro", "Verso", "Estribillo", "Solo", "Outro"] }
        """

        let raw = try await backend.completeJSON(prompt: prompt)
        let object = (try? JSONAIParser.object(from: raw)) ?? [:]
        let names = (object["sections"] as? [String] ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else { throw SongCoachError.noSections }
        return names
    }

    private static func parseObjectArray(from raw: String, key: String) -> [[String: Any]] {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let array = object[key] as? [[String: Any]] else {
            return []
        }
        return array
    }
}

private extension String {
    var difficultySearchTokens: [String] {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .filter { $0.count > 2 }
            .map(String.init)
    }
}
