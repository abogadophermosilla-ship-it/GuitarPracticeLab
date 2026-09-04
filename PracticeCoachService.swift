import Foundation

struct PracticeRecommendation: Codable {
    let focusSkill: String
    let reason: String
    let exerciseTitle: String
    let exerciseSource: String
    let suggestedMinutes: Int
    let targetBPM: Int
    let specialInstructions: String
}

struct ProgressChatExchange {
    let question: String
    let answer: String
}

enum PracticeCoachError: LocalizedError {
    case emptyResponse
    case emptyAnswer

    var errorDescription: String? {
        switch self {
        case .emptyResponse: "El asistente no devolvió una recomendación válida."
        case .emptyAnswer: "El asistente no devolvió una respuesta válida."
        }
    }
}

enum PracticeCoachService {
    static func recommendation(
        skills: [SkillTopic],
        lessons: [GuitarLesson],
        exercises: [LibraryExercise],
        equipment: [StudioAsset] = [],
        instruments: [Instrument] = [],
        pdfReferences: [String] = [],
        sessions: [PracticeSession] = [],
        tasks: [PracticeTask] = [],
        backend: JSONCompletionBackend
    ) async throws -> PracticeRecommendation {
        let context = contextBlock(
            skills: skills,
            lessons: lessons,
            exercises: exercises,
            equipment: equipment,
            instruments: instruments,
            pdfReferences: pdfReferences,
            sessions: sessions,
            tasks: tasks
        )

        let prompt = """
        Eres un asistente de práctica de guitarra. Tu tarea es elegir UNA sola prioridad concreta \
        para la próxima sesión de práctica, basándote en las habilidades débiles del alumno, las \
        indicaciones de su profesor, y los ejercicios reales que ya tiene en su biblioteca de estudio.

        \(context)

        Si en las notas del profesor o en el próximo objetivo hay una instrucción concreta y no \
        estándar (por ejemplo: usar un software o equipo específico de la lista de arriba, buscar \
        una versión distinta de un ejercicio, o cualquier tarea puntual que no sea simplemente \
        "practicar una habilidad"), esa instrucción tiene PRIORIDAD sobre elegir automáticamente una \
        habilidad débil genérica. En ese caso, describí exactamente qué hacer en el campo \
        "specialInstructions", mencionando el equipo/software real de la lista si corresponde. Si no \
        hay ninguna instrucción de ese tipo, deja "specialInstructions" vacío.

        Evitá recomendar exactamente lo mismo que la última sesión de práctica si fue hace menos de \
        un día, salvo que el resultado de esa sesión haya sido explícitamente "requiere revisión" o \
        el objetivo del profesor lo pida.

        Responde ÚNICAMENTE con un objeto JSON con esta forma exacta, sin texto adicional, en español:
        {
          "focusSkill": "nombre de la habilidad o área a reforzar",
          "reason": "explicación breve y objetiva de por qué es la prioridad ahora mismo (máximo 40 palabras)",
          "exerciseTitle": "un ejercicio específico de la biblioteca del alumno o una página real de un PDF, o una descripción concreta si no hay ninguno que calce",
          "exerciseSource": "libro y capítulo/página de donde sale el ejercicio, o vacío si no aplica",
          "suggestedMinutes": número entero de minutos sugeridos para este bloque,
          "targetBPM": número entero de BPM objetivo, o 0 si no aplica,
          "specialInstructions": "instrucción concreta y no estándar del profesor si existe, o vacío"
        }
        No inventes libros, páginas, ejercicios ni equipo que no estén en las listas de arriba.
        """

        let raw = try await backend.completeJSON(prompt: prompt)
        guard let object = try? JSONAIParser.object(from: raw),
              let focusSkill = object["focusSkill"] as? String,
              let exerciseTitle = object["exerciseTitle"] as? String else {
            throw PracticeCoachError.emptyResponse
        }
        return PracticeRecommendation(
            focusSkill: focusSkill,
            reason: object["reason"] as? String ?? "",
            exerciseTitle: exerciseTitle,
            exerciseSource: object["exerciseSource"] as? String ?? "",
            suggestedMinutes: object["suggestedMinutes"] as? Int ?? 10,
            targetBPM: object["targetBPM"] as? Int ?? 0,
            specialInstructions: object["specialInstructions"] as? String ?? ""
        )
    }

