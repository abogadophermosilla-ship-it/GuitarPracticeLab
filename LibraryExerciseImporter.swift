import Foundation
import SwiftData

/// Importa el catálogo de ejercicios compilado por la sesión paralela de análisis de PDFs
/// (`_catalogo_ejercicios/compiled_ejercicios_guitarra.json` — ver `HANDOFF.md` en esa misma
/// carpeta para el proceso completo de extracción/OCR/traducción/catalogación). El esquema es fijo
/// y no lo genera la IA de esta app, solo se transcribe:
/// `{ "libro", "titulo_ejercicio", "pagina", "tecnica", "dificultad", "descripcion" }`.
enum LibraryExerciseImporter {
    private struct ImportedExercise: Decodable {
        let libro: String
        let tituloEjercicio: String
        let pagina: Int
        let tecnica: String
        let dificultad: String
        let descripcion: String

        enum CodingKeys: String, CodingKey {
            case libro
            case tituloEjercicio = "titulo_ejercicio"
            case pagina
            case tecnica
            case dificultad
            case descripcion
        }
    }

    enum ImportError: LocalizedError {
        case invalidFormat

        var errorDescription: String? {
            "El archivo no tiene el formato esperado: un array de ejercicios con libro, titulo_ejercicio, pagina, tecnica, dificultad y descripcion."
        }
    }

    /// Nombre de colección fijo para distinguir los ejercicios importados de este catálogo de los
    /// agregados a mano desde "Agregar ejercicio".
    static let collectionName = "Catálogo de ejercicios"

    struct ImportReport {
        var added = 0
        var updated = 0
        var removedObsolete = 0
        var preservedWithProgress = 0
    }

    /// Importa desde `url` (el `compiled_ejercicios_guitarra.json`), evitando duplicar ejercicios ya
    /// importados antes (mismo libro + página + título + descripción) para que se pueda volver a
    /// correr cuando la otra sesión agregue más libros sin generar copias repetidas. La descripción
    /// forma parte de la clave porque el catálogo contiene dos ejercicios reales con el mismo título
    /// y página ("One-Position Runs"), uno pentatónico menor y otro mayor.
    @discardableResult
    static func importCatalog(from url: URL, existing: [LibraryExercise], into context: ModelContext) throws -> Int {
        try synchronizeCatalog(from: url, existing: existing, into: context).added
    }

    /// Sincroniza en vez de acumular versiones históricas del mismo catálogo. Antes la descripción
    /// formaba parte de la identidad: si el extractor mejoraba una frase, se insertaba una fila nueva
    /// y quedaba la anterior. La base activa llegó así a más de 2.200 filas para un catálogo de unas
    /// 1.650, ralentizando búsqueda, clasificación y renderizado.
    ///
    /// La identidad estable es libro + página + título; la descripción solo desempata el único caso
    /// real que comparte esos tres campos. Se conservan el UUID, favoritos, progreso, tempo y notas
    /// del registro elegido. Las filas obsoletas se eliminan únicamente si no tienen progreso ni una
    /// tarea/sesión vinculada.
    @discardableResult
    static func synchronizeCatalog(
        from url: URL,
        existing: [LibraryExercise],
        into context: ModelContext
    ) throws -> ImportReport {
        let data = try Data(contentsOf: url)
        let imported: [ImportedExercise]
        do {
            imported = try JSONDecoder().decode([ImportedExercise].self, from: data)
        } catch {
            throw ImportError.invalidFormat
        }

        let importedExisting = existing.filter { $0.collectionName == collectionName }
        var unusedByID = Dictionary(uniqueKeysWithValues: importedExisting.map { ($0.id, $0) })
        var byExactKey = Dictionary(grouping: importedExisting) {
            exactKey(book: $0.bookTitle, page: $0.page, title: $0.exerciseNumber, description: $0.notes)
        }
        var byStableKey = Dictionary(grouping: importedExisting) {
            stableKey(book: $0.bookTitle, page: $0.page, title: $0.exerciseNumber)
        }
        var report = ImportReport()

        for entry in imported {
            let exact = exactKey(
                book: entry.libro,
                page: entry.pagina,
                title: entry.tituloEjercicio,
                description: entry.descripcion
            )
            let stable = stableKey(book: entry.libro, page: entry.pagina, title: entry.tituloEjercicio)

            let match = byExactKey[exact]?.first(where: { unusedByID[$0.id] != nil })
                ?? byStableKey[stable]?.first(where: { unusedByID[$0.id] != nil })

            if let match {
                unusedByID.removeValue(forKey: match.id)
                let newDifficulty = difficultyLevel(for: entry.dificultad)
                let changed = match.bookTitle != entry.libro
                    || match.exerciseNumber != entry.tituloEjercicio
                    || match.page != entry.pagina
                    || match.technique != entry.tecnica
                    || match.difficulty != newDifficulty
                match.bookTitle = entry.libro
                match.exerciseNumber = entry.tituloEjercicio
                match.page = entry.pagina
                match.technique = entry.tecnica
                match.difficulty = newDifficulty
                // `notes` también admite observaciones personales. No se pisa al sincronizar: el
                // detalle estructural nuevo vive en el RAG y el texto del usuario permanece intacto.
                if changed { report.updated += 1 }
                continue
            }

            context.insert(LibraryExercise(
                collectionName: collectionName,
                bookTitle: entry.libro,
                exerciseNumber: entry.tituloEjercicio,
                page: entry.pagina,
                technique: entry.tecnica,
                notes: entry.descripcion,
                difficulty: difficultyLevel(for: entry.dificultad)
            ))
            report.added += 1
        }

        let linkedExerciseIDs = Set(
            ((try? context.fetch(FetchDescriptor<PracticeTask>())) ?? [])
                .filter { $0.sourceKind == .library }
                .compactMap(\.sourceID)
            + ((try? context.fetch(FetchDescriptor<PracticeSession>())) ?? [])
                .filter { $0.sourceKind == .library }
                .compactMap(\.sourceID)
        )

        for obsolete in unusedByID.values {
            let hasPersonalState = obsolete.isFavorite
                || obsolete.targetBPM > 0
                || obsolete.status != .notStarted
                || linkedExerciseIDs.contains(obsolete.id)
            if hasPersonalState {
                report.preservedWithProgress += 1
            } else {
                context.delete(obsolete)
                report.removedObsolete += 1
            }
        }
        try context.save()
        return report
    }

    private static func exactKey(book: String, page: Int, title: String, description: String) -> String {
        "\(stableKey(book: book, page: page, title: title))|\(normalized(description))"
    }

    private static func stableKey(book: String, page: Int, title: String) -> String {
        "\(normalized(book))|\(page)|\(normalized(title))"
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }

    private static func difficultyLevel(for rawValue: String) -> SkillLevel? {
        switch rawValue.lowercased() {
        case "principiante": .basic
        case "intermedio": .intermediate
        case "avanzado": .advanced
        default: nil
        }
    }
}
