import Foundation
import OSLog

enum GeminiServiceError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case noGroundingSources
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Agrega una clave de la API de Gemini en Configuración."
        case .invalidResponse:
            "Gemini devolvió una respuesta que no pudo interpretarse."
        case .noGroundingSources:
            "Google Search no devolvió fuentes verificables. Reformula la búsqueda o vuelve a intentarlo."
        case .server(let message):
            message
        }
    }
}

struct GeminiMonthlyUsageSnapshot: Codable, Equatable {
    var month = ""
    var requestCount = 0
    var inputTokens = 0
    var cachedInputTokens = 0
    var outputTokens = 0
    var thoughtTokens = 0
    var estimatedUSD = 0.0

    static let empty = GeminiMonthlyUsageSnapshot()

    var billedOutputTokens: Int { outputTokens + thoughtTokens }
}

/// Registro local del consumo informado por `usageMetadata`. No consulta ni modifica la cuenta de
/// Google: sirve para ver cuánto genera esta app, separado de otros clientes que usen la misma clave.
actor GeminiUsageLedger {
    static let shared = GeminiUsageLedger()

    private let storageKey = "geminiMonthlyUsageV1"
    private let defaults = UserDefaults.standard

    func record(model: String, usage: GeminiUsageMetadata, date: Date = .now) {
        var store = loadStore()
        let key = Self.monthKey(for: date)
        var snapshot = store[key] ?? GeminiMonthlyUsageSnapshot(month: key)
        snapshot.requestCount += 1
        snapshot.inputTokens += usage.promptTokenCount ?? 0
        snapshot.cachedInputTokens += usage.cachedContentTokenCount ?? 0
        snapshot.outputTokens += usage.candidatesTokenCount ?? 0
        snapshot.thoughtTokens += usage.thoughtsTokenCount ?? 0
        snapshot.estimatedUSD += Self.estimatedCostUSD(model: model, usage: usage, date: date)
        store[key] = snapshot
        if let data = try? JSONEncoder().encode(store) {
            defaults.set(data, forKey: storageKey)
        }
    }

    func currentMonth(date: Date = .now) -> GeminiMonthlyUsageSnapshot {
        let key = Self.monthKey(for: date)
        return loadStore()[key] ?? GeminiMonthlyUsageSnapshot(month: key)
    }

    /// Clave del tope mensual en dólares. `0` (el valor por defecto) significa sin tope.
    static let budgetDefaultsKey = "geminiMonthlyBudgetUSD"

    /// Lectura sincrónica del gasto del mes, para decidir el backend sin esperar al actor.
    ///
    /// El orquestador tiene que resolver esto antes de cada llamada y en un camino que ya es
    /// sensible a la latencia; el registro vive en `UserDefaults`, así que leerlo directo es exacto
    /// salvo por una escritura en vuelo — un margen irrelevante frente a un tope mensual.
    nonisolated static func spentThisMonthUSD(date: Date = .now) -> Double {
        guard let data = UserDefaults.standard.data(forKey: "geminiMonthlyUsageV1"),
              let store = try? JSONDecoder().decode([String: GeminiMonthlyUsageSnapshot].self, from: data)
        else { return 0 }
        return store[monthKey(for: date)]?.estimatedUSD ?? 0
    }

    /// Tope configurado, o `nil` si el usuario no puso ninguno.
    nonisolated static func monthlyBudgetUSD() -> Double? {
        let value = UserDefaults.standard.double(forKey: budgetDefaultsKey)
        return value > 0 ? value : nil
    }

    /// `true` cuando el gasto estimado del mes ya alcanzó el tope configurado.
    nonisolated static func budgetIsExhausted(date: Date = .now) -> Bool {
        guard let budget = monthlyBudgetUSD() else { return false }
        return spentThisMonthUSD(date: date) >= budget
    }

    private func loadStore() -> [String: GeminiMonthlyUsageSnapshot] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: GeminiMonthlyUsageSnapshot].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func monthKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    private static func estimatedCostUSD(model: String, usage: GeminiUsageMetadata, date: Date) -> Double {
        guard let price = pricing(for: model, date: date) else { return 0 }
        let prompt = max(0, usage.promptTokenCount ?? 0)
        let cached = min(prompt, max(0, usage.cachedContentTokenCount ?? 0))
        let regularInput = prompt - cached
        let output = max(0, usage.candidatesTokenCount ?? 0) + max(0, usage.thoughtsTokenCount ?? 0)
        return Double(regularInput) * price.input / 1_000_000
            + Double(cached) * price.cachedInput / 1_000_000
            + Double(output) * price.output / 1_000_000
    }

    static func pricing(for model: String, date: Date) -> (input: Double, cachedInput: Double, output: Double)? {
        if model.hasPrefix("gemini-3.8-flash")
            || model.hasPrefix("gemini-3.7-flash")
            || model.hasPrefix("gemini-3.6-flash") {
            let cutoff = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2027, month: 1, day: 1))!
            return date < cutoff ? (0.75, 0.075, 3.75) : (1.50, 0.15, 7.50)
        }
        if model.hasPrefix("gemini-3.5-flash-lite") { return (0.30, 0.03, 2.50) }
        if model.hasPrefix("gemini-3.5-flash") { return (1.50, 0.15, 9.00) }
        return nil
    }
}