    // MARK: - Chat de seguimiento

    /// Responde una pregunta puntual del alumno sobre la recomendación ya generada (p. ej. pedirle
    /// que especifique una página, aclare un término, o justifique mejor la elección), reusando el
    /// mismo contexto real (habilidades, clases, ejercicios, etc.) para no inventar datos.
    static func followUp(
        question: String,
        recommendation: PracticeRecommendation,
        history: [ProgressChatExchange],
        skills: [SkillTopic],
        lessons: [GuitarLesson],
        exercises: [LibraryExercise],
        equipment: [StudioAsset] = [],
        instruments: [Instrument] = [],
        pdfReferences: [String] = [],
        sessions: [PracticeSession] = [],
        tasks: [PracticeTask] = [],
        backend: JSONCompletionBackend
    ) async throws -> String {
        let context = contextBlock(
            skills: skills,
            lessons: lessons,
            exercises: exercises,
            equipment: equipment,
            instruments: instruments,
            pdfReferences: pdfReferences,
            sessions: sessions,
            tasks: tasks
        )

        let recommendationText = """
        - Prioridad elegida: \(recommendation.focusSkill)
        - Motivo: \(recommendation.reason)
        - Ejercicio sugerido: \(recommendation.exerciseTitle)
        - Fuente: \(recommendation.exerciseSource.isEmpty ? "sin fuente específica" : recommendation.exerciseSource)
        - Minutos sugeridos: \(recommendation.suggestedMinutes)
        - BPM objetivo: \(recommendation.targetBPM > 0 ? "\(recommendation.targetBPM)" : "no aplica")
        - Instrucción especial: \(recommendation.specialInstructions.isEmpty ? "ninguna" : recommendation.specialInstructions)
        """

        let historyText = history.suffix(6).map {
            "Alumno: \($0.question)\nAsistente: \($0.answer)"
        }.joined(separator: "\n\n")

        let prompt = """
        Eres el mismo asistente de práctica de guitarra que acaba de generar esta recomendación para \
        la próxima sesión. El alumno te está preguntando algo puntual sobre ella — puede pedirte que \
        especifiques, aclares un término, justifiques mejor la elección, o propongas una alternativa. \
        Responde en español neutro, tuteando (nunca voseo ni modismos regionales), de forma breve y \
        concreta.

        RECOMENDACIÓN ACTUAL:
        \(recommendationText)

        \(context)

        CONVERSACIÓN PREVIA CON EL ALUMNO SOBRE ESTA RECOMENDACIÓN:
        \(historyText.isEmpty ? "Ninguna todavía." : historyText)

        PREGUNTA DEL ALUMNO:
        \(question)

        No inventes libros, páginas, ejercicios ni equipo que no estén en el contexto de arriba. Si no \
        tienes información suficiente para responder con precisión, dilo y propón cómo comprobarlo.

        Responde ÚNICAMENTE con un objeto JSON con esta forma exacta, sin texto adicional:
        { "answer": "tu respuesta" }
        """

        let raw = try await backend.completeJSON(prompt: prompt)
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answer = object["answer"] as? String,
              !answer.isEmpty else {
            throw PracticeCoachError.emptyAnswer
        }
        return answer
    }

    // MARK: - Contexto compartido

