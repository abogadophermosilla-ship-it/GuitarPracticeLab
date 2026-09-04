import SwiftUI
import SwiftData

// Formulario de alta/edición de una canción, con su detalle de dificultad y las sugerencias por
// sección. Separado de RepertoireView.swift, que tenía la lista y este formulario en el mismo archivo.

private struct DifficultyDimensionsView: View {
    let dimensions: SongDifficultyDimensions

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 7) {
            ForEach(Array(dimensions.labeledValues.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 7) {
                    Text(item.0)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(DifficultyRating(stars: item.1).label)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }
}

struct NewSongView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SkillTopic.name) private var skills: [SkillTopic]
    // Igual que en la lista: el catálogo se pide al sugerir ejercicios o al sincronizar evidencia.
    @Query(sort: \Band.name) private var bands: [Band]
    @Query(sort: \Song.title) private var allSongs: [Song]
    @Query(sort: \SongDifficultyRecord.artist) private var difficultyRecords: [SongDifficultyRecord]
    @Query private var equipment: [StudioAsset]
    @Query private var instruments: [Instrument]
    @StateObject private var orchestrator = AIOrchestrator()

    /// Canción a editar. `nil` cuando el formulario se usa para agregar una canción nueva.
    var songToEdit: Song?

    @State private var title = ""
    @State private var artist = ""
    @State private var sections = ""
    @State private var status = ExerciseStatus.notStarted
    @State private var targetTempo = 0
    @State private var durationMinutes = 0
    @State private var durationRemainingSeconds = 0
    @State private var notes = ""
    @State private var didLoadInitialValues = false
    @State private var gpFileName = ""
    @State private var gpBookmarkData: Data?
    @State private var showingFileImporter = false
    @State private var sectionProgress: [SongSectionProgress] = []
    @State private var newSectionName = ""
    @State private var suggestionsBySection: [UUID: [SongExerciseSuggestion]] = [:]
    @State private var loadingSectionID: UUID?
    @State private var suggestionError = ""
    @State private var selectedSkillIDs: Set<UUID> = []
    @State private var suggestedSkills: [SkillTopic] = []
    @State private var isSuggestingSkills = false
    @State private var skillSuggestionError = ""
    @State private var isSuggestingSections = false
    @State private var sectionSuggestionError = ""
    @State private var gearSuggestion = ""
    @State private var isSuggestingGear = false
    @State private var gearSuggestionError = ""
    @State private var difficultyRole = SongGuitarRole.fullArrangement
    @State private var analyzedProfile: SongDifficultyProfile?
    @State private var isAnalyzingDifficulty = false
    @State private var difficultyAnalysisError = ""
    @State private var isAdjustingDifficulty = false
    @State private var manualDifficultyStars = 4.0

    private var isEditing: Bool { songToEdit != nil }

    private var difficultyInputKey: String {
        SongDifficultyIdentity.key(title: title, artist: artist, role: difficultyRole)
    }

    private var difficultyProfile: SongDifficultyProfile {
        if let analyzedProfile, analyzedProfile.catalogKey == difficultyInputKey {
            return analyzedProfile
        }
        if let persisted = songToEdit?.persistedDifficultyProfile,
           persisted.catalogKey == difficultyInputKey {
            return persisted
        }
        return SongDifficultyResolver.profile(
            title: title, artist: artist, sections: sections, notes: notes,
            role: difficultyRole, records: difficultyRecords, songs: allSongs,
            excludingSongID: songToEdit?.id
        )
    }

    private var difficultyAssessment: DifficultyAssessment {
        difficultyProfile.assessment
    }

    private var totalDurationSeconds: Int {
        max(0, durationMinutes * 60 + durationRemainingSeconds)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Canción") {
                    TextField("Título", text: $title)
                    TextField("Artista o banda", text: $artist)
                    Text("Si ya existe en tus bandas, la canción se vinculará a ella. Si es nueva, se agregará automáticamente a tus bandas favoritas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Picker("Parte evaluada", selection: $difficultyRole) {
                            ForEach(SongGuitarRole.allCases) { role in
                                Text(role.rawValue).tag(role)
                            }
                        }
                        DifficultySummaryView(assessment: difficultyAssessment)
                            .padding(.vertical, 4)
                        HStack(spacing: 8) {
                            StatusPill(text: difficultyProfile.source.displayName, tint: .indigo)
                            StatusPill(
                                text: difficultyProfile.confidence.displayName,
                                tint: difficultyProfile.confidence == .high ? .green :
                                    (difficultyProfile.confidence == .medium ? .orange : .gray)
                            )
                        }
                        if difficultyProfile.hasObjectiveDimensions {
                            DifficultyDimensionsView(dimensions: difficultyProfile.dimensions)
                        } else {
                            Text("Esta ficha antigua solo tiene una nota global. Analízala para obtener el desglose objetivo por dimensiones.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Button("Analizar y ampliar catálogo", systemImage: "sparkles") {
                                Task { await analyzeDifficulty() }
                            }
                            .disabled(
                                isAnalyzingDifficulty ||
                                artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            )
                            if isAnalyzingDifficulty { ProgressView().controlSize(.small) }
                            Spacer()
                            Button(isAdjustingDifficulty ? "Cerrar ajuste" : "Ajustar") {
                                manualDifficultyStars = difficultyProfile.rating.stars
                                isAdjustingDifficulty.toggle()
                            }
                            .font(.caption)
                        }
                        if artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           difficultyProfile.confidence == .low {
                            Text("Agrega el artista para evitar homónimos y habilitar el análisis objetivo.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !orchestrator.currentStatus.isEmpty, isAnalyzingDifficulty {
                            Text(orchestrator.currentStatus)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if !difficultyAnalysisError.isEmpty {
                            Text(difficultyAnalysisError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if isAdjustingDifficulty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Nota confirmada: \(DifficultyRating(stars: manualDifficultyStars).label)")
                                    .font(.caption.weight(.semibold))
                                Slider(value: $manualDifficultyStars, in: 0.5...10, step: 0.5)
                                Button("Confirmar corrección manual") {
                                    analyzedProfile = difficultyProfile.manuallyAdjusted(to: manualDifficultyStars)
                                    isAdjustingDifficulty = false
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
                Section("Estructura") {
                    TextField("Secciones (intro, verso, coro, solo...)", text: $sections, axis: .vertical)
                        .lineLimit(2...4)
                    HStack {
                        Button("Sugerir estructura", systemImage: "sparkles") {
                            Task { await suggestSections() }
                        }
                        .font(.caption)
                        .disabled(isSuggestingSections || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if isSuggestingSections { ProgressView().controlSize(.small) }
                    }
                    if !sectionSuggestionError.isEmpty {
                        Text(sectionSuggestionError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    BPMField(label: "Tempo objetivo:", value: $targetTempo)
                    HStack {
                        Stepper("Duración: \(durationMinutes) min", value: $durationMinutes, in: 0...120)
                        Stepper("\(durationRemainingSeconds) s", value: $durationRemainingSeconds, in: 0...59)
                            .frame(maxWidth: 130)
                    }
                    Text(totalDurationSeconds > 0
                         ? "Cada pasada completa contará como \(PracticeDurationFormatter.clockText(seconds: totalDurationSeconds))."
                         : "Registra la duración de la versión que practicas para calcular tiempo por pasadas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Estado", selection: $status) {
                        ForEach(ExerciseStatus.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                Section("Equipo y tono") {
                    HStack {
                        Button("Sugerir equipo/tono", systemImage: "sparkles") {
                            Task { await suggestGear() }
                        }
                        .font(.caption)
                        .disabled(isSuggestingGear || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if isSuggestingGear { ProgressView().controlSize(.small) }
                    }
                    if !gearSuggestion.isEmpty {
                        Text(gearSuggestion)
                            .font(.callout)
                    }
                    if !gearSuggestionError.isEmpty {
                        Text(gearSuggestionError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Section("Habilidades que refuerza") {
                    Text("Al tocarla ya (estado \"Dominado\") o al practicarla, ayuda a determinar tu nivel real en las habilidades vinculadas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(skills.filter { selectedSkillIDs.contains($0.id) }) { skill in
                        HStack {
                            Text(skill.name).font(.caption)
                            Spacer()
                            Button("Quitar", role: .destructive) { selectedSkillIDs.remove(skill.id) }
                                .font(.caption)
                                .buttonStyle(.plain)
                                .foregroundStyle(.red)
                        }
                    }
                    HStack {
                        Button("Sugerir habilidades", systemImage: "sparkles") {
                            Task { await suggestSkills() }
                        }
                        .font(.caption)
                        .disabled(isSuggestingSkills || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if isSuggestingSkills { ProgressView().controlSize(.small) }
                    }
                    if !suggestedSkills.isEmpty {
                        Text("Sugeridas — toca para agregar o quitar:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ForEach(suggestedSkills.filter { !selectedSkillIDs.contains($0.id) }) { skill in
                            Button {
                                selectedSkillIDs.insert(skill.id)
                            } label: {
                                Label(skill.name, systemImage: "plus.circle")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !skillSuggestionError.isEmpty {
                        Text(skillSuggestionError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Section("Progreso por secciones") {
                    ForEach(sectionProgress.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(sectionProgress[index].name)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Toggle("Aprendida", isOn: $sectionProgress[index].isLearned)
                                Button(role: .destructive) {
                                    let removedID = sectionProgress[index].id
                                    sectionProgress.remove(at: index)
                                    suggestionsBySection[removedID] = nil
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                            TextField("Debilidad (ej. \"falta el solo\")", text: $sectionProgress[index].weaknessNotes, axis: .vertical)
                                .font(.caption)
                                .lineLimit(1...3)

                            if !sectionProgress[index].weaknessNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                let sectionID = sectionProgress[index].id
                                HStack {
                                    Button("Sugerir ejercicios", systemImage: "sparkles") {
                                        Task { await suggestExercises(for: index) }
                                    }
                                    .font(.caption)
                                    .disabled(loadingSectionID == sectionID)
                                    if loadingSectionID == sectionID { ProgressView().controlSize(.small) }
                                }
                                if let results = suggestionsBySection[sectionID] {
                                    ForEach(Array(results.enumerated()), id: \.offset) { _, suggestion in
                                        SongSuggestionRow(suggestion: suggestion) { addTask(from: suggestion) }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    HStack {
                        TextField("Nueva sección (Intro, Solo...)", text: $newSectionName)
                        Button("Agregar") {
                            let trimmed = newSectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            sectionProgress.append(SongSectionProgress(name: trimmed))
                            newSectionName = ""
                        }
                    }
                    if !suggestionError.isEmpty {
                        Text(suggestionError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Section("Guitar Pro") {
                    if gpFileName.isEmpty {
                        Button("Adjuntar archivo Guitar Pro", systemImage: "doc.badge.plus") {
                            showingFileImporter = true
                        }
                    } else {
                        HStack {
                            Label(gpFileName, systemImage: "guitars")
                            Spacer()
                            Button("Quitar", role: .destructive) {
                                gpFileName = ""
                                gpBookmarkData = nil
                            }
                        }
                    }
                }
                Section("Notas") {
                    TextField("Notas", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Editar canción" : "Agregar canción")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                loadInitialValuesIfNeeded()
            }
            .task(id: difficultyInputKey) {
                // Espera a que título y artista queden quietos. Primero resuelve catálogo local/estático;
                // solo una canción realmente nueva consume IA. La ficha resultante se reutiliza después.
                let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedTitle.count >= 3, trimmedArtist.count >= 2 else { return }
                try? await Task.sleep(nanoseconds: 1_100_000_000)
                guard !Task.isCancelled else { return }
                let resolved = difficultyProfile
                if resolved.confidence == .high || resolved.source == .evolvingCatalog {
                    analyzedProfile = resolved
                    applySuggestedSectionsIfEmpty(resolved.suggestedSections)
                    return
                }
                await analyzeDifficulty()
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.item]) { result in
                if case .success(let url) = result, let bookmark = try? SecurityScopedFile.makeBookmark(for: url) {
                    gpFileName = url.lastPathComponent
                    gpBookmarkData = bookmark
                }
            }
        }
    }

    private func loadInitialValuesIfNeeded() {
        guard !didLoadInitialValues else { return }
        didLoadInitialValues = true
        guard let songToEdit else { return }

        title = songToEdit.title
        artist = songToEdit.artist
        sections = songToEdit.sections
        status = songToEdit.status
        targetTempo = songToEdit.targetTempo
        durationMinutes = songToEdit.durationSeconds / 60
        durationRemainingSeconds = songToEdit.durationSeconds % 60
        notes = songToEdit.notes
        gpFileName = songToEdit.gpFileName
        gpBookmarkData = songToEdit.gpBookmarkData
        sectionProgress = songToEdit.sectionProgress
        selectedSkillIDs = Set(songToEdit.linkedSkillIDs)
        difficultyRole = songToEdit.guitarRole
        analyzedProfile = songToEdit.persistedDifficultyProfile
    }

    @MainActor
    private func analyzeDifficulty() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedArtist.isEmpty, !isAnalyzingDifficulty else { return }

        difficultyAnalysisError = ""
        isAnalyzingDifficulty = true
        defer { isAnalyzingDifficulty = false }
        do {
            let profile = try await SongDifficultyAIService.analyzeSongBestAvailable(
                title: trimmedTitle,
                artist: trimmedArtist,
                role: difficultyRole,
                sections: sections,
                notes: notes,
                orchestrator: orchestrator
            )
            guard !Task.isCancelled else { return }
            analyzedProfile = profile
            manualDifficultyStars = profile.rating.stars
            applySuggestedSectionsIfEmpty(profile.suggestedSections)
        } catch is CancellationError {
            return
        } catch {
            difficultyAnalysisError = error.localizedDescription
        }
    }

    private func applySuggestedSectionsIfEmpty(_ names: [String]) {
        guard !names.isEmpty else { return }
        if sections.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections = names.joined(separator: ", ")
        }
        let existingNames = Set(sectionProgress.map { $0.name.lowercased() })
        sectionProgress.append(contentsOf: names
            .filter { !existingNames.contains($0.lowercased()) }
            .map { SongSectionProgress(name: $0) }
        )
    }

    @MainActor
    private func suggestSkills() async {
        skillSuggestionError = ""
        isSuggestingSkills = true
        defer { isSuggestingSkills = false }
        do {
            // .medium (antes .light): elegir qué habilidades refuerza una canción exige saber su
            // género/estilo real (blues lento vs. metal, etc.), no solo redactar texto corto — el
            // modelo más chico devolvía habilidades técnicamente reales del catálogo pero genéricas
            // e incoherentes con el estilo real de la canción (ej. gallops/tremolo para un blues lento).
            let backend = try await orchestrator.backend(for: .medium)
            suggestedSkills = try await SongCoachService.suggestSkills(
                songTitle: title,
                artist: artist,
                sections: sections,
                skills: skills,
                backend: backend
            )
        } catch {
            skillSuggestionError = error.localizedDescription
        }
    }

    /// Pide a Gemini la estructura de secciones (con respaldo local) y la aplica tanto al
    /// campo de texto libre `sections` como a `sectionProgress`, sin duplicar secciones que el usuario
    /// ya haya agregado a mano. Se llama tanto automáticamente (ver `.task(id: title)`) como desde el
    /// botón "Sugerir estructura" para reintentar o para canciones que se están editando.
    @MainActor
    private func suggestSections() async {
        sectionSuggestionError = ""
        isSuggestingSections = true
        defer { isSuggestingSections = false }
        do {
            let backend = try await orchestrator.backend(for: .light)
            let names = try await SongCoachService.suggestSections(
                songTitle: title,
                artist: artist,
                backend: backend
            )
            if sections.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sections = names.joined(separator: ", ")
            }
            let existingNames = Set(sectionProgress.map { $0.name.lowercased() })
            let newSections = names
                .filter { !existingNames.contains($0.lowercased()) }
                .map { SongSectionProgress(name: $0) }
            sectionProgress.append(contentsOf: newSections)
        } catch {
            sectionSuggestionError = error.localizedDescription
        }
    }

    @MainActor
    private func suggestGear() async {
        gearSuggestionError = ""
        isSuggestingGear = true
        defer { isSuggestingGear = false }
        do {
            let backend = try await orchestrator.backend(for: .light)
            gearSuggestion = try await GearCoachService.suggestSetup(
                songTitle: title,
                artist: artist,
                equipment: equipment,
                instruments: instruments,
                backend: backend
            )
        } catch {
            gearSuggestionError = error.localizedDescription
        }
    }

    /// Captura `id`/texto de la sección ANTES del `await` — el usuario puede borrar o reordenar
    /// secciones mientras la llamada está en vuelo, lo que correría el `index` original a otra
    /// sección; escribir el resultado por `id` en vez de por índice evita mezclar sugerencias entre
    /// secciones cuando eso pasa.
    @MainActor
    private func suggestExercises(for index: Int) async {
        guard sectionProgress.indices.contains(index) else { return }
        let sectionID = sectionProgress[index].id
        let weakness = sectionProgress[index].weaknessNotes
        let sectionName = sectionProgress[index].name

        suggestionError = ""
        loadingSectionID = sectionID
        defer { loadingSectionID = nil }

        let exercises = LibraryLookup.allExercises(in: modelContext)

        do {
            let backend = try await orchestrator.backend(for: .light)
            let results = try await SongCoachService.suggestExercises(
                forWeakness: weakness,
                songTitle: title.isEmpty ? "esta canción" : title,
                sectionName: sectionName,
                skills: skills,
                exercises: exercises,
                backend: backend
            )
            suggestionsBySection[sectionID] = results
        } catch {
            suggestionError = error.localizedDescription
        }
    }

    private func addTask(from suggestion: SongExerciseSuggestion) {
        let resolution = PracticeTaskDeduplication.resolve(
            candidateTitle: suggestion.title, candidateExerciseTitle: title,
            candidateSourceKind: songToEdit != nil ? .repertoire : .manual,
            candidateSourceID: songToEdit?.id, in: modelContext
        )
        guard PracticeTaskDeduplication.apply(resolution, in: modelContext) else { return }
        modelContext.insert(PracticeTask(
            title: suggestion.title,
            category: .technique,
            plannedMinutes: 10,
            sourceTitle: suggestion.source,
            exerciseTitle: title,
            priority: 1,
            instructions: suggestion.reason,
            sourceKind: songToEdit != nil ? .repertoire : .manual,
            sourceID: songToEdit?.id
        ))
    }

    private func save() {
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let band = BandLibrary.findOrCreateFavorite(
            named: trimmedArtist,
            among: bands,
            in: modelContext
        )
        let previousLinkedSkillIDs = songToEdit?.linkedSkillIDs ?? []
        let profileToSave = difficultyProfile
        let savedSong: Song
        if let songToEdit {
            let previousStatus = songToEdit.status
            songToEdit.title = title
            songToEdit.artist = trimmedArtist
            songToEdit.sections = sections
            songToEdit.status = status == .mastered ? .periodicReview : status
            songToEdit.targetTempo = targetTempo
            songToEdit.durationSeconds = totalDurationSeconds
            songToEdit.notes = notes
            songToEdit.gpFileName = gpFileName
            songToEdit.gpBookmarkData = gpBookmarkData
            songToEdit.sectionProgress = sectionProgress
            songToEdit.band = band
            songToEdit.linkedSkillIDs = Array(selectedSkillIDs)
            songToEdit.applyDifficultyProfile(profileToSave)
            ProgressTracker.recordIfLevelUp(
                itemName: songToEdit.title,
                category: .repertoire,
                previousLabel: previousStatus.rawValue,
                previousWeight: previousStatus.progressWeight,
                newLabel: status.rawValue,
                newWeight: status.progressWeight,
                in: modelContext
            )
            BadgeEvaluator.evaluate(context: modelContext)
            savedSong = songToEdit
        } else {
            let newSong = Song(
                title: title,
                artist: trimmedArtist,
                sections: sections,
                status: status == .mastered ? .periodicReview : status,
                targetTempo: targetTempo,
                durationSeconds: totalDurationSeconds,
                notes: notes,
                gpFileName: gpFileName,
                gpBookmarkData: gpBookmarkData,
                sectionProgress: sectionProgress,
                band: band,
                linkedSkillIDs: Array(selectedSkillIDs)
            )
            newSong.applyDifficultyProfile(profileToSave)
            modelContext.insert(newSong)
            savedSong = newSong
        }

        SongDifficultyStore.upsert(profileToSave, records: difficultyRecords, in: modelContext)

        let affectedSkillIDs = Set(previousLinkedSkillIDs).union(selectedSkillIDs)
        if !affectedSkillIDs.isEmpty {
            let songsForEvidence = allSongs.filter { $0.id != savedSong.id } + [savedSong]
            refreshSkillStatuses(affectedSkillIDs: affectedSkillIDs, songs: songsForEvidence)
        }
        dismiss()
    }

    /// Sincroniza la evidencia de aplicación musical de las canciones vinculadas. Se llama también
    /// al quitar un vínculo para retirar una señal que ya no corresponde.
    private func refreshSkillStatuses(affectedSkillIDs: Set<UUID>, songs: [Song]) {
        if !affectedSkillIDs.isEmpty {
            let exercises = LibraryLookup.allExercises(in: modelContext)
            for skillID in affectedSkillIDs {
                guard let topic = skills.first(where: { $0.id == skillID }) else { continue }
                SkillEvidenceService.syncCatalogEvidence(
                    for: topic,
                    songs: songs,
                    exercises: exercises,
                    in: modelContext
                )
            }
        }
        BadgeEvaluator.evaluate(context: modelContext)
    }
}

private struct SongSuggestionRow: View {
    let suggestion: SongExerciseSuggestion
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(.caption.weight(.medium))
                if !suggestion.source.isEmpty {
                    Text(suggestion.source)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !suggestion.reason.isEmpty {
                    Text(suggestion.reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button("Agregar tarea", systemImage: "plus") { onAdd() }
                .font(.caption)
                .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}
