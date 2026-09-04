import SwiftUI
import SwiftData

/// Consultas acotadas al catálogo de Biblioteca, que puede contener miles de registros.
///
/// Antes cada pantalla que necesitaba *un* ejercicio declaraba `@Query` sin filtro y materializaba
/// el catálogo entero — el Dashboard, el timer, Nueva sesión, Clases y Habilidades lo hacían al
/// mismo tiempo. Acá se pide solo lo que se va a mostrar: favoritos, coincidencias de búsqueda con
/// tope, o un ítem por `id`.
///
/// Los selectores pequeños conservan un respaldo en memoria si SwiftData no traduce su predicado;
/// la pantalla principal usa predicados ya validados y nunca cae en un fetch completo.
enum LibraryLookup {
    static let defaultLimit = 25
    /// Una pantalla completa más margen para que el primer render no materialice miles de filas.
    static let libraryPageSize = 80

    /// Carga paginada usada por la pantalla Biblioteca. La búsqueda se resuelve en el store y
    /// aplica el límite antes de crear modelos SwiftData; así cada tecla deja de recorrer y
    /// clasificar el catálogo completo en el hilo principal.
    static func browseExercises(
        matching text: String,
        in context: ModelContext,
        limit: Int
    ) -> [LibraryExercise] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var descriptor: FetchDescriptor<LibraryExercise>
        if query.isEmpty {
            descriptor = FetchDescriptor(sortBy: [SortDescriptor(\.bookTitle)])
        } else if let page = Int(query) {
            descriptor = FetchDescriptor(
                predicate: #Predicate {
                    $0.bookTitle.localizedStandardContains(query)
                        || $0.collectionName.localizedStandardContains(query)
                        || $0.technique.localizedStandardContains(query)
                        || $0.notes.localizedStandardContains(query)
                        || $0.exerciseNumber.localizedStandardContains(query)
                        || $0.chapter.localizedStandardContains(query)
                        || $0.page == page
                },
                sortBy: [SortDescriptor(\.bookTitle)]
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate {
                    $0.bookTitle.localizedStandardContains(query)
                        || $0.collectionName.localizedStandardContains(query)
                        || $0.technique.localizedStandardContains(query)
                        || $0.notes.localizedStandardContains(query)
                        || $0.exerciseNumber.localizedStandardContains(query)
                        || $0.chapter.localizedStandardContains(query)
                },
                sortBy: [SortDescriptor(\.bookTitle)]
            )
        }
        descriptor.fetchLimit = max(1, limit)
        return (try? context.fetch(descriptor)) ?? []
    }

    static func browseConcepts(
        matching text: String,
        in context: ModelContext,
        limit: Int
    ) -> [LibraryConcept] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var descriptor: FetchDescriptor<LibraryConcept>
        if query.isEmpty {
            descriptor = FetchDescriptor(sortBy: [SortDescriptor(\.bookTitle)])
        } else if let page = Int(query) {
            descriptor = FetchDescriptor(
                predicate: #Predicate {
                    $0.bookTitle.localizedStandardContains(query)
                        || $0.title.localizedStandardContains(query)
                        || $0.category.localizedStandardContains(query)
                        || $0.summary.localizedStandardContains(query)
                        || $0.page == page
                },
                sortBy: [SortDescriptor(\.bookTitle)]
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate {
                    $0.bookTitle.localizedStandardContains(query)
                        || $0.title.localizedStandardContains(query)
                        || $0.category.localizedStandardContains(query)
                        || $0.summary.localizedStandardContains(query)
                },
                sortBy: [SortDescriptor(\.bookTitle)]
            )
        }
        descriptor.fetchLimit = max(1, limit)
        return (try? context.fetch(descriptor)) ?? []
    }

    static func browseBooks(
        matching text: String,
        in context: ModelContext,
        limit: Int
    ) -> [LibraryBook] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let predicate: Predicate<LibraryBook>? = query.isEmpty ? nil : #Predicate {
            $0.title.localizedStandardContains(query)
                || $0.author.localizedStandardContains(query)
                || $0.fileName.localizedStandardContains(query)
        }
        var descriptor = FetchDescriptor<LibraryBook>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.title)]
        )
        descriptor.fetchLimit = max(1, limit)
        // `pageTexts` ocupa varios MB y no participa ni en la lista ni en la apertura del PDF.
        // Dejarlo fuera convierte esa propiedad en fault hasta que una función de IA la necesite.
        descriptor.propertiesToFetch = [
            \LibraryBook.id, \.title, \.author, \.fileName, \.bookmarkData, \.pageCount
        ]
        return (try? context.fetch(descriptor)) ?? []
    }

    static func matchingBook(for bookTitle: String, in context: ModelContext) -> LibraryBook? {
        let needle = bookTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }

        var descriptor = FetchDescriptor<LibraryBook>(sortBy: [SortDescriptor(\.title)])
        descriptor.propertiesToFetch = [
            \LibraryBook.id, \.title, \.author, \.fileName, \.bookmarkData, \.pageCount
        ]
        return (try? context.fetch(descriptor))?.first {
            $0.title.localizedCaseInsensitiveContains(needle)
                || needle.localizedCaseInsensitiveContains($0.title)
        }
    }

    static func favorites(in context: ModelContext, limit: Int = defaultLimit) -> [LibraryExercise] {
        var descriptor = FetchDescriptor<LibraryExercise>(
            predicate: #Predicate { $0.isFavorite },
            sortBy: [SortDescriptor(\.bookTitle)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    static func searchExercises(
        _ text: String,
        in context: ModelContext,
        limit: Int = defaultLimit
    ) -> [LibraryExercise] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return favorites(in: context, limit: limit) }

        var descriptor = FetchDescriptor<LibraryExercise>(
            predicate: #Predicate {
                $0.bookTitle.localizedStandardContains(query)
                    || $0.technique.localizedStandardContains(query)
                    || $0.exerciseNumber.localizedStandardContains(query)
                    || $0.chapter.localizedStandardContains(query)
            },
            sortBy: [SortDescriptor(\.bookTitle)]
        )
        descriptor.fetchLimit = limit
        if let matches = try? context.fetch(descriptor) { return matches }

        let all = (try? context.fetch(FetchDescriptor<LibraryExercise>())) ?? []
        return Array(
            all.filter {
                $0.displayName.localizedCaseInsensitiveContains(query)
                    || $0.bookTitle.localizedCaseInsensitiveContains(query)
                    || $0.technique.localizedCaseInsensitiveContains(query)
            }
            .prefix(limit)
        )
    }

    static func exercise(id: UUID?, in context: ModelContext) -> LibraryExercise? {
        guard let id else { return nil }
        var descriptor = FetchDescriptor<LibraryExercise>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    static func exerciseCount(in context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<LibraryExercise>())) ?? 0
    }

    static func conceptCount(in context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<LibraryConcept>())) ?? 0
    }

    static func bookCount(in context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<LibraryBook>())) ?? 0
    }

    /// Trae el catálogo completo, ordenado. Solo para lo que realmente lo necesita entero —
    /// la pantalla Biblioteca y el contexto que se le arma al asistente.
    static func allExercises(in context: ModelContext) -> [LibraryExercise] {
        (try? context.fetch(
            FetchDescriptor<LibraryExercise>(sortBy: [SortDescriptor(\.bookTitle)])
        )) ?? []
    }

    static func allBooks(in context: ModelContext) -> [LibraryBook] {
        (try? context.fetch(FetchDescriptor<LibraryBook>())) ?? []
    }

    static func allConcepts(in context: ModelContext) -> [LibraryConcept] {
        (try? context.fetch(
            FetchDescriptor<LibraryConcept>(sortBy: [SortDescriptor(\.bookTitle)])
        )) ?? []
    }

    /// Catálogo completo compartido entre las pantallas que sí lo necesitan al renderizar.
    ///
    /// Antes cada una de esas pantallas declaraba su propio `@Query` sin filtro: Buscar, Academia,
    /// el detalle de una habilidad y Progreso ordenaban los 1.561 ejercicios y los 963 conceptos por
    /// separado, y `@Query` los volvía a traer ante cualquier cambio del store — incluido guardar una
    /// sesión, que no toca el catálogo. Acá se trae una vez y se reutiliza; la invalidación compara
    /// el conteo, que es una consulta agregada y no materializa filas.
    ///
    /// Las pantallas que solo usan el catálogo dentro de una acción (armar el contexto del asistente,
    /// pedir sugerencias) no deben usar esto: les corresponde `allExercises`/`allConcepts` en el
    /// momento de la llamada, para no pagar nada por el solo hecho de abrir la pantalla.
    @MainActor
    final class Catalog {
        static let shared = Catalog()

        private var exercises: [LibraryExercise] = []
        private var exerciseCount: Int?
        private var concepts: [LibraryConcept] = []
        private var conceptCount: Int?

        private init() {}

        func exercises(in context: ModelContext) -> [LibraryExercise] {
            let count = LibraryLookup.exerciseCount(in: context)
            if exerciseCount != count {
                exercises = LibraryLookup.allExercises(in: context)
                exerciseCount = count
            }
            return exercises
        }

        func concepts(in context: ModelContext) -> [LibraryConcept] {
            let count = LibraryLookup.conceptCount(in: context)
            if conceptCount != count {
                concepts = LibraryLookup.allConcepts(in: context)
                conceptCount = count
            }
            return concepts
        }

        /// La sincronización de Biblioteca puede reemplazar registros sin mover el total. En ese
        /// caso el conteo no alcanza como señal y hay que invalidar a mano.
        func invalidate() {
            exercises = []
            exerciseCount = nil
            concepts = []
            conceptCount = nil
        }
    }

    static func searchConcepts(
        _ text: String,
        in context: ModelContext,
        limit: Int = defaultLimit
    ) -> [LibraryConcept] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var descriptor: FetchDescriptor<LibraryConcept>
        if query.isEmpty {
            descriptor = FetchDescriptor<LibraryConcept>(sortBy: [SortDescriptor(\.bookTitle)])
        } else {
            descriptor = FetchDescriptor<LibraryConcept>(
                predicate: #Predicate {
                    $0.bookTitle.localizedStandardContains(query)
                        || $0.title.localizedStandardContains(query)
                        || $0.category.localizedStandardContains(query)
                },
                sortBy: [SortDescriptor(\.bookTitle)]
            )
        }
        descriptor.fetchLimit = limit
        if let matches = try? context.fetch(descriptor) { return matches }

        let all = (try? context.fetch(FetchDescriptor<LibraryConcept>())) ?? []
        return Array(
            all.filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || $0.bookTitle.localizedCaseInsensitiveContains(query)
                    || $0.category.localizedCaseInsensitiveContains(query)
            }
            .prefix(limit)
        )
    }

    static func concept(id: UUID?, in context: ModelContext) -> LibraryConcept? {
        guard let id else { return nil }
        var descriptor = FetchDescriptor<LibraryConcept>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}