/// Ventana corta que evita cobrar dos veces exactamente la misma llamada.
///
/// Es un caché efímero: a los 60 segundos el prompt vuelve a viajar. Existe para el caso
/// concreto de repetir la misma petición sin querer — doble clic en "Generar", una vista que se
/// recompone y relanza su tarea, dos herramientas que arman el mismo contexto en la misma pantallada.
/// Deliberadamente NO es más largo: "sugerir de nuevo" un minuto después debe poder dar otra
/// respuesta, que es justamente lo que se espera de esos botones.
actor GeminiRequestCoalescer {
    static let shared = GeminiRequestCoalescer()

    private struct Entry {
        let response: String
        let storedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<String, Error>] = [:]
    private let ttl: TimeInterval = 60

    private static func key(model: String, prompt: String) -> String {
        // Conservar el prompt exacto evita las colisiones posibles de `hashValue`. La memoria queda
        // acotada por el TTL de 60 s y por la limpieza que ocurre al completar cada llamada.
        "\(model)\u{0}\(prompt)"
    }

    func response(
        model: String,
        prompt: String,
        operation: @escaping @Sendable () async throws -> String
    ) async throws -> String {
        let key = Self.key(model: model, prompt: prompt)
        let now = Date.now
        entries = entries.filter { now.timeIntervalSince($0.value.storedAt) < ttl }
        if let entry = entries[key] {
            return entry.response
        }
        if let existing = inFlight[key] {
            return try await existing.value
        }

        let task = Task { try await operation() }
        inFlight[key] = task
        do {
            let response = try await task.value
            inFlight[key] = nil
            let completedAt = Date.now
            entries = entries.filter { completedAt.timeIntervalSince($0.value.storedAt) < ttl }
            entries[key] = Entry(response: response, storedAt: completedAt)
            return response
        } catch {
            inFlight[key] = nil
            throw error
        }
    }
}

