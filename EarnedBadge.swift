import Foundation
import SwiftData

/// Registro de una insignia ya otorgada — `BadgeCatalog` define QUÉ se puede ganar y CUÁNDO se
/// cumple; esto solo guarda que ya se ganó y cuándo, para no volver a evaluarla ni mostrarla como
/// "nueva" de nuevo. `id` coincide con `BadgeDefinition.id`.
@Model
final class EarnedBadge {
    @Attribute(.unique) var id: String
    var dateEarned: Date

    init(id: String, dateEarned: Date = .now) {
        self.id = id
        self.dateEarned = dateEarned
    }
}