/// El rango por libro requiere leer el catálogo completo, pero no tiene por qué bloquear la
/// transición de pantalla. Se calcula una vez en un contexto privado y se reutiliza mientras no
/// cambie el número de ejercicios.
actor LibraryExerciseContextCache {
    static let shared = LibraryExerciseContextCache()

    private var cachedCount: Int?
    private var cachedContexts: [String: DifficultyClassifier.BookContext] = [:]

    func contexts(
        in container: ModelContainer,
        catalogCount: Int
    ) -> [String: DifficultyClassifier.BookContext] {
        if cachedCount == catalogCount { return cachedContexts }

        let context = ModelContext(container)
        var descriptor = FetchDescriptor<LibraryExercise>()
        descriptor.propertiesToFetch = [
            \LibraryExercise.bookTitle, \.page, \.exerciseNumber
        ]
        let exercises = (try? context.fetch(descriptor)) ?? []
        let contexts = DifficultyClassifier.bookContexts(for: exercises)
        cachedCount = catalogCount
        cachedContexts = contexts
        return contexts
    }
}

/// Selector de ejercicio de Biblioteca con buscador.
///
/// Reemplaza a los `Picker` que listaban los 1.561 ejercicios de una: un menú de mil filas en macOS
/// no solo es lento, es inservible. Sin escribir nada muestra los favoritos; escribiendo, hasta 25
/// coincidencias. La selección actual siempre aparece en la lista aunque no esté entre ellas.
struct LibraryExercisePicker: View {
    let title: String
    let noneLabel: String
    @Binding var selection: UUID?

    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var matches: [LibraryExercise] = []
    @State private var selected: LibraryExercise?

