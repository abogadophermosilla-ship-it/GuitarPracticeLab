import SwiftUI
import SwiftData

struct NewSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Instrument.name) private var instruments: [Instrument]
    @Query(sort: \Song.title) private var songs: [Song]
    @Query(sort: \PracticeTask.priority) private var practiceTasks: [PracticeTask]

    /// Sesión a editar. `nil` cuando el formulario se usa para registrar una sesión nueva.
    var sessionToEdit: PracticeSession?
    /// Tarea desde la que se abrió el formulario (botón "Iniciar tarea"). Precarga sus datos y, al
    /// guardar, la deja marcada como completada.
    var initialTaskID: UUID? = nil

    @State private var date = Date.now
    @State private var duration = 30
    @State private var instrumentName = ""
    @State private var category = PracticeCategory.technique
    @State private var selectedExerciseID: UUID?
    @State private var selectedSongID: UUID?
    @State private var selectedConceptID: UUID?
    @State private var sourceTitle = ""
    @State private var exerciseTitle = ""
    @State private var startBPM = 80
    @State private var endBPM = 80
    @State private var difficulty = 3
    @State private var result = PracticeResult.learning
    @State private var correctRepetitions = 0
    @State private var repertoireRepetitions = 0
    @State private var repertoireDurationSnapshot = 0
    @State private var initialSessionSongID: UUID?
    @State private var handledInitialSongSelection = false
    @State private var tensionRating = 1
    @State private var practiceContext = PracticeApplicationContext.isolated
    @State private var wasColdCheck = false
    @State private var notes = ""
    @State private var rhythmicFigure = RhythmicFigure.unspecified
    @State private var didLoadInitialValues = false
    @State private var linkedTaskID: UUID?

    private var isEditing: Bool { sessionToEdit != nil }

    private var selectedExercise: LibraryExercise? {
        LibraryLookup.exercise(id: selectedExerciseID, in: modelContext)
    }

    private var selectedSong: Song? {
        songs.first { $0.id == selectedSongID }
    }

    private var repertoireSongDurationSeconds: Int {
        if repertoireDurationSnapshot > 0 { return repertoireDurationSnapshot }
        return selectedSong?.durationSeconds ?? 0
    }

    private var resolvedDurationSeconds: Int {
        if category == .repertoire,
           repertoireRepetitions > 0,
           repertoireSongDurationSeconds > 0 {
            return repertoireRepetitions * repertoireSongDurationSeconds
        }
        return duration * 60
    }

    private var resolvedDurationMinutes: Int {
        max(1, Int(ceil(Double(resolvedDurationSeconds) / 60.0)))
    }

    private var selectedConcept: LibraryConcept? {
        LibraryLookup.concept(id: selectedConceptID, in: modelContext)
    }

    /// La canción escrita a mano no está todavía en Repertorio y hay título para crearla.
    private var canAddTypedSong: Bool {
        let typed = exerciseTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, selectedSong == nil else { return false }
        return !songs.contains { $0.title.localizedCaseInsensitiveCompare(typed) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sesión") {
                    DatePicker("Fecha", selection: $date)
                    if category == .repertoire,
                       repertoireRepetitions > 0,
                       repertoireSongDurationSeconds > 0 {
                        LabeledContent("Tiempo calculado") {
                            Text(PracticeDurationFormatter.clockText(seconds: resolvedDurationSeconds))
                                .monospacedDigit()
                        }
                        Text("Duración de la canción × pasadas completas. El historial conserva también los segundos exactos.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Stepper("Duración: \(duration) minutos", value: $duration, in: 1...360, step: 5)
                    }
                    Picker("Instrumento", selection: $instrumentName) {
                        Text("Sin especificar").tag("")
                        ForEach(instruments) { instrument in
                            Text(instrument.name).tag(instrument.name)
                        }
                    }
                    Picker("Área", selection: $category) {
                        ForEach(PracticeCategory.allCases) { item in
                            Label(item.rawValue, systemImage: item.icon).tag(item)
                        }
                    }
                    .onChange(of: category) { _, newValue in
                        if newValue != .repertoire {
                            selectedSongID = nil
                            repertoireRepetitions = 0
                        }
                        if newValue != .theory { selectedConceptID = nil }
                        if newValue == .repertoire || newValue == .theory { selectedExerciseID = nil }
                        if !newValue.supportsRhythmicFigure { rhythmicFigure = .unspecified }
                    }
                }

                Section("Material") {
                    // En Repertorio se elige una canción propia; en Teoría, un concepto de
                    // Biblioteca; en el resto de las áreas, un ejercicio de Biblioteca. Antes solo
                    // existía el picker de ejercicios, así que una sesión de repertorio o teoría
                    // quedaba como texto suelto, sin vínculo a su origen.
                    if category == .repertoire {
                        Picker("Canción del repertorio", selection: $selectedSongID) {
                            Text("Registro libre").tag(nil as UUID?)
                            ForEach(songs) { song in
                                Text(song.artist.isEmpty ? song.title : "\(song.title) · \(song.artist)")
                                    .tag(song.id as UUID?)
                            }
                        }
                        .onChange(of: selectedSongID) { _, _ in applySelectedSong() }
                        if selectedSong != nil, repertoireSongDurationSeconds > 0 {
                            let songDuration = PracticeDurationFormatter.clockText(
                                seconds: repertoireSongDurationSeconds
                            )
                            Stepper(
                                "Pasadas completas: \(repertoireRepetitions)",
                                value: $repertoireRepetitions,
                                in: 0...99
                            )
                            .onChange(of: repertoireRepetitions) { _, count in
                                guard count > 0 else { return }
                                duration = max(1, Int(ceil(Double(repertoireSongDurationSeconds * count) / 60.0)))
                            }
                            Text("Cada pasada de \(songDuration); \(repertoireRepetitions == 0 ? "usa la duración manual" : "total \(PracticeDurationFormatter.clockText(seconds: resolvedDurationSeconds))").")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if selectedSong != nil {
                            Label("Esta canción no tiene duración. Edítala en Repertorio para calcular las pasadas.", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } else if category == .theory {
                        LibraryConceptPicker(
                            title: "Concepto de biblioteca",
                            noneLabel: "Registro libre",
                            selection: $selectedConceptID
                        )
                        .onChange(of: selectedConceptID) { _, _ in applySelectedConcept() }
                    } else {
                        LibraryExercisePicker(
                            title: "Ejercicio de biblioteca",
                            noneLabel: "Registro libre",
                            selection: $selectedExerciseID
                        )
                        .onChange(of: selectedExerciseID) { _, _ in applySelectedExercise() }
                    }

                    TextField(category == .repertoire ? "Artista o fuente" : "Libro o fuente", text: $sourceTitle)
                    TextField(category == .repertoire ? "Canción" : "Ejercicio", text: $exerciseTitle)

                    if category == .repertoire {
                        if canAddTypedSong {
                            Button("Agregar \"\(exerciseTitle.trimmingCharacters(in: .whitespacesAndNewlines))\" al repertorio", systemImage: "plus.circle") {
                                addTypedSongToRepertoire()
                            }
                        }
                        Text("Al elegir una canción, la sesión queda vinculada a ella y se puede saltar a Repertorio desde la sesión. Si tocaste algo que no está en tu repertorio, escríbelo y agrégalo desde aquí.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Al elegir un ítem de Biblioteca, la sesión queda vinculada a él y se puede saltar a Biblioteca desde la sesión.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Métrica") {
                    HStack {
                        BPMField(label: "Tempo inicial:", value: $startBPM)
                        Spacer(minLength: 16)
                        BPMField(label: "Tempo final:", value: $endBPM)
                    }
                    Stepper("Esfuerzo percibido: \(difficulty)/5", value: $difficulty, in: 1...5)
                    Picker("Resultado", selection: $result) {
                        ForEach(PracticeResult.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    if category.supportsRhythmicFigure {
                        Picker("Figura o subdivisión", selection: $rhythmicFigure) {
                            ForEach(RhythmicFigure.allCases) { figure in
                                Text(figure.displayName).tag(figure)
                            }
                        }
                        Text(rhythmicFigure.pulseDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if category != .repertoire {
                        Stepper(
                            "Repeticiones correctas seguidas: \(correctRepetitions)",
                            value: $correctRepetitions,
                            in: 0...10
                        )
                    }
                    Stepper("Tensión: \(tensionRating)/5", value: $tensionRating, in: 1...5)
                    Picker("Comprobado", selection: $practiceContext) {
                        ForEach(PracticeApplicationContext.allCases) { context in
                            Text(context.rawValue).tag(context)
                        }
                    }
                    Toggle("Fue una prueba en frío", isOn: $wasColdCheck)
                    if tensionRating >= 4 {
                        Label("Baja la exigencia y revisa postura o agarre antes de insistir.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Observaciones") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Editar sesión" : "Nueva sesión")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(duration <= 0)
                }
            }
            .onAppear {
                loadInitialValuesIfNeeded()
            }
        }
    }

    private func loadInitialValuesIfNeeded() {
        guard !didLoadInitialValues else { return }
        didLoadInitialValues = true

        if let sessionToEdit {
            date = sessionToEdit.date
            duration = sessionToEdit.durationMinutes
            instrumentName = sessionToEdit.instrumentName
            category = sessionToEdit.category
            sourceTitle = sessionToEdit.sourceTitle
            exerciseTitle = sessionToEdit.exerciseTitle
            startBPM = sessionToEdit.startBPM
            endBPM = sessionToEdit.endBPM
            difficulty = sessionToEdit.difficulty
            result = sessionToEdit.result
            correctRepetitions = sessionToEdit.correctRepetitions
            repertoireRepetitions = sessionToEdit.repertoireRepetitions
            repertoireDurationSnapshot = sessionToEdit.repertoireSongDurationSeconds
            tensionRating = sessionToEdit.tensionRating
            practiceContext = sessionToEdit.practiceContext
            wasColdCheck = sessionToEdit.wasColdCheck
            notes = sessionToEdit.notes
            rhythmicFigure = sessionToEdit.rhythmicFigure
            // Si la sesión ya venía vinculada a una canción, un ejercicio o un concepto, dejar el
            // picker correspondiente en ese ítem para que editar no pierda el vínculo ni lo muestre
            // como "Registro libre".
            if sessionToEdit.sourceKind == .repertoire, let sourceID = sessionToEdit.sourceID,
               songs.contains(where: { $0.id == sourceID }) {
                selectedSongID = sourceID
                initialSessionSongID = sourceID
            } else if sessionToEdit.sourceKind == .library, let sourceID = sessionToEdit.sourceID {
                selectedExerciseID = sourceID
            } else if sessionToEdit.sourceKind == .libraryConcept, let sourceID = sessionToEdit.sourceID {
                selectedConceptID = sourceID
            }
        } else if let initialTaskID, let task = practiceTasks.first(where: { $0.id == initialTaskID }) {
            category = task.category
            if task.plannedMinutes > 0 { duration = task.plannedMinutes }
            sourceTitle = task.sourceTitle
            exerciseTitle = task.exerciseTitle.isEmpty ? task.title : task.exerciseTitle
            rhythmicFigure = task.rhythmicFigure
            if task.targetBPM > 0 {
                endBPM = task.targetBPM
                startBPM = max(40, Int(Double(task.targetBPM) * 0.75))
            }
            if task.sourceKind == .repertoire, let sourceID = task.sourceID, songs.contains(where: { $0.id == sourceID }) {
                selectedSongID = sourceID
            } else if task.sourceKind == .library, let sourceID = task.sourceID {
                selectedExerciseID = sourceID
            } else if task.sourceKind == .libraryConcept, let sourceID = task.sourceID {
                selectedConceptID = sourceID
            }
            linkedTaskID = task.id
            if let dimension = task.evidenceDimension {
                practiceContext = SkillChallengeBuilder.recommendedContext(for: dimension)
                wasColdCheck = dimension == .retention
            }
            if instrumentName.isEmpty { instrumentName = instruments.first?.name ?? "" }
        } else if instrumentName.isEmpty {
            instrumentName = instruments.first?.name ?? ""
        }
    }

    private func applySelectedExercise() {
        guard let selectedExercise else { return }
        sourceTitle = selectedExercise.bookTitle
        exerciseTitle = selectedExercise.displayName
        if selectedExercise.targetBPM > 0 {
            endBPM = selectedExercise.targetBPM
            startBPM = max(40, Int(Double(selectedExercise.targetBPM) * 0.75))
        }
    }

    private func applySelectedConcept() {
        guard let selectedConcept else { return }
        sourceTitle = selectedConcept.bookTitle
        exerciseTitle = selectedConcept.title
    }

    private func applySelectedSong() {
        guard let selectedSong else { return }
        if !handledInitialSongSelection, selectedSong.id == initialSessionSongID,
           repertoireDurationSnapshot > 0 {
            handledInitialSongSelection = true
        } else {
            repertoireDurationSnapshot = selectedSong.durationSeconds
            handledInitialSongSelection = true
        }
        sourceTitle = selectedSong.artist
        exerciseTitle = selectedSong.title
        if selectedSong.targetTempo > 0 {
            endBPM = selectedSong.targetTempo
            startBPM = max(40, Int(Double(selectedSong.targetTempo) * 0.75))
        }
    }

    /// Crea la canción escrita a mano en Repertorio y deja la sesión vinculada a ella, para no tener
    /// que salir del formulario, agregarla en la otra pantalla y volver a empezar el registro.
    private func addTypedSongToRepertoire() {
        let title = exerciseTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let song = Song(
            title: title,
            artist: sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            status: .learning,
            targetTempo: endBPM
        )
        modelContext.insert(song)
        selectedSongID = song.id
    }

    /// El único de los tres pickers que puede estar activo a la vez, según `category` — de ahí el
    /// orden fijo de prioridad para decidir a qué quedó vinculada la sesión.
    private var linkedSource: (kind: TaskSourceKind, id: UUID)? {
        if let selectedSong { return (.repertoire, selectedSong.id) }
        if let selectedExercise { return (.library, selectedExercise.id) }
        if let selectedConcept { return (.libraryConcept, selectedConcept.id) }
        return nil
    }

    private func save() {
        let linkedTask = linkedTaskID.flatMap { id in practiceTasks.first { $0.id == id } }
        let savedSession: PracticeSession
        if let sessionToEdit {
            sessionToEdit.date = date
            sessionToEdit.durationMinutes = resolvedDurationMinutes
            sessionToEdit.durationSeconds = resolvedDurationSeconds
            sessionToEdit.instrumentName = instrumentName
            sessionToEdit.category = category
            sessionToEdit.sourceTitle = sourceTitle
            sessionToEdit.exerciseTitle = exerciseTitle
            sessionToEdit.startBPM = startBPM
            sessionToEdit.endBPM = endBPM
            sessionToEdit.difficulty = difficulty
            sessionToEdit.result = result
            sessionToEdit.notes = notes
            sessionToEdit.correctRepetitions = correctRepetitions
            sessionToEdit.repertoireRepetitions = repertoireRepetitions
            sessionToEdit.repertoireSongDurationSeconds = category == .repertoire
                ? repertoireSongDurationSeconds : 0
            sessionToEdit.tensionRating = tensionRating
            sessionToEdit.practiceContext = practiceContext
            sessionToEdit.wasColdCheck = wasColdCheck
            sessionToEdit.rhythmicFigure = rhythmicFigure
            // Solo se pisa el origen si acá se eligió una canción, ejercicio o concepto: si la
            // sesión venía de otro lado (una tarea, el timer), su vínculo original se respeta.
            if let linkedSource {
                sessionToEdit.sourceKind = linkedSource.kind
                sessionToEdit.sourceID = linkedSource.id
            }
            savedSession = sessionToEdit
        } else {
            // Si la sesión se abrió desde "Iniciar tarea" y esta no tiene un ejercicio, canción o
            // concepto elegible en los pickers de arriba (por ejemplo viene de Academia, Clases o el
            // Profesor IA), el origen de la tarea igual se hereda directo — si no, esas sesiones
            // quedaban como "Registro libre" y perdían el botón "volver al origen" que sí tienen las
            // sesiones iniciadas desde el timer.
            let resolvedSource: (kind: TaskSourceKind, id: UUID)?
            if let linkedSource {
                resolvedSource = linkedSource
            } else if let linkedTaskID,
                      let task = practiceTasks.first(where: { $0.id == linkedTaskID }),
                      let taskSourceID = task.sourceID, task.sourceKind != .manual {
                resolvedSource = (task.sourceKind, taskSourceID)
            } else {
                resolvedSource = nil
            }
            let session = PracticeSession(
                date: date,
                durationMinutes: resolvedDurationMinutes,
                durationSeconds: resolvedDurationSeconds,
                instrumentName: instrumentName,
                category: category,
                sourceTitle: sourceTitle,
                exerciseTitle: exerciseTitle,
                startBPM: startBPM,
                endBPM: endBPM,
                difficulty: difficulty,
                result: result,
                notes: notes,
                sourceKind: resolvedSource?.kind ?? .manual,
                sourceID: resolvedSource?.id,
                correctRepetitions: correctRepetitions,
                repertoireRepetitions: repertoireRepetitions,
                repertoireSongDurationSeconds: category == .repertoire
                    ? repertoireSongDurationSeconds : 0,
                tensionRating: tensionRating,
                practiceContext: practiceContext,
                wasColdCheck: wasColdCheck,
                rhythmicFigure: rhythmicFigure,
                targetSkillID: linkedTask?.targetSkillID,
                evidenceDimension: linkedTask?.evidenceDimension,
                successCriterion: linkedTask?.successCriterion ?? ""
            )
            modelContext.insert(session)
            savedSession = session
        }
        SkillEvidenceService.recordPractice(session: savedSession, task: linkedTask, in: modelContext)
        if let task = linkedTask {
            RecurringPracticeService.completeTask(
                task,
                outcome: PracticeOutcome(
                    result: result,
                    endBPM: endBPM,
                    correctRepetitions: correctRepetitions,
                    tensionRating: tensionRating,
                    context: practiceContext,
                    wasColdCheck: wasColdCheck
                ),
                in: modelContext
            )
        }
        BadgeEvaluator.evaluate(context: modelContext)
        _ = try? PracticeCoachCoordinator.reevaluate(
            trigger: .sessionCompleted,
            in: modelContext
        )
        dismiss()
    }
}
