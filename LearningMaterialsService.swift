import Foundation
import AppKit

struct LearningMaterialEntry: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    let fileSize: Int64?
    let modifiedAt: Date?

    var id: String { url.standardizedFileURL.path }
    var name: String { url.lastPathComponent }

    var icon: String {
        if isDirectory { return "folder.fill" }
        switch url.pathExtension.lowercased() {
        case "pdf": return "doc.richtext.fill"
        case "png", "jpg", "jpeg", "heic", "gif": return "photo.fill"
        case "mp3", "wav", "aif", "aiff", "m4a", "flac": return "waveform"
        case "mp4", "mov", "m4v": return "film.fill"
        case "gp", "gp3", "gp4", "gp5", "gpx", "gpif": return "guitars.fill"
        case "logicx": return "music.note.list"
        case "zip", "rar", "7z": return "archivebox.fill"
        default: return "doc.fill"
        }
    }

    var detail: String {
        if isDirectory { return "Carpeta" }
        guard let fileSize else { return url.pathExtension.uppercased() }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

/// Fuente única para todos los materiales de aprendizaje que permanecen en el disco externo.
/// La ruta es visible/editable en Configuración y el bookmark conserva acceso entre lanzamientos.
enum LearningMaterialsService {
    static let rootPathKey = "learningMaterialsRoot"
    private static let rootBookmarkKey = "learningMaterialsRootBookmark"
    static let defaultRootPath = "/Volumes/VST/Clases"

    static var configuredPath: String {
        let value = UserDefaults.standard.string(forKey: rootPathKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? defaultRootPath : value
    }

    static var rootURL: URL {
        let pathURL = URL(fileURLWithPath: configuredPath, isDirectory: true).standardizedFileURL
        if let data = UserDefaults.standard.data(forKey: rootBookmarkKey),
           let resolved = SecurityScopedFile.resolve(data)?.standardizedFileURL,
           resolved.path == pathURL.path {
            return resolved
        }
        return pathURL
    }

    static var booksURL: URL {
        rootURL.appendingPathComponent("Libros", isDirectory: true)
    }

    static var classesURL: URL {
        rootURL.appendingPathComponent("Clases", isDirectory: true)
    }

    static var musicURL: URL {
        rootURL.appendingPathComponent("Musica", isDirectory: true)
    }

    static var projectsURL: URL {
        rootURL.appendingPathComponent("Proyectos", isDirectory: true)
    }

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: rootURL.path)
    }

    static func configureRoot(_ url: URL) throws {
        let standardized = url.standardizedFileURL
        let bookmark = try SecurityScopedFile.makeBookmark(for: standardized)
        UserDefaults.standard.set(standardized.path, forKey: rootPathKey)
        UserDefaults.standard.set(bookmark, forKey: rootBookmarkKey)
    }

    static func useDefaultRoot() {
        UserDefaults.standard.set(defaultRootPath, forKey: rootPathKey)
        UserDefaults.standard.removeObject(forKey: rootBookmarkKey)
    }

    static func entries(in folder: URL) -> [LearningMaterialEntry] {
        withRootAccess { _ in
            let keys: Set<URLResourceKey> = [
                .isDirectoryKey,
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .isHiddenKey
            ]
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )) ?? []

            return urls.compactMap { url in
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isHidden != true,
                      values.isDirectory == true || values.isRegularFile == true else { return nil }
                return LearningMaterialEntry(
                    url: url,
                    isDirectory: values.isDirectory == true,
                    fileSize: values.fileSize.map(Int64.init),
                    modifiedAt: values.contentModificationDate
                )
            }
            .sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        } ?? []
    }

    static func search(query: String, limit: Int = 40) -> [LearningMaterialEntry] {
        let needle = query.normalizedForMaterialSearch
        guard needle.count >= 2 else { return [] }

        return withRootAccess { root in
            let keys: Set<URLResourceKey> = [
                .isDirectoryKey,
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .isHiddenKey
            ]
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return [] }

            var matches: [LearningMaterialEntry] = []
            while let url = enumerator.nextObject() as? URL, matches.count < limit {
                if Task.isCancelled { break }
                guard url.lastPathComponent.normalizedForMaterialSearch.contains(needle),
                      let values = try? url.resourceValues(forKeys: keys),
                      values.isHidden != true,
                      values.isDirectory == true || values.isRegularFile == true else { continue }
                matches.append(LearningMaterialEntry(
                    url: url,
                    isDirectory: values.isDirectory == true,
                    fileSize: values.fileSize.map(Int64.init),
                    modifiedAt: values.contentModificationDate
                ))
            }
            return matches.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        } ?? []
    }

    static func open(_ url: URL) {
        withRootAccess { _ in
            NSWorkspace.shared.open(url)
        }
    }

    @discardableResult
    static func withRootAccess<T>(_ body: (URL) throws -> T) rethrows -> T? {
        let url = rootURL
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try body(url)
    }
}

private extension String {
    var normalizedForMaterialSearch: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}
