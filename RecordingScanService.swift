import Foundation
import SwiftData

enum RecordingScanError: LocalizedError {
    case cannotAccessFolder
    case cannotEnumerate

    var errorDescription: String? {
        switch self {
        case .cannotAccessFolder:
            "No se pudo acceder a la carpeta de grabaciones. Puede que se haya movido o eliminado."
        case .cannotEnumerate:
            "No se pudo leer el contenido de la carpeta."
        }
    }
}

struct RecordingScanSummary {
    var added = 0
    var modified = 0
    var scannedTotal = 0
}

enum RecordingScanService {
    /// Extensiones reconocidas como grabaciones: proyectos de Logic y exportaciones de audio habituales.
    private static let recognizedExtensions: Set<String> = [
        "logicx", "wav", "aif", "aiff", "mp3", "m4a", "caf", "flac"
    ]

    @MainActor
    static func scan(
        root: RecordingsLibraryRoot,
        existingRecordings: [Recording],
        modelContext: ModelContext
    ) throws -> RecordingScanSummary {
        guard let rootURL = SecurityScopedFile.resolve(root.bookmarkData) else {
            throw RecordingScanError.cannotAccessFolder
        }

        let granted = rootURL.startAccessingSecurityScopedResource()
        defer { if granted { rootURL.stopAccessingSecurityScopedResource() } }

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw RecordingScanError.cannotEnumerate
        }

        // Índice por carpeta relativa + nombre de archivo, para emparejar con lo ya registrado.
        var index: [String: Recording] = [:]
        for recording in existingRecordings {
            index["\(recording.relativeFolderPath)/\(recording.fileName)"] = recording
        }

        let rootPath = rootURL.standardizedFileURL.path
        var summary = RecordingScanSummary()

        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()

            if ext == "logicx" {
                // Tratamos el paquete como un solo elemento: no bajamos a su contenido interno.
                enumerator.skipDescendants()
            }

            guard recognizedExtensions.contains(ext) else { continue }
            guard let modifiedDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else {
                continue
            }
            guard let bookmark = try? SecurityScopedFile.makeBookmark(for: fileURL) else { continue }

            let folderURL = fileURL.deletingLastPathComponent().standardizedFileURL
            var relativeFolder = folderURL.path.replacingOccurrences(of: rootPath, with: "")
            if relativeFolder.hasPrefix("/") { relativeFolder.removeFirst() }

            let fileName = fileURL.lastPathComponent
            let key = "\(relativeFolder)/\(fileName)"
            summary.scannedTotal += 1

            if let existing = index[key] {
                if !Calendar.current.isDate(existing.lastModifiedDate, equalTo: modifiedDate, toGranularity: .second) {
                    existing.modificationLog.append(RecordingModificationEntry(
                        detectedAt: .now,
                        previousModifiedDate: existing.lastModifiedDate,
                        newModifiedDate: modifiedDate
                    ))
                    existing.lastModifiedDate = modifiedDate
                    summary.modified += 1
                }
                existing.bookmarkData = bookmark
            } else {
                let recording = Recording(
                    fileName: fileName,
                    relativeFolderPath: relativeFolder,
                    lastModifiedDate: modifiedDate,
                    bookmarkData: bookmark
                )
                modelContext.insert(recording)
                summary.added += 1
            }
        }

        root.lastScanDate = .now
        return summary
    }
}
