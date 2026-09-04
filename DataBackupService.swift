import Foundation
import SwiftData
import AppKit
import CryptoKit

/// Copia de seguridad del store de SwiftData completo (base activa + WAL + SHM).
///
/// Es el respaldo de fidelidad total: incluye lo que la exportación a JSON deja fuera a propósito
/// (los textos completos de los 18 PDFs, los recortes de imagen de Academia y los bookmarks de
/// seguridad de archivos externos). La exportación sirve para leer o migrar los datos a otra
/// herramienta; esto sirve para volver exactamente al estado anterior.
///
/// La restauración deliberadamente NO se ofrece con la app funcionando: pisar el store abierto deja
/// a SwiftData con un archivo distinto del que tiene mapeado en memoria. El único punto de
/// restauración es `DatabaseRecoveryView`, que aparece justo cuando el store no pudo abrirse y por
/// lo tanto nadie lo está usando todavía.
enum DataBackupService {
    /// Cada cuántos días corresponde un respaldo automático al abrir la app.
    static let automaticIntervalDays = 7
    /// Respaldos que se conservan antes de empezar a borrar los más viejos.
    static let maxStoredBackups = 8

    private static let lastAutomaticBackupKey = "lastAutomaticBackupAt"

    struct Entry: Identifiable, Hashable {
        let id: String
        let url: URL
        let createdAt: Date
        let byteSize: Int64

        var displayName: String {
            createdAt.formatted(date: .abbreviated, time: .shortened)
        }

        var displaySize: String {
            ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
        }
    }

    enum BackupError: LocalizedError {
        case storeNotFound
        case sourceChanged(String)
        case invalidBackup(String)

        var errorDescription: String? {
            switch self {
            case .storeNotFound:
                "No se encontró el archivo de la base de datos para respaldar."
            case .sourceChanged(let name):
                "La base cambió mientras se respaldaba \(name). Inténtalo de nuevo."
            case .invalidBackup(let reason):
                "El respaldo está incompleto o dañado: \(reason)"
            }
        }
    }

    private struct Manifest: Codable {
        struct Component: Codable {
            let name: String
            let byteSize: Int64
            let sha256: String
        }

        let formatVersion: Int
        let createdAt: Date
        let storeFileName: String
        let components: [Component]
    }

    private static let manifestFileName = "manifest.json"

    // MARK: - Ubicaciones

    static var backupsDirectory: URL {
        URL.applicationSupportDirectory
            .appending(path: "GuitarPracticeLab", directoryHint: .isDirectory)
            .appending(path: "Respaldos", directoryHint: .isDirectory)
    }

    /// Archivos que componen el store: el principal más el write-ahead log y el índice compartido.
    /// Hay que copiar los tres juntos — el `.store` solo puede quedar sin las escrituras que todavía
    /// viven en el `-wal`, que en una base activa son megabytes.
    ///
    /// Ojo con el sufijo: SQLite los nombra `default.store-wal` con guion, no `default.store.wal`.
    /// Usar `appendingPathExtension` genera el nombre con punto, no encuentra los archivos y deja un
    /// respaldo silenciosamente incompleto.
    static func storeComponents(for storeURL: URL) -> [URL] {
        let folder = storeURL.deletingLastPathComponent()
        let name = storeURL.lastPathComponent
        return [
            storeURL,
            folder.appending(path: "\(name)-wal"),
            folder.appending(path: "\(name)-shm")
        ]
    }

    /// URL real del store del contenedor activo, para no adivinar la ruta por defecto.
    static func storeURL(for container: ModelContainer) -> URL? {
        container.configurations.first?.url
    }