    private var options: [LibraryExercise] {
        guard let selected, !matches.contains(where: { $0.id == selected.id }) else { return matches }
        return [selected] + matches
    }

    var body: some View {
        TextField("Buscar ejercicio por nombre, libro o técnica", text: $searchText)
            .onAppear {
                matches = LibraryLookup.searchExercises(searchText, in: modelContext)
                selected = LibraryLookup.exercise(id: selection, in: modelContext)
            }
            .onChange(of: searchText) { _, newValue in
                matches = LibraryLookup.searchExercises(newValue, in: modelContext)
            }

        Picker(title, selection: $selection) {
            Text(noneLabel).tag(nil as UUID?)
            ForEach(options) { exercise in
                Text("\(exercise.bookTitle) · \(exercise.displayName)")
                    .tag(exercise.id as UUID?)
            }
        }
        .onChange(of: selection) { _, newValue in
            selected = LibraryLookup.exercise(id: newValue, in: modelContext)
        }

        if matches.isEmpty {
            Text(searchText.isEmpty
                 ? "Sin favoritos todavía — busca por nombre, libro o técnica."
                 : "Sin resultados para \"\(searchText)\".")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Selector de concepto o ejercicio teórico de Biblioteca con buscador — mismo patrón que
/// `LibraryExercisePicker`, pero contra `LibraryConcept` (963 conceptos), el catálogo de teoría.
struct LibraryConceptPicker: View {
    let title: String
    let noneLabel: String
    @Binding var selection: UUID?

    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var matches: [LibraryConcept] = []
    @State private var selected: LibraryConcept?

    private var options: [LibraryConcept] {
        guard let selected, !matches.contains(where: { $0.id == selected.id }) else { return matches }
        return [selected] + matches
    }

    var body: some View {
        TextField("Buscar concepto por título, libro o categoría", text: $searchText)
            .onAppear {
                matches = LibraryLookup.searchConcepts(searchText, in: modelContext)
                selected = LibraryLookup.concept(id: selection, in: modelContext)
            }
            .onChange(of: searchText) { _, newValue in
                matches = LibraryLookup.searchConcepts(newValue, in: modelContext)
            }

        Picker(title, selection: $selection) {
            Text(noneLabel).tag(nil as UUID?)
            ForEach(options) { concept in
                Text("\(concept.bookTitle) · \(concept.title)")
                    .tag(concept.id as UUID?)
            }
        }
        .onChange(of: selection) { _, newValue in
            selected = LibraryLookup.concept(id: newValue, in: modelContext)
        }

        if matches.isEmpty && !searchText.isEmpty {
            Text("Sin resultados para \"\(searchText)\".")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