struct GeminiService: GroundedJSONCompletionBackend {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "GuitarPracticeLab",
        category: "Gemini"
    )

    var apiKey: String
    var model: String = AIOrchestrator.defaultPaidAPIModel
    private let sourceTrace: GeminiCompletionSourceTrace
    private let session: URLSession

    init(
        apiKey: String,
        model: String = AIOrchestrator.defaultPaidAPIModel,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.sourceTrace = GeminiCompletionSourceTrace()
        self.session = session
    }

    func completionSource() async -> AICompletionSource? {
        AICompletionSource(provider: .gemini, model: await sourceTrace.model ?? model)
    }

    func completeJSON(prompt: String) async throws -> String {
        try await GeminiRequestCoalescer.shared.response(model: model, prompt: prompt) {
            try await completeJSON(
                prompt: prompt,
                requestModel: model,
                remainingServerRetries: 1,
                remainingTimeoutRetries: 1,
                remainingAvailabilityFallbacks: Self.availabilityFallbackModels(after: model),
                usesGoogleSearch: false
            )
        }
    }

    /// Ejecuta una búsqueda pública real mediante la herramienta administrada de Google. Las
    /// fuentes salen de `groundingMetadata`, no de texto o URLs que el modelo pudiera inventar.
    func completeGroundedJSON(prompt: String) async throws -> GroundedJSONCompletion {
        let result = try await requestJSON(
            prompt: prompt,
            requestModel: model,
            remainingServerRetries: 1,
            remainingTimeoutRetries: 1,
            remainingAvailabilityFallbacks: Self.availabilityFallbackModels(after: model),
            usesGoogleSearch: true
        )
        guard !result.webSources.isEmpty else {
            throw GeminiServiceError.noGroundingSources
        }
        return GroundedJSONCompletion(
            text: result.text,
            sources: result.webSources,
            searchAttributionHTML: result.searchAttributionHTML
        )
    }

    /// Comprueba credencial, modelo, red y formato de respuesta con una llamada mínima real.
    /// Evita el caché/coalescer a propósito: Configuración debe validar la clave escrita ahora,
    /// aunque haya una respuesta idéntica reciente obtenida con otra credencial.
    func checkConnection() async throws -> String {
        let result = try await requestJSON(
            prompt: #"Devuelve exactamente el objeto JSON {"ok":true}, sin claves adicionales."#,
            requestModel: model,
            remainingServerRetries: 0,
            remainingTimeoutRetries: 0,
            remainingAvailabilityFallbacks: Self.availabilityFallbackModels(after: model),
            usesGoogleSearch: false
        )
        return result.modelVersion ?? model
    }

    /// Los modelos estables comparten API pero no necesariamente el mismo pool de capacidad.
    /// Ante un 503 del modelo preferido se intenta una alternativa estable antes de abandonar la
    /// nube o cargar el respaldo local. No se usa para errores de clave, permisos o cuota.
    static func availabilityFallbackModels(after model: String) -> [String] {
        switch model {
        case "gemini-3.8-flash": ["gemini-3.7-flash"]
        case "gemini-3.7-flash": ["gemini-3.6-flash"]
        default: []
        }
    }

    /// 3.8 es el modelo preferido, pero no debe retener una herramienta durante minutos cuando su
    /// pool está saturado. 3.7 queda como alternativa inmediata; 3.6 conserva más margen cuando fue
    /// elegido directamente y es la última alternativa de nube antes del respaldo local.
    static func requestTimeout(for model: String) -> TimeInterval {
        switch model {
        case "gemini-3.8-flash": 45
        case "gemini-3.7-flash": 35
        case "gemini-3.6-flash": 75
        default: 120
        }
    }

    private func completeJSON(
        prompt: String,
        requestModel: String,
        remainingServerRetries: Int,
        remainingTimeoutRetries: Int,
        remainingAvailabilityFallbacks: [String],
        usesGoogleSearch: Bool
    ) async throws -> String {
        let result = try await requestJSON(
            prompt: prompt,
            requestModel: requestModel,
            remainingServerRetries: remainingServerRetries,
            remainingTimeoutRetries: remainingTimeoutRetries,
            remainingAvailabilityFallbacks: remainingAvailabilityFallbacks,
            usesGoogleSearch: usesGoogleSearch
        )
        return result.text
    }

    private func requestJSON(
        prompt: String,
        requestModel: String,
        remainingServerRetries: Int,
        remainingTimeoutRetries: Int,
        remainingAvailabilityFallbacks: [String],
        usesGoogleSearch: Bool
    ) async throws -> GeminiResponseParser.Parsed {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw GeminiServiceError.missingAPIKey
        }
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(requestModel):generateContent") else {
            throw GeminiServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeout(for: requestModel)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(trimmedKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(GeminiRequest(
            contents: [GeminiContent(role: "user", parts: [GeminiPart(text: prompt)])],
            generationConfig: GeminiGenerationConfig(responseMimeType: "application/json"),
            tools: usesGoogleSearch ? [GeminiTool(googleSearch: GeminiGoogleSearch())] : nil
        ))

        let data: Data
        let response: URLResponse
        do {
            Self.logger.info("Iniciando solicitud con \(requestModel, privacy: .public)")
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            // Una espera excesiva del modelo preferido es otra forma de indisponibilidad. Cambiar
            // de pool aquí evita repetir el modelo preferido antes de probar su alternativa estable.
            if let fallbackModel = remainingAvailabilityFallbacks.first {
                Self.logger.notice(
                    "\(requestModel, privacy: .public) agotó el tiempo; cambiando a \(fallbackModel, privacy: .public)"
                )
                return try await requestJSON(
                    prompt: prompt,
                    requestModel: fallbackModel,
                    remainingServerRetries: 0,
                    remainingTimeoutRetries: 0,
                    remainingAvailabilityFallbacks: Array(remainingAvailabilityFallbacks.dropFirst()),
                    usesGoogleSearch: usesGoogleSearch
                )
            }
            if remainingTimeoutRetries > 0 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return try await requestJSON(
                    prompt: prompt,
                    requestModel: requestModel,
                    remainingServerRetries: remainingServerRetries,
                    remainingTimeoutRetries: remainingTimeoutRetries - 1,
                    remainingAvailabilityFallbacks: remainingAvailabilityFallbacks,
                    usesGoogleSearch: usesGoogleSearch
                )
            }
            throw GeminiServiceError.server(
                "Gemini tardó demasiado en responder. Se probaron las alternativas disponibles; vuelve a intentarlo en unos minutos."
            )
        }
        guard let http = response as? HTTPURLResponse else {
            throw GeminiServiceError.invalidResponse
        }

        // Un 503 puede afectar a un pool de modelo y no a otro. Cambiar de 3.8 a 3.7 (o de 3.7 a
        // 3.6 cuando este se eligió directamente) evita insistir en el mismo pool. La alternativa
        // se intenta una sola vez; si también falla, el orquestador todavía puede usar Ollama.
        if http.statusCode == 503, let fallbackModel = remainingAvailabilityFallbacks.first {
            Self.logger.notice(
                "\(requestModel, privacy: .public) devolvió 503; cambiando a \(fallbackModel, privacy: .public)"
            )
            return try await requestJSON(
                prompt: prompt,
                requestModel: fallbackModel,
                remainingServerRetries: 0,
                remainingTimeoutRetries: 0,
                remainingAvailabilityFallbacks: Array(remainingAvailabilityFallbacks.dropFirst()),
                usesGoogleSearch: usesGoogleSearch
            )
        }

        // 429 = límites; 500/502/503/504 = errores temporales del lado de Google. Para modelos sin
        // alternativa se conserva un reintento corto, respetando Retry-After si viene informado.
        let isRetryable = http.statusCode == 429 || (500...504).contains(http.statusCode)
        if isRetryable, remainingServerRetries > 0 {
            let suggested = Double(http.value(forHTTPHeaderField: "retry-after") ?? "")
            let wait = suggested ?? 4
            try? await Task.sleep(nanoseconds: UInt64((wait + 0.5) * 1_000_000_000))
            return try await requestJSON(
                prompt: prompt,
                requestModel: requestModel,
                remainingServerRetries: remainingServerRetries - 1,
                remainingTimeoutRetries: remainingTimeoutRetries,
                remainingAvailabilityFallbacks: remainingAvailabilityFallbacks,
                usesGoogleSearch: usesGoogleSearch
            )
        }

        guard (200..<300).contains(http.statusCode) else {
            Self.logger.error(
                "\(requestModel, privacy: .public) terminó con HTTP \(http.statusCode, privacy: .public)"
            )
            throw GeminiServiceError.server(Self.readableMessage(status: http.statusCode, data: data))
        }

        let parsed = try GeminiResponseParser.parse(data)
        if let usage = parsed.usage {
            await GeminiUsageLedger.shared.record(model: requestModel, usage: usage)
        }
        await sourceTrace.record(requestModel)
        Self.logger.info("Solicitud completada con \(requestModel, privacy: .public)")
        return GeminiResponseParser.Parsed(
            text: parsed.text,
            usage: parsed.usage,
            modelVersion: parsed.modelVersion ?? requestModel,
            webSources: parsed.webSources,
            searchAttributionHTML: parsed.searchAttributionHTML
        )
    }

    /// Traduce el error de Google a algo accionable, en vez de volcar el JSON crudo en pantalla.
    static func readableMessage(status: Int, data: Data) -> String {
        let apiError = try? JSONDecoder().decode(GeminiAPIErrorEnvelope.self, from: data).error
        let detail = apiError?.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let reason = apiError?.details?.compactMap(\.reason).first ?? ""
        let googleDetail = detail.isEmpty ? "" : " Google: \(detail.prefix(300))"

        if reason == "API_KEY_INVALID" || detail.localizedCaseInsensitiveContains("API key not valid") {
            return "La clave de Gemini no es válida. Crea o copia una clave vigente desde Google AI Studio y vuelve a guardarla en Configuración."
        }

        switch status {
        case 503:
            return "Google tiene el modelo saturado o no disponible en este momento (error 503). Se reintentó sin éxito; vuelve a intentarlo más tarde o cambia el modelo en Configuración.\(googleDetail)"
        case 429:
            return "Gemini rechazó la llamada por un límite de solicitudes, tokens, cuota o gasto (error 429). Revisa los límites y la facturación del proyecto en Google AI Studio.\(googleDetail)"
        case 400:
            if apiError?.status == "FAILED_PRECONDITION" {
                return "El proyecto de Gemini no cumple un requisito de la API (error 400), normalmente facturación o disponibilidad regional. Revísalo en Google AI Studio.\(googleDetail)"
            }
            return "Google rechazó el formato de la petición (error 400).\(googleDetail)"
        case 401:
            return "Google no pudo autenticar la clave de Gemini (error 401). Vuelve a copiarla y guardarla en Configuración.\(googleDetail)"
        case 403:
            return "La clave o su proyecto no tienen permiso para usar Gemini o este modelo (error 403). Revisa las restricciones de la clave y el proyecto en Google AI Studio.\(googleDetail)"
        case 404:
            return "El modelo indicado en Configuración no existe, no está disponible para este proyecto o no admite esta operación (error 404).\(googleDetail)"
        case 500:
            return "Gemini tuvo un error interno (error 500). Si se repite, reduce el contexto enviado o prueba otro modelo.\(googleDetail)"
        case 504:
            return "Gemini no alcanzó a procesar la petición (error 504). El contexto puede ser demasiado grande; vuelve a intentarlo o usa una tarea más acotada.\(googleDetail)"
        default:
            return "Gemini devolvió un error \(status).\(googleDetail)"
        }
    }
}

