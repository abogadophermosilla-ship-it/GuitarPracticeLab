import Foundation
import SwiftData

/// Ideas de funcionalidad futura que el usuario quiere anotar entre sesiones (manejo de
/// software/amplificadores, trabajo rítmico de groove, etc.) — no implica que ya estén construidas.
@Model
final class BacklogIdea {
    @Attribute(.unique) var id: UUID
    var text: String
    var createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = .now) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}