    /// Ruta del store por defecto de SwiftData, para cuando el contenedor no llegó a crearse
    /// (pantalla de recuperación).
    static var defaultStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "default.store")
    }

    // MARK: - Crear y listar

    static func list(in directory: URL? = nil) -> [Entry] {
        let fileManager = FileManager.default
        let directory = directory ?? backupsDirectory
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents
            .filter { $0.hasDirectoryPath }
            .map { folder in
                let created = (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return Entry(
                    id: folder.lastPathComponent,
                    url: folder,
                    createdAt: created,
                    byteSize: directorySize(of: folder)
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    static func makeBackup(of storeURL: URL) throws -> Entry {
        try makeBackup(of: storeURL, in: backupsDirectory)
    }

    /// Variante inyectable para probar el flujo completo sin escribir en Application Support.
    @discardableResult
    static func makeBackup(of storeURL: URL, in directory: URL) throws -> Entry {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: storeURL.path) else { throw BackupError.storeNotFound }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let stamp = folderStampFormatter.string(from: .now)
        var destination = directory.appending(path: "respaldo-\(stamp)", directoryHint: .isDirectory)
        // Dos respaldos en el mismo minuto (uno automático y uno a mano) no deben pisarse.
        var attempt = 2
        while fileManager.fileExists(atPath: destination.path) {
            destination = directory.appending(path: "respaldo-\(stamp)-\(attempt)", directoryHint: .isDirectory)
            attempt += 1
        }
        // La carpeta temporal empieza con punto: `list` usa `.skipsHiddenFiles`, de modo que una
        // copia interrumpida nunca puede aparecer como restaurable. Solo se renombra al final,
        // después de verificar tamaños y checksums.
        let temporary = directory.appending(
            path: ".respaldo-en-progreso-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )

        do {
            try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
            let existingComponents = storeComponents(for: storeURL).filter {
                fileManager.fileExists(atPath: $0.path)
            }
            var manifestComponents: [Manifest.Component] = []

            for component in existingComponents {
                let copied = temporary.appending(path: component.lastPathComponent)
                try fileManager.copyItem(at: component, to: copied)
                let copiedHash = try sha256(of: copied)
                // En el respaldo manual la llamada corre en el actor principal después de guardar
                // el contexto. Si aun así SQLite cambia un componente durante la copia, se descarta
                // la instantánea en vez de conservar una mezcla inconsistente de momentos.
                guard try sha256(of: component) == copiedHash else {
                    throw BackupError.sourceChanged(component.lastPathComponent)
                }
                manifestComponents.append(Manifest.Component(
                    name: component.lastPathComponent,
                    byteSize: fileSize(of: copied),
                    sha256: copiedHash
                ))
            }

            let manifest = Manifest(
                formatVersion: 1,
                createdAt: .now,
                storeFileName: storeURL.lastPathComponent,
                components: manifestComponents
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(
                to: temporary.appending(path: manifestFileName),
                options: .atomic
            )
            try validateFolder(temporary)
            try fileManager.moveItem(at: temporary, to: destination)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }

        prune(in: directory)

        return Entry(
            id: destination.lastPathComponent,
            url: destination,
            createdAt: .now,
            byteSize: directorySize(of: destination)
        )
    }

    /// Respaldo automático al abrir, como máximo una vez por semana. Corre **antes** de abrir el
    /// store a propósito: si una migración de esquema sale mal, el respaldo que queda es el del
    /// estado anterior, que es justamente el que sirve para recuperarse. Nunca interrumpe el
    /// arranque: si falla, la app abre igual y siempre se puede respaldar a mano desde Configuración.
    static func backupIfDue(storeURL: URL) {
        let defaults = UserDefaults.standard
        let last = defaults.object(forKey: lastAutomaticBackupKey) as? Date
        if let last,
           let due = Calendar.current.date(byAdding: .day, value: automaticIntervalDays, to: last),
           due > .now {
            return
        }

        guard (try? makeBackup(of: storeURL)) != nil else { return }
        defaults.set(Date.now, forKey: lastAutomaticBackupKey)
    }

    static var lastAutomaticBackupDate: Date? {
        UserDefaults.standard.object(forKey: lastAutomaticBackupKey) as? Date
    }

    // MARK: - Borrar y restaurar

    static func delete(_ entry: Entry) {
        try? FileManager.default.removeItem(at: entry.url)
    }

    /// Verifica las copias nuevas mediante su manifiesto. Los respaldos creados por versiones
    /// anteriores siguen siendo válidos si conservan, como mínimo, el archivo principal `.store`.
    static func validate(_ entry: Entry) throws {
        try validateFolder(entry.url)
    }

    /// Solo para la pantalla de recuperación: reemplaza el store dañado por el del respaldo. El
    /// store actual se guarda al lado con sufijo `.dañado-<fecha>` en vez de borrarse, porque un
    /// store que no abre igual puede tener datos rescatables con herramientas de SQLite.
    static func restore(_ entry: Entry, toStoreAt storeURL: URL) throws {
        let fileManager = FileManager.default
        let stamp = folderStampFormatter.string(from: .now)

        // Nunca se toca el store actual antes de demostrar que la fuente de restauración está sana.
        try validate(entry)

        for component in storeComponents(for: storeURL) where fileManager.fileExists(atPath: component.path) {
            let quarantined = component.appendingPathExtension("danado-\(stamp)")
            try fileManager.moveItem(at: component, to: quarantined)
        }

        let storeFolder = storeURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: storeFolder, withIntermediateDirectories: true)

        let backupFiles = (try? fileManager.contentsOfDirectory(at: entry.url, includingPropertiesForKeys: nil)) ?? []
        for file in backupFiles where file.lastPathComponent != manifestFileName {
            try fileManager.copyItem(at: file, to: storeFolder.appending(path: file.lastPathComponent))
        }
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Internos

    private static func prune(in directory: URL) {
        let extra = list(in: directory).dropFirst(maxStoredBackups)
        extra.forEach(delete)
    }

    private static func validateFolder(_ folder: URL) throws {
        let fileManager = FileManager.default
        let manifestURL = folder.appending(path: manifestFileName)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            let files = (try? fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil
            )) ?? []
            guard files.contains(where: { $0.lastPathComponent.hasSuffix(".store") }) else {
                throw BackupError.invalidBackup("falta el archivo principal del store")
            }
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest: Manifest
        do {
            manifest = try decoder.decode(Manifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw BackupError.invalidBackup("el manifiesto no se puede leer")
        }
        guard manifest.formatVersion == 1 else {
            throw BackupError.invalidBackup("versión de manifiesto desconocida")
        }
        guard manifest.components.contains(where: { $0.name == manifest.storeFileName }) else {
            throw BackupError.invalidBackup("el manifiesto no contiene el store principal")
        }

        for component in manifest.components {
            let url = folder.appending(path: component.name)
            guard fileManager.fileExists(atPath: url.path) else {
                throw BackupError.invalidBackup("falta \(component.name)")
            }
            guard fileSize(of: url) == component.byteSize,
                  (try sha256(of: url)) == component.sha256 else {
                throw BackupError.invalidBackup("falló la verificación de \(component.name)")
            }
        }
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func fileSize(of url: URL) -> Int64 {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return Int64(size)
    }

    private static func directorySize(of folder: URL) -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        return files.reduce(into: Int64(0)) { total, file in
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
    }

    private static let folderStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()
}
