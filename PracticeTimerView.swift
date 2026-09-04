import SwiftUI
import SwiftData
import Combine

struct PracticeTimerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Instrument.name) private var instruments: [Instrument]
    @Query(sort: \PracticeTask.priority) private var tasks: [PracticeTask]
    @Query(sort: \Song.title) private var songs: [Song]

    /// Tarea a preseleccionar al abrir el timer (por ejemplo, desde la recomendación del asistente).
    var initialTaskID: UUID?
    /// Cola ordenada del plan de Hoy. Vacía mantiene el comportamiento de una sesión individual.
    var initialPlanTaskIDs: [UUID] = []

    @State private var selectedTaskID: UUID?
    @State private var selectedExerciseID: UUID?
    @State private var selectedSongID: UUID?
    @State private var planTaskIDs: [UUID] = []
    @State private var planStepIndex = 0
    @State private var category = PracticeCategory.technique
    @State private var exerciseSearchText = ""
    @State private var instrumentName = ""
    /// Tiempo de los tramos ya cerrados (todo lo anterior a la pausa actual). El tramo en curso NO
    /// vive acá: se calcula contra `runStartedAt` cada vez que hace falta.
    @State private var accumulatedSeconds: TimeInterval = 0
    /// Instante real en que arrancó el tramo actual, o `nil` si está pausado. Contar con reloj de
    /// pared en vez de sumar un segundo por tick del `Timer` es lo que hace que la duración sea
    /// correcta aunque el Mac se duerma o el hilo principal se trabe con una llamada de IA — con
    /// ticks, cada segundo que el timer no dispara es un segundo de práctica que se pierde.
    @State private var runStartedAt: Date?
    /// Solo existe para que la vista se redibuje una vez por segundo; el número que se muestra sale
    /// de las dos propiedades de arriba, no de esta.
    @State private var now = Date.now
    @State private var startBPM = 80
    @State private var endBPM = 80
    @State private var notes = ""
    @State private var rhythmicFigure = RhythmicFigure.unspecified
    @State private var difficulty = 3
    @State private var result = PracticeResult.learning
    @State private var correctRepetitions = 0
    @State private var repertoireRepetitions = 0
    @State private var tensionRating = 1
    @State private var practiceContext = PracticeApplicationContext.isolated
    @State private var wasColdCheck = false
    @State private var recoveredDraftDate: Date?
    @State private var metronome = MetronomeEngine()
    @State private var metronomeIsOn = false
    @State private var metronomeBPM = 80
    @State private var beatsPerBar = 4
    @State private var autoIncreaseEnabled = false
    @State private var autoIncreaseStep = 2
    @State private var autoIncreaseMinutes = 2
    /// Segundos de práctica en los que ocurrió la última subida automática de tempo.
    @State private var lastAutoIncreaseSeconds = 0
    /// El primer encendido del metrónomo fija el BPM inicial de la sesión; los cambios posteriores
    /// solo mueven el final.
    @State private var metronomeDidSetStartBPM = false
    @State private var filteredExercises: [LibraryExercise] = []
    @State private var exerciseCount = 0
    /// Sesiones ya insertadas durante esta apertura del cronómetro, una por tarea/ejercicio/canción
    /// distinta. Volver a algo que ya se venía practicando (después de pasar por otra cosa) suma
    /// minutos al mismo registro en vez de crear uno nuevo — así el total por tarea queda correcto en
    /// vez de fragmentado en varias entradas del mismo día.
    @State private var loggedSessions: [SelectionKind: PracticeSession] = [:]
    @AppStorage("practiceBreakRemindersEnabled") private var breakRemindersEnabled = true
    @AppStorage("defaultPracticeInstrumentName") private var defaultInstrumentName = ""
    @State private var showingBreakReminder = false
    @State private var nextBreakReminderSeconds = 25 * 60

    private enum PracticePhase: String, CaseIterable, Identifiable {
        case prepare = "Preparar"
        case practice = "Practicar"
        case review = "Cerrar"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .prepare: "slider.horizontal.3"
            case .practice: "play.fill"
            case .review: "checkmark.circle.fill"
            }
        }
    }

    @State private var phase = PracticePhase.prepare

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isRunning: Bool { runStartedAt != nil }

    private var elapsedSeconds: Int {
        let current = runStartedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return Int(accumulatedSeconds + current)
    }

    private var selectedTask: PracticeTask? {
        tasks.first { $0.id == selectedTaskID }
    }

    private var hasGuidedPlan: Bool { planTaskIDs.count > 1 }
    private var hasNextPlanTask: Bool { planStepIndex + 1 < planTaskIDs.count }
    private var nextPlanTask: PracticeTask? {
        guard hasNextPlanTask else { return nil }
        return tasks.first { $0.id == planTaskIDs[planStepIndex + 1] }
    }

    private var selectedExercise: LibraryExercise? {
        LibraryLookup.exercise(id: selectedExerciseID, in: modelContext)
    }

    private var selectedSong: Song? {
        songs.first { $0.id == selectedSongID }
    }

    /// Una tarea diaria de repertorio selecciona su canción mediante `sourceID`, sin llenar
    /// `selectedSongID`. Esta vista unificada permite mostrar y guardar la duración en ambos casos.
    private var activeRepertoireSong: Song? {
        if let selectedSong { return selectedSong }
        guard selectedTask?.sourceKind == .repertoire, let sourceID = selectedTask?.sourceID else {
            return nil
        }
        return songs.first { $0.id == sourceID }
    }

    private var expectedRepertoireSeconds: Int {
        (activeRepertoireSong?.durationSeconds ?? 0) * repertoireRepetitions
    }

    private var currentOutcome: PracticeOutcome {
        PracticeOutcome(
            result: result,
            endBPM: endBPM,
            correctRepetitions: correctRepetitions,
            tensionRating: tensionRating,
            context: practiceContext,
            wasColdCheck: wasColdCheck
        )
    }

    /// Identifica qué se está practicando ahora mismo, sin importar de qué lista viene — sirve para
    /// notar cuándo un cambio de selección es realmente un cambio (y no un reclic sobre lo mismo).
    private enum SelectionKind: Hashable {
        case free
        case task(UUID)
        case exercise(UUID)
        case song(UUID)
    }

    private var currentSelectionKind: SelectionKind {
        if let selectedTaskID { return .task(selectedTaskID) }
        if let selectedExerciseID { return .exercise(selectedExerciseID) }
        if let selectedSongID { return .song(selectedSongID) }
        return .free
    }

    /// El picker de Categoría escribe acá (no directo a `category`) para que cambiarla a mano limpie
    /// cualquier selección de otra categoría en el mismo gesto — sin depender de `.onChange`, cuyo
    /// orden relativo a las asignaciones directas de `category` que hacen `select(task:)` y
    /// `onAppear` (que si necesitan preservar la selección) no está garantizado.
    private var categoryBinding: Binding<PracticeCategory> {
        Binding(
            get: { category },
            set: { newValue in
                category = newValue
                selectFree()
            }
        )
    }

    /// Ordenadas por origen (Biblioteca, Profesor IA, Repertorio, Academia, Clases, Manual) para que
    /// se vean agrupadas en la lista sin depender de `Section` dentro de `Picker` — esa combinación
    /// no se renderizaba de forma confiable en macOS (probado con datos reales: una tarea de
    /// Biblioteca pendiente no aparecía en el picker).
    private var pendingTasks: [PracticeTask] {
        let order = TaskSourceKind.allCases
        return tasks.filter { !$0.isCompleted }
            .sorted {
                (order.firstIndex(of: $0.sourceKind) ?? order.count)
                    < (order.firstIndex(of: $1.sourceKind) ?? order.count)
            }
    }

    /// Solo las tareas de la categoría elegida — la categoría manda primero, la tarea es opcional
    /// dentro de ella.
    private var tasksInCategory: [PracticeTask] {
        pendingTasks.filter { $0.category == category }
    }

    /// Sin buscar, favoritos (lista corta y útil); buscando, hasta 25 coincidencias. La consulta va
    /// a la base con tope en vez de traer los 1.561 ejercicios y filtrar en memoria — ver
    /// `LibraryLookup`.
    private func reloadExercises() {
        filteredExercises = LibraryLookup.searchExercises(exerciseSearchText, in: modelContext)
    }

    private var elapsedText: String {
        let hours = elapsedSeconds / 3600
        let minutes = (elapsedSeconds % 3600) / 60
        let seconds = elapsedSeconds % 60
        return hours > 0
            ? String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                VStack(alignment: .leading) {
                    Text(phase == .prepare ? "Preparar práctica" : phase == .practice ? "Práctica en curso" : "Cerrar sesión")
                        .font(.largeTitle.bold())
                    Text(selectedTask?.title ?? selectedExercise?.displayName ?? selectedSong?.title ?? "Sesión libre")
                        .foregroundStyle(.secondary)
                    if hasGuidedPlan {
                        Label(
                            "Tarea \(planStepIndex + 1) de \(planTaskIDs.count)",
                            systemImage: "list.number"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PracticeTheme.accent)
                    }
                    if phase == .practice, let task = selectedTask, let taskModeLabel = task.taskModeLabel {
                        Label("Modo: \(taskModeLabel)", systemImage: task.taskModeIcon)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(task.category.color)
                    }
                    if phase == .practice, let instructions = selectedTask?.instructions, !instructions.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "text.bubble.fill")
                            Text(instructions)
                        }
                        .font(.callout)
                        .foregroundStyle(.orange)
                    }
                }
                Spacer()
                Button("Cerrar") { dismiss() }
            }

            phaseIndicator

            if phase != .prepare {
                Text(elapsedText)
                    .font(.system(size: 72, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                    .accessibilityLabel("Tiempo de práctica")
                    .accessibilityValue(elapsedText)
            }

            if phase == .practice {
                HStack(spacing: 14) {
                    Button(isRunning ? "Pausar" : "Continuar", systemImage: isRunning ? "pause.fill" : "play.fill") {
                        toggleRun()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Reiniciar", systemImage: "arrow.counterclockwise") {
                        resetTimer()
                    }
                    .controlSize(.large)
                }
            }

            if phase == .practice, let recoveredDraftDate {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                    Text("Se recuperó la práctica que quedó abierta el \(recoveredDraftDate.formatted(date: .abbreviated, time: .shortened)), en pausa. Presiona Continuar para seguir.")
                    Spacer()
                    Button("Descartar") {
                        resetTimer()
                        phase = .prepare
                    }
                }
                .font(.callout)
                .foregroundStyle(.orange)
            }

            if phase == .practice {
                GroupBox("Método de esta sesión") {
                VStack(alignment: .leading, spacing: 7) {
                    if selectedTask?.isDailyChromaticWarmup == true {
                        Label(
                            "\(DailyPracticeRoutine.chromaticMinutes) min completos: tempo cómodo, sonido uniforme y manos relajadas.",
                            systemImage: "timer"
                        )
                        Label("La combinación y figura rítmica del día están en las instrucciones.", systemImage: "metronome")
                    } else {
                        Label("1. Haz una prueba breve antes de estudiar.", systemImage: "play.circle")
                        Label("2. Aísla el punto exacto que falla y baja el tempo.", systemImage: "scope")
                        Label("3. Corrige hasta lograr repeticiones limpias y relajadas.", systemImage: "repeat")
                        Label("4. Reintégralo en la canción, groove o frase completa.", systemImage: "music.note")
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                }
            }

            Form {
                if phase == .prepare {
                    Picker("Categoría", selection: categoryBinding) {
                        ForEach(PracticeCategory.allCases) { item in
                            Label(item.rawValue, systemImage: item.icon).tag(item)
                        }
                    }

                    Section("Tarea") {
                    TaskSelectionRow(
                        icon: "circle.dashed",
                        title: "Sesión libre",
                        subtitle: "Cualquier cosa que quieras practicar",
                        isSelected: selectedTaskID == nil && selectedExerciseID == nil && selectedSongID == nil
                    ) {
                        selectFree()
                    }
                    ForEach(tasksInCategory) { task in
                        TaskSelectionRow(
                            icon: task.sourceKind.icon.isEmpty ? "checklist" : task.sourceKind.icon,
                            title: task.title,
                            subtitle: [
                                task.taskModeLabel,
                                task.sourceKind == .manual ? nil : task.sourceKind.sectionTitle,
                                task.sourceTitle
                            ]
                                .compactMap { $0 }
                                .filter { !$0.isEmpty }
                                .joined(separator: " · "),
                            minutes: task.plannedMinutes,
                            isSelected: selectedTaskID == task.id
                        ) {
                            select(task: task)
                        }
                    }
                }

                    if category == .technique {
                    Section("Ejercicio de Biblioteca") {
                        TextField("Buscar entre tus \(exerciseCount) ejercicios", text: $exerciseSearchText)
                            .onChange(of: exerciseSearchText) { _, _ in reloadExercises() }
                        ForEach(filteredExercises) { exercise in
                            TaskSelectionRow(
                                icon: "books.vertical.fill",
                                title: exercise.displayName,
                                subtitle: exercise.bookTitle,
                                isSelected: selectedExerciseID == exercise.id
                            ) {
                                select(exercise: exercise)
                            }
                        }
                        if exerciseSearchText.isEmpty && filteredExercises.isEmpty {
                            Text("Sin favoritos todavía — busca por nombre, libro o técnica.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if !exerciseSearchText.isEmpty && filteredExercises.isEmpty {
                            Text("Sin resultados.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                    if category == .repertoire {
                    Section("Canción de Repertorio") {
                        if songs.isEmpty {
                            Text("Sin canciones en Repertorio todavía.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(songs) { song in
                            TaskSelectionRow(
                                icon: "music.note.list",
                                title: song.title,
                                subtitle: [song.artist, song.formattedDuration]
                                    .compactMap { $0 }
                                    .filter { !$0.isEmpty }
                                    .joined(separator: " · "),
                                isSelected: selectedSongID == song.id
                            ) {
                                select(song: song)
                            }
                        }
                    }
                }

                    if let task = selectedTask, task.isDiagnosticChallenge {
                    Section("Reto verificable") {
                        if let dimension = task.evidenceDimension {
                            Label(dimension.rawValue, systemImage: dimension.icon)
                                .foregroundStyle(dimension.color)
                        }
                        Text(task.successCriterion)
                            .font(.callout)
                        Text("El resultado de esta sesión actualizará el perfil de dominio de la habilidad.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                    Picker("Instrumento", selection: $instrumentName) {
                        Text("Sin especificar").tag("")
                        ForEach(instruments) { Text($0.name).tag($0.name) }
                    }

                    HStack {
                        BPMField(label: "Inicio:", value: $startBPM)
                        Spacer(minLength: 16)
                        BPMField(label: "Objetivo:", value: $endBPM)
                    }

                    if category.supportsRhythmicFigure {
                        Section("Figura rítmica") {
                        Picker("Figura o subdivisión", selection: $rhythmicFigure) {
                            ForEach(RhythmicFigure.allCases) { figure in
                                Text(figure.displayName).tag(figure)
                            }
                        }
                        Text(rhythmicFigure.pulseDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if rhythmicFigure.isSpecified, !rhythmicFigure.countingGuide.isEmpty {
                            Text(rhythmicFigure.countingGuide)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        }
                    }
                }

                if phase == .practice {
                    Section("Metrónomo") {
                    HStack(spacing: 12) {
                        Button(
                            metronomeIsOn ? "Detener" : "Sonar",
                            systemImage: metronomeIsOn ? "stop.fill" : "metronome"
                        ) {
                            toggleMetronome()
                        }
                        .buttonStyle(.bordered)

                        BPMField(
                            label: "",
                            value: $metronomeBPM,
                            range: MetronomeEngine.minimumBPM...MetronomeEngine.maximumBPM
                        )

                        Picker("Compás", selection: $beatsPerBar) {
                            Text("2/4").tag(2)
                            Text("3/4").tag(3)
                            Text("4/4").tag(4)
                            Text("6/8").tag(6)
                        }
                        .frame(width: 150)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(metronomeBPM) },
                            set: { metronomeBPM = Int($0.rounded()) }
                        ),
                        in: Double(MetronomeEngine.minimumBPM)...Double(MetronomeEngine.maximumBPM),
                        step: 1
                    )
                    .accessibilityLabel("Tempo del metrónomo")
                    .accessibilityValue("\(metronomeBPM) BPM")

                    Toggle("Subir el tempo solo mientras practico", isOn: $autoIncreaseEnabled)
                    if autoIncreaseEnabled {
                        HStack {
                            Stepper("+\(autoIncreaseStep) BPM", value: $autoIncreaseStep, in: 1...10)
                            Stepper(
                                "cada \(autoIncreaseMinutes) min",
                                value: $autoIncreaseMinutes,
                                in: 1...15
                            )
                            Spacer()
                        }
                    }

                    Text("El tempo del metrónomo escribe el BPM final de la sesión, así que no hace falta anotarlo a mano. La subida automática solo avanza con el cronómetro corriendo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                if phase == .review {
                    Section("Evaluación al cerrar") {
                    Picker("Resultado", selection: $result) {
                        ForEach(PracticeResult.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    Text(result.guidance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        BPMField(label: "Inicio:", value: $startBPM)
                        Spacer(minLength: 16)
                        BPMField(label: "Final:", value: $endBPM)
                    }
                    Stepper("Esfuerzo percibido: \(difficulty)/5", value: $difficulty, in: 1...5)
                    if category == .repertoire {
                        if let song = activeRepertoireSong, let duration = song.formattedDuration {
                            Stepper(
                                "Pasadas completas: \(repertoireRepetitions)",
                                value: $repertoireRepetitions,
                                in: 0...99
                            )
                            HStack {
                                Label("Cada pasada: \(duration)", systemImage: "music.note")
                                Spacer()
                                Button("Sumar pasada", systemImage: "plus.circle") {
                                    repertoireRepetitions = min(99, repertoireRepetitions + 1)
                                }
                            }
                            .font(.caption)
                            if repertoireRepetitions > 0 {
                                LabeledContent("Tiempo musical esperado") {
                                    Text(PracticeDurationFormatter.clockText(seconds: expectedRepertoireSeconds))
                                        .monospacedDigit()
                                }
                                Text("El cronómetro guardará aparte el tiempo real (\(elapsedText)), incluyendo pausas o trabajo por secciones.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Label("La canción no tiene duración registrada. Edítala en Repertorio para contar pasadas completas.", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } else {
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
                        Label("No subas el tempo. Pausa y revisa postura, agarre y esfuerzo.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    }

                    TextField("Qué funcionó, qué falló y qué harás después", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .formStyle(.grouped)

            HStack {
                switch phase {
                case .prepare:
                    Spacer()
                    Button("Comenzar práctica", systemImage: "play.fill") { beginPractice() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                case .practice:
                    Button("Cambiar tarea", systemImage: "arrow.left") { returnToPreparation() }
                    Spacer()
                    Button("Terminar práctica", systemImage: "checkmark") { finishForReview() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(elapsedSeconds < 10)
                case .review:
                    Button("Seguir practicando", systemImage: "arrow.left") { phase = .practice }
                    Spacer()
                    Button(
                        hasNextPlanTask ? "Guardar y siguiente" : "Finalizar y guardar",
                        systemImage: hasNextPlanTask ? "arrow.right" : "checkmark"
                    ) {
                        if hasNextPlanTask {
                            saveAndAdvancePlan()
                        } else {
                            save()
                        }
                    }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .disabled(elapsedSeconds < 10)
                        .accessibilityIdentifier(hasNextPlanTask ? "practice.saveAndNext" : "practice.finish")
                }
            }
        }
        .padding(24)
        .onReceive(timer) { date in
            guard isRunning else { return }
            now = date
            applyAutoIncreaseIfDue()
            saveDraft()
            if breakRemindersEnabled, elapsedSeconds >= nextBreakReminderSeconds {
                nextBreakReminderSeconds += 25 * 60
                showingBreakReminder = true
            }
        }
        .onAppear {
            if !defaultInstrumentName.isEmpty,
               instruments.contains(where: { $0.name == defaultInstrumentName }) {
                instrumentName = defaultInstrumentName
            } else {
                instrumentName = instruments.first?.name ?? ""
            }
            restoreDraftIfAny()
            planTaskIDs = initialPlanTaskIDs.filter { id in
                tasks.contains { $0.id == id && !$0.isCompleted }
            }
            let requestedTaskID = planTaskIDs.first ?? initialTaskID
            if let requestedTaskID, let task = tasks.first(where: { $0.id == requestedTaskID }) {
                // La tarea pulsada en Hoy/Tareas tiene prioridad sobre la selección de un borrador.
                // `select(task:)` cierra primero cualquier tramo recuperado de otra tarea, por lo que
                // no se pierde ni se atribuye su tiempo a la tarea nueva.
                if selectedTaskID != task.id {
                    select(task: task)
                    recoveredDraftDate = nil
                }
                category = task.category
            }
            if startBPM > 0 { metronomeBPM = max(MetronomeEngine.minimumBPM, startBPM) }
            exerciseCount = LibraryLookup.exerciseCount(in: modelContext)
            reloadExercises()
            if elapsedSeconds > 0 { phase = .practice }
        }
        .onChange(of: metronomeBPM) { _, newValue in
            metronome.update(bpm: newValue, beatsPerBar: beatsPerBar)
            if metronomeIsOn { endBPM = newValue }
        }
        .onChange(of: beatsPerBar) { _, newValue in
            metronome.update(bpm: metronomeBPM, beatsPerBar: newValue)
        }
        .onChange(of: rhythmicFigure) { _, newValue in
            selectedTask?.rhythmicFigure = newValue
            saveDraft()
        }
        .onChange(of: repertoireRepetitions) { _, _ in saveDraft() }
        .onDisappear {
            metronome.stop()
            saveDraft()
        }
        .alert("Momento de una pausa", isPresented: $showingBreakReminder) {
            Button("Pausar 5 min") {
                if isRunning { toggleRun() }
            }
            Button("Seguir", role: .cancel) {}
        } message: {
            Text("Llevas 25 minutos efectivos. Soltar las manos, moverte e hidratarte ayuda a conservar precisión y evitar tensión acumulada.")
        }
    }

    private var phaseIndicator: some View {
        HStack(spacing: 8) {
            ForEach(Array(PracticePhase.allCases.enumerated()), id: \.element) { index, item in
                Label(item.rawValue, systemImage: item.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item == phase ? Color.white : Color.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        item == phase ? PracticeTheme.accent : Color.secondary.opacity(0.10),
                        in: Capsule()
                    )
                if index < PracticePhase.allCases.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Etapa actual: \(phase.rawValue)")
    }

    private func beginPractice() {
        phase = .practice
        if !isRunning { toggleRun() }
    }

    private func finishForReview() {
        if isRunning { toggleRun() }
        metronome.stop()
        metronomeIsOn = false
        phase = .review
        saveDraft()
    }

    private func returnToPreparation() {
        if isRunning { toggleRun() }
        metronome.stop()
        metronomeIsOn = false
        phase = .prepare
    }

    // MARK: - Metrónomo

    private func toggleMetronome() {
        if metronomeIsOn {
            metronome.stop()
            metronomeIsOn = false
            return
        }

        metronome.start(bpm: metronomeBPM, beatsPerBar: beatsPerBar)
        metronomeIsOn = metronome.isRunning
        guard metronomeIsOn else { return }

        if !metronomeDidSetStartBPM {
            startBPM = metronomeBPM
            metronomeDidSetStartBPM = true
        }
        endBPM = metronomeBPM
        lastAutoIncreaseSeconds = elapsedSeconds
    }

    /// La subida automática se cuenta contra el tiempo practicado, no contra la hora del reloj: si
    /// pausás para afinar, el tempo no sigue subiendo solo.
    private func applyAutoIncreaseIfDue() {
        guard metronomeIsOn, autoIncreaseEnabled else { return }
        guard elapsedSeconds - lastAutoIncreaseSeconds >= autoIncreaseMinutes * 60 else { return }
        lastAutoIncreaseSeconds = elapsedSeconds
        metronomeBPM = min(MetronomeEngine.maximumBPM, metronomeBPM + autoIncreaseStep)
    }

    // MARK: - Cronómetro

    private func toggleRun() {
        if let runStartedAt {
            accumulatedSeconds += max(0, Date.now.timeIntervalSince(runStartedAt))
            self.runStartedAt = nil
        } else {
            now = .now
            runStartedAt = now
        }
        recoveredDraftDate = nil
        saveDraft()
    }

    private func resetTimer() {
        runStartedAt = nil
        accumulatedSeconds = 0
        recoveredDraftDate = nil
        lastAutoIncreaseSeconds = 0
        nextBreakReminderSeconds = 25 * 60
        repertoireRepetitions = 0
        PracticeTimerDraft.clear()
    }

    // MARK: - Borrador de la práctica en curso

    /// Cerrar la ventana con el cronómetro corriendo perdía la sesión entera. Ahora queda anotada
    /// en disco y se recupera al volver a abrir el timer.
    private func saveDraft() {
        guard elapsedSeconds > 0 else { return }
        PracticeTimerDraft.save(.init(
            accumulatedSeconds: accumulatedSeconds,
            runStartedAt: runStartedAt,
            savedAt: .now,
            taskID: selectedTaskID,
            exerciseID: selectedExerciseID,
            songID: selectedSongID,
            categoryRaw: category.rawValue,
            instrumentName: instrumentName,
            startBPM: startBPM,
            endBPM: endBPM,
            notes: notes,
            difficulty: difficulty,
            resultRaw: result.rawValue,
            correctRepetitions: correctRepetitions,
            repertoireRepetitions: repertoireRepetitions,
            tensionRating: tensionRating,
            practiceContextRaw: practiceContext.rawValue,
            wasColdCheck: wasColdCheck,
            rhythmicFigureRaw: rhythmicFigure.rawValue
        ))
    }

    /// Se recupera siempre en pausa: si el timer quedó corriendo y la app estuvo cerrada tres días,
    /// contar ese tiempo como práctica sería mentir. Lo que estaba corriendo se cierra hasta el
    /// último momento en que sabemos que la app estaba viva (`savedAt`).
    ///
    /// Si el borrador quedó de un día anterior, no se suma al cronómetro de hoy — eso mezclaría dos
    /// días en una sola sesión. Se cierra solo con su fecha real (`saveStaleDraft`) y hoy arranca en
    /// cero.
    private func restoreDraftIfAny() {
        guard let draft = PracticeTimerDraft.load() else { return }

        var seconds = draft.accumulatedSeconds
        if let started = draft.runStartedAt {
            seconds += max(0, draft.savedAt.timeIntervalSince(started))
        }
        guard seconds >= 1 else {
            PracticeTimerDraft.clear()
            return
        }

        guard Calendar.current.isDateInToday(draft.savedAt) else {
            saveStaleDraft(draft, seconds: seconds)
            PracticeTimerDraft.clear()
            return
        }

        accumulatedSeconds = seconds
        runStartedAt = nil
        now = .now
        selectedTaskID = draft.taskID
        selectedExerciseID = draft.exerciseID
        selectedSongID = draft.songID
        category = PracticeCategory(rawValue: draft.categoryRaw) ?? category
        if !draft.instrumentName.isEmpty { instrumentName = draft.instrumentName }
        startBPM = draft.startBPM
        endBPM = draft.endBPM
        notes = draft.notes
        difficulty = draft.difficulty ?? 3
        result = PracticeResult(rawValue: draft.resultRaw ?? "") ?? .learning
        correctRepetitions = draft.correctRepetitions ?? 0
        repertoireRepetitions = draft.repertoireRepetitions ?? 0
        tensionRating = draft.tensionRating ?? 1
        practiceContext = PracticeApplicationContext(rawValue: draft.practiceContextRaw ?? "") ?? .isolated
        wasColdCheck = draft.wasColdCheck ?? false
        rhythmicFigure = draft.rhythmicFigureRaw.flatMap(RhythmicFigure.init(rawValue:)) ?? .unspecified
        nextBreakReminderSeconds = max(25 * 60, ((elapsedSeconds / (25 * 60)) + 1) * 25 * 60)
        recoveredDraftDate = draft.savedAt
    }

    /// Cierra un borrador dejado pausado en un día anterior como su propia `PracticeSession`, fechada
    /// el día real en que se practicó (no hoy). Igual que `logSegmentIfNeeded`, el umbral de 10s evita
    /// crear un registro por un reclic accidental que nunca llegó a ser práctica real.
    private func saveStaleDraft(_ draft: PracticeTimerDraft, seconds: TimeInterval) {
        guard seconds >= 10 else { return }

        let task = draft.taskID.flatMap { id in tasks.first { $0.id == id } }
        let exercise = LibraryLookup.exercise(id: draft.exerciseID, in: modelContext)
        let song = draft.songID.flatMap { id in songs.first { $0.id == id } }
        let minutes = max(1, Int(ceil(seconds / 60.0)))

        let session = buildSession(
            minutes: minutes,
            durationSeconds: Int(seconds.rounded()),
            date: draft.savedAt,
            task: task,
            exercise: exercise,
            song: song,
            instrumentName: draft.instrumentName,
            category: PracticeCategory(rawValue: draft.categoryRaw) ?? category,
            startBPM: draft.startBPM,
            endBPM: draft.endBPM,
            notes: draft.notes,
            difficulty: draft.difficulty,
            result: draft.resultRaw.flatMap { PracticeResult(rawValue: $0) },
            correctRepetitions: draft.correctRepetitions,
            repertoireRepetitions: draft.repertoireRepetitions,
            tensionRating: draft.tensionRating,
            practiceContext: draft.practiceContextRaw.flatMap { PracticeApplicationContext(rawValue: $0) },
            wasColdCheck: draft.wasColdCheck,
            rhythmicFigure: draft.rhythmicFigureRaw.flatMap(RhythmicFigure.init(rawValue:)) ?? .unspecified
        )
        modelContext.insert(session)
        SkillEvidenceService.recordPractice(session: session, task: task, in: modelContext)
        if let task {
            RecurringPracticeService.completeTask(
                task,
                outcome: PracticeOutcome(
                    result: PracticeResult(rawValue: draft.resultRaw ?? "") ?? .learning,
                    endBPM: draft.endBPM,
                    correctRepetitions: draft.correctRepetitions ?? 0,
                    tensionRating: draft.tensionRating ?? 1,
                    context: PracticeApplicationContext(rawValue: draft.practiceContextRaw ?? "") ?? .isolated,
                    wasColdCheck: draft.wasColdCheck ?? false
                ),
                in: modelContext
            )
        }
        BadgeEvaluator.evaluate(context: modelContext)
    }

    private func selectFree() {
        let changedSelection = currentSelectionKind != .free
        logSegmentIfNeeded(newSelection: .free)
        if changedSelection { repertoireRepetitions = 0 }
        selectedTaskID = nil
        selectedExerciseID = nil
        selectedSongID = nil
        rhythmicFigure = .unspecified
    }

    private func select(task: PracticeTask) {
        let selection = SelectionKind.task(task.id)
        let changedSelection = currentSelectionKind != selection
        logSegmentIfNeeded(newSelection: selection)
        if changedSelection { repertoireRepetitions = 0 }
        selectedTaskID = task.id
        if let index = planTaskIDs.firstIndex(of: task.id) { planStepIndex = index }
        selectedExerciseID = nil
        selectedSongID = nil
        rhythmicFigure = task.rhythmicFigure
        if let dimension = task.evidenceDimension {
            practiceContext = SkillChallengeBuilder.recommendedContext(for: dimension)
            wasColdCheck = dimension == .retention
        }
        applyTargetBPM(task.targetBPM)
    }

    private func select(exercise: LibraryExercise) {
        let selection = SelectionKind.exercise(exercise.id)
        let changedSelection = currentSelectionKind != selection
        logSegmentIfNeeded(newSelection: selection)
        if changedSelection { repertoireRepetitions = 0 }
        selectedExerciseID = exercise.id
        selectedTaskID = nil
        selectedSongID = nil
        rhythmicFigure = .unspecified
        applyTargetBPM(exercise.targetBPM)
    }

    private func select(song: Song) {
        let selection = SelectionKind.song(song.id)
        let changedSelection = currentSelectionKind != selection
        logSegmentIfNeeded(newSelection: selection)
        if changedSelection { repertoireRepetitions = 0 }
        selectedSongID = song.id
        selectedTaskID = nil
        selectedExerciseID = nil
        rhythmicFigure = .unspecified
        applyTargetBPM(song.targetTempo)
    }

    /// Si ya se venía practicando otra cosa (tarea, ejercicio o canción distinta) y hubo al menos
    /// algo de tiempo real invertido en ella, cierra ese tramo antes de cambiar la selección — así
    /// "20 min de Bending the Blues + 30 min de Paranoid" queda como dos registros, no uno solo con
    /// el título de lo último que quedó elegido. El umbral de 10s evita generar un registro vacío por
    /// un reclic accidental antes de arrancar el cronómetro.
    private func logSegmentIfNeeded(newSelection: SelectionKind) {
        guard newSelection != currentSelectionKind, elapsedSeconds >= 10 else { return }

        closeSegment(for: currentSelectionKind, seconds: Double(elapsedSeconds), task: selectedTask)

        accumulatedSeconds = 0
        if isRunning {
            now = .now
            runStartedAt = now
        }
        lastAutoIncreaseSeconds = 0
        notes = ""
        difficulty = 3
        result = .learning
        correctRepetitions = 0
        repertoireRepetitions = 0
        tensionRating = 1
        practiceContext = .isolated
        wasColdCheck = false
        saveDraft()
    }

    /// Cierra un tramo de `seconds` para `kind`. Si ya existe un registro de esta misma apertura del
    /// cronómetro para esa tarea/ejercicio/canción (volviste a ella después de practicar otra cosa),
    /// le suma los minutos y las notas en vez de crear una entrada nueva — el total por tarea queda
    /// como una sola suma, no fragmentado. Lo usan `logSegmentIfNeeded` (cierre de un tramo intermedio)
    /// y `save()` (cierre final).
    private func closeSegment(for kind: SelectionKind, seconds: TimeInterval, task: PracticeTask?) {
        guard seconds >= 10 else { return }
        let segmentSeconds = max(1, Int(seconds.rounded()))
        let minutes = max(1, Int(ceil(Double(segmentSeconds) / 60.0)))
        let recordedSession: PracticeSession

        if let existing = loggedSessions[kind] {
            existing.durationSeconds += segmentSeconds
            existing.durationMinutes = max(1, Int(ceil(Double(existing.durationSeconds) / 60.0)))
            existing.endBPM = endBPM
            if !notes.isEmpty {
                existing.notes = existing.notes.isEmpty ? notes : existing.notes + "\n" + notes
            }
            existing.difficulty = difficulty
            existing.result = result
            existing.correctRepetitions = correctRepetitions
            existing.repertoireRepetitions += repertoireRepetitions
            if existing.repertoireSongDurationSeconds == 0 {
                existing.repertoireSongDurationSeconds = activeRepertoireSong?.durationSeconds ?? 0
            }
            existing.tensionRating = tensionRating
            existing.practiceContext = practiceContext
            existing.wasColdCheck = wasColdCheck
            existing.rhythmicFigure = rhythmicFigure
            recordedSession = existing
        } else {
            let session = buildSession(minutes: minutes, durationSeconds: segmentSeconds)
            modelContext.insert(session)
            loggedSessions[kind] = session
            recordedSession = session
        }

        SkillEvidenceService.recordPractice(session: recordedSession, task: task, in: modelContext)

        if let task {
            RecurringPracticeService.completeTask(task, outcome: currentOutcome, in: modelContext)
        }
        BadgeEvaluator.evaluate(context: modelContext)
    }

    private func applyTargetBPM(_ target: Int) {
        guard target > 0 else { return }
        endBPM = target
        startBPM = max(40, Int(Double(target) * 0.75))
        // El metrónomo arranca en el tempo de calentamiento, no en la meta.
        if !metronomeIsOn { metronomeBPM = max(MetronomeEngine.minimumBPM, startBPM) }
    }

    /// Arma la `PracticeSession` del tramo en curso a partir de la selección y los BPM actuales.
    /// La usan tanto `save()` (cierre final) como `logSegmentIfNeeded` (cierre de un tramo intermedio
    /// al cambiar de tarea/ejercicio/canción sin parar el cronómetro) como `saveStaleDraft` (cierre
    /// de un borrador de un día anterior) — por eso todo lo que normalmente sale del estado de la
    /// vista se puede pisar con un parámetro explícito.
    private func buildSession(
        minutes: Int,
        durationSeconds: Int? = nil,
        date: Date = .now,
        task: PracticeTask? = nil,
        exercise: LibraryExercise? = nil,
        song: Song? = nil,
        instrumentName: String? = nil,
        category: PracticeCategory? = nil,
        startBPM: Int? = nil,
        endBPM: Int? = nil,
        notes: String? = nil,
        difficulty: Int? = nil,
        result: PracticeResult? = nil,
        correctRepetitions: Int? = nil,
        repertoireRepetitions: Int? = nil,
        tensionRating: Int? = nil,
        practiceContext: PracticeApplicationContext? = nil,
        wasColdCheck: Bool? = nil,
        rhythmicFigure: RhythmicFigure? = nil
    ) -> PracticeSession {
        let task = task ?? selectedTask
        let exercise = exercise ?? selectedExercise
        let song = song ?? selectedSong
        let instrumentName = instrumentName ?? self.instrumentName
        let category = category ?? self.category
        let startBPM = startBPM ?? self.startBPM
        let endBPM = endBPM ?? self.endBPM
        let notes = notes ?? self.notes
        let difficulty = difficulty ?? self.difficulty
        let result = result ?? self.result
        let correctRepetitions = correctRepetitions ?? self.correctRepetitions
        let repertoireRepetitions = repertoireRepetitions ?? self.repertoireRepetitions
        let tensionRating = tensionRating ?? self.tensionRating
        let practiceContext = practiceContext ?? self.practiceContext
        let wasColdCheck = wasColdCheck ?? self.wasColdCheck
        let rhythmicFigure = rhythmicFigure ?? self.rhythmicFigure
        let repertoireSong = song ?? task.flatMap { selectedTask in
            guard selectedTask.sourceKind == .repertoire, let sourceID = selectedTask.sourceID else {
                return nil
            }
            return songs.first { $0.id == sourceID }
        }

        let sourceTitle: String
        let exerciseTitle: String
        let sourceKind: TaskSourceKind
        let sourceID: UUID?

        if let task {
            sourceTitle = task.sourceTitle
            exerciseTitle = task.exerciseTitle.isEmpty ? task.title : task.exerciseTitle
            sourceKind = task.sourceKind
            sourceID = task.sourceID
        } else if let exercise {
            sourceTitle = exercise.bookTitle
            exerciseTitle = exercise.displayName
            sourceKind = .library
            sourceID = exercise.id
        } else if let song {
            sourceTitle = song.artist
            exerciseTitle = song.title
            sourceKind = .repertoire
            sourceID = song.id
        } else {
            sourceTitle = ""
            exerciseTitle = "Sesión libre"
            sourceKind = .manual
            sourceID = nil
        }

        return PracticeSession(
            date: date,
            durationMinutes: minutes,
            durationSeconds: durationSeconds ?? minutes * 60,
            instrumentName: instrumentName,
            category: category,
            sourceTitle: sourceTitle,
            exerciseTitle: exerciseTitle,
            startBPM: startBPM,
            endBPM: endBPM,
            difficulty: difficulty,
            result: result,
            notes: notes,
            sourceKind: sourceKind,
            sourceID: sourceID,
            correctRepetitions: correctRepetitions,
            repertoireRepetitions: category == .repertoire ? repertoireRepetitions : 0,
            repertoireSongDurationSeconds: category == .repertoire
                ? (repertoireSong?.durationSeconds ?? 0) : 0,
            tensionRating: tensionRating,
            practiceContext: practiceContext,
            wasColdCheck: wasColdCheck,
            rhythmicFigure: rhythmicFigure,
            targetSkillID: task?.targetSkillID,
            evidenceDimension: task?.evidenceDimension,
            successCriterion: task?.successCriterion ?? ""
        )
    }

    private func save() {
        closeSegment(for: currentSelectionKind, seconds: Double(elapsedSeconds), task: selectedTask)
        _ = try? PracticeCoachCoordinator.reevaluate(
            trigger: .sessionCompleted,
            in: modelContext
        )
        metronome.stop()
        // `onDisappear` guarda un borrador como red de seguridad. Vaciar el reloj antes de cerrar
        // evita que esa misma red vuelva a crear el borrador de una sesión ya finalizada.
        runStartedAt = nil
        accumulatedSeconds = 0
        PracticeTimerDraft.clear()
        dismiss()
    }

    /// Cierra el tramo actual con su evaluación y continúa inmediatamente con la siguiente tarea
    /// del plan, conservando instrumento y configuración del metrónomo. Cada tramo queda como una
    /// sesión independiente y la recurrencia de la tarea anterior se actualiza antes de avanzar.
    private func saveAndAdvancePlan() {
        guard let nextTask = nextPlanTask else {
            save()
            return
        }
        select(task: nextTask)
        category = nextTask.category
        phase = .practice
        if !isRunning { toggleRun() }
    }
}

/// Fila tocable para elegir la tarea del timer — mismo lenguaje visual (ícono + título/subtítulo +
/// indicador a la derecha) que `TaskRow`/`SessionRow` en el resto de la app, en vez de un `Picker`
/// nativo: un `Picker` trunca títulos largos y agrupar con `Section` dentro de `Picker` no se
/// renderiza de forma confiable en macOS.
private struct TaskSelectionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var minutes: Int = 0
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if minutes > 0 {
                    Text("\(minutes) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue([subtitle, minutes > 0 ? "\(minutes) minutos" : "", isSelected ? "Seleccionada" : ""]
            .filter { !$0.isEmpty }
            .joined(separator: ", "))
    }
}
