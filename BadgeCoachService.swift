import Foundation

/// Mensaje de felicitación generado por IA para una insignia ya ganada — mismo patrón prompt→JSON
/// que `RoutineCoachService`, pero acá no hay ajustes que aplicar ni datos que guardar: es solo texto
/// de lectura, pedido bajo demanda desde el popover de la insignia en Progreso.
enum BadgeCoachService {
    static func congratulate(
        badge: BadgeDefinition,
        dateEarned: Date,
        currentStreakDays: Int,
        backend: JSONCompletionBackend
    ) async throws -> String {
        let prompt = """
        Eres un coach de práctica de guitarra. El alumno acaba de ganar (o ya tiene ganada) esta \
        insignia real de la app:

        Insignia: \(badge.title) (\(badge.category.rawValue), rango Challenger)
        Descripción: \(badge.subtitle)
        Fecha en que la ganó: \(dateEarned.formatted(date: .abbreviated, time: .omitted))
        Racha actual de práctica: \(currentStreakDays) día\(currentStreakDays == 1 ? "" : "s") seguidos.

        Escribe un mensaje de felicitación de 1 a 2 oraciones, en español, tono cercano y natural \
        (no genérico tipo "¡felicidades!"), citando el logro concreto de la insignia.

        Responde solo JSON:
        { "message": "mensaje de felicitación de 1 a 2 oraciones" }
        """

        let raw = try await backend.completeJSON(prompt: prompt)
        let object = try JSONAIParser.object(from: raw)
        guard let message = object["message"] as? String, !message.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return message
    }
}
