import SwiftUI
import SwiftData

// Paneles de Biblioteca (Ejercicios, Libros PDF, Conceptos) con sus filas y vistas de detalle.
// Se separaron de LibraryView.swift, que quedaba con la pantalla, los tres paneles y sus detalles
// en un solo archivo de mil líneas.

struct LibraryExercisesPane: View {
    @Environment(\.modelContext) private var modelContext

    let searchText: String
    let revision: Int
    @Binding var selectedID: UUID?
    let onAddToTasks: (LibraryExercise) -> Void
    let onCountChanged: (Int) -> Void

    @State private var exercises: [LibraryExercise] = []
    @State private var contexts: [String: DifficultyClassifier.BookContext] = [:]
    @State private var limit = LibraryLookup.libraryPageSize
    @State private var totalCount = 0
    @State private var isLoading = true

    private var canLoadMore: Bool { exercises.count == limit && exercises.count < totalCount }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedID) {
                ForEach(exercises) { exercise in
                    let context = DifficultyClassifier.context(forBook: exercise.bookTitle, in: contexts)
                    LibraryExerciseRow(
                        exercise: exercise,
                        rating: DifficultyClassifier.rating(for: exercise, context: context)
                    )
                    .tag(exercise.id)
                    .contextMenu {
                        Button("Agregar a tareas", systemImage: "checklist") {
                            onAddToTasks(exercise)
                        }
                        Button("Eliminar", systemImage: "trash", role: .destructive) {
                            delete(exercise)
                        }
                    }
                }
                if canLoadMore {
                    Button("Mostrar más", systemImage: "chevron.down") {
                        limit += LibraryLookup.libraryPageSize
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(minWidth: 240, idealWidth: 320, maxWidth: 380)
            Divider()
            Group {
                if isLoading, exercises.isEmpty {
                    ProgressView("Cargando ejercicios…")
                } else if let exercise = exercises.first(where: { $0.id == selectedID }) ?? exercises.first {
                    let context = DifficultyClassifier.context(forBook: exercise.bookTitle, in: contexts)
                    ExerciseDetailView(
                        exercise: exercise,
                        assessment: DifficultyClassifier.assess(exercise, context: context),
                        onAddToTasks: onAddToTasks
                    )
                } else {
                    EmptyStateView(
                        icon: searchText.isEmpty ? "books.vertical" : "magnifyingglass",
                        title: searchText.isEmpty ? "Sin ejercicios" : "Sin resultados",
                        message: searchText.isEmpty ? "Agrega tu primer material." : "Prueba con otro libro, técnica o página."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: searchText) { _, _ in
            limit = LibraryLookup.libraryPageSize
        }
        .task(id: "results|\(searchText)|\(limit)|\(revision)") {
            await loadExercises()
        }
        .task(id: "contexts|\(revision)") {
            // Primero deja que la lista y su selección aparezcan; el contexto solo afina la nota.
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let count = LibraryLookup.exerciseCount(in: modelContext)
            let loaded = await LibraryExerciseContextCache.shared.contexts(
                in: modelContext.container,
                catalogCount: count
            )
            guard !Task.isCancelled else { return }
            contexts = loaded
        }
    }

    @MainActor
    private func loadExercises() async {
        isLoading = true
        await Task.yield()
        let count = LibraryLookup.exerciseCount(in: modelContext)
        let loaded = LibraryLookup.browseExercises(matching: searchText, in: modelContext, limit: limit)
        guard !Task.isCancelled else { return }
        totalCount = count
        exercises = loaded
        onCountChanged(count)
        if !loaded.contains(where: { $0.id == selectedID }) {
            selectedID = loaded.first?.id
        }
        isLoading = false
    }

    private func delete(_ exercise: LibraryExercise) {
        modelContext.delete(exercise)
        exercises.removeAll { $0.id == exercise.id }
        totalCount = max(0, totalCount - 1)
        onCountChanged(totalCount)
        if selectedID == exercise.id { selectedID = exercises.first?.id }
    }
}

struct LibraryBooksPane: View {
    @Environment(\.modelContext) private var modelContext

    let searchText: String
    let revision: Int
    @Binding var selectedID: UUID?
    let onCountChanged: (Int) -> Void

    @State private var books: [LibraryBook] = []
    @State private var isLoading = true

    var body: some View {
        HStack(spacing: 0) {
            List(books, selection: $selectedID) { book in
                LibraryBookRow(book: book)
                    .tag(book.id)
                    .contextMenu {
                        Button("Eliminar", systemImage: "trash", role: .destructive) {
                            delete(book)
                        }
                    }
            }
            .frame(minWidth: 240, idealWidth: 320, maxWidth: 380)
            Divider()
            Group {
                if isLoading, books.isEmpty {
                    ProgressView("Cargando libros…")
                } else if let book = books.first(where: { $0.id == selectedID }) ?? books.first {
                    LibraryBookDetailView(book: book)
                } else {
                    EmptyStateView(
                        icon: "doc.text.magnifyingglass",
                        title: searchText.isEmpty ? "Sin libros" : "Sin resultados",
                        message: searchText.isEmpty ? "Agrega el PDF de un libro de método." : "Prueba con otro título o autor."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: "\(searchText)|\(revision)") {
            await loadBooks()
        }
    }

    @MainActor
    private func loadBooks() async {
        isLoading = true
        await Task.yield()
        let count = LibraryLookup.bookCount(in: modelContext)
        let loaded = LibraryLookup.browseBooks(
            matching: searchText,
            in: modelContext,
            limit: max(count, LibraryLookup.libraryPageSize)
        )
        guard !Task.isCancelled else { return }
        books = loaded
        onCountChanged(count)
        if !loaded.contains(where: { $0.id == selectedID }) {
            selectedID = loaded.first?.id
        }
        isLoading = false
    }

    private func delete(_ book: LibraryBook) {
        modelContext.delete(book)
        books.removeAll { $0.id == book.id }
        onCountChanged(max(0, LibraryLookup.bookCount(in: modelContext)))
        if selectedID == book.id { selectedID = books.first?.id }
    }
}

struct LibraryConceptsPane: View {
    @Environment(\.modelContext) private var modelContext

    let searchText: String
    let revision: Int
    @Binding var selectedID: UUID?
    let onCountChanged: (Int) -> Void

    @State private var concepts: [LibraryConcept] = []
    @State private var limit = LibraryLookup.libraryPageSize
    @State private var totalCount = 0
    @State private var isLoading = true

    private var canLoadMore: Bool { concepts.count == limit && concepts.count < totalCount }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedID) {
                ForEach(concepts) { concept in
                    LibraryConceptRow(concept: concept)
                        .tag(concept.id)
                        .contextMenu {
                            Button("Eliminar", systemImage: "trash", role: .destructive) {
                                delete(concept)
                            }
                        }
                }
                if canLoadMore {
                    Button("Mostrar más", systemImage: "chevron.down") {
                        limit += LibraryLookup.libraryPageSize
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(minWidth: 240, idealWidth: 320, maxWidth: 380)
            Divider()
            Group {
                if isLoading, concepts.isEmpty {
                    ProgressView("Cargando conceptos…")
                } else if let concept = concepts.first(where: { $0.id == selectedID }) ?? concepts.first {
                    LibraryConceptDetailView(concept: concept)
                } else {
                    EmptyStateView(
                        icon: searchText.isEmpty ? "text.book.closed" : "magnifyingglass",
                        title: searchText.isEmpty ? "Sin conceptos" : "Sin resultados",
                        message: searchText.isEmpty ? "Importa el catálogo de conceptos de teoría." : "Prueba con otro título, libro o categoría."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: searchText) { _, _ in
            limit = LibraryLookup.libraryPageSize
        }
        .task(id: "\(searchText)|\(limit)|\(revision)") {
            await loadConcepts()
        }
    }

    @MainActor
    private func loadConcepts() async {
        isLoading = true
        await Task.yield()
        let count = LibraryLookup.conceptCount(in: modelContext)
        let loaded = LibraryLookup.browseConcepts(matching: searchText, in: modelContext, limit: limit)
        guard !Task.isCancelled else { return }
        totalCount = count
        concepts = loaded
        onCountChanged(count)
        if !loaded.contains(where: { $0.id == selectedID }) {
            selectedID = loaded.first?.id
        }
        isLoading = false
    }

    private func delete(_ concept: LibraryConcept) {
        modelContext.delete(concept)
        concepts.removeAll { $0.id == concept.id }
        totalCount = max(0, totalCount - 1)
        onCountChanged(totalCount)
        if selectedID == concept.id { selectedID = concepts.first?.id }
    }
}

private struct LibraryExerciseRow: View {
    let exercise: LibraryExercise
    let rating: DifficultyRating

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: exercise.isFavorite ? "star.fill" : "book.closed.fill")
                .foregroundStyle(exercise.isFavorite ? .yellow : .blue)
                .frame(width: 34, height: 34)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.displayName)
                    .font(.headline)
                Text("\(exercise.collectionName) · \(exercise.bookTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            DifficultyBadge(rating: rating)
            if exercise.targetBPM > 0 {
                Text("\(exercise.targetBPM) BPM")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            StatusPill(text: exercise.status.rawValue, tint: statusColor(exercise.status))
        }
        .padding(.vertical, 6)
    }

    private func statusColor(_ status: ExerciseStatus) -> Color {
        switch status {
        case .mastered: .green
        case .consolidating, .reducedTempo: .blue
        case .periodicReview: .purple
        default: .orange
        }
    }
}

private struct ExerciseDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var exercise: LibraryExercise
    let assessment: DifficultyAssessment
    var onAddToTasks: (LibraryExercise) -> Void
    @State private var showingPDF = false
    @State private var matchingBook: LibraryBook?
    @State private var finishedBookLookup = false

    /// El editor de notas escribe en este borrador y recién persiste al modelo tras una pausa
    /// de tipeo. Enlazar el `TextEditor` directo a `exercise.notes` guardaba en SwiftData en
    /// cada tecla, y cada guardado invalidaba las `@Query` de `LibraryView` (refiltrado de
    /// todo el catálogo —`filtered` lee `notes`— más redibujo de la lista): por eso escribir
    /// notas se sentía lento.
    @State private var notesDraft = ""
    /// Dueño del borrador: si cambia la selección hay que volcarlo al ejercicio anterior
    /// antes de cargar el nuevo, o se perdería lo último escrito.
    @State private var notesDraftOwner: LibraryExercise?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    Image(systemName: "book.closed.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.blue)
                        .frame(width: 70, height: 82)
                        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(exercise.collectionName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(exercise.bookTitle)
                            .font(.title2.bold())
                        Text(exercise.displayName)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if matchingBook != nil {
                        Button("Ver PDF", systemImage: "doc.text.magnifyingglass") {
                            showingPDF = true
                        }
                        .buttonStyle(.bordered)
                    }
                    Button("Agregar a tareas", systemImage: "checklist") {
                        onAddToTasks(exercise)
                    }
                    .buttonStyle(.bordered)
                }

                Divider()
                DifficultySummaryView(assessment: assessment)
                    .padding(12)
                    .background(assessment.rating.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                LabeledContent("Técnica", value: exercise.technique)
                LabeledContent("Página", value: exercise.page > 0 ? "\(exercise.page)" : "—")
                if finishedBookLookup, matchingBook == nil {
                    Text("El libro \"\(exercise.bookTitle)\" no está importado en Biblioteca → Libros PDF, así que no se puede abrir el PDF.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Tempo objetivo", value: exercise.targetBPM > 0 ? "\(exercise.targetBPM) BPM" : "—")

                Picker("Estado", selection: Binding(
                    get: { exercise.status },
                    set: { newValue in
                        let previous = exercise.status
                        exercise.status = newValue == .mastered ? .periodicReview : newValue
                        ProgressTracker.recordIfLevelUp(
                            itemName: exercise.displayName,
                            category: .exercise,
                            previousLabel: previous.rawValue,
                            previousWeight: previous.progressWeight,
                            newLabel: newValue.rawValue,
                            newWeight: newValue.progressWeight,
                            contextDetail: exercise.bookTitle,
                            in: modelContext
                        )
                        BadgeEvaluator.evaluate(context: modelContext)
                        refreshSkillStatuses()
                    }
                )) {
                    ForEach(ExerciseStatus.allCases) { status in
                        Text(status.rawValue).tag(status)
                    }
                }

                Toggle("Favorito", isOn: $exercise.isFavorite)

                Text("Descripción y notas")
                    .font(.headline)
                Text("El texto importado describe el ejercicio. Puedes añadir tus observaciones; ambas cosas afinan el resumen y la clasificación.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $notesDraft)
                    .frame(minHeight: 150)
                    .padding(8)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(24)
        }
        .onAppear { loadNotesDraft() }
        .onChange(of: exercise.id) { _, _ in loadNotesDraft() }
        .task(id: exercise.id) {
            finishedBookLookup = false
            matchingBook = nil
            await Task.yield()
            let book = LibraryLookup.matchingBook(for: exercise.bookTitle, in: modelContext)
            guard !Task.isCancelled else { return }
            matchingBook = book
            finishedBookLookup = true
        }
        .task(id: notesDraft) {
            // Espera a que la persona deje de tipear antes de tocar SwiftData.
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            commitNotesDraft()
        }
        .onDisappear { commitNotesDraft() }
        .sheet(isPresented: $showingPDF) {
            if let matchingBook {
                PDFBookViewerSheet(book: matchingBook, initialPage: exercise.page)
            }
        }
    }

    /// Vuelca el borrador pendiente al ejercicio que lo originó y carga el de la selección actual.
    private func loadNotesDraft() {
        if let owner = notesDraftOwner, owner.id != exercise.id {
            write(notesDraft, to: owner)
        }
        notesDraft = exercise.notes
        notesDraftOwner = exercise
    }

    private func commitNotesDraft() {
        guard let owner = notesDraftOwner, owner.id == exercise.id else { return }
        write(notesDraft, to: owner)
    }

    private func write(_ text: String, to target: LibraryExercise) {
        // `isDeleted` cubre el caso de borrar el ejercicio seleccionado desde el menú contextual.
        guard !target.isDeleted, target.notes != text else { return }
        target.notes = text
    }

    /// Sincroniza la evidencia agregada del catálogo para las habilidades relacionadas. El estado
    /// del ejercicio alimenta ejecución, pero ya no sustituye aplicación, transferencia o retención.
    private func refreshSkillStatuses() {
        let skills = (try? modelContext.fetch(FetchDescriptor<SkillTopic>())) ?? []
        let songs = (try? modelContext.fetch(FetchDescriptor<Song>())) ?? []
        let affected = SkillAssessmentCoachService.matchingSkills(for: exercise, topics: skills)
        // Esta operación solo ocurre al cambiar el estado. Mantener el catálogo entero en un
        // `@Query` dentro de cada ficha duplicaba su carga durante la apertura de Biblioteca.
        let allExercises = LibraryLookup.allExercises(in: modelContext)
        for topic in affected {
            SkillEvidenceService.syncCatalogEvidence(
                for: topic,
                songs: songs,
                exercises: allExercises,
                in: modelContext
            )
        }
        BadgeEvaluator.evaluate(context: modelContext)
    }
}

private struct LibraryBookRow: View {
    let book: LibraryBook

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .foregroundStyle(.red)
                .frame(width: 34, height: 34)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                Text("\(book.pageCount) páginas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

private struct LibraryBookDetailView: View {
    let book: LibraryBook

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    Image(systemName: "doc.text.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                        .frame(width: 70, height: 82)
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(book.fileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(book.title)
                            .font(.title2.bold())
                    }
                    Spacer()
                    Button("Abrir", systemImage: "arrow.up.forward.square") {
                        SecurityScopedFile.open(book.bookmarkData)
                    }
                }

                Divider()
                LabeledContent("Páginas", value: "\(book.pageCount)")
                Text("El asistente busca en el texto de este PDF para citarte páginas reales al recomendarte ejercicios o repertorio para tus habilidades débiles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}

private struct LibraryConceptRow: View {
    let concept: LibraryConcept

    private var assessment: DifficultyAssessment { DifficultyClassifier.assess(concept) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: concept.isExercise ? "pencil.and.list.clipboard" : "text.book.closed.fill")
                .foregroundStyle(.indigo)
                .frame(width: 34, height: 34)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(concept.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(concept.bookTitle) · p. \(concept.page)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            DifficultyBadge(rating: assessment.rating)
        }
        .padding(.vertical, 6)
    }
}

private struct LibraryConceptDetailView: View {
    let concept: LibraryConcept

    private var assessment: DifficultyAssessment { DifficultyClassifier.assess(concept) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    Image(systemName: concept.isExercise ? "pencil.and.list.clipboard" : "text.book.closed.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.indigo)
                        .frame(width: 70, height: 82)
                        .background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(concept.bookTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(concept.title)
                            .font(.title2.bold())
                        if !concept.category.isEmpty {
                            Text(concept.category)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()
                DifficultySummaryView(assessment: assessment)
                    .padding(12)
                    .background(assessment.rating.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                LabeledContent("Página", value: concept.page > 0 ? "\(concept.page)" : "—")
                LabeledContent("Tipo", value: concept.isExercise ? "Ejercicio teórico" : "Concepto")

                if !concept.summary.isEmpty {
                    Divider()
                    Text("Resumen")
                        .font(.headline)
                    Text(concept.summary)
                        .font(.callout)
                }
            }
            .padding(24)
        }
    }
}