    private static func contextBlock(
        skills: [SkillTopic],
        lessons: [GuitarLesson],
        exercises: [LibraryExercise],
        equipment: [StudioAsset],
        instruments: [Instrument],
        pdfReferences: [String],
        sessions: [PracticeSession],
        tasks: [PracticeTask]
    ) -> String {
        let weakSkills = skills
            .filter { $0.status == .notStarted || $0.status == .initial || $0.status == .basic }
            .sorted { lhs, rhs in
                if lhs.status != rhs.status {
                    return statusWeight(lhs.status) < statusWeight(rhs.status)
                }
                return lhs.name < rhs.name
            }
            .prefix(12)

        let skillLines = weakSkills.map {
            let difficulty = DifficultyClassifier.assess(skillNamed: $0.name).rating
            return "- [\($0.domain.rawValue) · \(difficulty.label)] \($0.name) — \($0.detail) (estado: \($0.status.rawValue))"
        }.joined(separator: "\n")

        let lesson = lessons.first
        let teacherLines = lesson.map { lesson -> String in
            var text = "Indicaciones: \(lesson.teacherNotes)\nPróximo objetivo: \(lesson.nextObjective)"
            if !lesson.attachments.isEmpty {
                let attachmentLines = lesson.attachments
                    .map { "- \($0.kind.rawValue): \($0.displayName)" }
                    .joined(separator: "\n")
                text += "\nArchivos que adjuntó el profesor (usa el nombre/tipo, no inventes su contenido):\n\(attachmentLines)"
            }
            return text
        } ?? "Sin clases registradas todavía."

        // Filtra a los ejercicios relacionados con las habilidades débiles de arriba (mismo matching
        // determinístico por texto que ya usa la evidencia práctica) en vez de mandar el catálogo
        // completo — con 1561 ejercicios importados, volcarlos todos satura el prompt del modelo
        // local sin ayudar a elegir. Si el matching no encuentra nada, cae a favoritos antes que a
        // una lista vacía o arbitraria.
        var seenExerciseIDs = Set<UUID>()
        var relevantExercises: [LibraryExercise] = []
        for skill in weakSkills {
            for exercise in SkillAssessmentCoachService.matchingExercises(for: skill, exercises: exercises) {
                if seenExerciseIDs.insert(exercise.id).inserted {
                    relevantExercises.append(exercise)
                }
            }
        }
        if relevantExercises.isEmpty {
            relevantExercises = exercises.filter(\.isFavorite)
        }
        let boundedExercises = relevantExercises.prefix(15)

        let exerciseLines = boundedExercises.map {
            "- \($0.bookTitle) (\($0.collectionName)), \($0.displayName), técnica: \($0.technique), tempo objetivo: \($0.targetBPM) BPM, estado: \($0.status.rawValue)"
        }.joined(separator: "\n")

        let recentSessionLine = sessions.sorted { $0.date > $1.date }.first.map {
            "\($0.date.formatted(date: .abbreviated, time: .shortened)): \($0.exerciseTitle.isEmpty ? $0.category.rawValue : $0.exerciseTitle), tiempo \($0.formattedDuration)\($0.repertoireRepetitions > 0 ? ", \($0.repertoireRepetitions) pasadas completas" : ""), resultado: \($0.result.rawValue)."
        } ?? "Sin sesiones registradas todavía."

        let pendingTaskLines = tasks.filter { !$0.isCompleted }.prefix(8).map {
            "- \($0.title)\($0.exerciseTitle.isEmpty ? "" : " (\($0.exerciseTitle))")"
        }.joined(separator: "\n")

        let equipmentLines = equipment.map {
            "- [\($0.assetType.rawValue)] \($0.name) (categoría: \($0.category), uso: \($0.usage))"
        }.joined(separator: "\n")

        let instrumentLines = instruments.map {
            "- \($0.name) (\($0.kind), afinación: \($0.tuning))"
        }.joined(separator: "\n")

        return """
        Habilidades débiles o sin trabajar (técnica y teoría):
        \(skillLines.isEmpty ? "No hay habilidades débiles registradas." : skillLines)

        Notas del profesor más recientes:
        \(teacherLines)

        Ejercicios disponibles en la biblioteca del alumno:
        \(exerciseLines.isEmpty ? "No hay ejercicios registrados." : exerciseLines)

        Equipo y software disponible:
        \(equipmentLines.isEmpty ? "Ninguno registrado." : equipmentLines)

        Instrumentos disponibles:
        \(instrumentLines.isEmpty ? "Ninguno registrado." : instrumentLines)

        Páginas reales de sus libros en PDF relacionadas con estas habilidades débiles:
        \(pdfReferences.isEmpty ? "Ninguna encontrada." : pdfReferences.joined(separator: "\n"))

        Última sesión de práctica registrada: \(recentSessionLine)

        Tareas que el alumno ya tiene pendientes (no sugieras algo prácticamente idéntico a una de \
        estas, salvo que continuarla sea realmente lo mejor):
        \(pendingTaskLines.isEmpty ? "Ninguna pendiente." : pendingTaskLines)
        """
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
}
