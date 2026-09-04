import Foundation
import SwiftData

/// Resumen semanal persistido: a diferencia de `RoutineCoachService.narrateWeek` (efímero, solo
/// `@State` en `ProgressOverviewView`, se pierde al salir de la pantalla), este queda guardado y
/// compara lo planificado contra lo realmente completado esa semana — ver `WeeklySummaryAnalytics`.
@Model
final class WeeklySummary {
    @Attribute(.unique) var id: UUID
    var weekStart: Date
    var weekEnd: Date
    var summaryText: String
    var plannedCount: Int
    var completedCount: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        weekStart: Date,
        weekEnd: Date,
        summaryText: String,
        plannedCount: Int,
        completedCount: Int,
        createdAt: Date = .now
    ) {
        self.id = id
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.summaryText = summaryText
        self.plannedCount = plannedCount
        self.completedCount = completedCount
        self.createdAt = createdAt
    }
}
