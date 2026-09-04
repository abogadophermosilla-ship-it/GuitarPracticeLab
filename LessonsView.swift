import SwiftUI
import SwiftData
import AppKit

struct LessonsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigator.self) private var navigator
    @Query(sort: \GuitarLesson.date, order: .reverse) private var lessons: [GuitarLesson]
    @State private var showingNewLesson = false
    @State private var lessonToEdit: GuitarLesson?
    @State private var lessonForAI: GuitarLesson?
    @State private var lessonForTask: GuitarLesson?

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    lessonsTitle
                    Spacer()
                    lessonsActions
                }
                VStack(alignment: .leading, spacing: 10) {
                    lessonsTitle
                    lessonsActions
                }
            }
            .padding(20)

            if lessons.isEmpty {
                EmptyStateView(icon: "graduationcap", title: "No hay clases", message: "Registra una clase y sus objetivos.")
            } else {
                List {
                    ForEach(lessons) { lesson in
                        CardContainer {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(lesson.date.formatted(date: .long, time: .omitted))
                                            .font(.headline)
                                        Text(lesson.teacherName)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if let next = lesson.nextLessonDate {
                                        StatusPill(text: "Próxima: \(next.formatted(date: .abbreviated, time: .shortened))", tint: .purple)
                                    }
                                }

                                if !lesson.topics.isEmpty {
                                    Label(lesson.topics, systemImage: "music.note.list")
                                }

                                Divider()
                                Text("Indicaciones")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Text(lesson.teacherNotes)

                                if !lesson.nextObjective.isEmpty {
                                    Text("Objetivo para la próxima clase")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    Text(lesson.nextObjective)
                                }

                                if !lesson.attachments.isEmpty {
                                    Divider()
                                    Text("Adjuntos")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    ForEach(lesson.attachments) { attachment in
                                        HStack {
                                            Label(attachment.displayName, systemImage: attachment.kind.icon)
                                                .font(.caption)
                                                .lineLimit(1)
                                            Spacer()
                                            Button("Abrir") { openAttachment(attachment) }
                                                .font(.caption)
                                                .buttonStyle(.plain)
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                }

                                Divider()
                                HStack {
                                    Button("Crear tarea", systemImage: "checklist") {
                                        lessonForTask = lesson
                                    }
                                    .buttonStyle(.bordered)
                                    if lesson.attachments.contains(where: \.isProcessableAudio) {
                                        Button("Analizar clase con IA", systemImage: "waveform.badge.magnifyingglass") {
                                            lessonForAI = lesson
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { lessonToEdit = lesson }
                        .listRowSeparator(.hidden)
                        .contextMenu {
                            Button("Editar", systemImage: "pencil") { lessonToEdit = lesson }
                            Button("Eliminar", systemImage: "trash", role: .destructive) {
                                modelContext.delete(lesson)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .sheet(isPresented: $showingNewLesson) {
            NewLessonView()
                .frame(minWidth: 520, idealWidth: 620, minHeight: 520)
        }
        .sheet(item: $lessonToEdit) { lesson in
            NewLessonView(lessonToEdit: lesson)
                .frame(minWidth: 520, idealWidth: 620, minHeight: 520)
        }
        .sheet(item: $lessonForAI) { lesson in
            LessonIntelligenceView(lesson: lesson)
                .frame(minWidth: 520, idealWidth: 720, minHeight: 560)
        }
        .sheet(item: $lessonForTask) { lesson in
            NewTaskFromLessonView(lesson: lesson)
                .frame(minWidth: 480, idealWidth: 560, minHeight: 480)
        }
        .onAppear { applyPendingFocus() }
        .onChange(of: navigator.focusLessonID) { _, _ in applyPendingFocus() }
    }

    private func applyPendingFocus() {
        guard let focusID = navigator.focusLessonID else { return }
        lessonToEdit = lessons.first { $0.id == focusID }
        navigator.focusLessonID = nil
    }

    private var lessonsTitle: some View {
        VStack(alignment: .leading) {
            Text("Clases")
                .font(.largeTitle.bold())
            Text("Conecta las indicaciones de tu profesor con la práctica diaria")
                .foregroundStyle(.secondary)
        }
    }

    private var lessonsActions: some View {
        HStack {
            Button("Abrir materiales", systemImage: "folder") {
                LearningMaterialsService.open(LearningMaterialsService.classesURL)
            }
            .disabled(!FileManager.default.fileExists(atPath: LearningMaterialsService.classesURL.path))
            Button("Registrar clase", systemImage: "plus") { showingNewLesson = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private func openAttachment(_ attachment: LessonAttachment) {
        if let data = attachment.bookmarkData {
            SecurityScopedFile.open(data)
        } else if let url = LessonAttachment.normalizedExternalURL(from: attachment.externalURLString) {
            NSWorkspace.shared.open(url)
        }
    }
}

struct NewLessonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Clase a editar. `nil` cuando el formulario se usa para registrar una clase nueva.
    var lessonToEdit: GuitarLesson?

    @State private var date = Date.now
    @State private var teacherName = ""
    @State private var topics = ""
    @State private var notes = ""
    @State private var objective = ""
    @State private var hasNextDate = true
    @State private var nextDate = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var didLoadInitialValues = false

    @State private var attachments: [LessonAttachment] = []
    @State private var removedAttachments: [LessonAttachment] = []
    @State private var newAttachmentKind: LessonAttachmentKind = .pdf
    @State private var newAttachmentURL = ""
    @State private var attachmentURLValidationMessage: String?
    @State private var showingFileImporter = false

    private var isEditing: Bool { lessonToEdit != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Clase") {
                    DatePicker("Fecha", selection: $date)
                    TextField("Profesor", text: $teacherName)
                    TextField("Temas revisados", text: $topics, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section("Seguimiento") {
                    TextField("Indicaciones del profesor", text: $notes, axis: .vertical)
                        .lineLimit(4...8)
                    TextField("Objetivo para la próxima clase", text: $objective, axis: .vertical)
                        .lineLimit(3...6)
                    Toggle("Registrar próxima clase", isOn: $hasNextDate)
                    if hasNextDate {
                        DatePicker("Próxima clase", selection: $nextDate)
                    }
                }
                Section("Adjuntos del profesor") {
                    ForEach(attachments) { attachment in
                        HStack {
                            Label(attachment.displayName, systemImage: attachment.kind.icon)
                                .lineLimit(1)
                            Spacer()
                            Text(attachment.kind.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button(role: .destructive) {
                                removeAttachment(attachment)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Picker("Tipo de adjunto", selection: $newAttachmentKind) {
                        ForEach(LessonAttachmentKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Button("Adjuntar archivo", systemImage: "doc.badge.plus") { showingFileImporter = true }
                    HStack {
                        TextField("Pega un enlace de YouTube", text: $newAttachmentURL)
                            .onSubmit { addURLAttachment() }
                        Button("Agregar enlace") { addURLAttachment() }
                            .disabled(newAttachmentURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let attachmentURLValidationMessage {
                        Label(attachmentURLValidationMessage, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Text("PDFs, Guitar Pro, proyectos de EZbass/EZkeys/EZdrummer/Superior Drummer, audios, videos o enlaces. Los audios pueden transcribirse localmente después de guardar la clase.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Editar clase" : "Registrar clase")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                loadInitialValuesIfNeeded()
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.item]) { result in
                if case .success(let url) = result, let bookmark = try? SecurityScopedFile.makeBookmark(for: url) {
                    attachments.append(LessonAttachment(fileName: url.lastPathComponent, bookmarkData: bookmark, kind: newAttachmentKind))
                }
            }
        }
    }

    @discardableResult
    private func addURLAttachment() -> Bool {
        guard let url = LessonAttachment.normalizedExternalURL(from: newAttachmentURL) else {
            attachmentURLValidationMessage = "Ingresa un enlace web válido."
            return false
        }

        let kind: LessonAttachmentKind = LessonAttachment.isYouTubeURL(url) ? .video : newAttachmentKind
        attachments.append(LessonAttachment(kind: kind, externalURLString: url.absoluteString))
        newAttachmentURL = ""
        attachmentURLValidationMessage = nil
        return true
    }

    private func removeAttachment(_ attachment: LessonAttachment) {
        attachments.removeAll { $0.id == attachment.id }
        removedAttachments.append(attachment)
    }

    private func loadInitialValuesIfNeeded() {
        guard !didLoadInitialValues else { return }
        didLoadInitialValues = true
        guard let lessonToEdit else { return }

        date = lessonToEdit.date
        teacherName = lessonToEdit.teacherName
        topics = lessonToEdit.topics
        notes = lessonToEdit.teacherNotes
        objective = lessonToEdit.nextObjective
        if let next = lessonToEdit.nextLessonDate {
            hasNextDate = true
            nextDate = next
        } else {
            hasNextDate = false
        }
        attachments = lessonToEdit.attachments
    }

    private func save() {
        // Si el usuario pegó el enlace y presionó Guardar sin pulsar antes “Agregar enlace”,
        // lo incorporamos a la clase en vez de descartarlo silenciosamente.
        if !newAttachmentURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !addURLAttachment() {
            return
        }

        for removed in removedAttachments {
            modelContext.delete(removed)
        }
        for attachment in attachments where attachment.modelContext == nil {
            modelContext.insert(attachment)
        }

        if let lessonToEdit {
            lessonToEdit.date = date
            lessonToEdit.teacherName = teacherName
            lessonToEdit.topics = topics
            lessonToEdit.teacherNotes = notes
            lessonToEdit.nextObjective = objective
            lessonToEdit.nextLessonDate = hasNextDate ? nextDate : nil
            lessonToEdit.attachments = attachments
        } else {
            let lesson = GuitarLesson(
                date: date,
                teacherName: teacherName,
                topics: topics,
                teacherNotes: notes,
                nextObjective: objective,
                nextLessonDate: hasNextDate ? nextDate : nil
            )
            lesson.attachments = attachments
            modelContext.insert(lesson)
        }
        _ = try? PracticeCoachCoordinator.reevaluate(
            trigger: .teacherInstructionSaved,
            in: modelContext
        )
        dismiss()
    }
}

private struct NewTaskFromLessonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Song.title) private var songs: [Song]

    let lesson: GuitarLesson

    @State private var title: String
    @State private var category = PracticeCategory.technique
    @State private var plannedMinutes = 15
    @State private var priority = 1
    @State private var scheduledDate = Date.now
    @State private var instructions: String
    @State private var linkedExerciseID: UUID?
    @State private var linkedSongID: UUID?
    @State private var theoryTaskMode = TheoryTaskMode.readAndExplain
    @State private var rhythmTaskMode = RhythmTaskMode.countAndClap
    @State private var repertoireTaskMode = RepertoireTaskMode.bySections

    init(lesson: GuitarLesson) {
        self.lesson = lesson
        _title = State(initialValue: lesson.nextObjective.isEmpty ? lesson.topics : lesson.nextObjective)
        _instructions = State(initialValue: lesson.nextObjective)
    }

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

                Section("Vínculo (opcional)") {
                    LibraryExercisePicker(
                        title: "Ejercicio de biblioteca",
                        noneLabel: "Sin vínculo específico",
                        selection: $linkedExerciseID
                    )
                    .onChange(of: linkedExerciseID) { _, newValue in
                        if newValue != nil { linkedSongID = nil }
                    }

                    Picker("Canción de repertorio", selection: $linkedSongID) {
                        Text("Sin vínculo específico").tag(nil as UUID?)
                        ForEach(songs) { song in
                            Text(song.title).tag(song.id as UUID?)
                        }
                    }
                    .onChange(of: linkedSongID) { _, newValue in
                        if newValue != nil { linkedExerciseID = nil }
                    }

                    Text("Si no eliges nada, la tarea queda vinculada a esta clase.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Instrucciones") {
                    TextField("Notas o instrucciones", text: $instructions, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Crear tarea desde la clase")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isTitleValid)
                }
            }
        }
    }

    private func save() {
        let sourceKind: TaskSourceKind
        let sourceID: UUID?
        if let linkedExerciseID {
            sourceKind = .library
            sourceID = linkedExerciseID
        } else if let linkedSongID {
            sourceKind = .repertoire
            sourceID = linkedSongID
        } else {
            sourceKind = .clases
            sourceID = lesson.id
        }

        modelContext.insert(PracticeTask(
            title: title,
            category: category,
            plannedMinutes: plannedMinutes,
            priority: priority,
            instructions: instructions,
            theoryTaskMode: category == .theory ? theoryTaskMode : .guided,
            rhythmTaskMode: category == .rhythm ? rhythmTaskMode : .guided,
            repertoireTaskMode: category == .repertoire ? repertoireTaskMode : .guided,
            scheduledDate: scheduledDate,
            sourceKind: sourceKind,
            sourceID: sourceID
        ))
        dismiss()
    }
}

private extension LessonAttachment {
    var isProcessableAudio: Bool {
        guard kind == .audio, bookmarkData != nil else { return false }
        return LocalAudioIntelligenceService.supportedAudioExtensions.contains(
            URL(fileURLWithPath: fileName).pathExtension.lowercased()
        )
    }
}
