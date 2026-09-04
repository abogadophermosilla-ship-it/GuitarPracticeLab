import Foundation

/// Cierra el hueco entre "importar un PDF a la Biblioteca" y "el Profesor IA puede citarlo":
/// escribe el texto que `LibraryBook.extractPageTexts` ya extrajo en el formato que
/// `Tools/book-rag/ingest.py` espera y dispara una ingesta incremental en background.
///
/// Mismo criterio de degradación que `BookPassageService`: si el volumen externo no está
/// montado, si el PDF no tiene texto extraíble (escaneado sin OCR) o si no hay un intérprete
/// de Python disponible, no rompe el import — el libro queda en la Biblioteca igual, solo sin
/// pasajes citables hasta que alguien corra `ingest.py` a mano.
enum BookRAGIndexer {
    enum Outcome: Sendable {
        case indexed
        case skipped(String)
        case failed(String)
    }

    private static var catalogoDir: URL {
        LearningMaterialsService.booksURL
            .appendingPathComponent("_catalogo_ejercicios", isDirectory: true)
    }
    private static var extractedDir: URL {
        catalogoDir.appendingPathComponent("extracted", isDirectory: true)
    }

    /// Herramienta personal excluida del bundle. Se puede indicar explícitamente al distribuir la
    /// app y, en desarrollo, se encuentra desde el checkout actual o desde este archivo fuente.
    private static var ingestScript: URL? {
        let environmentPath = ProcessInfo.processInfo.environment["GUITAR_PRACTICE_RAG_INGEST_SCRIPT"]
        let checkoutPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("Tools/book-rag/ingest.py")
        let sourcePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Tools/book-rag/ingest.py")
        return [environmentPath.map(URL.init(fileURLWithPath:)), checkoutPath, sourcePath]
            .compactMap { $0 }
            .first { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    private static let minExtractableChars = 200

    static func indexIfPossible(title: String, fileName: String, pageTexts: [String]) async -> Outcome {
        guard FileManager.default.fileExists(atPath: catalogoDir.path) else {
            return .skipped("el volumen de libros no está montado")
        }
        let totalChars = pageTexts.reduce(0) { $0 + $1.trimmingCharacters(in: .whitespacesAndNewlines).count }
        guard totalChars >= minExtractableChars else {
            return .skipped("el PDF no tiene texto extraíble (¿escaneado sin OCR?)")
        }
        guard let python = findPython() else {
            return .skipped("no se encontró un intérprete de Python")
        }
        guard let ingestScript else {
            return .skipped("no se encontró Tools/book-rag/ingest.py")
        }

        do {
            try FileManager.default.createDirectory(at: extractedDir, withIntermediateDirectories: true)
            let slug = uniqueSlug(for: title, fileName: fileName)
            let body = pageTexts.enumerated()
                .map { index, text in "===== PAGE \(index + 1) =====\n\(text)" }
                .joined(separator: "\n\n")
            try body.write(to: extractedDir.appendingPathComponent("\(slug).txt"), atomically: true, encoding: .utf8)

            let sidecar = try JSONSerialization.data(withJSONObject: ["titulo": title])
            try sidecar.write(to: extractedDir.appendingPathComponent("\(slug).json"))
        } catch {
            return .failed("no se pudo escribir el texto extraído (\(error.localizedDescription))")
        }

        return await runIngest(python: python, script: ingestScript)
    }

    private static func findPython() -> URL? {
        let candidates = [
            "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3.14",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        return candidates
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    private static func uniqueSlug(for title: String, fileName: String) -> String {
        let base = slugify(title.isEmpty ? fileName : title)
        var candidate = base
        var suffix = 2
        while FileManager.default.fileExists(atPath: extractedDir.appendingPathComponent("\(candidate).txt").path) {
            candidate = "\(base)_\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private static func slugify(_ text: String) -> String {
        let folded = text.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        var result = ""
        var lastWasSeparator = true
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                result += "_"
                lastWasSeparator = true
            }
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return trimmed.isEmpty ? "libro" : trimmed
    }

    private static func runIngest(python: URL, script: URL) async -> Outcome {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = python
            process.arguments = [script.path]
            process.currentDirectoryURL = script.deletingLastPathComponent()
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
            } catch {
                return Outcome.failed("no se pudo iniciar ingest.py (\(error.localizedDescription))")
            }
            // Hay que drenar la pipe ANTES de esperar la salida: ingest.py imprime progreso por
            // cada chunk embebido y, si nadie lee, el buffer se llena y el proceso queda colgado.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let output = String(data: data, encoding: .utf8) ?? ""
                return Outcome.failed("ingest.py falló (código \(process.terminationStatus)). \(output.suffix(600))")
            }
            return Outcome.indexed
        }.value
    }
}
