import Foundation
import SwiftData

/// Integra el corpus local terminado por la sesión de análisis en la Biblioteca real de la app.
/// Se usa para el bootstrap de un catálogo incompleto; una biblioteca ya poblada se omite antes
/// de tocar el disco externo. Las actualizaciones posteriores se hacen con los botones Importar.
enum LibraryIntegrationService {
    private struct BookSpec {
        let title: String
        let author: String
        let fileNameContains: String
    }

    private static let books = [
        BookSpec(title: "Blues a tu alcance", author: "", fileNameContains: "Blues a tu alcance.pdf"),
        BookSpec(title: "Breakthrough Blues-Rock Rhythm Fills", author: "Jeff McErlain", fileNameContains: "Breakthrough Blues-Rock Rhythm"),
        BookSpec(title: "Fretboard Freedom", author: "Troy Nelson", fileNameContains: "fretboard-freedom"),
        BookSpec(title: "Guitar Aerobics", author: "", fileNameContains: "Guitar Aerobics_"),
        BookSpec(title: "Heavy Metal Guitar Tricks", author: "", fileNameContains: "Heavy Metal Guitar Tricks"),
        BookSpec(title: "Heavy Metal Lead Guitar Vol I", author: "Troy Stetina", fileNameContains: "Heavy metal lead guitar 1"),
        BookSpec(title: "Heavy Metal Lead Guitar Vol II", author: "Troy Stetina", fileNameContains: "Heavy MEtal Lead Guitar Vol II"),
        BookSpec(title: "Improvisación para Muñones v1.05", author: "", fileNameContains: "Improvisación_para_Muñones_v1.05"),
        BookSpec(title: "Blues Rhythms You Can Use", author: "John Ganapes", fileNameContains: "john-ganapes-blues-rhythms"),
        BookSpec(title: "More Blues You Can Use", author: "John Ganapes", fileNameContains: "John Ganapes - More Blues"),
        BookSpec(title: "Metal Rhythm Guitar Volume I", author: "Troy Stetina", fileNameContains: "Metal Rhythm Guitar Volume I"),
        BookSpec(title: "Metal Rhythm Guitar Volume II", author: "Troy Stetina", fileNameContains: "Metal Rhythm Guitar Volume II"),
        BookSpec(title: "Secrets To Writing Killer Metal Songs", author: "", fileNameContains: "Secrets To Writing Killer Metal Songs"),
        BookSpec(title: "Shred Guitar", author: "Paul Hanson", fileNameContains: "Shred Guitar con anotaciones"),
        BookSpec(title: "Speed And Thrash Metal", author: "", fileNameContains: "Speed And Thrash Metal"),
        BookSpec(title: "Speed Mechanics For The Lead Guitar", author: "", fileNameContains: "Speed Mechanics For The Lead Guitar En"),
        BookSpec(title: "Teoría Básica Para Guitarristas Principiantes", author: "MIGUITARRAELECTRICA", fileNameContains: "MIGUITARRAELECTRICA"),
        BookSpec(title: "Total Rock Guitar", author: "", fileNameContains: "Total Rock Guitar"),
        BookSpec(title: "Triadas para Muñones V1.2", author: "", fileNameContains: "Triadas_para_munones_V1.2_editable")
    ]

    struct Report {
        var exercisesAdded = 0
        var conceptsAdded = 0
        var booksAdded = 0
        var errors: [String] = []
    }