private actor GeminiCompletionSourceTrace {
    private(set) var model: String?

    func record(_ model: String) {
        self.model = model
    }
}

private struct GeminiRequest: Encodable {
    let contents: [GeminiContent]
    let generationConfig: GeminiGenerationConfig
    let tools: [GeminiTool]?
}

private struct GeminiTool: Encodable {
    let googleSearch: GeminiGoogleSearch

    enum CodingKeys: String, CodingKey {
        case googleSearch = "google_search"
    }
}

private struct GeminiGoogleSearch: Encodable {}

private struct GeminiContent: Codable {
    let role: String
    let parts: [GeminiPart]
}

private struct GeminiPart: Codable {
    let text: String?
    let thought: Bool?

    init(text: String?, thought: Bool? = nil) {
        self.text = text
        self.thought = thought
    }
}

private struct GeminiGenerationConfig: Encodable {
    let responseMimeType: String
}

private struct GeminiResponse: Decodable {
    struct Candidate: Decodable {
        let content: GeminiContent?
        let finishReason: String?
        let groundingMetadata: GeminiGroundingMetadata?
    }
    let candidates: [Candidate]?
    let usageMetadata: GeminiUsageMetadata?
    let promptFeedback: PromptFeedback?
    let modelVersion: String?
    let responseId: String?

