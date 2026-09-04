import Foundation

struct GeneratedAcademyQuestion {
    let type: AcademyQuestionType
    let prompt: String
    let options: [String]
    let correctAnswer: String
    let explanation: String
}

enum AcademyQuestionDraftService {
    static func generate(
        recognizedText: String,
        requestedType: AcademyQuestionType,
        source: String,
        backend: JSONCompletionBackend
    ) async throws -> GeneratedAcademyQuestion {
        let prompt = """
        Crea una pregunta de teoría musical basada EXCLUSIVAMENTE en el texto OCR de una página real.
        Fuente: \(source)
        Tipo solicitado: \(requestedType.rawValue)

        TEXTO OCR:
        \(recognizedText.prefix(12_000))

        Para opción múltiple devuelve cuatro opciones y una respuesta idéntica a una de ellas.
        Para verdadero/falso usa options ["Verdadero","Falso"] y una de esas respuestas.
        Para completar palabra deja options vacío. No preguntes por datos cortados o ambiguos.

        Responde solo JSON:
        {
          "prompt": "enunciado",
          "options": ["..."],
          "correctAnswer": "respuesta",
          "explanation": "explicación breve basada en la fuente"
        }
        """
        let raw = try await backend.completeJSON(prompt: prompt)
        let object = try JSONAIParser.object(from: raw)
        guard let questionPrompt = object["prompt"] as? String, !questionPrompt.isEmpty,
              let correct = object["correctAnswer"] as? String, !correct.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        let options = object["options"] as? [String] ?? []
        if requestedType == .multipleChoice,
           (options.count != 4 || !options.contains(correct)) {
            throw AIServiceError.invalidResponse
        }
        return GeneratedAcademyQuestion(
            type: requestedType,
            prompt: questionPrompt,
            options: options,
            correctAnswer: correct,
            explanation: object["explanation"] as? String ?? ""
        )
    }
}

struct VideoResearchPlan {
    let searchQuery: String
    let learningObjective: String
    let evaluationCriteria: String
}

enum VideoResearchService {
    static func plan(
        goal: String,
        context: LearningContextSnapshot,
        backend: JSONCompletionBackend
    ) async throws -> VideoResearchPlan {
        let prompt = """
        Convierte este objetivo de guitarra en una búsqueda concreta de YouTube. La búsqueda debe \
        incluir la técnica, estilo o canción relevante y palabras que favorezcan una demostración \
        pedagógica útil, no publicidad. No inventes un video ni un canal.

        OBJETIVO: \(goal)
        CONTEXTO:
        \(context.text)

        Responde solo JSON:
        {
          "searchQuery": "consulta para YouTube",
          "learningObjective": "qué debe aprender el alumno",
          "evaluationCriteria": "cómo decidir si el video sirve"
        }
        """
        let raw = try await backend.completeJSON(prompt: prompt)
        let object = try JSONAIParser.object(from: raw)
        guard let searchQuery = object["searchQuery"] as? String, !searchQuery.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return VideoResearchPlan(
            searchQuery: searchQuery,
            learningObjective: object["learningObjective"] as? String ?? goal,
            evaluationCriteria: object["evaluationCriteria"] as? String ?? ""
        )
    }
}
