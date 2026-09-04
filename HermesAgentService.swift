import Foundation

enum HermesAgentConfiguration {
    static let defaultHost = "http://127.0.0.1:8642"
    static let apiKeyAccount = "hermes-agent-api-key"
    static let sessionKeyDefaultsKey = "hermesAgentSessionKey"

    static var sessionKey: String {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: sessionKeyDefaultsKey), !stored.isEmpty {
            return stored
        }
        let created = "guitar-practice-lab-\(UUID().uuidString.lowercased())"
        defaults.set(created, forKey: sessionKeyDefaultsKey)
        return created
    }
}

enum HermesAgentError: LocalizedError {
    case missingAPIKey
    case invalidHost
    case insecureRemoteHost
    case providerNotConfigured
    case invalidResponse
    case runFailed(String)
    case server(status: Int, message: String)
    case connection(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Falta la clave de Hermes. Guárdala en Configuración → Profesor IA avanzado."
        case .invalidHost:
            "La dirección del gateway de Hermes no es válida."
        case .insecureRemoteHost:
            "Un gateway Hermes remoto debe usar HTTPS para no exponer la clave API."
        case .providerNotConfigured:
            "El gateway está activo, pero Hermes no tiene un proveedor de inferencia autenticado. Ejecuta “guitar-practice-lab model” en Terminal para elegirlo."
        case .invalidResponse:
            "Hermes devolvió una respuesta que la app no pudo interpretar."
        case .runFailed(let message):
            message
        case .server(let status, let message):
            "Hermes devolvió un error \(status): \(message)"
        case .connection(let message):
            "No se pudo conectar con Hermes: \(message)"
        }
    }
}

struct HermesChatMessage: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var role: String
    var content: String
    var createdAt: Date = .now
}

struct HermesConversationMessage: Encodable, Equatable {
    let role: String
    let content: String
}

enum HermesAgentEvent: Equatable {
    case textDelta(String)
    case toolStarted(name: String, detail: String)
    case toolFinished(name: String, failed: Bool)
    case reasoning
    case approvalRequested(String)
    case completed(String)
    case failed(String)
    case cancelled
}

/// Cliente del API HTTP de Hermes. Se mantiene separado de `LocalGatewayService`: Ollama usa su
/// protocolo nativo (`/api/chat`), mientras Hermes expone Runs + SSE bajo `/v1/runs`.
struct HermesAgentService {
    let host: String
    let apiKey: String
    let sessionKey: String

    init(
        host: String = HermesAgentConfiguration.defaultHost,
        apiKey: String,
        sessionKey: String = HermesAgentConfiguration.sessionKey
    ) {
        self.host = host
        self.apiKey = apiKey
        self.sessionKey = sessionKey
    }

    func checkConnection() async throws -> String {
        let request = try makeRequest(path: "/v1/capabilities")
        let (data, response) = try await perform(request)
        try validate(response: response, data: data)
        let capabilities = try JSONDecoder().decode(CapabilitiesResponse.self, from: data)
        guard capabilities.platform == "hermes-agent" else {
            throw HermesAgentError.invalidResponse
        }

        let optionsRequest = try makeRequest(path: "/api/model/options")
        let (optionsData, optionsResponse) = try await perform(optionsRequest)
        try validate(response: optionsResponse, data: optionsData)
        let options = try JSONDecoder().decode(ModelOptionsResponse.self, from: optionsData)
        let selectedProvider = options.providers.first {
            $0.isCurrent || $0.slug == options.provider
        }
        guard options.provider != "auto", selectedProvider?.authenticated == true else {
            throw HermesAgentError.providerNotConfigured
        }
        return options.model.isEmpty ? capabilities.model : options.model
    }

