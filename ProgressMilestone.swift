import Foundation
import SwiftData

/// Registra cada vez que una habilidad, ejercicio o canción sube de nivel, para mostrar la
/// evolución real en el tiempo en la pestaña Progreso. Guarda las etiquetas de estado como texto
/// plano (no un enum tipado) porque las cuatro materias usan dos enums de nivel distintos
/// (`SkillMasteryLevel` para técnica/teoría, `ExerciseStatus` para ejercicios/repertorio).
@Model
final class ProgressMilestone {
    @Attribute(.unique) var id: UUID
    var date: Date
    var itemName: String
    var categoryRaw: String
    var previousStatusLabel: String
    var newStatusLabel: String
    var contextDetail: String

    init(
        id: UUID = UUID(),
        date: Date = .now,
        itemName: String,
        category: ProgressCategory,
        previousStatusLabel: String,
        newStatusLabel: String,
        contextDetail: String = ""
    ) {
        self.id = id
        self.date = date
        self.itemName = itemName
        self.categoryRaw = category.rawValue
        self.previousStatusLabel = previousStatusLabel
        self.newStatusLabel = newStatusLabel
        self.contextDetail = contextDetail
    }

    var category: ProgressCategory {
        get { ProgressCategory(rawValue: categoryRaw) ?? .exercise }
        set { categoryRaw = newValue.rawValue }
    }
}

enum ProgressTracker {
    /// Inserta un hito solo si `newWeight` representa un avance real respecto a `previousWeight`
    /// (usar `.progressWeight` de `ExerciseStatus` o `SkillMasteryLevel` según corresponda), para
    /// que el feed de "subidas de nivel" no se llene con cambios laterales o retrocesos.
    @discardableResult
    static func recordIfLevelUp(
        itemName: String,
        category: ProgressCategory,
        previousLabel: String,
        previousWeight: Int,
        newLabel: String,
        newWeight: Int,
        contextDetail: String = "",
        in context: ModelContext
    ) -> Bool {
        guard newWeight > previousWeight else { return false }
        context.insert(ProgressMilestone(
            itemName: itemName,
            category: category,
            previousStatusLabel: previousLabel,
            newStatusLabel: newLabel,
            contextDetail: contextDetail
        ))
        return true
    }
}
