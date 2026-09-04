import Foundation

/// Cuenta cuántas veces se abre cada sección del menú lateral.
///
/// La app tiene 17 secciones y sigue creciendo; sin un dato propio, decidir qué podar, qué fusionar
/// y dónde poner el trabajo siguiente es pura intuición. Esto no manda nada a ninguna parte: vive en
/// `UserDefaults`, es un entero por sección y se puede reiniciar desde Configuración.
///
/// No mide tiempo de permanencia a propósito — abrir una sección ya es la señal de intención, y
/// medir permanencia obligaría a distinguir uso real de una ventana olvidada abierta.
enum SectionUsageTracker {
    private static let countsKey = "sectionOpenCountsV1"
    private static let startedKey = "sectionOpenCountsStartedAt"
    private static var didRecordInitialOpen = false

    /// Inyectable solo para que las pruebas no escriban en los contadores reales del usuario: el
    /// target de tests corre dentro de la app y comparte su dominio de `UserDefaults`.
    static var defaults: UserDefaults = .standard

    /// Registra una apertura. Reabrir la sección que ya estaba activa no cuenta: el llamador solo
    /// invoca esto cuando la selección cambia de verdad.
    static func recordOpen(_ section: String) {
        var counts = allCounts()
        counts[section, default: 0] += 1
        defaults.set(counts, forKey: countsKey)
        if defaults.object(forKey: startedKey) == nil {
            defaults.set(Date.now, forKey: startedKey)
        }
    }

    /// Registra la sección que ya venía seleccionada al abrir la ventana. `onChange` no se dispara
    /// para ese valor inicial, por lo que "Hoy" quedaba sistemáticamente subcontado. La marca vive
    /// solo durante el proceso actual y evita duplicar la apertura si SwiftUI reconstruye la vista.
    static func recordInitialOpenIfNeeded(_ section: String) {
        guard !didRecordInitialOpen else { return }
        didRecordInitialOpen = true
        recordOpen(section)
    }

    static func allCounts() -> [String: Int] {
        defaults.dictionary(forKey: countsKey) as? [String: Int] ?? [:]
    }

    /// Fecha desde la que se está midiendo, para poder leer los números en contexto.
    static func measuringSince() -> Date? {
        defaults.object(forKey: startedKey) as? Date
    }

    static func totalOpens() -> Int {
        allCounts().values.reduce(0, +)
    }

    /// Secciones ordenadas de más a menos usada. Incluye en 0 las que nunca se abrieron: justamente
    /// esas son las que interesa ver.
    static func ranking(allSections: [String]) -> [(section: String, count: Int)] {
        let counts = allCounts()
        return allSections
            .map { (section: $0, count: counts[$0] ?? 0) }
            .sorted {
                $0.count == $1.count
                    ? $0.section.localizedCaseInsensitiveCompare($1.section) == .orderedAscending
                    : $0.count > $1.count
            }
    }

    static func reset() {
        defaults.removeObject(forKey: countsKey)
        defaults.removeObject(forKey: startedKey)
        didRecordInitialOpen = false
    }
}
