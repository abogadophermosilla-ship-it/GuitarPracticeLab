import Foundation

enum AIOrchestratorError: LocalizedError {
    case systemBusy
    case missingPaidAPIKey
    case monthlyBudgetReached(spent: Double, budget: Double)
    case budgetReachedWithoutLocalBackend(spent: Double, budget: Double)

    var errorDescription: String? {
        switch self {
        case .systemBusy:
            "El sistema está muy ocupado ahora mismo (RAM o CPU al límite). Espera un momento e inténtalo de nuevo."
        case .missingPaidAPIKey:
            "Agrega la clave de la API pagada de Gemini en Configuración."
        case let .monthlyBudgetReached(spent, budget):
            "Alcanzaste el tope mensual de Gemini (US$ \(String(format: "%.2f", spent)) de US$ \(String(format: "%.2f", budget))). Súbelo o quítalo en Configuración para volver a usar la API pagada."
        case let .budgetReachedWithoutLocalBackend(spent, budget):
            "Alcanzaste el tope mensual de Gemini (US$ \(String(format: "%.2f", spent)) de US$ \(String(format: "%.2f", budget))) y el gateway local no está disponible para reemplazarlo. Enciende el gateway o ajusta el tope en Configuración."
        }
    }
}

/// Punto único de IA estructurada: usa Gemini pagado como proveedor principal y prepara, cuando la
/// máquina tiene margen y Ollama está disponible, el modelo local más adecuado como respaldo. Una
/// caída del respaldo nunca impide llamar a Gemini.
@MainActor
final class AIOrchestrator: ObservableObject {
    @Published private(set) var currentStatus = ""

    nonisolated static let paidAPIKeychainAccount = "gemini-api-key"
    nonisolated static let defaultPaidAPIModel = "gemini-3.8-flash"
    nonisolated static let paidAPIModelMigrationKey = "didMigrateGeminiDefaultTo38"

    /// Actualiza únicamente los modelos que fueron predeterminados anteriores. Un identificador
    /// escrito a mano se conserva, para no reemplazar configuraciones personalizadas del usuario.
    @discardableResult
    nonisolated static func migratePaidAPIModelIfNeeded(
        defaults: UserDefaults = .standard
    ) -> String {
        let stored = defaults.string(forKey: "geminiModel")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !defaults.bool(forKey: paidAPIModelMigrationKey) else {
            return stored.isEmpty ? defaultPaidAPIModel : stored
        }

        let previousDefaults = [
            "",
            "gemini-3.5-flash",
            "gemini-3.6-flash",
            "gemini-3.7-flash"
        ]
        let resolved = previousDefaults.contains(stored) ? defaultPaidAPIModel : stored
        if resolved != stored {
            defaults.set(resolved, forKey: "geminiModel")
        }
        defaults.set(true, forKey: paidAPIModelMigrationKey)
        return resolved
    }

    /// Último modelo local entregado por este orquestador, para poder descargar exactamente ese y no
    /// lo que hayan cargado otros — ver `releaseLocalModels()`.
    private var lastLocalModel: String?

    private var gatewayHost: String {
        let stored = UserDefaults.standard.string(forKey: "localGatewayHost")
        return (stored?.isEmpty == false) ? stored! : LocalGatewayService.defaultHost
    }

    private func paidAPIKey() throws -> String {
        // No convertir errores del Llavero en una cadena vacía: si la firma perdió el entitlement,
        // todas las funciones Gemini parecían tener una clave ausente aunque el ítem siguiera allí.
        try KeychainStore.readThrowing(account: AIOrchestrator.paidAPIKeychainAccount)
    }

    private var paidAPIModel: String {
        Self.migratePaidAPIModelIfNeeded()
    }

    /// Gemini pagado sin fallback. Se usa donde la función necesita atribuir correctamente si el
    /// resultado final vino de Gemini o del análisis local.
    func paidCloudBackend() throws -> JSONCompletionBackend {
        let key = try paidAPIKey()
        guard !key.isEmpty else {
            currentStatus = "Falta la clave de Gemini"
            throw AIOrchestratorError.missingPaidAPIKey
        }
        if let budget = GeminiUsageLedger.monthlyBudgetUSD(), GeminiUsageLedger.budgetIsExhausted() {
            let spent = GeminiUsageLedger.spentThisMonthUSD()
            currentStatus = "Tope mensual de Gemini alcanzado"
            throw AIOrchestratorError.monthlyBudgetReached(spent: spent, budget: budget)
        }
        let model = paidAPIModel
        currentStatus = "Gemini pagado · \(model)"
        return GeminiService(apiKey: key, model: model)
    }

