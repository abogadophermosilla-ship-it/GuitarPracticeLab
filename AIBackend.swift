import Foundation

struct AICompletionSource: Codable, Equatable, Sendable {
    enum Provider: String, Codable, Sendable {
        case gemini
        case local
    }

    var provider: Provider
    var model: String

    var displayName: String {
        switch provider {
        case .gemini:
            if model == "gemini-3.8-flash" { return "Gemini 3.8 Flash" }
            if model == "gemini-3.7-flash" { return "Gemini 3.7 Flash" }
            return "Gemini · \(model)"
        case .local:
            return "IA local · \(model)"
        }
    }
}

/// Fuente pública devuelta por el grounding de Google Search. Se guarda junto al mensaje para que
/// la respuesta siga siendo auditable después de cerrar la app, sin confiar en enlaces escritos
/// por el modelo dentro de su propio JSON.
struct WebSource: Codable, Equatable, Identifiable, Sendable {
    var title: String
    var url: String

    var id: String { url }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return host ?? "Fuente web" }
        return trimmed
    }

    var host: String? {
        guard let value = URL(string: url)?.host(percentEncoded: false) else { return nil }
        let normalized = value.replacingOccurrences(of: "www.", with: "")
        // GenerateContent puede entregar un redirect de atribución en vez de la URL final. En ese
        // caso el título sigue identificando la fuente, pero mostrar el host de Google confundiría.
        guard normalized != "vertexaisearch.cloud.google.com" else { return nil }
        return normalized
    }
}

struct GroundedJSONCompletion: Sendable {
    var text: String
    var sources: [WebSource]
    var searchAttributionHTML: String?
}

/// Interfaz común para cualquier backend de IA que devuelva una única respuesta en JSON a partir
/// de un prompt — la cumplen tanto `GeminiService` (nube) como `LocalGatewayService` (local), así
/// los servicios de coaching no dependen de cuál de los dos se use.
protocol JSONCompletionBackend {
    func completeJSON(prompt: String) async throws -> String
    func completionSource() async -> AICompletionSource?
}

/// Capacidad adicional, deliberadamente separada del backend común: una consulta que pide Internet
/// no puede degradarse silenciosamente al modelo local, porque eso aparentaría haber investigado
/// fuentes que nunca se consultaron.
protocol GroundedJSONCompletionBackend: JSONCompletionBackend {
    func completeGroundedJSON(prompt: String) async throws -> GroundedJSONCompletion
}

extension JSONCompletionBackend {
    func completionSource() async -> AICompletionSource? { nil }
}

enum FallbackJSONCompletionError: LocalizedError {
    case bothFailed(primary: String, fallback: String)

    var errorDescription: String? {
        switch self {
        case .bothFailed(let primary, let fallback):
            "Gemini no pudo completar la petición (\(primary)). El respaldo local también falló (\(fallback))."
        }
    }
}

/// Ejecuta siempre el proveedor principal y consulta el modelo local únicamente cuando la llamada
/// principal falla. El protocolo común mantiene este detalle fuera de todos los servicios de coach
/// y deja abierta una migración futura a otro proveedor sin reescribirlos.
struct FallbackJSONCompletionBackend: JSONCompletionBackend {
    let primary: JSONCompletionBackend
    let fallback: JSONCompletionBackend
    private let trace: AICompletionSourceTrace

    init(primary: JSONCompletionBackend, fallback: JSONCompletionBackend) {
        self.primary = primary
        self.fallback = fallback
        self.trace = AICompletionSourceTrace()
    }

    func completeJSON(prompt: String) async throws -> String {
        do {
            let result = try await primary.completeJSON(prompt: prompt)
            await trace.record(await primary.completionSource())
            return result
        } catch {
            let primaryError = error
            if Self.isCancellation(error) { throw error }
            try Task.checkCancellation()

            do {
                let result = try await fallback.completeJSON(prompt: prompt)
                await trace.record(await fallback.completionSource())
                return result
            } catch {
                if Self.isCancellation(error) { throw error }
                try Task.checkCancellation()
                throw FallbackJSONCompletionError.bothFailed(
                    primary: primaryError.localizedDescription,
                    fallback: error.localizedDescription
                )
            }
        }
    }

    func completionSource() async -> AICompletionSource? {
        await trace.current
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return (error as? URLError)?.code == .cancelled
    }
}

private actor AICompletionSourceTrace {
    private(set) var current: AICompletionSource?

    func record(_ source: AICompletionSource?) {
        current = source
    }
}
