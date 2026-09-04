import Foundation
import SwiftData

@Model
final class Instrument {
    @Attribute(.unique) var id: UUID
    var name: String
    var kind: String
    var pickups: String
    var tuning: String
    var notes: String
    var isActive: Bool

    init(
        id: UUID = UUID(),
        name: String,
        kind: String,
        pickups: String = "",
        tuning: String = "Estándar",
        notes: String = "",
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.pickups = pickups
        self.tuning = tuning
        self.notes = notes
        self.isActive = isActive
    }
}