    func startRun(
        input: String,
        instructions: String,
        history: [HermesConversationMessage]
    ) async throws -> String {
        var request = try makeRequest(path: "/v1/runs", method: "POST")
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder().encode(RunRequest(
            input: input,
            instructions: instructions,
            conversationHistory: history,
            sessionID: sessionKey
        ))

        let (data, response) = try await perform(request)
        try validate(response: response, data: data, acceptedStatuses: 200..<300)
        let decoded = try JSONDecoder().decode(RunStartResponse.self, from: data)
        guard !decoded.runID.isEmpty else { throw HermesAgentError.invalidResponse }
        return decoded.runID
    }

    func events(for runID: String) throws -> AsyncThrowingStream<HermesAgentEvent, Error> {
        var request = try makeRequest(path: "/v1/runs/\(runID)/events")
        // Hermes puede tardar bastante en entregar el primer evento cuando recibe el snapshot
        // completo de aprendizaje o ejecuta razonamiento/herramientas. El timeout general de
        // 10 segundos sirve para las llamadas de control, pero es demasiado corto para SSE.
        request.timeoutInterval = 600

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw HermesAgentError.invalidResponse
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var payload = ""
                        for try await line in bytes.lines {
                            payload += line
                        }
                        throw HermesAgentError.server(
                            status: http.statusCode,
                            message: Self.readableServerMessage(from: Data(payload.utf8))
                        )
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard let event = Self.event(fromSSELine: line) else { continue }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.connectionError(from: error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func stop(runID: String) async throws {
        var request = try makeRequest(path: "/v1/runs/\(runID)/stop", method: "POST")
        request.timeoutInterval = 8
        request.httpBody = Data("{}".utf8)
        let (data, response) = try await perform(request)
        try validate(response: response, data: data)
    }

    func denyApproval(runID: String) async throws {
        var request = try makeRequest(path: "/v1/runs/\(runID)/approval", method: "POST")
        request.timeoutInterval = 8
        request.httpBody = try JSONEncoder().encode(ApprovalRequest(choice: "deny"))
        let (data, response) = try await perform(request)
        try validate(response: response, data: data)
    }

    static func normalizedBaseURL(from rawHost: String) throws -> URL {
        var value = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        if value.hasSuffix("/v1") { value.removeLast(3) }

        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              let host = url.host,
              scheme == "http" || scheme == "https" else {
            throw HermesAgentError.invalidHost
        }

        let isLoopback = host == "127.0.0.1" || host == "localhost" || host == "::1"
        guard scheme == "https" || isLoopback else {
            throw HermesAgentError.insecureRemoteHost
        }
        return url
    }

    /// Parser aislado para poder probar el contrato SSE sin levantar un gateway real.
    static func event(fromSSELine line: String) -> HermesAgentEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let data = json.data(using: .utf8),
              let wire = try? JSONDecoder().decode(WireEvent.self, from: data) else {
            return nil
        }

        switch wire.event {
        case "message.delta", "assistant.delta":
            guard let delta = wire.delta, !delta.isEmpty else { return nil }
            return .textDelta(delta)
        case "tool.started":
            return .toolStarted(
                name: wire.tool ?? "herramienta",
                detail: wire.preview ?? ""
            )
        case "tool.completed":
            return .toolFinished(name: wire.tool ?? "herramienta", failed: wire.toolFailed ?? false)
        case "tool.failed":
            return .toolFinished(name: wire.tool ?? "herramienta", failed: true)
        case "reasoning.available":
            return .reasoning
        case "approval.request":
            return .approvalRequested(wire.preview ?? wire.command ?? wire.tool ?? "acción protegida")
        case "run.completed":
            return .completed(wire.output ?? "")
        case "run.failed", "error":
            let message = wire.error ?? wire.message ?? "La ejecución falló."
            if message.localizedCaseInsensitiveContains("provider authentication failed") ||
                message.localizedCaseInsensitiveContains("no inference provider configured") {
                return .failed(
                    "Hermes no tiene un proveedor de inferencia autenticado. Ejecuta “guitar-practice-lab model” en Terminal y vuelve a intentarlo."
                )
            }
            return .failed(message)
        case "run.cancelled":
            return .cancelled
        default:
            return nil
        }
    }

    private func makeRequest(path: String, method: String = "GET") throws -> URLRequest {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw HermesAgentError.missingAPIKey }
        let baseURL = try Self.normalizedBaseURL(from: host)
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw HermesAgentError.invalidHost
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue(sessionKey, forHTTPHeaderField: "X-Hermes-Session-Key")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw Self.connectionError(from: error)
        }
    }

    private func validate(
        response: URLResponse,
        data: Data,
        acceptedStatuses: Range<Int> = 200..<300
    ) throws {
        guard let http = response as? HTTPURLResponse else {
            throw HermesAgentError.invalidResponse
        }
        guard acceptedStatuses.contains(http.statusCode) else {
            throw HermesAgentError.server(
                status: http.statusCode,
                message: Self.readableServerMessage(from: data)
            )
        }
    }

    private static func connectionError(from error: Error) -> Error {
        if error is HermesAgentError { return error }
        if error is CancellationError { return error }
        return HermesAgentError.connection(error.localizedDescription)
    }

    private static func readableServerMessage(from data: Data) -> String {
        if let payload = try? JSONDecoder().decode(ServerErrorEnvelope.self, from: data) {
            return payload.error.message
        }
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw?.isEmpty == false ? String(raw!.prefix(300)) : "respuesta no válida"
    }
}

