import Foundation
import Darwin
import AppKit

/// Cuánto "pesa" una tarea de IA, para decidir qué tan grande puede ser el modelo local que la
/// resuelve sin arriesgar el resto del sistema (en particular CoreAudio/Logic Pro).
enum TaskWeight {
    case light
    case medium
    case heavy
}

enum LocalModelTier: String, CaseIterable {
    // Rápidos — tareas interactivas del día a día
    case qwenCoder30b = "ollama-code:latest"
    case qwen35b = "ollama-main:latest"
    case gemma26b = "ollama-alt:latest"
    // Razonamiento — vale la pena esperar
    case qwen38_27b = "ollama-reason:latest"

    /// Perfiles reales tal como figuran en `ollama list` en esta máquina (actualizado 2026-08-22
    /// según `FASE3_RESULTADOS.md` y `MLX_EXTENSIVE_BENCHMARK_2026-08-22.md`). Se usan los alias
    /// `ollama-*`, no los tags base, para conservar el system prompt, temperatura y contexto medidos
    /// y para que Ollama no cargue dos veces los mismos pesos bajo nombres distintos.
    ///
    /// Qwen3.8 27B (`ollama-reason`, sobre el quant UD-Q4_K_XL de Unsloth) reemplazó a Qwen3.6
    /// 27B MTP, que fue eliminado. Qwen3 8B y `ollama-fast` también salieron de Ollama al pasar el
    /// rol de texto rápido a oMLX; esta app todavía usa la API nativa de Ollama, por lo que las
    /// tareas ligeras degradan al perfil Ollama más rápido disponible en vez de pedir un tag
    /// inexistente.
    ///
    /// Estimación conservadora (parámetros × ~0.9 GB + margen fijo de 2 GB para KV cache/contexto),
    /// todavía NO remedida en esta máquina — con Ollama directo, `/api/ps` volvería a dar una
    /// medición real (como en el catálogo original de 4 tags), pero no se re-midió en este cambio;
    /// sigue siendo un piso de seguridad a propósito (sobrestima antes que subestimar).
    var approximateFootprintBytes: UInt64 {
        switch self {
        case .qwenCoder30b: 29_500_000_000
        case .qwen35b: 34_000_000_000
        case .gemma26b: 26_000_000_000
        case .qwen38_27b: 28_000_000_000
        }
    }

    var displayName: String {
        switch self {
        case .qwenCoder30b: "Qwen3 Coder 30B"
        case .qwen35b: "Qwen3.6 35B"
        case .gemma26b: "Gemma 4 26B MLX"
        case .qwen38_27b: "Qwen3.8 27B"
        }
    }
}

struct ResourceSnapshot {
    let freeBytes: UInt64
    let totalBytes: UInt64
    let loadAverage1m: Double
    let thermalState: ProcessInfo.ThermalState
}

/// Decide automáticamente qué modelo local usar según la RAM y CPU libres en este instante, para
/// aprovechar recursos disponibles sin arriesgar dropouts de audio en Logic Pro. Nunca recomienda
/// caer a la nube: si ni el modelo más chico es seguro ahora mismo, devuelve `nil` y la app espera.
enum ResourceMonitor {
    static func snapshot() -> ResourceSnapshot {
        ResourceSnapshot(
            freeBytes: freePhysicalMemory(),
            totalBytes: ProcessInfo.processInfo.physicalMemory,
            loadAverage1m: currentLoadAverage(),
            thermalState: ProcessInfo.processInfo.thermalState
        )
    }

    /// Margen multiplicativo estricto, el original del proyecto. Se aplica SOLO cuando hay una app
    /// de audio en tiempo real corriendo: CoreAudio no tolera presión de memoria ni swapping, y un
    /// corte de audio en medio de una grabación es mucho peor que una función de IA que no arranca.
    private static let audioSafetyMargin = 1.5

