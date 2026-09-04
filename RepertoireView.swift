import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RepertoireView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigator.self) private var navigator
    @Query(sort: \Song.title) private var songs: [Song]
    @Query(sort: \PracticeSession.date, order: .reverse) private var sessions: [PracticeSession]
    @Query(sort: \PracticeTask.createdAt, order: .reverse) private var tasks: [PracticeTask]
    @Query(sort: \SkillTopic.name) private var skills: [SkillTopic]
    // Los ejercicios se piden al sugerir repertorio, no al abrir la pantalla.
    @Query private var books: [LibraryBook]
    @Query(sort: \RepertoireSuggestionRecord.createdAt, order: .reverse) private var suggestions: [RepertoireSuggestionRecord]
    @Query(sort: \Band.name) private var bands: [Band]
    @Query(sort: \SongDifficultyRecord.artist) private var difficultyRecords: [SongDifficultyRecord]
    @AppStorage("musicalTastes") private var musicalTastes = ""
    @AppStorage("assessmentContext") private var assessmentContext = ""
    @StateObject private var orchestrator = AIOrchestrator()
    @State private var showingNewSong = false
    @State private var showingNewBand = false
    @State private var bandToEdit: Band?
    @State private var songToEdit: Song?
    @State private var isRefreshingSuggestions = false
    @State private var suggestionError = ""
    @State private var isRefreshingDurations = false
    @State private var durationRefreshMessage = ""
    @State private var durationRefreshError = ""

    private var favoriteBands: [Band] { bands.filter(\.isFavorite) }
    /// Asume una sola banda propia marcada como proyecto tributo (el caso real de uso hoy); si
    /// hubiera más de una, solo la primera por nombre gana el setlist fijo — no es un error, solo
    /// una simplificación deliberada.
    private var tributeBand: Band? { bands.first(where: \.isTributeProject) }
    private var tributeSetlist: [Song] {
        guard let tributeBand else { return [] }
        return songs.filter { $0.band?.id == tributeBand.id }
    }

    private var repertoireSessions: [PracticeSession] { sessions.filter { $0.category == .repertoire } }

    /// Cambia solo cuando se agrega o se renombra una canción. La duración queda fuera para que
    /// aplicar la respuesta de Gemini no dispare inmediatamente una segunda sincronización.
    private var durationRefreshKey: String {
        songs
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { "\($0.id.uuidString)|\($0.title)|\($0.artist)" }
            .joined(separator: "\n")
    }

    /// Con Test Integral, primero aparece el material que mejor calza hoy; dentro de la misma zona,
    /// de menor a mayor dificultad. Sin evaluación, la escala sigue siendo útil por sí sola.
    private var rankedSongs: [Song] {
        let level = StudentLevelService.currentRating
        let fitOrder: [DifficultyFit: Int] = [.onLevel: 0, .review: 1, .stretch: 2, .tooHard: 3, .mastered: 4]
        return songs.sorted { lhs, rhs in
            let left = SongDifficultyResolver.profile(for: lhs, records: difficultyRecords).rating
            let right = SongDifficultyResolver.profile(for: rhs, records: difficultyRecords).rating
            if let level {
                let leftOrder = fitOrder[left.fit(forStudentLevel: level), default: 5]
                let rightOrder = fitOrder[right.fit(forStudentLevel: level), default: 5]
                if leftOrder != rightOrder { return leftOrder < rightOrder }
            }
            if left != right { return left < right }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        repertoireTitle
                        Spacer()
                        repertoireActions
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        repertoireTitle
                        repertoireActions
                    }
                }

                if !durationRefreshMessage.isEmpty {
                    Label(durationRefreshMessage, systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !durationRefreshError.isEmpty {
                    Label(durationRefreshError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let tributeBand {
                    CardContainer {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(
                                title: "Tu banda: \(tributeBand.name)",
                                subtitle: tributeSetlist.isEmpty ? nil : "\(tributeSetlist.count) canciones en el setlist"
                            )
                            if tributeSetlist.isEmpty {
                                Text("Agrega una canción y asígnale \"\(tributeBand.name)\" como banda para armar el setlist.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                                    ForEach(tributeSetlist) { song in
                                        SongCard(song: song, skills: skills, difficultyRecords: difficultyRecords)
                                            .contentShape(Rectangle())
                                            .onTapGesture { songToEdit = song }
                                    }
                                }
                            }
                        }
                    }
                }

                CardContainer {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            SectionHeader(title: "Sugerido por el asistente", subtitle: "según tus habilidades más débiles")
                            Spacer()
                            if isRefreshingSuggestions {
                                ProgressView().controlSize(.small)
                            } else {
                                Button("Actualizar", systemImage: "arrow.clockwise") {
                                    Task { await refreshSuggestions() }
                                }
                            }
                        }

                        if !suggestionError.isEmpty {
                            Text(suggestionError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if !orchestrator.currentStatus.isEmpty {
                            Text(orchestrator.currentStatus)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        if suggestions.isEmpty {
                            Text("Sin sugerencias todavía. Completa la autoevaluación de Habilidades, o presiona Actualizar.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(suggestions) { suggestion in
                            RepertoireSuggestionRow(
                                    suggestion: suggestion,
                                    difficultyRecords: difficultyRecords,
                                    onAdd: { addSuggestion(suggestion) },
                                    onDismiss: { modelContext.delete(suggestion) }
                                )
                                if suggestion.id != suggestions.last?.id { Divider() }
                            }
                        }
                    }
                }

                CardContainer {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionHeader(title: "Bandas favoritas")
                            Spacer()
                            Button("Agregar banda", systemImage: "plus") { showingNewBand = true }
                        }
                        if favoriteBands.isEmpty {
                            Text("Sin bandas favoritas todavía. Se agregan solas al aceptar una sugerencia, o cargalas a mano.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(favoriteBands) { band in
                                HStack {
                                    Text(band.name)
                                        .font(.subheadline.weight(.medium))
                                    if band.isTributeProject {
                                        StatusPill(text: "Tu banda", tint: .purple)
                                            .fixedSize()
                                    }
                                    if !band.likedSongTitles.isEmpty {
                                        Text("· \(band.likedSongTitles.joined(separator: ", "))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { bandToEdit = band }
                                if band.id != favoriteBands.last?.id { Divider() }
                            }
                        }
                    }
                }

                if songs.isEmpty {
                    EmptyStateView(icon: "music.note.list", title: "Sin canciones", message: "Agrega la primera canción de tu repertorio.")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
                        ForEach(rankedSongs) { song in
                            SongCard(song: song, skills: skills, difficultyRecords: difficultyRecords)
                                .contentShape(Rectangle())
                                .onTapGesture { songToEdit = song }
                                .contextMenu {
                                    Button("Editar", systemImage: "pencil") { songToEdit = song }
                                    Button("Eliminar", systemImage: "trash", role: .destructive) {
                                        modelContext.delete(song)
                                    }
                                }
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 4)

                Text("Sesiones registradas")
                    .font(.title2.bold())

                if repertoireSessions.isEmpty {
                    EmptyStateView(icon: "clock", title: "Sin sesiones de repertorio", message: "Registra una sesión con la categoría Repertorio.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(repertoireSessions) { session in
                            VStack(alignment: .leading) {
                                Text(session.exerciseTitle.isEmpty ? "Práctica de repertorio" : session.exerciseTitle).font(.headline)
                                Text([
                                    session.date.formatted(date: .abbreviated, time: .omitted),
                                    session.formattedDuration,
                                    session.repertoireRepetitions > 0
                                        ? "\(session.repertoireRepetitions) pasada\(session.repertoireRepetitions == 1 ? "" : "s")"
                                        : nil,
                                    session.rhythmicFigure.isSpecified ? session.rhythmicFigure.displayName : nil
                                ].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            if session.id != repertoireSessions.last?.id { Divider() }
                        }
                    }
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showingNewSong) {
            NewSongView()
                .frame(minWidth: 520, idealWidth: 600, minHeight: 520)
        }
        .sheet(item: $songToEdit) { song in
            NewSongView(songToEdit: song)
                .frame(minWidth: 520, idealWidth: 600, minHeight: 520)
        }
        .sheet(isPresented: $showingNewBand) {
            NewBandView()
                .frame(minWidth: 360, idealWidth: 420, minHeight: 300)
        }
        .sheet(item: $bandToEdit) { band in
            NewBandView(bandToEdit: band)
                .frame(minWidth: 360, idealWidth: 420, minHeight: 300)
        }
        .onAppear { applyPendingFocus() }
        .onChange(of: navigator.focusSongID) { _, _ in applyPendingFocus() }
        .task(id: durationRefreshKey) {
            await refreshSongDurations(force: false)
        }
    }

    private var repertoireTitle: some View {
        VStack(alignment: .leading) {
            Text("Repertorio")
                .font(.largeTitle.bold())
            Text("Canciones clasificadas sobre 10★ y priorizadas para tu nivel")
                .foregroundStyle(.secondary)
        }
    }

    private var repertoireActions: some View {
        HStack {
            if isRefreshingDurations {
                ProgressView()
                    .controlSize(.small)
                    .help("Actualizando duraciones con Gemini")
            }
            Button("Actualizar duraciones", systemImage: "clock.arrow.circlepath") {
                Task { await refreshSongDurations(force: true) }
            }
            .disabled(isRefreshingDurations || songs.isEmpty)
            Button("Agregar canción", systemImage: "plus") { showingNewSong = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private func applyPendingFocus() {
        guard let focusID = navigator.focusSongID else { return }
        songToEdit = songs.first { $0.id == focusID }
        navigator.focusSongID = nil
    }

    /// Completa y refresca el repertorio en lotes con el backend pagado de Gemini. Las respuestas
    /// dudosas no pisan un valor existente; una sincronización automática se repite al renombrar la
    /// canción y, como mantenimiento, cada 30 días.
    @MainActor
    private func refreshSongDurations(force: Bool) async {
        guard !isRefreshingDurations else { return }
        let allQueries = songs
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { SongDurationQuery(id: $0.id, title: $0.title, artist: $0.artist) }
        let pending = SongDurationRefreshStore.pending(from: allQueries, force: force)
        guard !pending.isEmpty else { return }

        isRefreshingDurations = true
        durationRefreshError = ""
        if force { durationRefreshMessage = "" }
        defer { isRefreshingDurations = false }

        do {
            // El usuario pidió expresamente Gemini para este dato: no sustituir silenciosamente la
            // fuente por Ollama si la clave, el presupuesto o la red no están disponibles.
            let backend = try orchestrator.paidCloudBackend()
            var results: [SongDurationResult] = []
            for start in stride(from: 0, to: pending.count, by: 25) {
                try Task.checkCancellation()
                let end = min(start + 25, pending.count)
                results += try await SongDurationAIService.lookup(
                    songs: Array(pending[start..<end]),
                    backend: backend
                )
            }

            var changed = 0
            for result in results {
                guard let song = songs.first(where: { $0.id == result.songID }) else { continue }
                if song.durationSeconds != result.durationSeconds {
                    song.durationSeconds = result.durationSeconds
                    changed += 1
                }
                updateDailyRepertoireTask(for: song)
            }
            try modelContext.save()
            SongDurationRefreshStore.markChecked(pending)

            if results.isEmpty {
                durationRefreshMessage = "Gemini no reconoció con certeza las canciones pendientes; se conservaron sus duraciones."
            } else if changed == 0 {
                durationRefreshMessage = "Gemini comprobó \(results.count) duración\(results.count == 1 ? "" : "es"); ya estaban al día."
            } else {
                durationRefreshMessage = "Gemini actualizó \(changed) duración\(changed == 1 ? "" : "es") del repertorio."
            }
        } catch is CancellationError {
            return
        } catch {
            durationRefreshError = error.localizedDescription
        }
    }

    /// Si la canción ya estaba en el plan diario, su presupuesto y el texto de la pasada completa
    /// deben reflejar la nueva duración inmediatamente, no recién al crear la tarea de mañana.
    private func updateDailyRepertoireTask(for song: Song) {
        let duration = song.formattedDuration.map { " (\($0))" } ?? ""
        for task in tasks where
            !task.isCompleted
            && task.sourceKind == .repertoire
            && task.sourceID == song.id
            && task.title.hasPrefix("Repertorio diario ·") {
            task.title = "Repertorio diario · \(song.title)"
            task.plannedMinutes = DailyRepertoirePlanner.plannedMinutes(for: song)
            task.sourceTitle = song.artist
            task.exerciseTitle = song.title
            task.targetBPM = song.targetTempo
            task.instructions = "Haz al menos una pasada completa\(duration) y registra cuántas pasadas hiciste. Si aparece un fallo, aísla la sección antes de volver a tocarla entera."
        }
    }

    private func addSuggestion(_ suggestion: RepertoireSuggestionRecord) {
        let band = findOrCreateFavoriteBand(named: suggestion.artist)
        let song = Song(
            title: suggestion.title,
            artist: suggestion.artist,
            status: .notStarted,
            notes: "Sugerida por el asistente para reforzar: \(suggestion.targetSkill). \(suggestion.reason)",
            band: band
        )
        let profile = SongDifficultyResolver.profile(
            title: song.title, artist: song.artist, notes: song.notes,
            records: difficultyRecords, songs: songs
        )
        song.applyDifficultyProfile(profile)
        SongDifficultyStore.upsert(profile, records: difficultyRecords, in: modelContext)
        modelContext.insert(song)
        modelContext.delete(suggestion)
    }

    /// Al aceptar una sugerencia, la banda del artista queda marcada como favorita — "todo lo que
    /// escucho, me gusta, toco, me hace mejor guitarrista". Si ya existía (agregada a mano o de una
    /// sugerencia anterior), solo la marca favorita en vez de duplicarla.
    private func findOrCreateFavoriteBand(named artist: String) -> Band? {
        let trimmed = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = bands.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            existing.isFavorite = true
            return existing
        }
        let band = Band(name: trimmed, isFavorite: true)
        modelContext.insert(band)
        return band
    }

    @MainActor
    private func refreshSuggestions() async {
        suggestionError = ""
        isRefreshingSuggestions = true
        defer { isRefreshingSuggestions = false }

        let exercises = LibraryLookup.allExercises(in: modelContext)

        do {
            // Gemini pagado es la fuente principal de conocimiento musical; el modelo local queda
            // como respaldo automático si la llamada de nube falla.
            let backend = try await orchestrator.backend(for: .medium)
            let fresh = try await SkillAssessmentCoachService.suggestRepertoire(
                topics: skills,
                exercises: exercises,
                songs: songs,
                favoriteBands: favoriteBands,
                musicalTastes: musicalTastes,
                context: assessmentContext,
                pdfReferences: pdfReferences(),
                backend: backend
            )
            RepertoireSuggestionStore.replace(fresh, in: modelContext)
        } catch {
            suggestionError = error.localizedDescription
        }
    }

    /// Busca en el texto real de los PDFs importados páginas relacionadas con las habilidades
    /// más débiles, para que el asistente pueda citar páginas concretas en vez de inventarlas.
    private func pdfReferences() -> [String] {
        guard !books.isEmpty else { return [] }
        let weakest = skills.filter { $0.status != .consolidated }.prefix(10)

        var lines: [String] = []
        for skill in weakest {
            for book in books {
                for match in book.matchingPages(for: [skill.name]) {
                    lines.append("- \(book.title), página \(match.page): \"\(match.snippet)\" (relacionado con \(skill.name))")
                }
            }
        }
        return lines
    }
}

private struct RepertoireSuggestionRow: View {
    let suggestion: RepertoireSuggestionRecord
    var difficultyRecords: [SongDifficultyRecord] = []
    let onAdd: () -> Void
    let onDismiss: () -> Void

    private var assessment: DifficultyAssessment {
        SongDifficultyResolver.profile(
            title: suggestion.title, artist: suggestion.artist, records: difficultyRecords
        ).assessment
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.title)
                    .font(.subheadline.weight(.medium))
                if !suggestion.artist.isEmpty {
                    Text(suggestion.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !suggestion.targetSkill.isEmpty {
                    Text("Refuerza: \(suggestion.targetSkill)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !suggestion.reason.isEmpty {
                    Text(suggestion.reason)
                        .font(.caption)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                DifficultyBadge(rating: assessment.rating)
                if let level = StudentLevelService.currentRating {
                    DifficultyFitBadge(fit: assessment.rating.fit(forStudentLevel: level))
                }
            }
            Button("Descartar", role: .destructive) { onDismiss() }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            Button("Agregar", systemImage: "plus") { onAdd() }
        }
        .padding(.vertical, 4)
    }
}

private struct SongCard: View {
    let song: Song
    var skills: [SkillTopic] = []
    var difficultyRecords: [SongDifficultyRecord] = []

    private var linkedSkillNames: [String] {
        guard !song.linkedSkillIDs.isEmpty else { return [] }
        return skills.filter { song.linkedSkillIDs.contains($0.id) }.map(\.name)
    }

    private var assessment: DifficultyAssessment {
        SongDifficultyResolver.profile(for: song, records: difficultyRecords).assessment
    }

    private var statusColor: Color {
        switch song.status {
        case .mastered: .green
        case .consolidating, .reducedTempo: .blue
        case .periodicReview: .purple
        default: .orange
        }
    }

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "music.note")
                        .font(.title2)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text(song.title).font(.headline)
                        if !song.artist.isEmpty {
                            Text(song.artist).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    DifficultyBadge(rating: assessment.rating)
                    StatusPill(text: song.status.rawValue, tint: statusColor)
                }
                if let level = StudentLevelService.currentRating {
                    DifficultyFitBadge(fit: assessment.rating.fit(forStudentLevel: level))
                }
                if let band = song.band {
                    StatusPill(text: band.name, tint: .purple)
                        .fixedSize()
                }
                if !song.sections.isEmpty {
                    Divider()
                    Text(song.sections)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !song.sectionProgress.isEmpty {
                    let learnedCount = song.sectionProgress.filter(\.isLearned).count
                    Text("\(learnedCount)/\(song.sectionProgress.count) secciones aprendidas")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if song.targetTempo > 0 {
                    Text("\(song.targetTempo) BPM objetivo")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let duration = song.formattedDuration {
                    Label(duration, systemImage: "clock")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if !linkedSkillNames.isEmpty {
                    Text("Refuerza: \(linkedSkillNames.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !song.gpFileName.isEmpty {
                    Divider()
                    HStack {
                        Label(song.gpFileName, systemImage: "guitars")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        if let data = song.gpBookmarkData {
                            Button("Abrir") { SecurityScopedFile.open(data) }
                                .font(.caption)
                                .buttonStyle(.plain)
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
    }
}

private struct NewBandView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SongDifficultyRecord.title) private var difficultyRecords: [SongDifficultyRecord]
    @StateObject private var orchestrator = AIOrchestrator()

    /// Banda a editar. `nil` cuando el formulario se usa para agregar una banda nueva.
    var bandToEdit: Band?

    @State private var name = ""
    @State private var isFavorite = true
    @State private var isTributeProject = false
    @State private var notes = ""
    @State private var didLoadInitialValues = false
    @State private var catalogDrafts: [SongDifficultyProfile] = []
    @State private var isExpandingCatalog = false
    @State private var catalogError = ""

    private var isEditing: Bool { bandToEdit != nil }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre de la banda", text: $name)
                Toggle("Favorita", isOn: $isFavorite)
                Toggle("Es tu banda (proyecto tributo)", isOn: $isTributeProject)
                Text("Marca esto solo para tu propia banda — sus canciones arman el setlist fijo arriba de Repertorio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Notas / canciones que te gustan de esta banda", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
                Section("Catálogo de dificultad") {
                    let existingCount = difficultyRecords.filter {
                        SongDifficultyIdentity.normalized($0.artist) == SongDifficultyIdentity.normalized(name)
                    }.count
                    Text("\(existingCount + catalogDrafts.count) canciones disponibles para reconocer futuras altas sin repetir el análisis.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Ampliar catálogo de esta banda", systemImage: "sparkles") {
                        Task { await expandCatalog() }
                    }
                    .disabled(
                        isExpandingCatalog ||
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    if isExpandingCatalog {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(orchestrator.currentStatus)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !catalogDrafts.isEmpty {
                        ForEach(catalogDrafts, id: \.catalogKey) { profile in
                            HStack {
                                Text(profile.title).font(.caption)
                                Spacer()
                                Text(profile.rating.label)
                                    .font(.caption.monospacedDigit().weight(.semibold))
                                Text(profile.confidence.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !catalogError.isEmpty {
                        Text(catalogError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Editar banda" : "Agregar banda")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { loadInitialValuesIfNeeded() }
        }
    }

    private func loadInitialValuesIfNeeded() {
        guard !didLoadInitialValues else { return }
        didLoadInitialValues = true
        guard let bandToEdit else { return }

        name = bandToEdit.name
        isFavorite = bandToEdit.isFavorite
        isTributeProject = bandToEdit.isTributeProject
        notes = bandToEdit.notes
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let bandToEdit {
            bandToEdit.name = trimmedName
            bandToEdit.isFavorite = isFavorite
            bandToEdit.isTributeProject = isTributeProject
            bandToEdit.notes = notes
        } else {
            modelContext.insert(Band(
                name: trimmedName,
                isFavorite: isFavorite,
                isTributeProject: isTributeProject,
                notes: notes
            ))
        }
        for profile in catalogDrafts {
            SongDifficultyStore.upsert(profile, records: difficultyRecords, in: modelContext)
        }
        dismiss()
    }

    @MainActor
    private func expandCatalog() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !isExpandingCatalog else { return }
        catalogError = ""
        isExpandingCatalog = true
        defer { isExpandingCatalog = false }
        do {
            let profiles = try await SongDifficultyAIService.analyzeBandBestAvailable(
                artist: trimmedName,
                orchestrator: orchestrator
            )
            guard !profiles.isEmpty else {
                catalogError = "La IA no reconoció canciones de esta banda con suficiente certeza."
                return
            }
            let existingKeys = Set(difficultyRecords.map(\.catalogKey))
            catalogDrafts = profiles.filter { !existingKeys.contains($0.catalogKey) }
        } catch {
            catalogError = error.localizedDescription
        }
    }
}
