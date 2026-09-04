import Foundation
import SwiftData

@Model
final class StudioAsset {
    @Attribute(.unique) var id: UUID
    var name: String
    var assetTypeRaw: String
    var category: String
    var usage: String
    var notes: String

    init(
        id: UUID = UUID(),
        name: String,
        assetType: AssetType,
        category: String,
        usage: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.assetTypeRaw = assetType.rawValue
        self.category = category
        self.usage = usage
        self.notes = notes
    }

    var assetType: AssetType {
        get { AssetType(rawValue: assetTypeRaw) ?? .hardware }
        set { assetTypeRaw = newValue.rawValue }
    }
}
