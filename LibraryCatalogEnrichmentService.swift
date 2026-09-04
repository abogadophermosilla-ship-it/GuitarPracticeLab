import Foundation
import SwiftData

/// Enriquecimiento en lote del catálogo de Biblioteca: para cada ejercicio o concepto sin procesar
/// todavía, pide a la IA local qué habilidades practica y guarda el resultado en `aiSkillIDs`
/// (`SkillAssessmentCoachService` ya lo suma al matching por texto existente). Etiquetar los 2.524
/// ítems uno por uno con IA interactiva no era viable por costo/tiempo — corriendo en lote con un
/// modelo local, sin nadie esperando, sí lo es.
///
/// Siempre usa `LocalModelTier.qwen38_27b` vía `AIOrchestrator.localBackend(forcing:)`, que nunca
/// intenta Gemini: procesar miles de ítems por la API pagada no tendría sentido ni costo/beneficio.
/// Solo corre cuando el usuario lo inicia a mano desde Configuración y retoma donde quedó la
/// próxima vez, porque el progreso vive en los propios modelos: `aiSkillsEnrichedAt == nil` marca
/// lo pendiente.
///
/// Pide el modelo con `ignoringRAMLimit: true`: a pedido explícito del usuario, este lote salta el
/// chequeo de RAM (incluido el margen estricto que protege audio en vivo tipo Logic Pro) en vez de
/// quedar pausado esperando memoria libre que puede tardar en llegar. El gate de térmica/carga de
/// `AIOrchestrator` sigue activo — protege contra sobrecalentar la máquina, no depende de la RAM.
@MainActor
@Observable
final class LibraryCatalogEnrichmentService {
    /// Instancia única: si viviera en el `@State` de `SettingsView`, salir y volver a Configuración
    /// crearía una segunda instancia mientras la anterior sigue corriendo en background (el `Task`
    /// se mantiene vivo por su propia captura fuerte de `self`, no por la vista) — dos lotes
    /// concurrentes pisándose. El singleton evita eso y además deja ver el progreso real al volver.
    static let shared = LibraryCatalogEnrichmentService()

    enum RunState: Equatable {
        case idle
        case running
        case paused(reason: String)
        case finished
    }

    private(set) var state: RunState = .idle
    private(set) var processedCount = 0
    private(set) var totalCount = 0
    private(set) var currentLabel = ""

    private var task: Task<Void, Never>?

    var isActive: Bool {
        switch state {
        case .running, .paused: true
        case .idle, .finished: false
        }
    }

    func refreshCounts(modelContext: ModelContext) {
        totalCount = LibraryLookup.exerciseCount(in: modelContext) + LibraryLookup.conceptCount(in: modelContext)
        processedCount = Self.enrichedExerciseCount(in: modelContext) + Self.enrichedConceptCount(in: modelContext)
        if totalCount > 0, processedCount >= totalCount, task == nil {
            state = .finished
        }
    }

