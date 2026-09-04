import Foundation
import SwiftData

/// Banda musical — favorita (aceptada desde una sugerencia de repertorio, o agregada a mano) o el
/// proyecto tributo real del usuario (`isTributeProject`). "Todo lo que escucho, me gusta, toco, me
/// hace mejor guitarrista": las bandas favoritas alimentan las sugerencias de repertorio, y las
/// canciones del repertorio pueden vincularse a una banda vía `Song.band`.
@Model
final class Band {
    @Attribute(.unique) var id: UUID
    var name: String
    var isFavorite: Bool
    var isTributeProject: Bool
    var notes: String
    var likedSongTitles: [String]

    init(
        id: UUID = UUID(),
        name: String,
        isFavorite: Bool = false,
        isTributeProject: Bool = false,
        notes: String = "",
        likedSongTitles: [String] = []
    ) {
        self.id = id
        self.name = name
        self.isFavorite = isFavorite
        self.isTributeProject = isTributeProject
        self.notes = notes
        self.likedSongTitles = likedSongTitles
    }
}

/// Mantiene una sola identidad de banda para todos los nombres escritos a mano. El texto del
/// artista en una canción puede venir con otras mayúsculas, tildes o espacios, pero debe seguir
/// apuntando a la banda que el usuario ya tenía en vez de crear un duplicado.
enum BandLibrary {
    static func findOrCreateFavorite(
        named rawName: String,
        among bands: [Band],
        in modelContext: ModelContext
    ) -> Band? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let identity = normalizedIdentity(name)
        if let existing = bands.first(where: { normalizedIdentity($0.name) == identity }) {
            existing.isFavorite = true
            return existing
        }

        let band = Band(name: name, isFavorite: true)
        modelContext.insert(band)
        return band
    }

    private static func normalizedIdentity(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
