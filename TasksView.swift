import SwiftUI
import SwiftData

private enum TaskListFilter: String, CaseIterable, Identifiable {
    case today = "Hoy"
    case pending = "Pendientes"
    case upcoming = "Próximas"
    case completed = "Completadas"

    var id: String { rawValue }
}

struct TasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigator.self) private var navigator
    @Query(sort: \PracticeTask.priority) private var tasks: [PracticeTask]
    @State private var showingNewTask = false
    @State private var showingTimer = false
    @State private var timerTaskID: UUID?
    @State private var filter = TaskListFilter.today
    @State private var searchText = ""

    private var visibleTasks: [PracticeTask] {
        let startOfToday = Calendar.current.startOfDay(for: .now)
        let startOfTomorrow = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday) ?? .distantFuture
        return tasks.filter { task in
            let matchesFilter: Bool
            switch filter {
            case .today:
                matchesFilter = !task.isCompleted && task.scheduledDate < startOfTomorrow
            case .pending:
                matchesFilter = !task.isCompleted
            case .upcoming:
                matchesFilter = !task.isCompleted && task.scheduledDate >= startOfTomorrow
            case .completed:
                matchesFilter = task.isCompleted
            }
            guard matchesFilter else { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return [task.title, task.exerciseTitle, task.sourceTitle, task.instructions]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack { taskTitle; Spacer(); taskControls }
                VStack(alignment: .leading, spacing: 12) { taskTitle; taskControls }
            }
            .padding(24)

            if tasks.isEmpty {
                EmptyStateView(icon: "checklist", title: "Sin tareas", message: "Agrega una tarea nueva o marca un ejercicio de Biblioteca, Repertorio o el Profesor IA.")
            } else if visibleTasks.isEmpty {
                ContentUnavailableView.search(text: searchText.isEmpty ? filter.rawValue : searchText)
            } else {
                List {
                    ForEach(PracticeBucket.allCases) { bucket in
                        let items = visibleTasks.filter { PracticeBucket.bucket(for: $0.category) == bucket }
                        if !items.isEmpty {
                            Section(bucket.rawValue) {
                                ForEach(items) { task in
                                    TaskRow(
                                        task: task,
                                        onSelectTask: { openTask(task) },
                                        onOpenTimer: {
                                            if task.isDailyFretboardTraining {
                                                navigator.selection = .fretboard
                                            } else {
                                                timerTaskID = task.id
                                                showingTimer = true
                                            }
                                        },
                                        onDelete: { modelContext.delete(task) },
                                        onOpenSource: task.sourceKind == .manual ? nil : {
                                            navigator.go(to: task.sourceKind, id: task.sourceID)
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showingNewTask) {
            NewTaskView()
                .frame(minWidth: 480, idealWidth: 560, minHeight: 480)
        }
        .sheet(isPresented: $showingTimer) {
            PracticeTimerView(initialTaskID: timerTaskID)
                .frame(minWidth: 500, idealWidth: 580, minHeight: 540)
        }
    }

    private var taskTitle: some View {
        VStack(alignment: .leading) {
            Text("Tareas")
                .font(.largeTitle.bold())
            Text("Prioriza lo de hoy sin perder el historial ni lo programado")
                .foregroundStyle(.secondary)
        }
    }

    private var taskControls: some View {
        HStack {
            TextField("Buscar tareas", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 150, idealWidth: 210, maxWidth: 240)
                .accessibilityIdentifier("tasks.search")
            Picker("Vista", selection: $filter) {
                ForEach(TaskListFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 390)
            .accessibilityIdentifier("tasks.filter")
            Button("Nueva tarea", systemImage: "plus") { showingNewTask = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private func openTask(_ task: PracticeTask) {
        if task.sourceKind.targetSection != nil {
            navigator.go(to: task.sourceKind, id: task.sourceID)
        } else {
            timerTaskID = task.id
            showingTimer = true
        }
    }
}

struct NewTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Song.title) private var songs: [Song]

    @State private var title = ""
    @State private var category = PracticeCategory.technique
    @State private var plannedMinutes = 15
    @State private var priority = 1
    @State private var scheduledDate = Date.now
    @State private var instructions = ""
    @State private var selectedSongID: UUID?
    @State private var theoryTaskMode = TheoryTaskMode.readAndExplain
    @State private var rhythmTaskMode = RhythmTaskMode.countAndClap
    @State private var repertoireTaskMode = RepertoireTaskMode.bySections
    @State private var rhythmicFigure = RhythmicFigure.unspecified

    private var isTitleValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tarea") {
                    TextField("Título", text: $title)
                    Picker("Área", selection: $category) {
                        ForEach(PracticeCategory.allCases) { item in
                            Label(item.rawValue, systemImage: item.icon).tag(item)
                        }
                    }
                    .onChange(of: category) { oldValue, newValue in
                        if newValue != .repertoire { selectedSongID = nil }
                        if !newValue.supportsRhythmicFigure { rhythmicFigure = .unspecified }
                        let trimmed = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                        let canReplaceInstructions = trimmed.isEmpty ||
                            (oldValue == .theory && instructions == theoryTaskMode.defaultInstructions) ||
                            (oldValue == .rhythm && instructions == rhythmTaskMode.defaultInstructions) ||
                            (oldValue == .repertoire && instructions == repertoireTaskMode.defaultInstructions)
                        if newValue == .theory, canReplaceInstructions {
                            instructions = theoryTaskMode.defaultInstructions
                        } else if newValue == .rhythm, canReplaceInstructions {
                            instructions = rhythmTaskMode.defaultInstructions
                        } else if newValue == .repertoire, canReplaceInstructions {
                            instructions = repertoireTaskMode.defaultInstructions
                        }
                    }
                    Stepper("Duración: \(plannedMinutes) minutos", value: $plannedMinutes, in: 5...240, step: 5)
                    Picker("Prioridad", selection: $priority) {
                        Text("Alta").tag(0)
                        Text("Media").tag(1)
                        Text("Baja").tag(2)
                    }
                    DatePicker("Fecha programada", selection: $scheduledDate, displayedComponents: .date)
                }

                if category == .theory {
                    Section("Cómo hacer la tarea") {
                        Picker("Modo de estudio", selection: $theoryTaskMode) {
                            ForEach(TheoryTaskMode.allCases) { mode in
                                Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                            }
                        }
                        .onChange(of: theoryTaskMode) { oldValue, newValue in
                            let trimmed = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.isEmpty || instructions == oldValue.defaultInstructions {
                                instructions = newValue.defaultInstructions
                            }
                        }

                        Text(theoryTaskMode.defaultInstructions)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if category == .rhythm {
                    Section("Cómo hacer la tarea") {
                        Picker("Modo de práctica", selection: $rhythmTaskMode) {
                            ForEach(RhythmTaskMode.allCases) { mode in
                                Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                            }
                        }
                        .onChange(of: rhythmTaskMode) { oldValue, newValue in
                            let trimmed = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.isEmpty || instructions == oldValue.defaultInstructions {
                                instructions = newValue.defaultInstructions
                            }
                        }

                        Text(rhythmTaskMode.defaultInstructions)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if category == .repertoire {
                    Section("Cómo hacer la tarea") {
                        Picker("Modo de práctica", selection: $repertoireTaskMode) {
                            ForEach(RepertoireTaskMode.allCases) { mode in
                                Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                            }
                        }
                        .onChange(of: repertoireTaskMode) { oldValue, newValue in
                            let trimmed = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.isEmpty || instructions == oldValue.defaultInstructions {
                                instructions = newValue.defaultInstructions
                            }
                        }

                        Text(repertoireTaskMode.defaultInstructions)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if category == .repertoire {
                    Section("Repertorio") {
                        Picker("Canción del repertorio", selection: $selectedSongID) {
                            Text("Sin vincular").tag(nil as UUID?)
                            ForEach(songs) { song in
                                Text(song.artist.isEmpty ? song.title : "\(song.title) · \(song.artist)")
                                    .tag(song.id as UUID?)
                            }
                        }
                        if songs.isEmpty {
                            Text("Todavía no hay canciones en Repertorio.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Al elegir una canción, la tarea queda vinculada a ella y se puede saltar a Repertorio desde Tareas.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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
                    }
                }

                Section("Instrucciones") {
                    TextField("Notas o instrucciones", text: $instructions, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Nueva tarea")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        let linkedSong = selectedSongID.flatMap { id in songs.first { $0.id == id } }
                        modelContext.insert(PracticeTask(
                            title: title,
                            category: category,
                            plannedMinutes: plannedMinutes,
                            sourceTitle: linkedSong?.artist ?? "",
                            exerciseTitle: linkedSong?.title ?? "",
                            priority: priority,
                            instructions: instructions,
                            theoryTaskMode: category == .theory ? theoryTaskMode : .guided,
                            rhythmTaskMode: category == .rhythm ? rhythmTaskMode : .guided,
                            repertoireTaskMode: category == .repertoire ? repertoireTaskMode : .guided,
                            scheduledDate: scheduledDate,
                            sourceKind: linkedSong != nil ? .repertoire : .manual,
                            sourceID: linkedSong?.id,
                            rhythmicFigure: rhythmicFigure
                        ))
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isTitleValid)
                }
            }
        }
    }
}