    /// Reserva fija que se deja libre para el resto del sistema cuando NO hay audio corriendo.
    /// Medido el 2026-08-06 en esta máquina (51.5 GB totales, 32 GB libres con uso normal): el
    /// margen de 1.5x exigía entre 39 y 51 GB libres para los modelos de `.medium`/`.heavy`, o sea
    /// los bloqueaba SIEMPRE — `qwen35b` llegaba a pedir 51.0 GB de los 51.5 GB físicos, imposible
    /// incluso con la máquina recién encendida. Una reserva aditiva mantiene el sentido original
    /// (que quede RAM para el resto del sistema) sin volverlo inalcanzable.
    ///
    /// Bajada de 6 GB a 3 GB el 2026-08-10 a pedido explícito del usuario: con 6 GB, el modelo de
    /// razonamiento de 27B pedía 33 GB libres sin audio, y con ~32 GB libres "de uso normal"
    /// quedaba afuera por muy poco margen — la tarjeta caía a `qwen8b` casi siempre. El usuario
    /// aceptó explícitamente que un modelo mejor use más RAM "unos segundos" cuando no hay audio en
    /// juego. Sigue siendo una reserva real (no cero) para no dejar el sistema sin margen, y el
    /// margen estricto de audio (`audioSafetyMargin`, sin tocar) sigue protegiendo CoreAudio/Logic
    /// Pro igual que antes — esto solo afecta el caso sin audio corriendo.
    private static let idleReserveBytes: UInt64 = 3_000_000_000

    static func recommendedTier(for weight: TaskWeight, snapshot: ResourceSnapshot = ResourceMonitor.snapshot()) -> LocalModelTier? {
        guard isSafeToRunLocal(snapshot: snapshot) else { return nil }

        let audioIsRunning = isAudioAppRunning()
        return allowedTiers(for: weight).first { tier in
            fits(tier, freeBytes: snapshot.freeBytes, audioIsRunning: audioIsRunning)
        }
    }

    /// Gate general de térmica/carga, independiente del modelo elegido — lo comparten
    /// `recommendedTier` y las rutas que fuerzan un modelo puntual fuera del catálogo por peso
    /// (ver `AIOrchestrator.localBackend(forcing:)`).
    static func isSafeToRunLocal(snapshot: ResourceSnapshot = ResourceMonitor.snapshot()) -> Bool {
        guard snapshot.thermalState != .critical, snapshot.thermalState != .serious else { return false }
        let coreCount = Double(max(ProcessInfo.processInfo.activeProcessorCount, 1))
        return snapshot.loadAverage1m < coreCount * 0.85
    }

    /// `true` si el modelo entra en la RAM libre actual bajo el criterio que corresponda.
    static func fits(_ tier: LocalModelTier, freeBytes: UInt64, audioIsRunning: Bool) -> Bool {
        let footprint = Double(tier.approximateFootprintBytes)
        let strict = footprint * audioSafetyMargin
        // Sin audio se toma el MENOR de los dos criterios, nunca solo el aditivo: para modelos de
        // menos de 12 GB la reserva fija de 6 GB resulta MÁS exigente que el margen de 1.5x (con
        // `qwen8b`, 9.5+6=15.5 GB contra 9.5*1.5=14.25 GB), así que aplicar el aditivo a secas
        // apretaba justo al único modelo que hoy se usa, en vez de soltarlo. Con `min` la regla sin
        // audio siempre es igual o más permisiva que la regla con audio, que es lo que se quería.
        let required = audioIsRunning ? strict : min(strict, footprint + Double(idleReserveBytes))
        return Double(freeBytes) > required
    }

    /// Solo DAWs que graban o reproducen audio en tiempo real, donde un corte arruina el trabajo.
    /// Se comparan por prefijo del identificador de bundle para cubrir distintas versiones.
    ///
    /// A propósito NO se incluyen editores/librarians de hardware como FM9-Edit de Fractal Audio
    /// (`com.FractalAudio.FM9Edit`): el usuario los deja abiertos de forma permanente, así que
    /// contarlos como "hay audio en juego" volvería a aplicar el margen estricto todo el tiempo y
    /// dejaría este chequeo sin efecto — verificado en vivo el 2026-08-06, con FM9-Edit corriendo
    /// la detección daba `true` de manera constante. Esos programas hablan con el hardware por USB,
    /// no dependen de la RAM del Mac para sostener un buffer de CoreAudio.
    private static let audioAppBundlePrefixes = [
        "com.apple.logic",
        "com.apple.mainstage",
        "com.apple.garageband",
        "com.avid.protools",
        "com.ableton.live",
        "com.cockos.reaper",
        "com.steinberg.cubase",
        "com.steinberg.nuendo",
        "com.presonus.studioone",
        "com.image-line.flstudio",
        "com.bitwig.bitwig",
        // Simuladores de amplificador en modo standalone: es lo que un guitarrista deja sonando
        // mientras practica, y un corte de audio ahí molesta igual que en una DAW.
        "com.neuraldsp",
        "com.ikmultimedia",
        "com.line6.helix",
        "com.ikmultimedia.tonex",
        "com.positivegrid"
    ]

