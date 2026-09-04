import Foundation

/// Sugerencia de equipo/ajustes de tono para una canción del repertorio, a partir del equipo
/// (`StudioAsset`) e instrumentos (`Instrument`) reales del alumno — mismo patrón prompt→JSON que
/// `SongCoachService`. Solo texto de lectura, sin selección/confirmación: no hay nada que aplicar a
/// un modelo de datos.
enum GearCoachService {
    static func suggestSetup(
        songTitle: String,
        artist: String,
        equipment: [StudioAsset],
        instruments: [Instrument],
        backend: JSONCompletionBackend
    ) async throws -> String {
        let equipmentLines = equipment.map {
            "- [\($0.assetType.rawValue)] \($0.name) (categoría: \($0.category), uso: \($0.usage))"
        }.joined(separator: "\n")

        let instrumentLines = instruments.map {
            "- \($0.name) (\($0.kind), afinación: \($0.tuning))"
        }.joined(separator: "\n")

        let artistLine = artist.isEmpty ? "" : " del artista/banda \(artist)"

        let prompt = """
        Eres un asistente de tono y equipo para guitarra. El alumno quiere una sugerencia de ampli, \
        pedales o ajustes para tocar la canción "\(songTitle)"\(artistLine), usando ÚNICAMENTE el \
        equipo e instrumentos reales que tiene disponibles, listados abajo. No inventes equipo que no \
        esté en estas listas — si no hay nada que calce bien, dilo explícitamente en vez de inventar.

        Equipo y software disponible:
        \(equipmentLines.isEmpty ? "Ninguno registrado." : equipmentLines)

        Instrumentos disponibles:
        \(instrumentLines.isEmpty ? "Ninguno registrado." : instrumentLines)

        Responde con una recomendación de 2 a 4 oraciones, en español, concreta y práctica.

        Responde solo JSON:
        { "summary": "recomendación de equipo/tono en 2 a 4 oraciones" }
        """

        let raw = try await backend.completeJSON(prompt: prompt)
        let object = try JSONAIParser.object(from: raw)
        guard let summary = object["summary"] as? String, !summary.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return summary
    }
}
