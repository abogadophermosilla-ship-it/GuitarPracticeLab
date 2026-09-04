import Foundation
import SwiftData

/// Importa el catálogo de conceptos de teoría compilado por la sesión paralela de análisis de PDFs
/// (`_catalogo_ejercicios/compiled_teoria_guitarra.json` — ver `HANDOFF.md` en esa misma carpeta).
/// Esquema fijo y no lo genera la IA de esta app, solo se transcribe:
/// `{ "libro", "titulo", "pagina", "tipo", "categoria", "nivel", "resumen" }`.
enum LibraryConceptImporter {
    private struct ImportedConcept: Decodable {
        let libro: String
        let titulo: String
        let pagina: Int
        let tipo: String
        let categoria: String
        let nivel: String
        let resumen: String
    }

    enum ImportError: LocalizedError {
        case invalidFormat

        var errorDescription: String? {
            "El archivo no tiene el formato esperado: un array de conceptos con libro, titulo, pagina, tipo, categoria, nivel y resumen."
        }
    }

    /// Importa desde `url` (el `compiled_teoria_guitarra.json`), evitando duplicar conceptos ya
    /// importados antes (mismo libro + página + título) para que se pueda volver a correr cuando la
    /// otra sesión agregue más libros sin generar copias repetidas. Devuelve cuántos se agregaron.
    @discardableResult
    static func importCatalog(from url: URL, existing: [LibraryConcept], into context: ModelContext) throws -> Int {
        let data = try Data(contentsOf: url)
        let imported: [ImportedConcept]
        do {
            imported = try JSONDecoder().decode([ImportedConcept].self, from: data)
        } catch {
            throw ImportError.invalidFormat
        }

        var seenKeys = Set(existing.map { key(book: $0.bookTitle, page: $0.page, title: $0.title) })

        var addedCount = 0
        for entry in imported {
            let entryKey = key(book: entry.libro, page: entry.pagina, title: entry.titulo)
            guard !seenKeys.contains(entryKey) else { continue }
            seenKeys.insert(entryKey)

            context.insert(LibraryConcept(
                bookTitle: entry.libro,
                title: entry.titulo,
                page: entry.pagina,
                category: entry.categoria,
                level: level(for: entry.nivel),
                summary: entry.resumen,
                isExercise: entry.tipo == "ejercicio_teorico"
            ))
            addedCount += 1
        }
        return addedCount
    }

    private static func key(book: String, page: Int, title: String) -> String {
        "\(book)|\(page)|\(title)"
    }

    private static func level(for rawValue: String) -> SkillLevel? {
        switch rawValue.lowercased() {
        case "principiante": .basic
        case "intermedio": .intermediate
        case "avanzado": .advanced
        default: nil
        }
    }
}
