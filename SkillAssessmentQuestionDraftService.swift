import Foundation

/// Redacta UNA pregunta nueva de autoevaluación por llamada (nunca un lote), calibrada al mismo
/// rubro que `SkillAssessmentQuestionBank`: para Técnica, 5 opciones que van de menor a mayor dominio
/// (puntaje 0-4 por posición, igual que el helper `q(...)` del banco fijo); para Teoría, 4 opciones
/// con una sola correcta más "No lo sé." (igual que el helper `tq(...)`). Las preguntas del banco fijo
/// nunca se tocan — esto solo alimenta `SkillTopic.pendingCandidateQuestions`, que el usuario revisa
/// y aprueba a mano antes de que cuenten para algo (ver `SkillAssessmentQuestionReviewView`).
enum SkillAssessmentQuestionDraftService {
    static func draftQuestion(for topic: SkillTopic, backend: JSONCompletionBackend) async throws -> AssessmentQuestion {
        let existingTexts = (
            SkillAssessmentQuestionBank.questions(for: topic.name)
            + topic.approvedRotationPool
            + topic.pendingCandidateQuestions
        ).map(\.question)

        let prompt = topic.domain == .theory
            ? theoryPrompt(for: topic, existingTexts: existingTexts)
            : techniquePrompt(for: topic, existingTexts: existingTexts)

        let raw = try await backend.completeJSON(prompt: prompt)
        let object = try JSONAIParser.object(from: raw)
        guard let question = (object["question"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !question.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        guard !isDuplicate(question, of: existingTexts) else {
            throw AIServiceError.invalidResponse
        }

        return topic.domain == .theory
            ? try theoryQuestion(question: question, object: object)
            : try techniqueQuestion(question: question, object: object)
    }

    // MARK: - Técnica (5 opciones, puntaje 0-4 por posición)

    private static func techniquePrompt(for topic: SkillTopic, existingTexts: [String]) -> String {
        let examples = SkillAssessmentQuestionBank.questions(for: topic.name).prefix(2)
        let exampleLines = examples.map { example in
            "- \"\(example.question)\" → opciones de menor a mayor dominio: " +
            example.options.map { "\"\($0.text)\"" }.joined(separator: ", ")
        }.joined(separator: "\n")

        return """
        Eres un profesor de guitarra eléctrica escribiendo UNA pregunta nueva de autoevaluación de \
        técnica para la habilidad "\(topic.name)" (\(topic.detail)).

        Estilo del test integral que ya usa el alumno, para calibrar dificultad y tono (no las repitas):
        \(exampleLines.isEmpty ? "Sin ejemplos disponibles." : exampleLines)

        No repitas ninguna de estas preguntas ya existentes para esta habilidad:
        \(existingTexts.isEmpty ? "Ninguna." : existingTexts.map { "- \($0)" }.joined(separator: "\n"))

        Escribe una pregunta nueva de autodiagnóstico (no de opción correcta/incorrecta) con \
        EXACTAMENTE 5 opciones ordenadas de menor a mayor dominio de la técnica, mismo espíritu que \
        los ejemplos.

        Responde ÚNICAMENTE con un objeto JSON con esta forma exacta, en español, sin texto adicional:
        {
          "question": "el enunciado",
          "options": ["nivel más bajo de dominio", "...", "...", "...", "nivel más alto de dominio"]
        }
        """
    }

    private static func techniqueQuestion(question: String, object: [String: Any]) throws -> AssessmentQuestion {
        guard let rawOptions = object["options"] as? [String] else { throw AIServiceError.invalidResponse }
        let texts = rawOptions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard texts.count == 5, texts.allSatisfy({ !$0.isEmpty }) else { throw AIServiceError.invalidResponse }
        let options = texts.enumerated().map { index, text in
            AssessmentOption(text: text, points: index)
        }
        return AssessmentQuestion(question: question, options: options)
    }

    // MARK: - Teoría (4 opciones, una correcta + "No lo sé.")

    private static func theoryPrompt(for topic: SkillTopic, existingTexts: [String]) -> String {
        let examples = SkillAssessmentQuestionBank.questions(for: topic.name).prefix(2)
        let exampleLines = examples.map { example in
            "- \"\(example.question)\" → opciones: " + example.options.prefix(4).map { "\"\($0.text)\"" }.joined(separator: ", ")
        }.joined(separator: "\n")

        return """
        Eres un profesor de teoría musical aplicada a la guitarra eléctrica escribiendo UNA pregunta \
        nueva de opción múltiple para el módulo "\(topic.name)" (\(topic.detail)).

        Estilo del test integral que ya usa el alumno, para calibrar dificultad y tono (no las repitas):
        \(exampleLines.isEmpty ? "Sin ejemplos disponibles." : exampleLines)

        No repitas ninguna de estas preguntas ya existentes para este módulo:
        \(existingTexts.isEmpty ? "Ninguna." : existingTexts.map { "- \($0)" }.joined(separator: "\n"))

        Escribe una pregunta nueva con EXACTAMENTE 4 opciones, de las cuales una sola es correcta.

        Responde ÚNICAMENTE con un objeto JSON con esta forma exacta, en español, sin texto adicional:
        {
          "question": "el enunciado",
          "options": ["opción A", "opción B", "opción C", "opción D"],
          "correctIndex": 0
        }
        """
    }

    private static func theoryQuestion(question: String, object: [String: Any]) throws -> AssessmentQuestion {
        guard let rawOptions = object["options"] as? [String],
              let correctIndex = object["correctIndex"] as? Int else {
            throw AIServiceError.invalidResponse
        }
        let texts = rawOptions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard texts.count == 4, texts.allSatisfy({ !$0.isEmpty }), (0...3).contains(correctIndex) else {
            throw AIServiceError.invalidResponse
        }
        var options = texts.enumerated().map { index, text in
            AssessmentOption(text: text, points: index == correctIndex ? 1 : 0)
        }
        options.append(AssessmentOption(text: "No lo sé.", points: 0))
        return AssessmentQuestion(question: question, options: options)
    }

    // MARK: - Duplicados

    private static func isDuplicate(_ question: String, of existingTexts: [String]) -> Bool {
        let normalized = normalize(question)
        return existingTexts.contains { normalize($0) == normalized }
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
