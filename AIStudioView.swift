import SwiftUI
import SwiftData
import AppKit
import WebKit

private enum AIStudioMode: String, CaseIterable, Identifiable {
    case teacher = "Profesor"
    case advanced = "Avanzado"
    case week = "Semana"
    case routine = "Rutina"
    case ladder = "Escalera"
    case videos = "Videos"
    case groove = "Groove"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .teacher: "bubble.left.and.text.bubble.right"
        case .advanced: "sparkles"
        case .week: "calendar"
        case .routine: "arrow.triangle.2.circlepath"
        case .ladder: "chart.line.uptrend.xyaxis"
        case .videos: "play.rectangle"
        case .groove: "waveform.path"
        }
    }
}

struct AIStudioView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GuitarLesson.date, order: .reverse) private var lessons: [GuitarLesson]
    @Query(sort: \SkillTopic.name) private var skills: [SkillTopic]
    // El catálogo entero solo hace falta al armar el contexto de una herramienta, no al abrir la
    // pantalla: se pide en el momento de la llamada (ver `learningContext` y `generateRoutineReview`)
    // en vez de mantener 1.561 ejercicios y 963 conceptos vivos en un `@Query`.
    @Query(sort: \LibraryBook.title) private var books: [LibraryBook]
    @Query(sort: \Song.title) private var songs: [Song]
    @Query(sort: \Band.name) private var bands: [Band]
    @Query(sort: \PracticeSession.date, order: .reverse) private var sessions: [PracticeSession]
    @Query(sort: \PracticeTask.createdAt, order: .reverse) private var tasks: [PracticeTask]
    @Query(sort: \TeacherChatMessage.createdAt) private var chatMessages: [TeacherChatMessage]
    @Query(sort: \TeacherConversation.updatedAt, order: .reverse)
    private var conversations: [TeacherConversation]
    @Query(sort: \WeeklyPracticePlan.createdAt, order: .reverse)
    private var savedWeeklyPlans: [WeeklyPracticePlan]
    @Query(sort: \AIArtifact.createdAt, order: .reverse) private var savedArtifacts: [AIArtifact]
    @Query(sort: \ProgressMilestone.date, order: .reverse) private var milestones: [ProgressMilestone]
    @Query(sort: \SkillEvidence.occurredAt, order: .reverse) private var evidence: [SkillEvidence]
    @Query private var coachStates: [PracticeCoachStateRecord]

    @StateObject private var orchestrator = AIOrchestrator()
    @AppStorage("musicalTastes") private var musicalTastes = ""
    @State private var mode: AIStudioMode = .teacher
    @State private var errorMessage = ""

    @State private var chatInput = ""
    @State private var chatIsWorking = false
    @State private var chatUsesWeb = false
    @State private var followUps: [String] = []
    @State private var selectedConversationID: UUID?
    @State private var conversationTitleDraft = ""
    @State private var conversationToRenameID: UUID?
    @State private var conversationToDeleteID: UUID?
    @State private var showingRenameConversation = false
    @State private var showingDeleteConversation = false

    @State private var weekDays = 4
    @AppStorage("dailyPracticeGoalMinutes") private var dailyMinutes = 45
    @State private var weeklySummary = ""
    @State private var weeklyItems: [WeeklyPracticePlanItem] = []
    @State private var weekIsWorking = false
    @State private var weekWasSaved = false
    @State private var weekSaveMessage = ""
    @State private var weeklyCompletionSource: AICompletionSource?
    @AppStorage("practicePlanInstruction") private var practicePlanInstruction = ""
    @AppStorage("practicePlanDesiredTechniques") private var practicePlanDesiredTechniques = ""
    @AppStorage("practicePlanLessonsPriority") private var practicePlanLessonsPriority = PracticePlanFocusPriority.high.rawValue
    @AppStorage("practicePlanBandPriority") private var practicePlanBandPriority = PracticePlanFocusPriority.normal.rawValue
    @AppStorage("practicePlanDesiredTechniquesPriority") private var practicePlanDesiredTechniquesPriority = PracticePlanFocusPriority.normal.rawValue
    @AppStorage("practicePlanWeakTechniquesPriority") private var practicePlanWeakTechniquesPriority = PracticePlanFocusPriority.high.rawValue
    @AppStorage("practicePlanEnjoymentPriority") private var practicePlanEnjoymentPriority = PracticePlanFocusPriority.normal.rawValue

    @State private var ladderGoal = ""
    @State private var ladderTitle = ""
    @State private var ladderRationale = ""
    @State private var ladderSteps: [SkillLadderStep] = []
    @State private var ladderIsWorking = false
    @State private var ladderWasSaved = false
    @State private var ladderCompletionSource: AICompletionSource?

    @State private var routineSummary = ""
    @State private var routineAdjustments: [RoutineAdjustment] = []
    @State private var routineIsWorking = false
    @State private var routineWasSaved = false
    @State private var routineCompletionSource: AICompletionSource?

    @State private var videoGoal = ""
    @State private var videoPlan: VideoResearchPlan?
    @State private var videoResults: [YouTubeVideoResult] = []
    @State private var videosAreWorking = false
    @State private var videosWereSaved = false
    @State private var videoCompletionSource: AICompletionSource?

    @State private var grooveRequest = "Blues shuffle para entender la subdivisión"
    @State private var grooveBPM = 80
    @State private var grooveBars = 4
    @State private var groove: GroovePattern?
    @State private var grooveIsWorking = false
    @State private var savedGrooveURL: URL?
    @State private var grooveCompletionSource: AICompletionSource?

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    titleBlock
                    Spacer()
                    modePicker
                        .frame(width: 560)
                }
                VStack(alignment: .leading, spacing: 10) {
                    titleBlock
                    modePicker
                }
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Group {
                        switch mode {
                        case .teacher: teacherContent
                        case .advanced: AdvancedTeacherView()
                        case .week: weekContent
                        case .routine: routineContent
                        case .ladder: ladderContent
                        case .videos: videosContent
                        case .groove: grooveContent
                        }
                    }
                    savedResultsContent
                }
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(20)
            }
        }
        .navigationTitle("Profesor IA")
        .onAppear { ensureConversationSelection() }
        .onChange(of: conversations.map(\.id)) { _, _ in ensureConversationSelection() }
        .alert("Renombrar conversación", isPresented: $showingRenameConversation) {
            TextField("Nombre", text: $conversationTitleDraft)
            Button("Cancelar", role: .cancel) {}
            Button("Guardar") { renameConversation() }
                .disabled(conversationTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("El nombre solo organiza tu historial; no se envía al modelo.")
        }
        .alert("Eliminar conversación", isPresented: $showingDeleteConversation) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar", role: .destructive) { deleteConversation() }
        } message: {
            Text("Se eliminarán todos los mensajes de esta conversación. Esta acción no afecta tus tareas ni tu progreso.")
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Profesor IA")
                .font(.largeTitle.bold())
            Text("Tus clases, libros, repertorio y práctica se convierten en decisiones concretas")
                .foregroundStyle(.secondary)
        }
    }

    private var modePicker: some View {
        Picker("Herramienta", selection: $mode) {
            ForEach(AIStudioMode.allCases) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    private var selectedConversation: TeacherConversation? {
        conversations.first { $0.id == selectedConversationID }
    }

    private var activeChatMessages: [TeacherChatMessage] {
        TeacherConversationService.messages(in: selectedConversation, from: chatMessages)
    }

    private var teacherContent: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                conversationSidebar
                    .frame(width: 230)
                teacherConversationContent
                    .frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 14) {
                conversationPicker
                teacherConversationContent
            }
        }
    }

    private var conversationSidebar: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Conversaciones")
                        .font(.headline)
                    Spacer()
                    Button("Nueva conversación", systemImage: "square.and.pencil") {
                        createConversation()
                    }
                    .labelStyle(.iconOnly)
                    .help("Nueva conversación")
                    .accessibilityIdentifier("teacher.newConversation")
                }
                Divider()
                ForEach(conversations) { conversation in
                    conversationRow(conversation)
                }
            }
        }
    }

    private var conversationPicker: some View {
        HStack {
            Picker("Conversación", selection: $selectedConversationID) {
                ForEach(conversations) { conversation in
                    Text(conversation.title).tag(conversation.id as UUID?)
                }
            }
            .accessibilityIdentifier("teacher.conversationPicker")
            Button("Nueva", systemImage: "square.and.pencil") { createConversation() }
                .accessibilityIdentifier("teacher.newConversation")
        }
    }

    private func conversationRow(_ conversation: TeacherConversation) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Button {
                selectConversation(conversation)
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: selectedConversationID == conversation.id
                          ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                        .foregroundStyle(selectedConversationID == conversation.id ? PracticeTheme.accent : Color.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conversation.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                        Text(conversation.messageIDs.isEmpty
                             ? "Sin mensajes"
                             : conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button("Renombrar", systemImage: "pencil") { beginRenaming(conversation) }
                Button("Eliminar", systemImage: "trash", role: .destructive) {
                    conversationToDeleteID = conversation.id
                    showingDeleteConversation = true
                }
                .disabled(chatIsWorking)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Opciones de conversación")
        }
        .padding(8)
        .background(
            selectedConversationID == conversation.id
                ? PracticeTheme.accent.opacity(0.10) : Color.clear,
            in: RoundedRectangle(cornerRadius: 9)
        )
        .contextMenu {
            Button("Renombrar", systemImage: "pencil") { beginRenaming(conversation) }
            Button("Eliminar", systemImage: "trash", role: .destructive) {
                conversationToDeleteID = conversation.id
                showingDeleteConversation = true
            }
            .disabled(chatIsWorking)
        }
    }

    private var teacherConversationContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardContainer {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        Label("Responde con tus datos y cita clases, libros y páginas reales", systemImage: "books.vertical")
                            .font(.headline)
                        Spacer()
                        if !activeChatMessages.isEmpty {
                            Button("Borrar conversación", systemImage: "trash") { clearChat() }
                                .buttonStyle(.plain)
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                    Text("No modifica tu progreso. Si le pides buscar en Internet, consultará Google Search y mostrará las fuentes externas usadas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if activeChatMessages.isEmpty {
                EmptyStateView(
                    icon: "bubble.left.and.text.bubble.right",
                    title: "Inicia la conversación",
                    message: "Pregunta qué practicar, por qué falla una técnica o cómo conectar una canción con tus libros."
                )
                .frame(minHeight: 180)
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(activeChatMessages) { message in
                        chatBubble(message)
                    }
                }
            }

            if !followUps.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        ForEach(followUps.prefix(3), id: \.self) { suggestion in
                            Button(suggestion) {
                                chatInput = suggestion
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    VStack(alignment: .leading) {
                        ForEach(followUps.prefix(3), id: \.self) { suggestion in
                            Button(suggestion) { chatInput = suggestion }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }

            CardContainer {
                VStack(alignment: .leading, spacing: 10) {
                    TextField(
                        "Ej. ¿Qué debería practicar hoy para mejorar el solo pendiente?",
                        text: $chatInput,
                        axis: .vertical
                    )
                    .lineLimit(2...6)
                    .accessibilityIdentifier("teacher.chatInput")
                    if VirtualTeacherWebSearchIntent.isRequested(in: chatInput) {
                        Label(
                            "Búsqueda externa activada para esta pregunta · se priorizarán fuentes confiables",
                            systemImage: "globe.badge.chevron.backward"
                        )
                        .font(.caption)
                        .foregroundStyle(.blue)
                    }
                    HStack {
                        if chatIsWorking {
                            ProgressView(chatUsesWeb ? "Buscando y verificando fuentes…" : "Consultando a Gemini…")
                                .controlSize(.small)
                        }
                        Spacer()
                        Button("Preguntar", systemImage: "arrow.up.circle.fill") {
                            Task { await sendChatMessage() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(chatIsWorking || chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("teacher.sendMessage")
                    }
                }
            }
            errorView
        }
    }

    private func chatBubble(_ message: TeacherChatMessage) -> some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 8) {
                Text(message.role == "user" ? "Tú" : "Profesor")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(message.content)
                    .textSelection(.enabled)
                if message.role != "user", let source = message.completionSource {
                    completionSourceBadge(source)
                }
                if !message.citations.isEmpty {
                    Divider()
                    Text(message.citations.map { "[\($0)]" }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.indigo)
                }
                if !message.webSources.isEmpty {
                    Divider()
                    Label("Fuentes externas", systemImage: "globe")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                    ForEach(message.webSources) { source in
                        if let url = URL(string: source.url) {
                            Link(destination: url) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(source.displayTitle)
                                        .lineLimit(2)
                                    if let host = source.host,
                                       !source.displayTitle.localizedCaseInsensitiveContains(host) {
                                        Text(host)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .font(.caption)
                        }
                    }
                }
                if let attribution = message.searchAttributionHTML, !attribution.isEmpty {
                    GoogleSearchAttributionView(html: attribution)
                        .frame(height: 48)
                        .accessibilityLabel("Sugerencias de Google Search")
                }
                if !message.suggestedPractice.isEmpty {
                    Divider()
                    ForEach(message.suggestedPractice) { suggestion in
                        practiceSuggestionRow(suggestion, in: message)
                    }
                }
            }
            .padding(14)
            .background(
                message.role == "user" ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 14)
            )
            if message.role != "user" { Spacer(minLength: 48) }
        }
    }

    private func practiceSuggestionRow(_ suggestion: PracticeSuggestion, in message: TeacherChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(.caption.weight(.medium))
                Text("\(suggestion.category.rawValue) · \(suggestion.minutes) min")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !suggestion.instructions.isEmpty {
                    Text(suggestion.instructions)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if suggestion.wasAdded {
                Label(
                    suggestion.addedScheduledDate.map {
                        "Agregada · \($0.formatted(date: .abbreviated, time: .omitted))"
                    } ?? "Agregada",
                    systemImage: "checkmark.circle.fill"
                )
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button("Agregar a esta semana", systemImage: "plus") {
                    addSuggestionToWeek(suggestion, in: message)
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 2)
    }

    private func addSuggestionToWeek(_ suggestion: PracticeSuggestion, in message: TeacherChatMessage) {
        errorMessage = ""
        let resolution = PracticeTaskDeduplication.resolve(
            candidateTitle: suggestion.title, candidateSourceKind: .profesor, in: modelContext
        )
        let existing: PracticeTask?
        switch resolution {
        case .keepExisting(let task), .replaceExisting(let task): existing = task
        case .none: existing = nil
        }
        let budget = UserDefaults.standard.integer(forKey: "dailyPracticeGoalMinutes")
        let proposedDate = WeeklyTaskScheduler.scheduledDate(
            for: suggestion.minutes,
            among: tasks,
            excluding: existing?.id,
            dailyBudgetMinutes: budget > 0 ? budget : 45
        )

        let scheduledDate: Date
        do {
            switch resolution {
            case .none:
                modelContext.insert(PracticeTask(
                    title: suggestion.title,
                    category: suggestion.category,
                    plannedMinutes: suggestion.minutes,
                    sourceTitle: suggestion.sourceTitle,
                    instructions: suggestion.instructions,
                    scheduledDate: proposedDate,
                    sourceKind: .profesor
                ))
                scheduledDate = proposedDate
            case .replaceExisting(let task):
                modelContext.delete(task)
                modelContext.insert(PracticeTask(
                    title: suggestion.title,
                    category: suggestion.category,
                    plannedMinutes: suggestion.minutes,
                    sourceTitle: suggestion.sourceTitle,
                    instructions: suggestion.instructions,
                    scheduledDate: proposedDate,
                    sourceKind: .profesor
                ))
                scheduledDate = proposedDate
            case .keepExisting(let task):
                // Si la coincidencia ya está en la ventana prometida, no se altera. Si estaba
                // semanas más adelante (el fallo observado), se trae a la fecha disponible.
                if !WeeklyTaskScheduler.contains(task.scheduledDate) {
                    task.scheduledDate = proposedDate
                }
                scheduledDate = task.scheduledDate
            }
            try modelContext.save()

            var updated = message.suggestedPractice
            guard let index = updated.firstIndex(where: { $0.id == suggestion.id }) else { return }
            updated[index].wasAdded = true
            updated[index].addedScheduledDate = scheduledDate
            message.suggestedPractice = updated
            try modelContext.save()
        } catch {
            errorMessage = "No se pudo agregar la tarea a esta semana: \(error.localizedDescription)"
        }
    }

    private var weekContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(
                        title: "Plan semanal razonado",
                        subtitle: "La propuesta no crea tareas hasta que confirmes"
                    )
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Stepper("Días: \(weekDays)", value: $weekDays, in: 1...7)
                            Stepper("\(dailyMinutes) min/día", value: $dailyMinutes, in: 15...120, step: 5)
                            Spacer()
                            weekGenerateButton
                        }
                        VStack(alignment: .leading) {
                            Stepper("Días: \(weekDays)", value: $weekDays, in: 1...7)
                            Stepper("\(dailyMinutes) min/día", value: $dailyMinutes, in: 15...120, step: 5)
                            weekGenerateButton
                        }
                    }
                    Divider()
                    SectionHeader(
                        title: "Enfoque del plan",
                        subtitle: "Dile a la app qué necesita pesar más en esta etapa"
                    )
                    TextField(
                        "Ej. Se acerca un ensayo: prioriza el repertorio de mi banda sin abandonar alternate picking.",
                        text: $practicePlanInstruction,
                        axis: .vertical
                    )
                    .lineLimit(2...4)

                    VStack(spacing: 8) {
                        ForEach(PracticePlanFocus.allCases) { focus in
                            planFocusRow(focus)
                        }
                    }

                    if planFocusPriority(for: .desiredTechniques) != .omit {
                        TextField(
                            "Técnicas que quieres trabajar (ej. alternate picking, bends afinados)",
                            text: $practicePlanDesiredTechniques,
                            axis: .vertical
                        )
                        .lineLimit(1...3)
                    }
                    if !practicePlanPreferences.hasActiveFocus {
                        Label("Activa al menos un foco para poder generar la semana.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if !weeklyItems.isEmpty {
                if let source = weeklyCompletionSource {
                    completionSourceBadge(source)
                }
                Text(weeklySummary)
                    .foregroundStyle(.secondary)
                ForEach($weeklyItems) { $item in
                    CardContainer {
                        HStack(alignment: .top, spacing: 12) {
                            Toggle("", isOn: $item.isSelected)
                                .labelsHidden()
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.title).font(.headline)
                                    Spacer()
                                    if let focus = item.planningFocus {
                                        StatusPill(text: focus.rawValue, tint: item.category.color.opacity(0.75))
                                    }
                                    StatusPill(text: "\(item.minutes) min", tint: item.category.color)
                                }
                                Text(item.scheduledDate.formatted(date: .complete, time: .omitted))
                                    .font(.caption.bold())
                                if !item.instructions.isEmpty { Text(item.instructions) }
                                if !item.sourceTitle.isEmpty {
                                    Label(item.sourceTitle, systemImage: "books.vertical")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Button("Guardar plan y agregar tareas seleccionadas", systemImage: "checkmark.circle.fill") {
                    saveWeeklyPlan()
                }
                .buttonStyle(.borderedProminent)
                .disabled(weekWasSaved || !weeklyItems.contains(where: \.isSelected))
                if !weekSaveMessage.isEmpty {
                    Label(weekSaveMessage, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            errorView
        }
    }

    private var weekGenerateButton: some View {
        Button {
            Task { await generateWeeklyPlan() }
        } label: {
            if weekIsWorking {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generando… 3.7 → 3.6 automático")
                }
            } else {
                Label("Generar semana", systemImage: "sparkles")
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(weekIsWorking || !practicePlanPreferences.hasActiveFocus)
    }

    private var practicePlanPreferences: PracticePlanPreferences {
        PracticePlanPreferences(
            instruction: practicePlanInstruction,
            desiredTechniques: practicePlanDesiredTechniques,
            lessons: planFocusPriority(for: .lessons),
            band: planFocusPriority(for: .band),
            desiredTechniquesPriority: planFocusPriority(for: .desiredTechniques),
            weakTechniques: planFocusPriority(for: .weakTechniques),
            enjoyment: planFocusPriority(for: .enjoyment)
        )
    }

    private func planFocusRow(_ focus: PracticePlanFocus) -> some View {
        HStack(spacing: 12) {
            Image(systemName: focus.icon)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(focus.title)
                    .font(.callout.weight(.medium))
                Text(focus.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Picker("Prioridad", selection: planFocusPriorityBinding(for: focus)) {
                ForEach(PracticePlanFocusPriority.allCases) { priority in
                    Text(priority.title).tag(priority.rawValue)
                }
            }
            .labelsHidden()
            .frame(width: 130)
        }
        .padding(.vertical, 3)
    }

    private func planFocusPriority(for focus: PracticePlanFocus) -> PracticePlanFocusPriority {
        let rawValue: Int
        switch focus {
        case .lessons: rawValue = practicePlanLessonsPriority
        case .band: rawValue = practicePlanBandPriority
        case .desiredTechniques: rawValue = practicePlanDesiredTechniquesPriority
        case .weakTechniques: rawValue = practicePlanWeakTechniquesPriority
        case .enjoyment: rawValue = practicePlanEnjoymentPriority
        }
        return PracticePlanFocusPriority(rawValue: rawValue) ?? .normal
    }

    private func planFocusPriorityBinding(for focus: PracticePlanFocus) -> Binding<Int> {
        Binding(
            get: { planFocusPriority(for: focus).rawValue },
            set: { newValue in
                switch focus {
                case .lessons: practicePlanLessonsPriority = newValue
                case .band: practicePlanBandPriority = newValue
                case .desiredTechniques: practicePlanDesiredTechniquesPriority = newValue
                case .weakTechniques: practicePlanWeakTechniquesPriority = newValue
                case .enjoyment: practicePlanEnjoymentPriority = newValue
                }
            }
        )
    }

    private var routineSignals: RoutineSignals {
        RoutineAnalytics.computeSignals(sessions: sessions, milestones: milestones)
    }

    private var routineContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(
                        title: "Revisión de rutina",
                        subtitle: "Patrones de varias semanas, no una tarea puntual — para eso ya está el Asistente de progreso de Hoy"
                    )
                    if routineSignals.hasEnoughData {
                        Text("Racha actual: \(routineSignals.currentStreakDays) días · \(routineSignals.totalSessions) sesiones en las últimas \(routineSignals.windowWeeks) semanas.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Generar revisión de rutina", systemImage: "arrow.triangle.2.circlepath") {
                            Task { await generateRoutineReview() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(routineIsWorking)
                        if routineIsWorking {
                            ProgressView(orchestrator.currentStatus.isEmpty ? "Analizando tu rutina…" : orchestrator.currentStatus)
                        }
                    } else {
                        Text("Todavía no hay suficientes sesiones registradas (mínimo 4) para detectar un patrón real de rutina. Sigue registrando tu práctica y vuelve más adelante.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !routineAdjustments.isEmpty {
                if let source = routineCompletionSource {
                    completionSourceBadge(source)
                }
                Text(routineSummary)
                    .foregroundStyle(.secondary)
                ForEach($routineAdjustments) { $adjustment in
                    CardContainer {
                        HStack(alignment: .top, spacing: 12) {
                            Toggle("", isOn: $adjustment.isSelected)
                                .labelsHidden()
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    if let category = adjustment.category {
                                        StatusPill(text: category.rawValue, tint: category.color)
                                    } else {
                                        StatusPill(text: "Transversal", tint: .gray)
                                    }
                                    Spacer()
                                    StatusPill(text: "\(adjustment.suggestedWeeklyMinutes) min/semana", tint: .green)
                                }
                                Text(adjustment.observation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(adjustment.adjustment)
                                    .font(.callout.weight(.medium))
                                if !adjustment.material.isEmpty {
                                    // "Para esto, toca esto": el ítem concreto de Biblioteca o
                                    // Repertorio con el que aterrizar el ajuste. Validado contra el
                                    // catálogo real en `RoutineCoachService`, nunca inventado.
                                    Label(adjustment.material, systemImage: "music.note.list")
                                        .font(.caption)
                                        .foregroundStyle(.purple)
                                        .padding(.vertical, 4)
                                        .padding(.horizontal, 8)
                                        .background(.purple.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                                }
                                if !adjustment.suggestedDays.isEmpty {
                                    Text(adjustment.suggestedDays.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Button("Guardar revisión y agregar tareas seleccionadas", systemImage: "checkmark.circle.fill") {
                    saveRoutineReview()
                }
                .buttonStyle(.borderedProminent)
                .disabled(routineWasSaved || !routineAdjustments.contains(where: \.isSelected))
            }
            errorView
        }
    }

    private var ladderContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(
                        title: "Escalera de habilidades",
                        subtitle: "Prerrequisitos y criterios medibles"
                    )
                    TextField(
                        "Objetivo: tocar el solo de…, dominar bending afinado…",
                        text: $ladderGoal,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    Button("Construir recorrido", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                        Task { await generateLadder() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(ladderIsWorking || ladderGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if ladderIsWorking {
                        ProgressView(orchestrator.currentStatus.isEmpty ? "Razonando…" : orchestrator.currentStatus)
                    }
                }
            }

            if !ladderSteps.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    if let source = ladderCompletionSource {
                        completionSourceBadge(source)
                    }
                    Text(ladderTitle).font(.title2.bold())
                    Text(ladderRationale).foregroundStyle(.secondary)
                }
                ForEach(ladderSteps) { step in
                    CardContainer {
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(step.order)")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(.indigo, in: Circle())
                            VStack(alignment: .leading, spacing: 7) {
                                Text(step.skill).font(.headline)
                                if !step.currentEvidence.isEmpty {
                                    Text("Punto de partida: \(step.currentEvidence)")
                                        .foregroundStyle(.secondary)
                                }
                                Text(step.practice)
                                Label(step.successCriterion, systemImage: "checkmark.seal")
                                    .font(.callout.bold())
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
                Button("Guardar escalera", systemImage: "square.and.arrow.down") {
                    saveLadder()
                }
                .buttonStyle(.borderedProminent)
                .disabled(ladderWasSaved)
            }
            errorView
        }
    }

    private var videosContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(
                        title: "Videos verificados",
                        subtitle: "Resultados reales de YouTube, no enlaces inventados"
                    )
                    TextField(
                        "Qué quieres trabajar: bending afinado, blues shuffle…",
                        text: $videoGoal,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    Button("Diseñar y buscar", systemImage: "magnifyingglass") {
                        Task { await researchVideos() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(videosAreWorking || videoGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if videosAreWorking {
                        ProgressView(orchestrator.currentStatus.isEmpty ? "Buscando…" : orchestrator.currentStatus)
                    }
                }
            }

            if let videoPlan {
                CardContainer {
                    VStack(alignment: .leading, spacing: 8) {
                        if let source = videoCompletionSource {
                            completionSourceBadge(source)
                        }
                        Label(videoPlan.learningObjective, systemImage: "scope")
                            .font(.headline)
                        Text("Consulta real: \(videoPlan.searchQuery)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !videoPlan.evaluationCriteria.isEmpty {
                            Text("Elige usando este criterio: \(videoPlan.evaluationCriteria)")
                        }
                    }
                }
            }

            ForEach(videoResults) { video in
                CardContainer {
                    HStack(alignment: .top, spacing: 14) {
                        AsyncImage(url: video.thumbnailURL) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.secondary.opacity(0.1)
                        }
                        .frame(width: 150, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 6) {
                            Text(video.title).font(.headline).lineLimit(2)
                            Text(video.channelTitle)
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(video.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Button("Abrir en YouTube", systemImage: "arrow.up.right.square") {
                                if let url = video.videoURL { NSWorkspace.shared.open(url) }
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
            }

            if !videoResults.isEmpty {
                Label("Resultados verificados con YouTube Data API", systemImage: "play.rectangle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.red)
                Button("Guardar investigación", systemImage: "bookmark") {
                    saveVideoResearch()
                }
                .buttonStyle(.borderedProminent)
                .disabled(videosWereSaved)
            }
            errorView
        }
    }

    private var grooveContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardContainer {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(
                        title: "Acompañamiento adaptativo",
                        subtitle: "MIDI compatible con Logic y Superior Drummer"
                    )
                    TextField("Estilo y propósito", text: $grooveRequest, axis: .vertical)
                        .lineLimit(2...4)
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            BPMField(label: "", value: $grooveBPM, range: 30...240)
                            Stepper("\(grooveBars) compases", value: $grooveBars, in: 1...16)
                            Spacer()
                            grooveGenerateButton
                        }
                        VStack(alignment: .leading) {
                            BPMField(label: "", value: $grooveBPM, range: 30...240)
                            Stepper("\(grooveBars) compases", value: $grooveBars, in: 1...16)
                            grooveGenerateButton
                        }
                    }
                    if grooveIsWorking {
                        ProgressView(orchestrator.currentStatus.isEmpty ? "Componiendo…" : orchestrator.currentStatus)
                    }
                }
            }

            if let groove {
                CardContainer {
                    VStack(alignment: .leading, spacing: 12) {
                        if let source = grooveCompletionSource {
                            completionSourceBadge(source)
                        }
                        HStack {
                            VStack(alignment: .leading) {
                                Text(groove.title).font(.title2.bold())
                                Text("\(groove.style) · \(groove.bpm) BPM · \(groove.bars) compases")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusPill(text: "Canal MIDI 10", tint: .orange)
                        }
                        Text(groove.explanation)
                        grooveGrid(groove)
                        Text("K = bombo · S = caja · H = hi-hat")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Guardar MIDI y crear tarea", systemImage: "pianokeys") {
                    saveGroove()
                }
                .buttonStyle(.borderedProminent)
                .disabled(savedGrooveURL != nil)
                if let savedGrooveURL {
                    Button("Mostrar MIDI en Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([savedGrooveURL])
                    }
                }
            }
            errorView
        }
    }

    @ViewBuilder
    private var savedResultsContent: some View {
        let visibleArtifacts = savedArtifacts.filter {
            switch mode {
            case .ladder: $0.kind == .skillLadder
            case .videos: $0.kind == .videoResearch
            case .groove: $0.kind == .groove
            case .routine: $0.kind == .routineReview
            default: false
            }
        }
        if mode == .week, !savedWeeklyPlans.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Planes guardados")
                ForEach(Array(savedWeeklyPlans.prefix(3))) { plan in
                    DisclosureGroup(plan.weekStart.formatted(date: .complete, time: .omitted)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(plan.summary)
                            Text("\(plan.items.count) tareas · \(plan.items.reduce(0) { $0 + $1.minutes }) minutos")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        } else if !visibleArtifacts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Resultados guardados")
                ForEach(Array(visibleArtifacts.prefix(6))) { artifact in
                    DisclosureGroup(artifact.title) {
                        VStack(alignment: .leading, spacing: 8) {
                            if !artifact.body.isEmpty {
                                Text(artifact.body).textSelection(.enabled)
                            }
                            ForEach(artifact.filePaths, id: \.self) { path in
                                Button("Abrir \(URL(fileURLWithPath: path).lastPathComponent)") {
                                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                                }
                            }
                            ForEach(artifact.links, id: \.self) { link in
                                if let url = URL(string: link) {
                                    Button("Abrir enlace", systemImage: "arrow.up.right.square") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                            }
                            Text(artifact.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private var grooveGenerateButton: some View {
        Button("Generar groove", systemImage: "sparkles") {
            Task { await generateGroove() }
        }
        .buttonStyle(.borderedProminent)
        .disabled(grooveIsWorking || grooveRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func grooveGrid(_ groove: GroovePattern) -> some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                Text("")
                ForEach(0..<16, id: \.self) { position in
                    Text("\(position + 1)")
                        .font(.caption2.monospacedDigit())
                        .frame(minWidth: 20)
                }
            }
            grooveRow("K", values: groove.steps.map(\.kick), tint: .blue)
            grooveRow("S", values: groove.steps.map(\.snare), tint: .orange)
            grooveRow("H", values: groove.steps.map(\.hiHat), tint: .green)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func grooveRow(_ label: String, values: [Bool], tint: Color) -> some View {
        GridRow {
            Text(label).font(.caption.bold())
            ForEach(Array(values.enumerated()), id: \.offset) { _, active in
                Circle()
                    .fill(active ? tint : Color.secondary.opacity(0.12))
                    .frame(width: 16, height: 16)
            }
        }
    }

    @ViewBuilder
    private var errorView: some View {
        if !errorMessage.isEmpty {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    private func completionSourceBadge(_ source: AICompletionSource) -> some View {
        let tint: Color = source.provider == .gemini ? .blue : .green
        return Label(
            "Generado con \(source.displayName)",
            systemImage: source.provider == .gemini ? "sparkles" : "desktopcomputer"
        )
        .font(.caption.bold())
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.10), in: Capsule())
    }

    @MainActor
    private func sendChatMessage() async {
        let question = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        ensureConversationSelection()
        guard !question.isEmpty, let conversation = selectedConversation else { return }
        let history = activeChatMessages
        let searchWeb = VirtualTeacherWebSearchIntent.isRequested(in: question)
        chatInput = ""
        errorMessage = ""
        chatIsWorking = true
        chatUsesWeb = searchWeb
        let userMessage = TeacherChatMessage(role: "user", content: question)
        TeacherConversationService.append(userMessage, to: conversation, in: modelContext)
        if history.isEmpty, conversation.isUntitled {
            conversation.title = TeacherConversationService.suggestedTitle(from: question)
        }
        try? modelContext.save()
        defer {
            chatIsWorking = false
            chatUsesWeb = false
        }
        do {
            let context = await learningContext(for: question, includeChatHistory: false)
            // El snapshot RAG del Profesor es el más grande de la app. Gemini pagado lo procesa
            // primero; el orquestador solo recurre al modelo local si la llamada falla.
            // Una búsqueda web, en cambio, usa Gemini sin fallback: responder desde Ollama después
            // de pedir Internet haría parecer que se consultaron fuentes que nunca se abrieron.
            let backend: JSONCompletionBackend
            if searchWeb {
                backend = try orchestrator.paidCloudBackend()
            } else {
                backend = try await orchestrator.backend(for: .heavy)
            }
            let reply = try await VirtualTeacherService.reply(
                question: question,
                history: history,
                context: context,
                backend: backend,
                searchWeb: searchWeb
            )
            let completionSource = await backend.completionSource()
            let assistantMessage = TeacherChatMessage(
                role: "assistant",
                content: reply.answer,
                citations: reply.citations,
                suggestedPractice: reply.suggestedPractice,
                completionSource: completionSource,
                webSources: reply.webSources,
                searchAttributionHTML: reply.searchAttributionHTML
            )
            TeacherConversationService.append(assistantMessage, to: conversation, in: modelContext)
            try? modelContext.save()
            if selectedConversationID == conversation.id {
                followUps = reply.followUps
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearChat() {
        guard let conversation = selectedConversation else { return }
        TeacherConversationService.clear(conversation, messages: chatMessages, in: modelContext)
        followUps = []
        errorMessage = ""
        try? modelContext.save()
    }

    private func ensureConversationSelection() {
        if let selectedConversationID,
           conversations.contains(where: { $0.id == selectedConversationID }) {
            return
        }
        let selected = TeacherConversationService.ensureInitialConversation(
            conversations: conversations,
            messages: chatMessages,
            in: modelContext
        )
        selectedConversationID = selected.id
        try? modelContext.save()
    }

    private func createConversation() {
        let conversation = TeacherConversationService.create(in: modelContext)
        selectedConversationID = conversation.id
        chatInput = ""
        followUps = []
        errorMessage = ""
        try? modelContext.save()
    }

    private func selectConversation(_ conversation: TeacherConversation) {
        selectedConversationID = conversation.id
        chatInput = ""
        followUps = []
        errorMessage = ""
    }

    private func beginRenaming(_ conversation: TeacherConversation) {
        conversationToRenameID = conversation.id
        conversationTitleDraft = conversation.title
        showingRenameConversation = true
    }

    private func renameConversation() {
        guard let id = conversationToRenameID,
              let conversation = conversations.first(where: { $0.id == id }) else { return }
        let title = conversationTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        conversation.title = title
        conversation.updatedAt = .now
        conversationToRenameID = nil
        try? modelContext.save()
    }

    private func deleteConversation() {
        guard let id = conversationToDeleteID,
              let conversation = conversations.first(where: { $0.id == id }) else { return }
        let nextConversation = conversations.first { $0.id != id }
        TeacherConversationService.delete(conversation, messages: chatMessages, in: modelContext)
        if let nextConversation {
            selectedConversationID = nextConversation.id
        } else {
            selectedConversationID = TeacherConversationService.create(in: modelContext).id
        }
        conversationToDeleteID = nil
        followUps = []
        try? modelContext.save()
    }

    @MainActor
    private func generateWeeklyPlan() async {
        weekIsWorking = true
        errorMessage = ""
        weekWasSaved = false
        weekSaveMessage = ""
        weeklyCompletionSource = nil
        defer { weekIsWorking = false }
        do {
            let start = Calendar.current.startOfDay(for: .now)
            let backend = try await orchestrator.backend(for: .heavy)
            let result = try await WeeklyPracticePlannerService.generate(
                weekStart: start,
                days: weekDays,
                dailyMinutes: dailyMinutes,
                context: await learningContext(for: ""),
                preferences: practicePlanPreferences,
                backend: backend
            )
            weeklySummary = result.summary
            weeklyItems = result.items
            weeklyCompletionSource = await backend.completionSource()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveWeeklyPlan() {
        errorMessage = ""
        var addedCount = 0
        var existingCount = 0
        for index in weeklyItems.indices where weeklyItems[index].isSelected {
            let item = weeklyItems[index]
            let resolution = PracticeTaskDeduplication.resolve(
                candidateTitle: item.title, candidateExerciseTitle: item.exerciseTitle,
                candidateSourceKind: .profesor,
                candidateScheduledDate: item.scheduledDate,
                in: modelContext
            )
            if PracticeTaskDeduplication.apply(resolution, in: modelContext) {
                modelContext.insert(PracticeTask(
                    title: item.title,
                    category: item.category,
                    plannedMinutes: item.minutes,
                    sourceTitle: item.sourceTitle,
                    exerciseTitle: item.exerciseTitle,
                    targetBPM: item.targetBPM,
                    priority: practicePlanPreferences.taskPriority(for: item.planningFocus),
                    instructions: item.instructions,
                    scheduledDate: item.scheduledDate,
                    sourceKind: .profesor
                ))
                addedCount += 1
                weeklyItems[index].wasAddedToTasks = true
            } else {
                existingCount += 1
                weeklyItems[index].wasAddedToTasks = false
            }
        }
        modelContext.insert(WeeklyPracticePlan(
            weekStart: Calendar.current.startOfDay(for: .now),
            summary: weeklySummary,
            items: weeklyItems
        ))
        do {
            try modelContext.save()
            _ = try? PracticeCoachCoordinator.reevaluate(
                trigger: .weeklyPlanSaved,
                in: modelContext
            )
            weekSaveMessage = existingCount == 0
                ? "Se agregaron \(addedCount) tareas a la semana."
                : "Se agregaron \(addedCount) tareas; \(existingCount) ya estaban programadas ese día."
            weekWasSaved = true
        } catch {
            errorMessage = "No se pudo guardar el plan semanal: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func generateRoutineReview() async {
        routineIsWorking = true
        errorMessage = ""
        routineWasSaved = false
        routineCompletionSource = nil
        defer { routineIsWorking = false }
        let exercises = LibraryLookup.allExercises(in: modelContext)
        let concepts = LibraryLookup.allConcepts(in: modelContext)
        do {
            let backend = try await orchestrator.backend(for: .medium)
            let result = try await RoutineCoachService.review(
                signals: routineSignals,
                exercises: exercises,
                songs: songs,
                concepts: concepts,
                backend: backend
            )
            routineSummary = result.summary
            routineAdjustments = result.adjustments
            routineCompletionSource = await backend.completionSource()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Guarda todo en un solo paso atómico (mismo patrón que `saveWeeklyPlan()`): crea las tareas de
    /// los ajustes seleccionados Y archiva la revisión completa a la vez, en vez de dos botones
    /// separados — evita el estado a medio guardar de "agregué tareas pero nunca guardé la revisión,
    /// y el indicador de días sin revisar queda desactualizado en silencio".
    private func saveRoutineReview() {
        for adjustment in routineAdjustments where adjustment.isSelected {
            let category = adjustment.category ?? .technique
            // El material concreto viaja a las instrucciones de la tarea: sin esto, la tarea creada
            // vuelve a quedar en un consejo genérico y se pierde el "para esto, toca esto".
            let instructions = adjustment.material.isEmpty
                ? adjustment.observation
                : "\(adjustment.observation)\n\nMaterial: \(adjustment.material)"
            let resolution = PracticeTaskDeduplication.resolve(
                candidateTitle: adjustment.adjustment, candidateSourceKind: .profesor, in: modelContext
            )
            let shouldInsert = PracticeTaskDeduplication.apply(resolution, in: modelContext)
            if adjustment.suggestedDays.isEmpty {
                // Sin días puntuales, la tarea es una sola — `suggestedWeeklyMinutes` es un TOTAL
                // semanal (rango 15-300) y no una duración de sesión; taparlo en 120 evita crear una
                // tarea de hasta 5 horas cuando el ajuste es transversal.
                if shouldInsert {
                    modelContext.insert(PracticeTask(
                        title: adjustment.adjustment,
                        category: category,
                        plannedMinutes: min(120, max(5, adjustment.suggestedWeeklyMinutes)),
                        priority: 1,
                        instructions: instructions,
                        sourceKind: .profesor
                    ))
                }
            } else if shouldInsert {
                let minutesPerDay = max(5, adjustment.suggestedWeeklyMinutes / adjustment.suggestedDays.count)
                for dayName in adjustment.suggestedDays {
                    modelContext.insert(PracticeTask(
                        title: adjustment.adjustment,
                        category: category,
                        plannedMinutes: minutesPerDay,
                        priority: 1,
                        instructions: instructions,
                        scheduledDate: nextDate(forWeekdayName: dayName),
                        sourceKind: .profesor
                    ))
                }
            }
        }
        let data = try? JSONEncoder().encode(routineAdjustments)
        modelContext.insert(AIArtifact(
            kind: .routineReview,
            title: "Revisión de rutina",
            body: routineSummary,
            metadataJSON: data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        ))
        _ = try? PracticeCoachCoordinator.reevaluate(
            trigger: .routineReviewSaved,
            in: modelContext
        )
        routineWasSaved = true
    }

    /// Próxima ocurrencia de ese día de la semana desde hoy (0-6 días adelante) — `suggestedDays`
    /// llega como nombres en español, no como `Calendar.component(.weekday)` (1=domingo).
    private func nextDate(forWeekdayName name: String, from start: Date = .now) -> Date {
        let calendar = Calendar.current
        guard let index = RoutineCoachService.validDays.firstIndex(of: name) else { return start }
        let targetWeekday = index == 6 ? 1 : index + 2
        let todayWeekday = calendar.component(.weekday, from: start)
        let diff = (targetWeekday - todayWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: diff, to: calendar.startOfDay(for: start)) ?? start
    }

    @MainActor
    private func generateLadder() async {
        ladderIsWorking = true
        ladderWasSaved = false
        errorMessage = ""
        ladderCompletionSource = nil
        defer { ladderIsWorking = false }
        do {
            let backend = try await orchestrator.backend(for: .heavy)
            let result = try await SkillLadderService.generate(
                goal: ladderGoal,
                context: await learningContext(for: ladderGoal),
                backend: backend
            )
            ladderTitle = result.title
            ladderRationale = result.rationale
            ladderSteps = result.steps
            ladderCompletionSource = await backend.completionSource()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveLadder() {
        let data = try? JSONEncoder().encode(ladderSteps)
        modelContext.insert(AIArtifact(
            kind: .skillLadder,
            title: ladderTitle,
            body: ladderRationale,
            sourceName: ladderGoal,
            metadataJSON: data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        ))
        ladderWasSaved = true
    }

    @MainActor
    private func researchVideos() async {
        videosAreWorking = true
        videosWereSaved = false
        errorMessage = ""
        videoCompletionSource = nil
        defer { videosAreWorking = false }
        do {
            let backend = try await orchestrator.backend(for: .light)
            let plan = try await VideoResearchService.plan(
                goal: videoGoal,
                context: await learningContext(for: videoGoal),
                backend: backend
            )
            let apiKey = KeychainStore.read(account: "youtube-data-api-key")
            videoResults = try await YouTubeSearchService.search(
                query: plan.searchQuery,
                apiKey: apiKey
            )
            videoPlan = plan
            videoCompletionSource = await backend.completionSource()
            if videoResults.isEmpty {
                errorMessage = "YouTube no devolvió videos para \"\(plan.searchQuery)\". Prueba reformular el objetivo con otras palabras."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveVideoResearch() {
        guard let videoPlan else { return }
        let data = try? JSONEncoder().encode(videoResults)
        modelContext.insert(AIArtifact(
            kind: .videoResearch,
            title: "Videos · \(videoGoal)",
            body: """
            Objetivo: \(videoPlan.learningObjective)
            Criterio: \(videoPlan.evaluationCriteria)
            """,
            sourceName: videoPlan.searchQuery,
            links: videoResults.compactMap { $0.videoURL?.absoluteString },
            metadataJSON: data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        ))
        videosWereSaved = true
    }

    @MainActor
    private func generateGroove() async {
        grooveIsWorking = true
        savedGrooveURL = nil
        errorMessage = ""
        grooveCompletionSource = nil
        defer { grooveIsWorking = false }
        do {
            let backend = try await orchestrator.backend(for: .light)
            groove = try await GrooveGeneratorService.generate(
                request: grooveRequest,
                bpm: grooveBPM,
                bars: grooveBars,
                context: await learningContext(for: grooveRequest),
                backend: backend
            )
            grooveCompletionSource = await backend.completionSource()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveGroove() {
        guard let groove else { return }
        do {
            let url = try GrooveGeneratorService.saveMIDI(groove)
            modelContext.insert(AIArtifact(
                kind: .groove,
                title: groove.title,
                body: groove.explanation,
                sourceName: groove.style,
                filePaths: [url.path]
            ))
            let grooveTaskTitle = "Practicar con \(groove.title)"
            let resolution = PracticeTaskDeduplication.resolve(
                candidateTitle: grooveTaskTitle, candidateExerciseTitle: groove.title,
                candidateSourceKind: .profesor, in: modelContext
            )
            if PracticeTaskDeduplication.apply(resolution, in: modelContext) {
                modelContext.insert(PracticeTask(
                    title: grooveTaskTitle,
                    category: .rhythm,
                    plannedMinutes: 15,
                    sourceTitle: "Groove IA",
                    exerciseTitle: groove.title,
                    targetBPM: groove.bpm,
                    instructions: "\(groove.explanation) Carga el MIDI en Superior Drummer o Logic Pro.",
                    sourceKind: .profesor
                ))
            }
            savedGrooveURL = url
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// `includeChatHistory` se desactiva solo para el chat del Profesor: `VirtualTeacherService.reply`
    /// ya arma su propia sección de conversación reciente a partir de `history`, así que incluirla
    /// también acá duplicaría los mismos mensajes en el prompt. El resto de las herramientas (Semana,
    /// Escalera, Videos, Groove) sí se benefician de ver la conversación reciente con el Profesor.
    /// Es `async` porque los pasajes textuales de los libros salen del servicio local `book-rag`
    /// (ver `BookPassageService`), que necesita una llamada HTTP para vectorizar la pregunta.
    /// `searchQuietly` no lanza: si el servicio o Ollama están apagados devuelve `[]` y el contexto
    /// queda exactamente como era antes de existir el índice, sin romper ninguna herramienta.
    private func learningContext(
        for query: String,
        includeChatHistory: Bool = true
    ) async -> LearningContextSnapshot {
        // El catálogo se lee antes de la llamada HTTP, mientras seguimos en el hilo principal.
        let exercises = LibraryLookup.allExercises(in: modelContext)
        let concepts = LibraryLookup.allConcepts(in: modelContext)
        let passages = await BookPassageService().searchQuietly(query: query)
        return LearningContextBuilder.build(
            query: query,
            lessons: lessons,
            skills: skills,
            exercises: exercises,
            concepts: concepts,
            books: books,
            songs: songs,
            sessions: sessions,
            tasks: tasks,
            chatMessages: includeChatHistory ? activeChatMessages : [],
            evidence: evidence,
            bands: bands,
            musicalTastes: musicalTastes,
            bookPassages: passages,
            coachDecision: coachStates.first?.currentDecision
        )
    }
}

/// Google entrega este HTML/CSS como parte de `searchEntryPoint` y exige mostrarlo sin alterarlo
/// junto a las respuestas grounded. El web view no tiene scroll propio para integrarse en la burbuja.
private struct GoogleSearchAttributionView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.underPageBackgroundColor = .clear
        view.enclosingScrollView?.hasVerticalScroller = false
        view.enclosingScrollView?.hasHorizontalScroller = false
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        view.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML = ""

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }
    }
}