    /// Detecta si hay alguna app de audio corriendo, para decidir cuál de los dos criterios de RAM
    /// aplicar. La protección de CoreAudio así solo cuesta capacidad cuando efectivamente hay audio
    /// en juego, en vez de bloquear los modelos grandes todo el tiempo.
    ///
    /// Respeta el ajuste "Permitir procesamiento local mientras Logic Pro está abierto"
    /// (`allowHeavyAIWithLogic` en Configuración), el mismo que ya consulta
    /// `LocalAudioIntelligenceService`: si el usuario activó esa opción, ya declaró que acepta el
    /// riesgo, y sería incoherente que un lado de la app lo permita y el otro siga frenando.
    static func isAudioAppRunning() -> Bool {
        guard !UserDefaults.standard.bool(forKey: "allowHeavyAIWithLogic") else { return false }
        return NSWorkspace.shared.runningApplications.contains { app in
            guard let identifier = app.bundleIdentifier?.lowercased() else { return false }
            return audioAppBundlePrefixes.contains { identifier.hasPrefix($0) }
        }
    }

    /// Orden de preferencia dentro de cada peso — `recommendedTier` toma el primero que quepa en la
    /// RAM libre actual, así que el orden importa: mejor calidad primero, degradando a algo más
    /// chico solo si no hay margen. Desde que Qwen3 8B pasó a oMLX no queda un modelo chico en el
    /// endpoint nativo de Ollama que usa esta app. Gemma 4 es el primer candidato de `.light` porque
    /// fue el más rápido y el único 6/6 de la batería MLX/GGUF del 2026-08-22; si no cabe, se
    /// intenta el perfil general y luego se devuelve `nil` con el mismo mensaje de recursos de hoy.
    private static func allowedTiers(for weight: TaskWeight) -> [LocalModelTier] {
        switch weight {
        case .light: [.gemma26b, .qwen35b]
        case .medium: [.qwen38_27b, .qwenCoder30b, .qwen35b, .gemma26b]
        case .heavy: [.qwen38_27b, .qwenCoder30b, .qwen35b]
        }
    }

    private static func freePhysicalMemory() -> UInt64 {
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        // macOS usa la RAM "libre" de forma oportunista (cache de disco, páginas especulativas) y la
        // devuelve al instante apenas algo la necesita — por eso `free_count` solo (lo que de verdad
        // está vacío ahora mismo) subestima cuánto hay realmente disponible para un modelo nuevo.
        // `inactive_count` (páginas de archivo cacheadas, reclamables) ya se sumaba; se agrega
        // `purgeable_count` (páginas marcadas descartables al instante, sin escritura de por medio,
        // p. ej. cachés de apps) porque también son RAM que el sistema entrega de inmediato bajo
        // presión, no memoria realmente comprometida. Sigue siendo una subestimación a propósito
        // (no se suma `active_count`, que sí puede requerir swap), consistente con el resto de este
        // archivo: prefiere quedarse corto antes que arriesgar CoreAudio/el resto del sistema.
        let freePages = UInt64(stats.free_count) + UInt64(stats.inactive_count) + UInt64(stats.purgeable_count)
        return freePages * UInt64(pageSize)
    }

    private static func currentLoadAverage() -> Double {
        var load = [Double](repeating: 0, count: 3)
        getloadavg(&load, 3)
        return load.first ?? 0
    }
}
