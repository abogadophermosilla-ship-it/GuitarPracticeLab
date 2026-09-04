import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private enum LibraryMode: String, CaseIterable, Identifiable {
    case exercises = "Ejercicios"
    case books = "Libros PDF"
    case concepts = "Conceptos"
    case bookSearch = "Buscar en libros"
    var id: String { rawValue }
}

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigator.self) private var navigator
    @AppStorage(LearningMaterialsService.rootPathKey)
    private var materialsRoot = LearningMaterialsService.defaultRootPath
    @State private var mode: LibraryMode = .exercises
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var selectedID: UUID?
    @State private var selectedBookID: UUID?
    @State private var selectedConceptID: UUID?
    @State private var showingNewExercise = false
    @State private var showingImportBook = false
    @State private var isImportingBook = false
    @State private var importError = ""
    @State private var bookIndexMessage = ""
    @State private var showingImportCatalog = false
    @State private var isImportingCatalog = false
    @State private var catalogImportMessage = ""
    @State private var showingImportConcepts = false
    @State private var isImportingConcepts = false
    @State private var conceptImportMessage = ""
    @State private var externalLibraryAvailable = false
    @State private var exerciseCount = 0
    @State private var conceptCount = 0
    @State private var bookCount = 0
    @State private var catalogRevision = 0
    @State private var attemptedAutomaticCatalogCleanup = false

    private var searchPrompt: String {
        switch mode {
        case .bookSearch: "Pregunta algo o describe una técnica — busca por significado, no por palabra exacta"
        default: "Buscar por libro, autor, técnica, página, ejercicio o concepto"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            responsiveHeader
                .padding(20)

            HStack(spacing: 8) {
                Label(
                    externalLibraryAvailable ? "VST/Clases/Libros conectado" : "Biblioteca externa desconectada",
                    systemImage: externalLibraryAvailable
                        ? "externaldrive.fill.badge.checkmark"
                        : "externaldrive.badge.xmark"
                )
                .foregroundStyle(externalLibraryAvailable ? .green : .orange)
                Spacer()
                Text("\(exerciseCount) ejercicios · \(conceptCount) conceptos · \(bookCount) libros")
                    .foregroundStyle(.secondary)
                Button("Abrir carpeta", systemImage: "folder") {
                    LearningMaterialsService.open(LearningMaterialsService.booksURL)
                }
                .disabled(!externalLibraryAvailable)
            }
            .font(.caption)
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            if !importError.isEmpty {
                Text(importError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
            }
            if !catalogImportMessage.isEmpty {
                Text(catalogImportMessage)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 24)
            }
            if !conceptImportMessage.isEmpty {
                Text(conceptImportMessage)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 24)
            }
            if !bookIndexMessage.isEmpty {
                Text(bookIndexMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }

            switch mode {
            case .exercises:
                LibraryExercisesPane(
                    searchText: debouncedSearchText,
                    revision: catalogRevision,
                    selectedID: $selectedID,
                    onAddToTasks: addToTasks,
                    onCountChanged: { exerciseCount = $0 }
                )
            case .books:
                // Sin debounce a propósito: la Biblioteca de libros es chica (decenas, no miles
                // como Ejercicios) y el fetch con filtro ya corre en un puñado de milisegundos,
                // así que el debounce de 100ms pensado para esa tabla grande solo suma demora
                // percibida acá sin evitar ningún trabajo real.
                LibraryBooksPane(
                    searchText: searchText,
                    revision: catalogRevision,
                    selectedID: $selectedBookID,
                    onCountChanged: { bookCount = $0 }
                )
            case .concepts:
                LibraryConceptsPane(
                    searchText: debouncedSearchText,
                    revision: catalogRevision,
                    selectedID: $selectedConceptID,
                    onCountChanged: { conceptCount = $0 }
                )
            case .bookSearch:
                // Sin pasar por `debouncedSearchText`: acá el debounce lo hace la propia pestaña,
                // más largo (450ms) porque cada consulta dispara una llamada HTTP al servicio local
                // que a su vez pide un embedding a Ollama, no un fetch de SwiftData en el disco.
                LibraryBookSearchPane(searchText: searchText)
            }
        }
        .searchable(text: $searchText, prompt: searchPrompt)
        .task(id: searchText) {
            // Debounce breve para agrupar pulsaciones rápidas. La consulta posterior ya está
            // acotada en SwiftData, así que puede responder sin la espera larga anterior.
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            debouncedSearchText = searchText
        }
        .sheet(isPresented: $showingNewExercise) {
            NewExerciseView()
                .frame(minWidth: 540, minHeight: 540)
        }
        .onAppear {
            applyPendingFocus()
            applyPendingConceptFocus()
            refreshCatalogCounts()
        }
        .task(id: materialsRoot) {
            await refreshExternalLibraryAvailability()
        }
        .task(id: "cleanup|\(externalLibraryAvailable)|\(exerciseCount)") {
            await optimizeOversizedCatalogIfNeeded()
        }
        .onChange(of: showingNewExercise) { wasShowing, isShowing in
            guard wasShowing, !isShowing else { return }
            catalogRevision += 1
            refreshCatalogCounts()
        }
        .onChange(of: navigator.focusExerciseID) { _, _ in applyPendingFocus() }
        .onChange(of: navigator.focusLibraryConceptID) { _, _ in applyPendingConceptFocus() }
        .fileImporter(isPresented: $showingImportBook, allowedContentTypes: [.pdf]) { result in
            importBook(result)
        }
        .fileImporter(isPresented: $showingImportCatalog, allowedContentTypes: [.json]) { result in
            importCatalog(result)
        }
        .fileImporter(isPresented: $showingImportConcepts, allowedContentTypes: [.json]) { result in
            importConcepts(result)
        }
    }

    /// Se refresca al aparecer y al cambiar la carpeta raíz, sin bloquear el hilo de interfaz.
    @MainActor
    private func refreshExternalLibraryAvailability() async {
        // Un disco externo dormido puede tardar varios segundos en responder a `stat`. Esa espera
        // no debe congelar la transición a Biblioteca, por eso incluso la resolución del bookmark
        // y la consulta al filesystem ocurren fuera del actor principal.
        let available = await Task.detached(priority: .utility) {
            FileManager.default.fileExists(atPath: LearningMaterialsService.booksURL.path)
        }.value
        guard !Task.isCancelled else { return }
        externalLibraryAvailable = available
    }

    /// Los contadores usan `fetchCount`: consultan SQLite sin materializar miles de modelos.
    /// Cada panel actualiza además su propio total al cargar o eliminar contenido.
    private func refreshCatalogCounts() {
        exerciseCount = LibraryLookup.exerciseCount(in: modelContext)
        conceptCount = LibraryLookup.conceptCount(in: modelContext)
        bookCount = LibraryLookup.bookCount(in: modelContext)
    }

    private var responsiveHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                libraryTitle
                Spacer()
                libraryControls
            }
            VStack(alignment: .leading, spacing: 12) {
                libraryTitle
                libraryControls
            }
        }
    }

    private var libraryTitle: some View {
        VStack(alignment: .leading) {
            Text("Biblioteca")
                .font(.largeTitle.bold())
            Text("Ejercicios y teoría extraídos de tus libros externos")
                .foregroundStyle(.secondary)
        }
    }

    private var libraryControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                modePicker
                modeActions
            }
            VStack(alignment: .leading, spacing: 8) {
                modePicker
                modeActions
            }
        }
    }

    private var modePicker: some View {
        Picker("Vista", selection: $mode) {
            ForEach(LibraryMode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
    }

    @ViewBuilder
    private var modeActions: some View {
        HStack {
            switch mode {
            case .exercises:
                if isImportingCatalog {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Importar catálogo", systemImage: "square.and.arrow.down") {
                        showingImportCatalog = true
                    }
                }
                Button("Agregar ejercicio", systemImage: "plus") { showingNewExercise = true }
                    .buttonStyle(.borderedProminent)
            case .books:
                if isImportingBook {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Agregar PDF", systemImage: "doc.badge.plus") { showingImportBook = true }
                        .buttonStyle(.borderedProminent)
                }
            case .concepts:
                if isImportingConcepts {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Importar conceptos", systemImage: "square.and.arrow.down") {
                        showingImportConcepts = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .bookSearch:
                EmptyView()
            }
        }
    }

    private func importCatalog(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        importError = ""
        catalogImportMessage = ""
        isImportingCatalog = true
        Task {
            defer { isImportingCatalog = false }
            do {
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                let existing = LibraryLookup.allExercises(in: modelContext)
                let report = try LibraryExerciseImporter.synchronizeCatalog(
                    from: url, existing: existing, into: modelContext
                )
                await MainActor.run {
                    catalogImportMessage = importSummary(report)
                    refreshCatalogCounts()
                    if report.added + report.updated + report.removedObsolete > 0 {
                        catalogRevision += 1
                    }
                }
            } catch {
                await MainActor.run {
                    importError = "No se pudo importar el catálogo: \(error.localizedDescription)"
                }
            }
        }
    }

    /// La base histórica puede contener versiones antiguas del catálogo acumuladas. Solo se
    /// activa cuando el conteo es claramente mayor al corpus actual; así una biblioteca normal no
    /// vuelve a leer el disco externo cada vez que se abre esta pantalla.
    @MainActor
    private func optimizeOversizedCatalogIfNeeded() async {
        guard externalLibraryAvailable,
              exerciseCount > 1_800,
              !attemptedAutomaticCatalogCleanup,
              !isImportingCatalog else { return }
        attemptedAutomaticCatalogCleanup = true
        isImportingCatalog = true
        defer { isImportingCatalog = false }

        let url = LearningMaterialsService.booksURL
            .appendingPathComponent("_catalogo_ejercicios", isDirectory: true)
            .appendingPathComponent("compiled_ejercicios_guitarra.json")
        guard FileManager.default.isReadableFile(atPath: url.path) else { return }

        do {
            let report = try LibraryExerciseImporter.synchronizeCatalog(
                from: url,
                existing: LibraryLookup.allExercises(in: modelContext),
                into: modelContext
            )
            catalogImportMessage = "Biblioteca optimizada. \(importSummary(report))"
            refreshCatalogCounts()
            catalogRevision += 1
        } catch {
            // La optimización automática es mantenimiento oportunista; la lista ya cargada sigue
            // siendo válida si el volumen se desconecta a mitad de la lectura.
            importError = "No se pudo optimizar el catálogo: \(error.localizedDescription)"
        }
    }

    private func importSummary(_ report: LibraryExerciseImporter.ImportReport) -> String {
        var parts: [String] = []
        if report.added > 0 { parts.append("\(report.added) agregados") }
        if report.updated > 0 { parts.append("\(report.updated) actualizados") }
        if report.removedObsolete > 0 { parts.append("\(report.removedObsolete) duplicados obsoletos retirados") }
        if report.preservedWithProgress > 0 { parts.append("\(report.preservedWithProgress) históricos conservados por tener progreso") }
        return parts.isEmpty ? "El catálogo ya estaba sincronizado." : parts.joined(separator: " · ") + "."
    }

    private func importConcepts(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        importError = ""
        conceptImportMessage = ""
        isImportingConcepts = true
        Task {
            defer { isImportingConcepts = false }
            do {
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                let existing = LibraryLookup.allConcepts(in: modelContext)
                let added = try LibraryConceptImporter.importCatalog(from: url, existing: existing, into: modelContext)
                await MainActor.run {
                    conceptImportMessage = added == 0
                        ? "No hay conceptos nuevos — el catálogo ya estaba importado."
                        : "Se agregaron \(added) conceptos nuevos al catálogo."
                    refreshCatalogCounts()
                    if added > 0 { catalogRevision += 1 }
                }
            } catch {
                await MainActor.run {
                    importError = "No se pudo importar el catálogo de conceptos: \(error.localizedDescription)"
                }
            }
        }
    }

    private func importBook(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        importError = ""
        bookIndexMessage = ""
        isImportingBook = true
        Task {
            defer { isImportingBook = false }
            do {
                let bookmark = try SecurityScopedFile.makeBookmark(for: url)
                let pageTexts = LibraryBook.extractPageTexts(from: url)
                let title = url.deletingPathExtension().lastPathComponent
                await MainActor.run {
                    modelContext.insert(LibraryBook(
                        title: title,
                        fileName: url.lastPathComponent,
                        bookmarkData: bookmark,
                        pageCount: pageTexts.count,
                        pageTexts: pageTexts
                    ))
                    refreshCatalogCounts()
                    catalogRevision += 1
                }
                let outcome = await BookRAGIndexer.indexIfPossible(
                    title: title, fileName: url.lastPathComponent, pageTexts: pageTexts
                )
                await MainActor.run {
                    switch outcome {
                    case .indexed:
                        bookIndexMessage = "Libro indexado para el Profesor IA."
                    case .skipped(let reason):
                        bookIndexMessage = "Agregado a la Biblioteca. No quedó indexado para el Profesor IA: \(reason)."
                    case .failed(let reason):
                        bookIndexMessage = "Agregado a la Biblioteca, pero falló la indexación para el Profesor IA: \(reason)."
                    }
                }
            } catch {
                await MainActor.run {
                    importError = "No se pudo leer el PDF: \(error.localizedDescription)"
                }
            }
        }
    }

    private func addToTasks(_ exercise: LibraryExercise) {
        let resolution = PracticeTaskDeduplication.resolve(
            candidateTitle: exercise.displayName, candidateSourceKind: .library,
            candidateSourceID: exercise.id, in: modelContext
        )
        guard PracticeTaskDeduplication.apply(resolution, in: modelContext) else { return }
        modelContext.insert(PracticeTask(
            title: exercise.displayName,
            category: .technique,
            plannedMinutes: 15,
            sourceTitle: exercise.bookTitle,
            exerciseTitle: exercise.displayName,
            targetBPM: exercise.targetBPM,
            priority: 1,
            instructions: exercise.page > 0 ? "Trabajar el ejercicio de la página \(exercise.page)." : "",
            sourceKind: .library,
            sourceID: exercise.id
        ))
    }

    private func applyPendingFocus() {
        guard let focusID = navigator.focusExerciseID else { return }
        mode = .exercises
        selectedID = focusID
        navigator.focusExerciseID = nil
    }

    private func applyPendingConceptFocus() {
        guard let focusID = navigator.focusLibraryConceptID else { return }
        mode = .concepts
        selectedConceptID = focusID
        navigator.focusLibraryConceptID = nil
    }
}

/// Cada modo vive en un subárbol distinto para que SwiftData solo materialice el catálogo que
/// está visible. Antes, abrir Ejercicios también cargaba Conceptos y el texto completo de los PDF.
struct NewExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var collection = ""
    @State private var book = ""
    @State private var chapter = ""
    @State private var exercise = ""
    @State private var page = 0
    @State private var technique = ""
    @State private var targetBPM = 0
    @State private var status = ExerciseStatus.notStarted
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Fuente") {
                    TextField("Colección o autor", text: $collection)
                    TextField("Libro", text: $book)
                    TextField("Capítulo", text: $chapter)
                    TextField("Número o nombre del ejercicio", text: $exercise)
                    Stepper("Página: \(page == 0 ? "—" : String(page))", value: $page, in: 0...2000)
                }
                Section("Progresión") {
                    TextField("Técnica o habilidad", text: $technique)
                    BPMField(label: "Tempo objetivo:", value: $targetBPM)
                    Picker("Estado", selection: $status) {
                        ForEach(ExerciseStatus.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Notas", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Agregar ejercicio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        modelContext.insert(LibraryExercise(
                            collectionName: collection,
                            bookTitle: book,
                            chapter: chapter,
                            exerciseNumber: exercise,
                            page: page,
                            technique: technique,
                            targetBPM: targetBPM,
                            status: status,
                            notes: notes
                        ))
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(book.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || technique.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
