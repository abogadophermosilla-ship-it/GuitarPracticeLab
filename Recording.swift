import Foundation
import SwiftData

/// Una entrada en el historial de modificaciones detectadas de una grabación. Se agrega
/// automáticamente cuando un rescaneo detecta que la fecha de modificación del archivo cambió
/// desde el último escaneo — no requiere nada manual del usuario.
struct RecordingModificationEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var detectedAt: Date
    var previousModifiedDate: Date?
    var newModifiedDate: Date
}

@Model
final class Recording {
    @Attribute(.unique) var id: UUID
    var fileName: String
    /// Ruta relativa a la carpeta raíz, sin el nombre de archivo (ej. "Repertorio/Nombre de la
    /// canción") — se usa como categoría, derivada de cómo el usuario organiza sus subcarpetas.
    var relativeFolderPath: String
    var lastModifiedDate: Date
    var bookmarkData: Data
    var modificationLog: [RecordingModificationEntry]
    var firstSeenAt: Date

    init(
        id: UUID = UUID(),
        fileName: String,
        relativeFolderPath: String,
        lastModifiedDate: Date,
        bookmarkData: Data,
        modificationLog: [RecordingModificationEntry] = [],
        firstSeenAt: Date = .now
    ) {
        self.id = id
        self.fileName = fileName
        self.relativeFolderPath = relativeFolderPath
        self.lastModifiedDate = lastModifiedDate
        self.bookmarkData = bookmarkData
        self.modificationLog = modificationLog
        self.firstSeenAt = firstSeenAt
    }

    /// Ruta relativa sin barras al inicio/final, o "Sin categoría" si el archivo está directamente
    /// en la raíz de la carpeta vinculada.
    var category: String {
        let trimmed = relativeFolderPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? "Sin categoría" : trimmed
    }
}

/// La carpeta raíz de grabaciones vinculada por el usuario (bookmark con security scope, mismo
/// patrón que ya usa la app para PDFs y Guitar Pro). Solo existe una a la vez.
@Model
final class RecordingsLibraryRoot {
    @Attribute(.unique) var id: UUID
    var folderName: String
    var bookmarkData: Data
    var lastScanDate: Date?

    init(
        id: UUID = UUID(),
        folderName: String,
        bookmarkData: Data,
        lastScanDate: Date? = nil
    ) {
        self.id = id
        self.folderName = folderName
        self.bookmarkData = bookmarkData
        self.lastScanDate = lastScanDate
    }
}