    @discardableResult
    static func integrateIfAvailable(in context: ModelContext) -> Report {
        // Antes se recorría VST, se leían ambos JSON y se enumeraban todos los PDF en cada
        // lanzamiento, aunque los miles de registros ya estuvieran importados. En un disco dormido
        // esa comprobación podía bloquear la app durante decenas de segundos.
        let hasExercises = ((try? context.fetchCount(FetchDescriptor<LibraryExercise>())) ?? 0) > 0
        let hasConcepts = ((try? context.fetchCount(FetchDescriptor<LibraryConcept>())) ?? 0) > 0
        let hasBooks = ((try? context.fetchCount(FetchDescriptor<LibraryBook>())) ?? 0) > 0
        guard !hasExercises || !hasConcepts || !hasBooks else { return Report() }

        let libraryRoot = LearningMaterialsService.booksURL
        guard FileManager.default.fileExists(atPath: libraryRoot.path) else { return Report() }

        var report = Report()
        let catalogFolder = libraryRoot.appendingPathComponent("_catalogo_ejercicios", isDirectory: true)

        do {
            let existing = try context.fetch(FetchDescriptor<LibraryExercise>())
            let url = catalogFolder.appendingPathComponent("compiled_ejercicios_guitarra.json")
            if FileManager.default.fileExists(atPath: url.path) {
                report.exercisesAdded = try LibraryExerciseImporter.importCatalog(
                    from: url,
                    existing: existing,
                    into: context
                )
            }
        } catch {
            report.errors.append("Ejercicios: \(error.localizedDescription)")
        }

        do {
            let existing = try context.fetch(FetchDescriptor<LibraryConcept>())
            let url = catalogFolder.appendingPathComponent("compiled_teoria_guitarra.json")
            if FileManager.default.fileExists(atPath: url.path) {
                report.conceptsAdded = try LibraryConceptImporter.importCatalog(
                    from: url,
                    existing: existing,
                    into: context
                )
            }
        } catch {
            report.errors.append("Conceptos: \(error.localizedDescription)")
        }

        do {
            let existingBooks = try context.fetch(FetchDescriptor<LibraryBook>())
            let existingByTitle = Dictionary(uniqueKeysWithValues: existingBooks.map {
                (normalized($0.title), $0)
            })
            let pdfURLs = allPDFs(in: libraryRoot)

            for spec in books {
                guard let url = bestPDF(for: spec, among: pdfURLs) else {
                    report.errors.append("PDF no encontrado: \(spec.title)")
                    continue
                }
                if let existing = existingByTitle[normalized(spec.title)] {
                    guard existing.fileName != url.lastPathComponent else { continue }
                    do {
                        existing.bookmarkData = try SecurityScopedFile.makeBookmark(for: url)
                        existing.fileName = url.lastPathComponent
                        existing.pageTexts = LibraryBook.extractPageTexts(from: url)
                        existing.pageCount = existing.pageTexts.count
                    } catch {
                        report.errors.append("\(spec.title): \(error.localizedDescription)")
                    }
                    continue
                }
                do {
                    let bookmark = try SecurityScopedFile.makeBookmark(for: url)
                    let pageTexts = LibraryBook.extractPageTexts(from: url)
                    context.insert(LibraryBook(
                        title: spec.title,
                        author: spec.author,
                        fileName: url.lastPathComponent,
                        bookmarkData: bookmark,
                        pageCount: pageTexts.count,
                        pageTexts: pageTexts
                    ))
                    report.booksAdded += 1
                } catch {
                    report.errors.append("\(spec.title): \(error.localizedDescription)")
                }
            }
        } catch {
            report.errors.append("Libros PDF: \(error.localizedDescription)")
        }

        do {
            try context.save()
        } catch {
            report.errors.append("Guardado: \(error.localizedDescription)")
        }
        return report
    }

    private static func allPDFs(in libraryRoot: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: libraryRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// Si un fragmento coincide con más de un archivo (por ejemplo "Volume I" también es prefijo de
    /// "Volume II"), elige el nombre normalizado cuya longitud quede más cerca del fragmento.
    private static func bestPDF(for spec: BookSpec, among urls: [URL]) -> URL? {
        let needle = normalized(spec.fileNameContains)
        return urls
            .filter { normalized($0.deletingPathExtension().lastPathComponent).contains(needle) }
            .min {
                abs(normalized($0.deletingPathExtension().lastPathComponent).count - needle.count) <
                abs(normalized($1.deletingPathExtension().lastPathComponent).count - needle.count)
            }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }
}