    struct PromptFeedback: Decodable {
        let blockReason: String?
    }
}

/// Interpreta la respuesta completa antes de entregarla a los parsers específicos de cada función.
/// Gemini puede dividir el texto entre varias partes o terminar por límite/safety; aceptar solo la
/// primera parte convertía esos casos en JSON truncado y el error aparecía lejos de la API.
enum GeminiResponseParser {
    struct Parsed {
        let text: String
        let usage: GeminiUsageMetadata?
        let modelVersion: String?
        let webSources: [WebSource]
        let searchAttributionHTML: String?
    }

    static func parse(_ data: Data) throws -> Parsed {
        let decoded: GeminiResponse
        do {
            decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        } catch {
            throw GeminiServiceError.server(
                "Gemini respondió con un formato incompatible con la app. Actualiza la integración o prueba otro modelo."
            )
        }

        guard let candidate = decoded.candidates?.first else {
            if let reason = decoded.promptFeedback?.blockReason, !reason.isEmpty {
                throw GeminiServiceError.server(
                    "Gemini bloqueó la petición antes de generar una respuesta (\(reason)). Reformula el contenido e inténtalo de nuevo."
                )
            }
            throw GeminiServiceError.invalidResponse
        }

        let finishReason = candidate.finishReason ?? "STOP"
        guard finishReason == "STOP" else {
            switch finishReason {
            case "MAX_TOKENS":
                throw GeminiServiceError.server(
                    "Gemini cortó la respuesta por límite de salida (MAX_TOKENS), por lo que el JSON quedó incompleto. Reduce el contexto o divide la tarea."
                )
            case "SAFETY", "RECITATION", "LANGUAGE", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII", "IMAGE_SAFETY":
                throw GeminiServiceError.server(
                    "Gemini detuvo la respuesta por su filtro de contenido (\(finishReason)). Reformula la petición e inténtalo de nuevo."
                )
            default:
                throw GeminiServiceError.server(
                    "Gemini no completó la respuesta (\(finishReason)). Vuelve a intentarlo o usa otro modelo."
                )
            }
        }

        let text = candidate.content?.parts
            .filter { $0.thought != true }
            .compactMap(\.text)
            .joined() ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeminiServiceError.invalidResponse
        }