    func start(modelContext: ModelContext, orchestrator: AIOrchestrator) {
        guard task == nil else { return }
        state = .running
        task = Task { [weak self] in
            await self?.run(modelContext: modelContext, orchestrator: orchestrator)
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        // Siempre vuelve a `.idle`, sin importar si el estado justo antes era `.running` o
        // `.paused(reason:)` — de lo contrario, pausar durante un backoff dejaba el botón mostrando
        // "Pausar" para siempre (`isActive` es `true` en ambos casos) y jamás se podía reanudar.
        state = .idle
    }

    private func run(modelContext: ModelContext, orchestrator: AIOrchestrator) async {
        let skills = (try? modelContext.fetch(FetchDescriptor<SkillTopic>())) ?? []
        guard !skills.isEmpty else {
            state = .paused(reason: "No hay habilidades cargadas todavía (completa una Autoevaluación primero).")
            task = nil
            return
        }

        while !Task.isCancelled {
            refreshCounts(modelContext: modelContext)

            if let exercise = Self.nextPendingExercise(in: modelContext) {
                currentLabel = exercise.displayName
                await enrich(
                    text: "Técnica: \(exercise.technique). Libro: \(exercise.bookTitle). Capítulo: \(exercise.chapter).",
                    skills: skills,
                    orchestrator: orchestrator
                ) { ids in
                    exercise.aiSkillIDs = ids
                    exercise.aiSkillsEnrichedAt = .now
                }
                try? modelContext.save()
            } else if let concept = Self.nextPendingConcept(in: modelContext) {
                currentLabel = concept.title
                let kind = concept.isExercise ? "Ejercicio teórico" : "Concepto"
                await enrich(
                    text: "\(kind): \(concept.title). Categoría: \(concept.category). Resumen: \(concept.summary).",
                    skills: skills,
                    orchestrator: orchestrator
                ) { ids in
                    concept.aiSkillIDs = ids
                    concept.aiSkillsEnrichedAt = .now
                }
                try? modelContext.save()
            } else {
                break
            }
        }

        await orchestrator.releaseLocalModels()
        task = nil
        if !Task.isCancelled {
            refreshCounts(modelContext: modelContext)
            currentLabel = ""
            state = .finished
        }
        // Si se canceló, `stop()` ya dejó `state = .idle` de forma síncrona — nada que hacer acá.
    }

    private func enrich(
        text: String,
        skills: [SkillTopic],
        orchestrator: AIOrchestrator,
        apply: ([UUID]) -> Void
    ) async {
        do {
            let backend = try await orchestrator.localBackend(forcing: .qwen38_27b, ignoringRAMLimit: true)
            let ids = try await Self.classifySkills(text: text, skills: skills, backend: backend)
            apply(ids)
            state = .running
        } catch AIOrchestratorError.systemBusy {
            // Con `ignoringRAMLimit: true` esto ya no dispara por RAM ni por audio en vivo — solo
            // queda térmica/carga (`ResourceMonitor.isSafeToRunLocal`) o el gateway caído.
            state = .paused(reason: "Sistema ocupado (térmica o CPU al límite) o gateway local caído — reintenta en 30 s.")
            try? await Task.sleep(for: .seconds(30))
        } catch LocalGatewayError.serverUnreachable, LocalGatewayError.server {
            // Falla de transporte a mitad de la llamada (no en el chequeo previo de
            // `localBackend(forcing:)`) — el ítem NO se marca procesado, se reintenta igual que
            // `systemBusy`, para no perder ítems buenos por un hipo de Ollama a mitad de un lote de
            // horas.
            state = .paused(reason: "Ollama no respondió — reintenta en 30 s.")
            try? await Task.sleep(for: .seconds(30))
        } catch {
            // Ítem problemático (JSON inválido, ítem sin texto útil, etc.): se marca procesado sin
            // vínculos para no trabarse en el mismo ítem para siempre. El motivo queda visible hasta
            // que el próximo ítem lo pise.
            apply([])
            state = .paused(reason: "Último ítem sin vínculos claros: \(error.localizedDescription)")
        }
    }

    private static func classifySkills(
        text: String,
        skills: [SkillTopic],
        backend: JSONCompletionBackend
    ) async throws -> [UUID] {
        let catalog = skills.map { "- \($0.name): \($0.detail)" }.joined(separator: "\n")
        let prompt = """
        Eres un profesor de guitarra clasificando material de estudio. Dado el siguiente ítem del \
        catálogo, indica cuáles de las habilidades listadas abajo practica DIRECTAMENTE. Sé \
        conservador: solo marca una habilidad si el ítem la practica de forma clara, no por \
        asociación lejana. Si ninguna aplica, devuelve una lista vacía. Usa EXACTAMENTE los nombres \
        de la lista, no inventes otros ni los traduzcas.

        Ítem:
        \(text)

        Habilidades disponibles:
        \(catalog)

        Responde SOLO JSON: {"habilidades": ["nombre exacto", ...]}
        """
        let raw = try await backend.completeJSON(prompt: prompt)
        let object = try JSONAIParser.object(from: raw)
        guard let names = object["habilidades"] as? [String] else { return [] }
        let byName = Dictionary(skills.map { ($0.name.lowercased(), $0.id) }, uniquingKeysWith: { first, _ in first })
        return names.compactMap { byName[$0.lowercased()] }
    }

    private static func nextPendingExercise(in context: ModelContext) -> LibraryExercise? {
        var descriptor = FetchDescriptor<LibraryExercise>(predicate: #Predicate { $0.aiSkillsEnrichedAt == nil })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private static func nextPendingConcept(in context: ModelContext) -> LibraryConcept? {
        var descriptor = FetchDescriptor<LibraryConcept>(predicate: #Predicate { $0.aiSkillsEnrichedAt == nil })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private static func enrichedExerciseCount(in context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<LibraryExercise>(predicate: #Predicate { $0.aiSkillsEnrichedAt != nil }))) ?? 0
    }

    private static func enrichedConceptCount(in context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<LibraryConcept>(predicate: #Predicate { $0.aiSkillsEnrichedAt != nil }))) ?? 0
    }
}