@MainActor
final class HermesChatStore: ObservableObject {
    @Published private(set) var messages: [HermesChatMessage]

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder().decode([HermesChatMessage].self, from: data) {
            messages = decoded
        } else {
            messages = []
        }
    }

    func append(_ message: HermesChatMessage, persist: Bool = true) {
        messages.append(message)
        if persist { save() }
    }

    func update(id: UUID, content: String, persist: Bool = false) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = content
        if persist { save() }
    }

    func remove(id: UUID) {
        messages.removeAll { $0.id == id }
        save()
    }

    func persist() {
        save()
    }

    func clear() {
        messages = []
        save()
    }

    private func save() {
        do {
            let folder = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(messages)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // El historial mejora la experiencia, pero nunca debe impedir que el chat funcione.
        }
    }

    private static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("GuitarPracticeLab", isDirectory: true)
            .appendingPathComponent("hermes-chat.json")
    }
}

private struct CapabilitiesResponse: Decodable {
    let platform: String
    let model: String
}

private struct ModelOptionsResponse: Decodable {
    struct Provider: Decodable {
        let slug: String
        let isCurrent: Bool
        let authenticated: Bool

        enum CodingKeys: String, CodingKey {
            case slug, authenticated
            case isCurrent = "is_current"
        }
    }

    let model: String
    let provider: String
    let providers: [Provider]
}

private struct RunRequest: Encodable {
    let input: String
    let instructions: String
    let conversationHistory: [HermesConversationMessage]
    let sessionID: String

    enum CodingKeys: String, CodingKey {
        case input, instructions
        case conversationHistory = "conversation_history"
        case sessionID = "session_id"
    }
}

private struct RunStartResponse: Decodable {
    let runID: String

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
    }
}

private struct ApprovalRequest: Encodable {
    let choice: String
}

private struct WireEvent: Decodable {
    let event: String
    let delta: String?
    let output: String?
    let error: String?
    let toolFailed: Bool?
    let message: String?
    let tool: String?
    let preview: String?
    let command: String?

    enum CodingKeys: String, CodingKey {
        case event, delta, output, error, message, tool, preview, command
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        event = try container.decode(String.self, forKey: .event)
        delta = try? container.decode(String.self, forKey: .delta)
        output = try? container.decode(String.self, forKey: .output)
        error = try? container.decode(String.self, forKey: .error)
        toolFailed = try? container.decode(Bool.self, forKey: .error)
        message = try? container.decode(String.self, forKey: .message)
        tool = try? container.decode(String.self, forKey: .tool)
        preview = try? container.decode(String.self, forKey: .preview)
        command = try? container.decode(String.self, forKey: .command)
    }
}

private struct ServerErrorEnvelope: Decodable {
    struct Detail: Decodable {
        let message: String
    }
    let error: Detail
}