    /// Backend habitual de la app. Gemini siempre es el primer intento. Si el sistema tiene recursos
    /// y Ollama responde, añade un respaldo local; si no, devuelve Gemini solo.
    ///
    /// `isBatch: true` mantiene el respaldo local residente durante una tanda y requiere llamar a
    /// `releaseLocalModels()` al terminar, igual que antes de introducir Gemini como principal.
    func backend(for weight: TaskWeight, isBatch: Bool = false) async throws -> JSONCompletionBackend {
        // Con el tope alcanzado la app no deja de funcionar: sigue con el gateway local, que es
        // gratis. Solo falla si tampoco hay respaldo, y en ese caso el mensaje dice exactamente
        // por qué y cómo cambiarlo.
        if let budget = GeminiUsageLedger.monthlyBudgetUSD(), GeminiUsageLedger.budgetIsExhausted() {
            let spent = GeminiUsageLedger.spentThisMonthUSD()
            guard let local = await availableLocalBackend(for: weight, isBatch: isBatch) else {
                currentStatus = "Tope mensual de Gemini alcanzado · sin respaldo local"
                throw AIOrchestratorError.budgetReachedWithoutLocalBackend(spent: spent, budget: budget)
            }
            currentStatus = "Tope mensual de Gemini alcanzado · usando respaldo local"
            return local
        }

        let cloud = try paidCloudBackend()
        guard let local = await availableLocalBackend(for: weight, isBatch: isBatch) else {
            currentStatus = "Gemini pagado · \(paidAPIModel) · sin respaldo local"
            return cloud
        }
        return FallbackJSONCompletionBackend(primary: cloud, fallback: local)
    }

    /// Respaldo local explícito para flujos que necesitan registrar qué proveedor produjo el dato.
    func localBackend(for weight: TaskWeight, isBatch: Bool = false) async throws -> JSONCompletionBackend {
        guard let backend = await availableLocalBackend(for: weight, isBatch: isBatch) else {
            currentStatus = "Respaldo local no disponible"
            throw AIOrchestratorError.systemBusy
        }
        return backend
    }

    /// Fuerza un modelo local puntual fuera del catálogo por `TaskWeight` — nunca intenta Gemini.
    /// Pensado para lotes largos (ej. `LibraryCatalogEnrichmentService`) donde el modelo debe ser
    /// siempre el mismo y jamás debe consumir presupuesto pagado. Aplica el mismo gate de
    /// térmica/carga que `backend(for:)`.
    ///
    /// `ignoringRAMLimit: true` salta por completo el chequeo de `ResourceMonitor.fits` — tanto la
    /// reserva de RAM en reposo como el margen estricto que protege audio en vivo (Logic Pro, etc.).
    /// Pensado para lotes que el usuario inicia a mano sabiendo que van a competir por RAM y
    /// aceptando ese costo con tal de que el lote no quede pausado esperando memoria libre que puede
    /// no llegar nunca. El gate de térmica/carga NO se salta: protege contra sobrecalentar la
    /// máquina, algo independiente de cuánta RAM haya disponible.
    func localBackend(
        forcing tier: LocalModelTier,
        isBatch: Bool = true,
        ignoringRAMLimit: Bool = false
    ) async throws -> JSONCompletionBackend {
        let host = gatewayHost
        guard await LocalGatewayService.reachabilityError(host: host) == nil else {
            currentStatus = "Gateway local no disponible"
            throw AIOrchestratorError.systemBusy
        }
        let snapshot = ResourceMonitor.snapshot()
        guard ResourceMonitor.isSafeToRunLocal(snapshot: snapshot) else {
            currentStatus = "Sistema muy ocupado para \(tier.displayName)"
            throw AIOrchestratorError.systemBusy
        }
        if !ignoringRAMLimit {
            guard ResourceMonitor.fits(tier, freeBytes: snapshot.freeBytes, audioIsRunning: ResourceMonitor.isAudioAppRunning()) else {
                currentStatus = "Sin RAM libre para \(tier.displayName)"
                throw AIOrchestratorError.systemBusy
            }
        }
        lastLocalModel = tier.rawValue
        currentStatus = "\(tier.displayName) · lote"
        return LocalGatewayService(
            host: host,
            model: tier.rawValue,
            keepAlive: isBatch ? LocalGatewayService.batchKeepAlive : LocalGatewayService.defaultKeepAlive
        )
    }

    private func availableLocalBackend(for weight: TaskWeight, isBatch: Bool) async -> JSONCompletionBackend? {
        guard let tier = ResourceMonitor.recommendedTier(for: weight) else { return nil }
        let host = gatewayHost
        guard await LocalGatewayService.reachabilityError(host: host) == nil else { return nil }

        let freeGB = Double(ResourceMonitor.snapshot().freeBytes) / 1_000_000_000
        currentStatus = "Gemini pagado · respaldo \(tier.displayName) · \(String(format: "%.0f", freeGB)) GB libres"
        lastLocalModel = tier.rawValue
        return LocalGatewayService(
            host: host,
            model: tier.rawValue,
            keepAlive: isBatch ? LocalGatewayService.batchKeepAlive : LocalGatewayService.defaultKeepAlive
        )
    }

    /// Libera la memoria del último modelo local que ESTE orquestador entregó. Pensado para llamarse
    /// al final de una tanda; es seguro llamarlo siempre, incluso si no se pidió ningún backend.
    ///
    /// Descarga solo ese modelo y no todo lo residente: en esta máquina el usuario suele tener otros
    /// modelos cargados por su cuenta (terminal, benchmarks) y no corresponde desalojárselos.
    func releaseLocalModels() async {
        guard let model = lastLocalModel else { return }
        lastLocalModel = nil
        await LocalGatewayService.releaseModel(model, host: gatewayHost)
        currentStatus = ""
    }
}
