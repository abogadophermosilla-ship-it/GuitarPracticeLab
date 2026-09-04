import Foundation

enum LocalGatewayError: LocalizedError {
    case serverUnreachable(String)
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .serverUnreachable(let reason):
            "No se pudo conectar con Ollama (\(reason)). Verifica que esté corriendo (\"ollama serve\") o revisa la dirección en Configuración."
        case .invalidResponse:
            "Ollama devolvió una respuesta que no pudo interpretarse."
        case .server(let message):
            message
        }
    }
}

struct GatewayMessage: Codable {
    let role: String
    let content: String
}

/// Backend real de IA local — habla directo el protocolo nativo de Ollama (`/api/chat`), no el
/// compatible con OpenAI. Cambiado el 2026-08-01: se probó en vivo que el endpoint
/// `/v1/chat/completions` de Ollama (versión 0.32.5 instalada) NO respeta `"think": false` y siempre
/// devuelve el razonamiento completo de los modelos Qwen3 (10-19s incluso para un prompt trivial de
/// una línea), mientras que `/api/chat` con `"think": false` responde en fracciones de segundo una
/// vez el modelo está cargado. El nombre del tipo se mantiene (no se renombró) porque
/// `AIOrchestrator`/`SettingsView` ya lo referencian así — solo cambió el transporte interno.
struct LocalGatewayService: JSONCompletionBackend {
    static let defaultHost = "http://127.0.0.1:11434"

    /// Cuánto queda el modelo residente en memoria después de responder. El valor por omisión de
    /// Ollama son 5 minutos (medido el 2026-08-06: `qwen3:8b` retuvo 10.4 GB durante 5 minutos de
    /// inactividad total y los soltó al segundo exacto), que es justo lo que el usuario reportó como
    /// "los modelos siguen corriendo pese a no estar haciendo una tarea". 2 minutos alcanza para
    /// encadenar un par de acciones seguidas sin recargar, y libera bastante antes.
    static let defaultKeepAlive = "2m"

    /// Keep-alive largo para una tanda de llamadas seguidas (por ejemplo generar candidatas para las
    /// 38 habilidades): recargar el modelo entre una y otra sería carísimo, más aún porque los
    /// modelos viven en un volumen externo. Al terminar la tanda hay que llamar a
    /// `releaseModel(_:host:)` en vez de esperar a que expire.
    static let batchKeepAlive = "15m"

    /// Tokens de contexto reservados por llamada. Sin este parámetro Ollama reserva su valor por
    /// omisión de 32768, y con `OLLAMA_KV_CACHE_TYPE=f16` eso son ~4.6 GB de caché KV solo para
    /// `qwen3:8b` — el 45% de su huella (medido el 2026-08-06). Los prompts reales de las funciones
    /// que siguen corriendo en local midieron entre 389 y 696 tokens, y el más grande posible es el
    /// borrador desde OCR, acotado a 12.000 caracteres (~4.000 tokens). 16384 deja un margen de 4x
    /// sobre ese peor caso y aun así reduce la caché KV a la mitad.
    ///
    /// Cuidado al bajarlo más: si un prompt supera este valor, Ollama recorta el contexto en
    /// silencio y la respuesta se degrada sin ningún error visible.
    static let contextTokens = 16384

    var host: String = LocalGatewayService.defaultHost
    var model: String
    var keepAlive: String = LocalGatewayService.defaultKeepAlive

    func completionSource() async -> AICompletionSource? {
        AICompletionSource(provider: .local, model: model)
    }

    func completeJSON(prompt: String) async throws -> String {
        let request = try makeRequest(messages: [GatewayMessage(role: "user", content: prompt)])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LocalGatewayError.serverUnreachable(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LocalGatewayError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let payload = String(data: data, encoding: .utf8) ?? "Error HTTP \(http.statusCode)"
            throw LocalGatewayError.server(payload)
        }

        let decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        let content = decoded.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw LocalGatewayError.invalidResponse
        }
        return content
    }

    /// Confirma si Ollama responde, sin cargar ningún modelo en memoria. Devuelve `nil` si está
    /// disponible, o el error real (mensaje del sistema, no genérico) si no.
    static func reachabilityError(host: String = LocalGatewayService.defaultHost) async -> LocalGatewayError? {
        guard let url = URL(string: "\(host)/api/tags") else {
            return .serverUnreachable("dirección inválida: \(host)")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                return .server("HTTP \(http.statusCode)")
            }
            return nil
        } catch {
            return .serverUnreachable(error.localizedDescription)
        }
    }

    static func isReachable(host: String = LocalGatewayService.defaultHost) async -> Bool {
        await reachabilityError(host: host) == nil
    }

    private func makeRequest(messages: [GatewayMessage]) throws -> URLRequest {
        guard let url = URL(string: "\(host)/api/chat") else {
            throw LocalGatewayError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // "think: false" evita el razonamiento largo de los modelos Qwen3 en /api/chat — confirmado
        // en vivo (ver comentario del tipo) que sin esto una llamada trivial tarda 10-19s en vez de
        // fracciones de segundo.
        request.httpBody = try JSONEncoder().encode(OllamaChatRequest(
            model: model,
            messages: messages,
            stream: false,
            format: "json",
            think: false,
            keepAlive: keepAlive,
            options: OllamaOptions(numCtx: LocalGatewayService.contextTokens)
        ))
        return request
    }

    /// Descarga de memoria UN modelo puntual, sin matar el servicio de Ollama. Se usa al terminar una
    /// tanda para no dejar ocupados varios GB esperando a que expire el keep-alive.
    ///
    /// Recibe el tag exacto que cargó quien llama, a propósito: una versión anterior consultaba
    /// `/api/ps` y descargaba TODO lo residente, lo que desalojaba también modelos que esta app no
    /// había cargado — por ejemplo el que el usuario tenga corriendo en su terminal o en otra
    /// herramienta de Ollama en esta misma máquina.
    ///
    /// Los errores se ignoran a propósito: esto es una cortesía de limpieza, no una operación de la
    /// que dependa ninguna función.
    static func releaseModel(_ model: String, host: String = LocalGatewayService.defaultHost) async {
        guard !model.isEmpty, let unloadURL = URL(string: "\(host)/api/generate") else { return }
        var request = URLRequest(url: unloadURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(OllamaUnloadRequest(model: model, keepAlive: 0))
        _ = try? await URLSession.shared.data(for: request)
    }
}

private struct OllamaChatRequest: Encodable {
    let model: String
    let messages: [GatewayMessage]
    let stream: Bool
    let format: String
    let think: Bool
    let keepAlive: String
    let options: OllamaOptions

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, format, think, options
        case keepAlive = "keep_alive"
    }
}

private struct OllamaOptions: Encodable {
    let numCtx: Int

    enum CodingKeys: String, CodingKey {
        case numCtx = "num_ctx"
    }
}

private struct OllamaUnloadRequest: Encodable {
    let model: String
    let keepAlive: Int

    enum CodingKeys: String, CodingKey {
        case model
        case keepAlive = "keep_alive"
    }
}


private struct OllamaChatResponse: Decodable {
    let message: GatewayMessage
}