        return Parsed(
            text: text,
            usage: decoded.usageMetadata,
            modelVersion: decoded.modelVersion,
            webSources: webSources(from: candidate.groundingMetadata),
            searchAttributionHTML: candidate.groundingMetadata?.searchEntryPoint?.renderedContent
        )
    }

    private static func webSources(from metadata: GeminiGroundingMetadata?) -> [WebSource] {
        guard let chunks = metadata?.groundingChunks, !chunks.isEmpty else { return [] }
        let supportedIndexes = Set(
            (metadata?.groundingSupports ?? []).flatMap { $0.groundingChunkIndices ?? [] }
        )
        let indexes = supportedIndexes.isEmpty ? Array(chunks.indices) : supportedIndexes.sorted()
        var seenURLs = Set<String>()
        return indexes.compactMap { index in
            guard chunks.indices.contains(index), let web = chunks[index].web,
                  let url = URL(string: web.uri),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  seenURLs.insert(web.uri).inserted
            else { return nil }
            return WebSource(title: web.title ?? "", url: web.uri)
        }
    }
}

private struct GeminiGroundingMetadata: Decodable {
    struct Chunk: Decodable {
        struct Web: Decodable {
            let uri: String
            let title: String?
        }

        let web: Web?
    }

    struct Support: Decodable {
        let groundingChunkIndices: [Int]?
    }

    struct SearchEntryPoint: Decodable {
        let renderedContent: String?
    }

    let groundingChunks: [Chunk]?
    let groundingSupports: [Support]?
    let searchEntryPoint: SearchEntryPoint?
}

private struct GeminiAPIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let code: Int?
        let message: String?
        let status: String?
        let details: [Detail]?
    }

    struct Detail: Decodable {
        let reason: String?
    }

    let error: APIError
}

struct GeminiUsageMetadata: Decodable {
    let promptTokenCount: Int?
    let cachedContentTokenCount: Int?
    let candidatesTokenCount: Int?
    let thoughtsTokenCount: Int?
    let totalTokenCount: Int?
}
