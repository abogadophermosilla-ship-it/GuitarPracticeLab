import SwiftUI
import SwiftData

struct GlobalSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SkillTopic.name) private var skills: [SkillTopic]
    @Query(sort: \LibraryBook.title) private var books: [LibraryBook]
    @Query(sort: \Song.title) private var songs: [Song]
    @Query(sort: \RepertoireSuggestionRecord.createdAt, order: .reverse)
    private var repertoireSuggestions: [RepertoireSuggestionRecord]
    @Query(sort: \Band.name) private var bands: [Band]

    @State private var query = ""
    @State private var materialMatches: [LearningMaterialEntry] = []
    @State private var actionMessage = ""

    /// El buscador cruza el catálogo entero con tokens normalizados, así que necesita todas las
    /// filas — pero compartidas con las demás pantallas, no una copia propia por vista.
    private var exercises: [LibraryExercise] {
        LibraryLookup.Catalog.shared.exercises(in: modelContext)
    }

    private var concepts: [LibraryConcept] {
        LibraryLookup.Catalog.shared.concepts(in: modelContext)
    }

    private var tokens: [String] {
        query.normalizedGlobalSearch
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private var matchingSkills: [SkillTopic] {
        guard !tokens.isEmpty else { return [] }
        return skills.filter {
            matches([$0.name, $0.detail, $0.concept, $0.correctExecution, $0.commonErrors, $0.notes])
        }
    }

    private var matchingExercises: [LibraryExercise] {
        guard !tokens.isEmpty else { return [] }
        return exercises.filter {
            matches([$0.technique, $0.displayName, $0.bookTitle, $0.collectionName, $0.notes])
        }
    }

    private var matchingConcepts: [LibraryConcept] {
        guard !tokens.isEmpty else { return [] }
        return concepts.filter {
            matches([$0.title, $0.category, $0.summary, $0.bookTitle])
        }
    }

    private var matchingSongs: [Song] {
        guard !tokens.isEmpty else { return [] }
        return songs.filter {
            matches([
                $0.title,
                $0.artist,
                $0.sections,
                $0.notes,
                $0.band?.name ?? "",
                $0.sectionProgress.map(\.name).joined(separator: " "),
                $0.sectionProgress.map(\.weaknessNotes).joined(separator: " ")
            ])
        }
    }

    private var matchingSuggestions: [RepertoireSuggestionRecord] {
        guard !tokens.isEmpty else { return [] }
        return repertoireSuggestions.filter {
            matches([$0.title, $0.artist, $0.reason, $0.targetSkill])
        }
    }

    private var matchingBooks: [LibraryBook] {
        guard !tokens.isEmpty else { return [] }
        return books.filter { matches([$0.title, $0.author, $0.fileName]) }
    }

    private var totalMatches: Int {
        matchingSkills.count + matchingExercises.count + matchingConcepts.count +
            matchingSongs.count + matchingSuggestions.count + matchingBooks.count + materialMatches.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(20)
            Divider()

            if tokens.isEmpty {
                emptySearch
            } else if totalMatches == 0 {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "Sin coincidencias",
                    message: "Prueba con el nombre de una técnica, canción, artista, libro o material."
                )
            } else {
                results
            }
        }
        .navigationTitle("Buscar")
        .task(id: query) {
            materialMatches = []
            guard query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { return }
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            let searchQuery = query
            let found = await Task.detached {
                LearningMaterialsService.search(query: searchQuery)
            }.value
            guard !Task.isCancelled else { return }
            materialMatches = found
        }
        .onChange(of: query) { _, _ in actionMessage = "" }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Buscador global")
                .font(.largeTitle.bold())
            Text("Encuentra una técnica en toda la app y conviértela directamente en práctica.")
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Ejemplo: bending, shuffle, tríadas, Kaos Etiliko…", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Borrar búsqueda")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))

            if !actionMessage.isEmpty {
                Label(actionMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private var emptySearch: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            Text("Busca en todo tu aprendizaje")
                .font(.title2.bold())
            Text("Habilidades, \(exercises.count) ejercicios, teoría, canciones, sugerencias y archivos del disco externo.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                ForEach(["bending", "shuffle", "tríadas", "improvisación"], id: \.self) { example in
                    Button(example) { query = example }
                        .buttonStyle(.bordered)
                }
            }
            Spacer()
        }
        .padding(24)
    }

    private var results: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Text("\(totalMatches) coincidencias para “\(query)”")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                resultSection("Habilidades", icon: "lightbulb.fill", count: matchingSkills.count) {
                    ForEach(matchingSkills.prefix(20)) { skill in
                        let rating = DifficultyClassifier.assess(skillNamed: skill.name).rating
                        SearchResultRow(
                            icon: skill.domain == .theory ? "book.closed.fill" : "metronome",
                            tint: skill.domain == .theory ? .indigo : .blue,
                            title: skill.name,
                            subtitle: "\(skill.domain.rawValue) · \(rating.label) · \(skill.status.rawValue)",
                            detail: skill.detail,
                            actionTitle: "Agregar al plan"
                        ) {
                            addSkillToPlan(skill)
                        }
                    }
                }

                resultSection("Ejercicios de Biblioteca", icon: "books.vertical.fill", count: matchingExercises.count) {
                    let contexts = DifficultyClassifier.bookContexts(for: exercises)
                    ForEach(matchingExercises.prefix(30)) { exercise in
                        let rating = DifficultyClassifier.assess(
                            exercise,
                            context: DifficultyClassifier.context(forBook: exercise.bookTitle, in: contexts)
                        ).rating
                        SearchResultRow(
                            icon: "figure.strengthtraining.traditional",
                            tint: .orange,
                            title: exercise.displayName,
                            subtitle: "\(exercise.bookTitle) · p. \(exercise.page) · \(rating.label)",
                            detail: exercise.notes,
                            actionTitle: "Agregar al plan"
                        ) {
                            addExerciseToPlan(exercise)
                        }
                    }
                }

                resultSection("Repertorio", icon: "music.note.list", count: matchingSongs.count + matchingSuggestions.count) {
                    ForEach(matchingSongs.prefix(20)) { song in
                        let rating = SongDifficultyCatalog.assess(song).rating
                        SearchResultRow(
                            icon: "music.note",
                            tint: .green,
                            title: song.title,
                            subtitle: [song.artist, rating.label, song.status.rawValue].filter { !$0.isEmpty }.joined(separator: " · "),
                            detail: songSearchDetail(song),
                            actionTitle: "Practicar canción"
                        ) {
                            addSongToPlan(song)
                        }
                    }
                    ForEach(matchingSuggestions.prefix(20)) { suggestion in
                        let rating = SongDifficultyCatalog.assess(title: suggestion.title, artist: suggestion.artist).rating
                        SearchResultRow(
                            icon: "sparkles",
                            tint: .purple,
                            title: suggestion.title,
                            subtitle: "\(suggestion.artist) · \(rating.label) · sugerida para \(suggestion.targetSkill)",
                            detail: suggestion.reason,
                            actionTitle: "Agregar al repertorio"
                        ) {
                            addSuggestionToRepertoire(suggestion)
                        }
                    }
                }

                resultSection("Teoría para leer", icon: "text.book.closed.fill", count: matchingConcepts.count) {
                    ForEach(matchingConcepts.prefix(30)) { concept in
                        let rating = DifficultyClassifier.assess(concept).rating
                        SearchResultRow(
                            icon: concept.isExercise ? "pencil.and.list.clipboard" : "text.book.closed.fill",
                            tint: .indigo,
                            title: concept.title,
                            subtitle: "\(concept.bookTitle) · p. \(concept.page) · \(rating.label)",
                            detail: concept.summary,
                            actionTitle: matchingBook(for: concept) == nil ? nil : "Abrir libro"
                        ) {
                            if let book = matchingBook(for: concept) {
                                SecurityScopedFile.open(book.bookmarkData)
                            }
                        }
                    }
                }

                resultSection("Libros PDF", icon: "doc.richtext.fill", count: matchingBooks.count) {
                    ForEach(matchingBooks.prefix(20)) { book in
                        SearchResultRow(
                            icon: "doc.richtext.fill",
                            tint: .red,
                            title: book.title,
                            subtitle: "\(book.pageCount) páginas",
                            detail: book.author,
                            actionTitle: "Abrir PDF"
                        ) {
                            SecurityScopedFile.open(book.bookmarkData)
                        }
                    }
                }

                resultSection("Archivos externos", icon: "externaldrive.fill", count: materialMatches.count) {
                    ForEach(materialMatches) { material in
                        SearchResultRow(
                            icon: material.icon,
                            tint: material.isDirectory ? .blue : .gray,
                            title: material.name,
                            subtitle: relativeMaterialPath(material.url),
                            detail: material.detail,
                            actionTitle: "Abrir"
                        ) {
                            LearningMaterialsService.open(material.url)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 980, alignment: .leading)
        }
    }

    @ViewBuilder
    private func resultSection<Content: View>(
        _ title: String,
        icon: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if count > 0 {
            CardContainer {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Label(title, systemImage: icon)
                            .font(.headline)
                        Spacer()
                        Text("\(count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 8)
                    content()
                }
            }
        }
    }

    private func matches(_ fields: [String]) -> Bool {
        let haystack = fields.joined(separator: " ").normalizedGlobalSearch
        return tokens.allSatisfy(haystack.contains)
    }

    private func addSkillToPlan(_ skill: SkillTopic) {
        let resolution = PracticeTaskDeduplication.resolve(candidateTitle: skill.name, in: modelContext)
        guard PracticeTaskDeduplication.apply(resolution, in: modelContext) else {
            actionMessage = "“\(skill.name)” ya estaba en tu plan."
            return
        }
        modelContext.insert(PracticeTask(
            title: skill.name,
            category: skill.domain == .theory ? .theory : .technique,
            plannedMinutes: 15,
            sourceTitle: "Habilidades",
            exerciseTitle: skill.name,
            priority: 1,
            instructions: skill.correctExecution.isEmpty ? skill.detail : skill.correctExecution
        ))
        actionMessage = "“\(skill.name)” se agregó al plan de hoy."
    }

    private func addExerciseToPlan(_ exercise: LibraryExercise) {
        let resolution = PracticeTaskDeduplication.resolve(
            candidateTitle: exercise.displayName, candidateSourceKind: .library,
            candidateSourceID: exercise.id, in: modelContext
        )
        guard PracticeTaskDeduplication.apply(resolution, in: modelContext) else {
            actionMessage = "“\(exercise.displayName)” ya estaba en tu plan."
            return
        }
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
        actionMessage = "“\(exercise.displayName)” se agregó al plan de hoy."
    }

    private func addSongToPlan(_ song: Song) {
        let resolution = PracticeTaskDeduplication.resolve(
            candidateTitle: song.title, candidateSourceKind: .repertoire,
            candidateSourceID: song.id, in: modelContext
        )
        guard PracticeTaskDeduplication.apply(resolution, in: modelContext) else {
            actionMessage = "“\(song.title)” ya estaba en tu plan."
            return
        }
        modelContext.insert(PracticeTask(
            title: song.title,
            category: .repertoire,
            plannedMinutes: 20,
            sourceTitle: song.artist,
            exerciseTitle: song.title,
            targetBPM: song.targetTempo,
            priority: 1,
            instructions: "\(RepertoireTaskMode.bySections.defaultInstructions)\n\n\(songSearchDetail(song))",
            repertoireTaskMode: .bySections,
            sourceKind: .repertoire,
            sourceID: song.id
        ))
        actionMessage = "“\(song.title)” se agregó al plan de hoy."
    }

    private func addSuggestionToRepertoire(_ suggestion: RepertoireSuggestionRecord) {
        let duplicate = songs.contains {
            $0.title.caseInsensitiveCompare(suggestion.title) == .orderedSame &&
                $0.artist.caseInsensitiveCompare(suggestion.artist) == .orderedSame
        }
        guard !duplicate else {
            actionMessage = "“\(suggestion.title)” ya está en tu repertorio."
            return
        }

        let band = findOrCreateFavoriteBand(named: suggestion.artist, songTitle: suggestion.title)
        modelContext.insert(Song(
            title: suggestion.title,
            artist: suggestion.artist,
            notes: "Sugerida para reforzar \(suggestion.targetSkill). \(suggestion.reason)",
            band: band
        ))
        modelContext.delete(suggestion)
        actionMessage = "“\(suggestion.title)” se agregó al repertorio."
    }

    private func findOrCreateFavoriteBand(named name: String, songTitle: String) -> Band? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = bands.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            existing.isFavorite = true
            if !existing.likedSongTitles.contains(where: { $0.caseInsensitiveCompare(songTitle) == .orderedSame }) {
                existing.likedSongTitles.append(songTitle)
            }
            return existing
        }
        let band = Band(name: trimmed, isFavorite: true, likedSongTitles: [songTitle])
        modelContext.insert(band)
        return band
    }

    private func songSearchDetail(_ song: Song) -> String {
        let pending = song.sectionProgress.filter { !$0.isLearned }
        if !pending.isEmpty {
            return "Pendiente: " + pending.map {
                $0.weaknessNotes.isEmpty ? $0.name : "\($0.name) — \($0.weaknessNotes)"
            }.joined(separator: " · ")
        }
        return song.notes
    }

    private func matchingBook(for concept: LibraryConcept) -> LibraryBook? {
        let title = concept.bookTitle.normalizedGlobalSearch
        return books.first {
            let candidate = $0.title.normalizedGlobalSearch
            return candidate == title || candidate.contains(title) || title.contains(candidate)
        }
    }

    private func relativeMaterialPath(_ url: URL) -> String {
        let root = LearningMaterialsService.rootURL.path
        guard url.path.hasPrefix(root) else { return url.deletingLastPathComponent().path }
        return String(url.deletingLastPathComponent().path.dropFirst(root.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

private struct SearchResultRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let detail: String
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
        Divider()
    }
}

private extension String {
    var normalizedGlobalSearch: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}
