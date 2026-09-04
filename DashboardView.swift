import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigator.self) private var navigator
    @Query(sort: \PracticeSession.date, order: .reverse) private var sessions: [PracticeSession]
    @Query(sort: \PracticeTask.priority) private var tasks: [PracticeTask]
    @Query(sort: \GuitarLesson.date, order: .reverse) private var lessons: [GuitarLesson]
    @Query(sort: \Song.title) private var songs: [Song]
    @Query(sort: \Instrument.name) private var instruments: [Instrument]
    @AppStorage("weeklyGoalMinutes") private var weeklyGoal = 240
    @AppStorage("dailyPracticeGoalMinutes") private var dailyGoal = 45
    @AppStorage("hasCompletedSkillAssessment") private var hasCompletedAssessment = false
    @AppStorage(SkillAudioAssessmentSchedule.completionKey) private var hasCompletedAudioAssessment = false
    @AppStorage(SkillAudioAssessmentSchedule.lastCompletedAtKey) private var lastAudioAssessmentAt = 0.0
    @AppStorage("hasSeenPracticeOnboarding") private var hasSeenOnboarding = false
    @AppStorage("defaultPracticeInstrumentName") private var defaultInstrumentName = ""

    @State private var showingSession = false
    @State private var showingTimer = false
    @State private var timerTaskID: UUID?
    @State private var timerPlanTaskIDs: [UUID] = []
    @State private var showingAssessment = false
    @State private var showingAudioAssessment = false
    @State private var showingOnboarding = false
    @State private var openAssessmentAfterOnboarding = false
    @State private var showingNewTask = false
    @State private var rebalancedTaskCount = 0

    private var weeklyMinutes: Int { PracticeAnalytics.totalMinutesThisWeek(sessions) }
    private var practicedDays: Int { PracticeAnalytics.practicedDaysThisWeek(sessions) }
    private var todayMinutes: Int { PracticeAnalytics.totalMinutesToday(sessions) }
    private var todaySessions: [PracticeSession] { PracticeAnalytics.sessionsToday(sessions) }
    private var dailyPlan: DailyPracticePlan {
        DailyPracticePlanner.makePlan(tasks: tasks, budgetMinutes: dailyGoal)
    }
    private var todayTasks: [PracticeTask] {
        dailyPlan.tasks
    }
    private var nextLesson: GuitarLesson? {
        lessons
            .compactMap { lesson -> (GuitarLesson, Date)? in
                guard let date = lesson.nextLessonDate, date >= Calendar.current.startOfDay(for: .now) else { return nil }
                return (lesson, date)
            }
            .sorted { $0.1 < $1.1 }
            .first?.0
    }

    private var audioAssessmentIsDue: Bool {
        guard hasCompletedAudioAssessment else { return true }
        let completedAt = lastAudioAssessmentAt > 0
            ? Date(timeIntervalSince1970: lastAudioAssessmentAt)
            : nil
        return SkillAudioAssessmentSchedule.isMonthlyReviewDue(
            hasCompletedInitial: hasCompletedAudioAssessment,
            lastCompletedAt: completedAt
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                    practicePlan
                            .frame(maxWidth: .infinity)
                        VStack(spacing: 18) {
                            teacherCard
                            ProgressCoachCard(sessions: sessions, tasks: tasks)
                        }
                        .frame(width: 300)
                    }
                    VStack(spacing: 18) {
                        practicePlan
                        teacherCard
                        ProgressCoachCard(sessions: sessions, tasks: tasks)
                    }
                }

                practicedToday
                metrics

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        weeklyChart
                        categoryChart
                            .frame(width: 390)
                    }
                    VStack(spacing: 18) {
                        weeklyChart
                        categoryChart
                    }
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showingSession) {
            NewSessionView()
                .frame(minWidth: 540, idealWidth: 660, minHeight: 540)
        }
        .sheet(isPresented: $showingNewTask) {
            NewTaskView()
                .frame(minWidth: 480, idealWidth: 560, minHeight: 480)
        }
        .sheet(isPresented: $showingTimer) {
            PracticeTimerView(initialTaskID: timerTaskID, initialPlanTaskIDs: timerPlanTaskIDs)
                .frame(minWidth: 500, idealWidth: 580, minHeight: 540)
        }
        .sheet(isPresented: $showingAssessment) {
            SkillAssessmentView()
                .frame(minWidth: 560, idealWidth: 680, minHeight: 540)
        }
        .sheet(isPresented: $showingAudioAssessment) {
            SkillAudioAssessmentView(mode: hasCompletedAudioAssessment ? .monthly : .initial)
                .frame(minWidth: 620, idealWidth: 760, minHeight: 600)
        }
        .sheet(isPresented: $showingOnboarding, onDismiss: {
            hasSeenOnboarding = true
            if openAssessmentAfterOnboarding {
                openAssessmentAfterOnboarding = false
                showingAssessment = true
            }
        }) {
            PracticeOnboardingView(
                dailyGoal: $dailyGoal,
                weeklyGoal: $weeklyGoal,
                defaultInstrumentName: $defaultInstrumentName,
                instruments: instruments,
                onContinue: {
                    hasSeenOnboarding = true
                    showingOnboarding = false
                },
                onAssessment: {
                    hasSeenOnboarding = true
                    openAssessmentAfterOnboarding = true
                    showingOnboarding = false
                }
            )
            .frame(minWidth: 520, idealWidth: 580, minHeight: 480)
        }
        .onChange(of: navigator.pendingAction) { _, _ in consumePendingAction() }
        .onAppear {
            consumePendingAction()
            if hasCompletedAssessment {
                hasSeenOnboarding = true
            } else if !hasSeenOnboarding {
                showingOnboarding = true
            }
            refreshReminders()
            ensureDailyRepertoire()
            rebalancePracticePlan()
        }
        // Cada sesión nueva puede correr el horario habitual y, sobre todo, deja sin sentido el
        // aviso de hoy.
        .onChange(of: sessions.count) { _, _ in
            refreshReminders()
            ensureDailyRepertoire()
        }
        .onChange(of: tasks.count) { _, _ in
            ensureDailyRepertoire()
            rebalancePracticePlan()
        }
        .onChange(of: songs.count) { _, _ in ensureDailyRepertoire() }
        .onChange(of: dailyGoal) { _, _ in rebalancePracticePlan() }
    }

    /// Reprograma los avisos con el historial al día. No hace nada si el usuario no los activó en
    /// Configuración; las fechas se copian antes del `Task` porque los modelos de SwiftData no
    /// cruzan a otro contexto de concurrencia.
    private func refreshReminders() {
        guard PracticeReminderService.isEnabled else { return }
        let dates = sessions.map(\.date)
        Task { await PracticeReminderService.refresh(sessionDates: dates) }
    }

    /// Si hoy todavía no hubo repertorio ni existe una tarea vencida, incorpora la canción menos
    /// practicada. Si esa canción ya tenía una revisión futura, la adelanta en vez de duplicarla.
    /// El planificador luego la reserva, incluso si la respuesta semanal de IA no la incluyó.
    private func ensureDailyRepertoire() {
        guard !DailyRepertoirePlanner.isSatisfiedToday(tasks: tasks, sessions: sessions),
              let song = DailyRepertoirePlanner.recommendedSong(songs: songs, sessions: sessions)
        else { return }

        let today = Calendar.current.startOfDay(for: .now)
        let pendingTask = tasks
            .filter { !$0.isCompleted && $0.category == .repertoire && $0.sourceID == song.id }
            .sorted(by: { $0.scheduledDate < $1.scheduledDate })
            .first
        if let pending = pendingTask {
            pending.scheduledDate = today
            pending.plannedMinutes = DailyRepertoirePlanner.plannedMinutes(for: song)
        } else {
            let duration = song.formattedDuration.map { " (\($0))" } ?? ""
            modelContext.insert(PracticeTask(
                title: "Repertorio diario · \(song.title)",
                category: .repertoire,
                plannedMinutes: DailyRepertoirePlanner.plannedMinutes(for: song),
                sourceTitle: song.artist,
                exerciseTitle: song.title,
                targetBPM: song.targetTempo,
                priority: 0,
                instructions: "Haz al menos una pasada completa\(duration) y registra cuántas pasadas hiciste. Si aparece un fallo, aísla la sección antes de volver a tocarla entera.",
                repertoireTaskMode: .guided,
                scheduledDate: today,
                sourceKind: .repertoire,
                sourceID: song.id
            ))
        }
        try? modelContext.save()
    }

    /// Reparte el excedente en días futuros en vez de convertir todas las tareas atrasadas en una
    /// deuda imposible para hoy. El cálculo es determinístico y respeta lo que ya estaba agendado.
    private func rebalancePracticePlan() {
        let plan = DailyPracticePlanner.makePlan(tasks: tasks, budgetMinutes: dailyGoal)
        let assignments = DailyPracticePlanner.redistributedDates(
            for: plan.deferred,
            among: tasks,
            budgetMinutes: dailyGoal
        )
        guard !assignments.isEmpty else { return }
        for task in plan.deferred {
            if let date = assignments[task.id] { task.scheduledDate = date }
        }
        rebalancedTaskCount = assignments.count
        try? modelContext.save()
    }

    /// Ejecuta lo que pidió el menú (⌘N / ⌘R) y lo limpia, para que volver al Dashboard más tarde no
    /// vuelva a abrir la misma hoja.
    private func consumePendingAction() {
        guard let action = navigator.pendingAction else { return }
        navigator.pendingAction = nil
        switch action {
        case .newSession: showingSession = true
        case .startPractice:
            timerTaskID = nil
            timerPlanTaskIDs = []
            showingTimer = true
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                dashboardTitle
                Spacer()
                dashboardActions
            }
            VStack(alignment: .leading, spacing: 10) {
                dashboardTitle
                dashboardActions
            }
        }
    }

    private var dashboardTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hoy")
                .font(.largeTitle.bold())
            Text(Date.now.formatted(
                Date.FormatStyle(date: .complete, time: .omitted, locale: Locale(identifier: "es_CL"))
            ))
                .foregroundStyle(.secondary)
        }
    }

    private var dashboardActions: some View {
        HStack {
            if audioAssessmentIsDue {
                Button("Evaluación práctica", systemImage: "waveform.badge.mic") {
                    showingAudioAssessment = true
                }
                .accessibilityIdentifier("dashboard.audioAssessment")
            }
            Button("Registrar sesión", systemImage: "plus") { showingSession = true }
            Button("Iniciar práctica", systemImage: "play.fill") {
                timerTaskID = nil
                timerPlanTaskIDs = []
                showingTimer = true
            }
                .buttonStyle(.borderedProminent)
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
            MetricCard(title: "Minutos hoy", value: "\(todayMinutes)", detail: todaySessions.isEmpty ? "sin práctica todavía" : "\(todaySessions.count) sesión\(todaySessions.count == 1 ? "" : "es")", icon: "clock.arrow.circlepath", tint: .teal)
            MetricCard(title: "Minutos esta semana", value: "\(weeklyMinutes)", detail: "de \(weeklyGoal) minutos", icon: "clock.fill", tint: .blue)
            MetricCard(title: "Días practicados", value: "\(practicedDays)/7", detail: "esta semana", icon: "calendar", tint: .green)
            MetricCard(title: "Próxima clase", value: nextLesson?.nextLessonDate?.formatted(date: .abbreviated, time: .shortened) ?? "Sin fecha", detail: nextLesson?.teacherName ?? "Registra tu próxima clase", icon: "graduationcap.fill", tint: .purple)
            MetricCard(title: "Cumplimiento", value: "\(min(100, Int((Double(weeklyMinutes) / Double(max(weeklyGoal, 1))) * 100)))%", detail: "objetivo semanal", icon: "target", tint: .orange)
        }
    }

    private var practicePlan: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    SectionHeader(
                        title: "Plan de práctica de hoy",
                        subtitle: "\(dailyPlan.plannedMinutes) de \(dailyGoal) min"
                    )
                    Button { showingNewTask = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .help("Agregar tarea")
                    Spacer()
                    let guidedTasks = todayTasks.filter { !$0.isCompleted && !$0.isDailyFretboardTraining }
                    if !guidedTasks.isEmpty {
                        Button("Iniciar plan", systemImage: "play.fill") {
                            timerTaskID = guidedTasks.first?.id
                            timerPlanTaskIDs = guidedTasks.map(\.id)
                            showingTimer = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityIdentifier("dashboard.startDailyPlan")
                    }
                }

                if rebalancedTaskCount > 0 {
                    Label(
                        "Se reprogramaron \(rebalancedTaskCount) tarea\(rebalancedTaskCount == 1 ? "" : "s") para respetar tu presupuesto diario.",
                        systemImage: "calendar.badge.clock"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if todayTasks.isEmpty {
                    EmptyStateView(icon: "checklist", title: "Sin tareas", message: "Agrega una tarea nueva, o desde una clase o la biblioteca.")
                        .frame(height: 260)
                } else {
                    ForEach(todayTasks) { task in
                        TaskRow(
                            task: task,
                            onSelectTask: { openTask(task) },
                            onOpenSource: task.sourceKind == .manual ? nil : {
                                navigator.go(to: task.sourceKind, id: task.sourceID)
                            },
                            onStartTask: {
                                if task.isDailyFretboardTraining {
                                    navigator.selection = .fretboard
                                } else {
                                    timerTaskID = task.id
                                    timerPlanTaskIDs = []
                                    showingTimer = true
                                }
                            }
                        )
                        if task.id != todayTasks.last?.id { Divider() }
                    }
                }
            }
        }
    }

    /// Seleccionar el nombre de una tarea abre su contenido real (canción, ejercicio, concepto,
    /// clase, etc.). Las tareas manuales no tienen un origen al que volver, por lo que entran al
    /// cronómetro con esa tarea ya elegida.
    private func openTask(_ task: PracticeTask) {
        if task.sourceKind.targetSection != nil {
            navigator.go(to: task.sourceKind, id: task.sourceID)
        } else {
            timerTaskID = task.id
            timerPlanTaskIDs = []
            showingTimer = true
        }
    }

    private var practicedToday: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "Practicado hoy",
                    subtitle: todaySessions.isEmpty ? nil : "\(todayMinutes) min en total"
                )

                if todaySessions.isEmpty {
                    Text("Todavía no registras práctica hoy. Este contador vuelve a cero cada día.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(todaySessions) { session in
                        HStack(spacing: 12) {
                            Image(systemName: session.category.icon)
                                .foregroundStyle(session.category.color)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.exerciseTitle.isEmpty ? session.category.rawValue : session.exerciseTitle)
                                    .fontWeight(.medium)
                                if !session.sourceTitle.isEmpty {
                                    Text(session.sourceTitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if session.rhythmicFigure.isSpecified {
                                StatusPill(text: session.rhythmicFigure.displayName, tint: session.category.color)
                                    .fixedSize()
                            }
                            Text(session.formattedDuration)
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if session.id != todaySessions.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var teacherCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Indicaciones del profesor")
                if let lesson = lessons.first {
                    Text(lesson.teacherNotes)
                        .font(.callout)
                    if !lesson.nextObjective.isEmpty {
                        Divider()
                        Text("Próximo objetivo")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(lesson.nextObjective)
                            .font(.callout)
                    }
                    Button("Ver en Clases", systemImage: TaskSourceKind.clases.icon) {
                        navigator.go(to: .clases, id: lesson.id)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                } else {
                    Text("Registra una clase para conectar las indicaciones de tu profesor con tu plan diario.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var weeklyChart: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Progreso semanal", subtitle: "Objetivo: \(weeklyGoal) min")
                Chart(PracticeAnalytics.dailyPoints(sessions)) { point in
                    BarMark(
                        x: .value("Día", point.date, unit: .day),
                        y: .value("Minutos", point.minutes)
                    )
                    .foregroundStyle(.blue.gradient)
                    .cornerRadius(5)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .frame(height: 230)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Progreso semanal")
                .accessibilityValue("\(weeklyMinutes) minutos practicados en \(practicedDays) días; objetivo de \(weeklyGoal) minutos")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var categoryChart: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Distribución por área")
                let points = PracticeAnalytics.categoryPoints(sessions)
                if points.isEmpty {
                    EmptyStateView(icon: "chart.pie", title: "Sin datos", message: "Registra una sesión esta semana.")
                        .frame(height: 230)
                } else {
                    Chart(points) { point in
                        SectorMark(
                            angle: .value("Minutos", point.minutes),
                            innerRadius: .ratio(0.58),
                            angularInset: 2
                        )
                        .foregroundStyle(by: .value("Área", point.category.rawValue))
                    }
                    // `.foregroundStyle(point.category.color)` (antes) le daba color a cada sector
                    // pero no le daba a Charts ninguna serie de la que armar una leyenda real — por
                    // eso `.chartLegend` no mostraba nada. `foregroundStyle(by:)` + esta escala
                    // explícita (mismos colores que `PracticeCategory.color` en el resto de la app)
                    // hacen que la leyenda sí aparezca y coincida exactamente.
                    .chartForegroundStyleScale(
                        domain: PracticeCategory.allCases.map(\.rawValue),
                        range: PracticeCategory.allCases.map(\.color)
                    )
                    .chartLegend(position: .bottom, alignment: .leading)
                    .frame(height: 230)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Distribución por área")
                    .accessibilityValue(
                        points.map { "\($0.category.rawValue): \($0.minutes) minutos" }
                            .joined(separator: ", ")
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Primera experiencia corta: deja la app utilizable en menos de dos minutos y presenta el Test
/// Integral como una decisión, no como una barrera modal obligatoria antes de ver el plan diario.
private struct PracticeOnboardingView: View {
    @Binding var dailyGoal: Int
    @Binding var weeklyGoal: Int
    @Binding var defaultInstrumentName: String
    let instruments: [Instrument]
    let onContinue: () -> Void
    let onAssessment: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "guitars.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(PracticeTheme.accent)
                    .frame(width: 62, height: 62)
                    .background(PracticeTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Prepara tu espacio de práctica")
                        .font(.largeTitle.bold())
                    Text("Define un presupuesto realista. Después entrarás directo al plan de hoy; todo lo demás puede esperar.")
                        .foregroundStyle(.secondary)
                }
            }

            Form {
                Section("Tiempo disponible") {
                    Stepper("Por día: \(dailyGoal) minutos", value: $dailyGoal, in: 15...180, step: 5)
                    Stepper("Por semana: \(weeklyGoal) minutos", value: $weeklyGoal, in: 30...2000, step: 30)
                }

                if !instruments.isEmpty {
                    Section("Instrumento habitual") {
                        Picker("Instrumento", selection: $defaultInstrumentName) {
                            Text("Elegir cada vez").tag("")
                            ForEach(instruments) { instrument in
                                Text(instrument.name).tag(instrument.name)
                            }
                        }
                    }
                }

                Section("Diagnóstico opcional") {
                    Text("El Test Integral construye una estimación inicial detallada, pero es largo. Puedes practicar ahora y completarlo por partes cuando te resulte útil.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Abrir Test Integral", systemImage: "checklist", action: onAssessment)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Ir a mi plan", systemImage: "arrow.right", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
    }
}

struct TaskRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var task: PracticeTask
    var onSelectTask: (() -> Void)? = nil
    var onOpenTimer: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onOpenSource: (() -> Void)? = nil
    var onStartTask: (() -> Void)? = nil
    @State private var showingCompletion = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if task.isCompleted {
                    task.isCompleted = false
                    task.completedAt = nil
                } else {
                    showingCompletion = true
                }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isCompleted ? .green : task.category.color)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Marcar \(task.title) como pendiente" : "Completar \(task.title)")

            Image(systemName: task.category.icon)
                .foregroundStyle(task.category.color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .fontWeight(.medium)
                    .strikethrough(task.isCompleted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !task.sourceTitle.isEmpty {
                    Text([task.sourceTitle, task.exerciseTitle].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if task.isCompleted {
                    Text(task.lastResult.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if task.isDiagnosticChallenge, let dimension = task.evidenceDimension {
                    Label("Comprobación: \(dimension.rawValue)", systemImage: dimension.icon)
                        .font(.caption)
                        .foregroundStyle(dimension.color)
                    if !task.successCriterion.isEmpty {
                        Text(task.successCriterion)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                if let taskModeLabel = task.taskModeLabel {
                    Label("Modo: \(taskModeLabel)", systemImage: task.taskModeIcon)
                        .font(.caption)
                        .foregroundStyle(task.category.color)
                        .lineLimit(1)
                    if !task.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(task.instructions)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .layoutPriority(1)
            .contentShape(Rectangle())
            .onTapGesture { onSelectTask?() }
            .accessibilityAddTraits(onSelectTask == nil ? [] : .isButton)
            .accessibilityAction(named: "Abrir \(task.title)") { onSelectTask?() }
            Spacer(minLength: 8)
            if task.category.supportsRhythmicFigure {
                if task.isCompleted {
                    if task.rhythmicFigure.isSpecified {
                        StatusPill(text: task.rhythmicFigure.displayName, tint: task.category.color)
                            .fixedSize()
                    }
                } else {
                    Menu {
                        ForEach(RhythmicFigure.allCases) { figure in
                            Button {
                                task.rhythmicFigure = figure
                            } label: {
                                if task.rhythmicFigure == figure {
                                    Label(figure.displayName, systemImage: "checkmark")
                                } else {
                                    Text(figure.displayName)
                                }
                            }
                        }
                    } label: {
                        StatusPill(
                            text: task.rhythmicFigure.isSpecified ? task.rhythmicFigure.displayName : "Elegir figura…",
                            tint: task.category.color
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Elegir figura o subdivisión rítmica")
                }
            }
            if task.targetBPM > 0 {
                StatusPill(text: "\(task.targetBPM) BPM", tint: task.category.color)
                    .fixedSize()
            }
            Text("\(task.plannedMinutes) min")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
            if let onStartTask, !task.isCompleted {
                Button("Iniciar tarea", systemImage: "play.fill") { onStartTask() }
                    .buttonStyle(.bordered)
                    .tint(task.category.color)
                    .controlSize(.small)
                    .fixedSize()
            }
            if let onOpenSource {
                Button { onOpenSource() } label: {
                    Image(systemName: task.sourceKind.icon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(task.sourceKind.label)
                .accessibilityLabel("Abrir origen: \(task.sourceKind.label)")
            }
            if let onOpenTimer {
                Button { onOpenTimer() } label: {
                    Image(systemName: "timer")
                }
                .buttonStyle(.plain)
                .foregroundStyle(task.category.color)
                .help("Cronometrar esta tarea")
                .accessibilityLabel("Cronometrar \(task.title)")
            }
        }
        .opacity(task.isCompleted ? 0.55 : 1)
        .contextMenu {
            if let onDelete {
                Button("Eliminar", systemImage: "trash", role: .destructive) { onDelete() }
            }
        }
        .sheet(isPresented: $showingCompletion) {
            TaskCompletionView(task: task)
                .frame(minWidth: 460, idealWidth: 520, minHeight: 500)
        }
    }
}

/// Evaluar antes de cerrar evita que "marcar hecha" se interprete como "dominada". La misma
/// estructura se usa en el cronómetro y al registrar una sesión manual.
private struct TaskCompletionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var task: PracticeTask

    @State private var result = PracticeResult.learning
    @State private var endBPM = 0
    @State private var correctRepetitions = 0
    @State private var tensionRating = 1
    @State private var practiceContext = PracticeApplicationContext.isolated
    @State private var wasColdCheck = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Qué cambió") {
                    Picker("Resultado", selection: $result) {
                        ForEach(PracticeResult.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    Text(result.guidance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    BPMField(label: "BPM final:", value: $endBPM)
                    Stepper(
                        "Repeticiones correctas seguidas: \(correctRepetitions)",
                        value: $correctRepetitions,
                        in: 0...10
                    )
                }

                Section("Calidad") {
                    Stepper("Tensión: \(tensionRating)/5", value: $tensionRating, in: 1...5)
                    Picker("Comprobado", selection: $practiceContext) {
                        ForEach(PracticeApplicationContext.allCases) { context in
                            Text(context.rawValue).tag(context)
                        }
                    }
                    Toggle("Fue una prueba en frío", isOn: $wasColdCheck)
                    Text("Una prueba en frío se hace antes de volver a estudiar el pasaje. Solo una ejecución limpia, relajada y repetible amplía la revisión.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if tensionRating >= 4 {
                        Label("No aumentes el tempo. Revisa postura, agarre y descanso antes de repetir.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Evaluar \(task.title)")
            .onAppear {
                endBPM = task.targetBPM
                result = task.lastResult
                practiceContext = task.lastPracticeContext
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar resultado") {
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
                        _ = try? PracticeCoachCoordinator.reevaluate(
                            trigger: .taskCompleted,
                            in: modelContext
                        )
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

private struct ProgressCoachCard: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SkillTopic.name) private var skills: [SkillTopic]
    @Query(sort: \GuitarLesson.date, order: .reverse) private var lessons: [GuitarLesson]
    @Query(sort: \StudioAsset.name) private var equipment: [StudioAsset]
    @Query(sort: \Instrument.name) private var instruments: [Instrument]
    @Query private var coachStates: [PracticeCoachStateRecord]

    let sessions: [PracticeSession]
    let tasks: [PracticeTask]

    @StateObject private var orchestrator = AIOrchestrator()
    @State private var errorMessage = ""
    @State private var showingTimer = false
    @State private var timerTaskID: UUID?
    @State private var showingChangeConfirmation = false
    @State private var chatHistory: [ProgressChatExchange] = []
    @State private var chatInput = ""
    @State private var isChatLoading = false
    @State private var chatErrorMessage = ""

    private var decision: PracticeCoachDecision? { coachStates.first?.currentDecision }
    private var currentChangeIsApplied: Bool { coachStates.first?.hasAppliedCurrentChange == true }

    private var localRecommendation: String {
        PracticeAnalytics.recommendation(sessions: sessions, tasks: tasks)
    }

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Asistente de progreso", systemImage: "sparkles")
                        .font(.headline)
                    Spacer()
                }

                if let decision {
                    VStack(alignment: .leading, spacing: 8) {
                        StatusPill(text: decision.priority.title, tint: decision.priority == .safety ? .orange : .purple)
                        Text(decision.title)
                            .font(.callout.weight(.semibold))
                        Text(decision.nextAction)
                            .font(.callout)
                        Text(decision.reason)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Divider()
                        if !decision.exerciseTitle.isEmpty {
                            Text(decision.exerciseTitle)
                                .font(.callout.weight(.medium))
                        }
                        if !decision.sourceTitle.isEmpty {
                            Text(decision.sourceTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            if decision.targetBPM > 0 {
                                StatusPill(text: "\(decision.targetBPM) BPM", tint: .blue)
                            }
                            if decision.suggestedMinutes > 0 {
                                StatusPill(text: "\(decision.suggestedMinutes) min", tint: .green)
                            }
                        }

                        if !decision.evidence.isEmpty {
                            DisclosureGroup("Evidencia") {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(decision.evidence) { item in
                                        Text("\(item.label): \(item.detail)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(.top, 4)
                            }
                            .font(.caption.weight(.semibold))
                        }

                        if decision.change.kind != .none {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Qué cambiaría", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.caption.weight(.semibold))
                                Text(decision.change.summary)
                                    .font(.caption)
                                if decision.change.requiresConfirmation && !currentChangeIsApplied {
                                    Button("Revisar y confirmar") { showingChangeConfirmation = true }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                } else if currentChangeIsApplied {
                                    Label("Cambio confirmado", systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(10)
                            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                } else {
                    Text(localRecommendation)
                        .font(.callout)
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack {
                    Spacer()
                    if decision?.taskID != nil && (decision?.suggestedMinutes ?? 0) > 0 {
                        Button("Practicar esto ahora", systemImage: "play.fill") { startPracticing() }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("Reevaluar", systemImage: "arrow.clockwise") { refresh(trigger: .manualRefresh) }
                }

                if decision != nil {
                    Divider()
                    followUpChat
                }
            }
        }
        .sheet(isPresented: $showingTimer) {
            PracticeTimerView(initialTaskID: timerTaskID)
                .frame(minWidth: 500, idealWidth: 580, minHeight: 540)
        }
        .task { refresh(trigger: .appLaunch) }
        .alert("Confirmar cambio del plan", isPresented: $showingChangeConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Aplicar cambio") { approveChange() }
        } message: {
            Text(decision?.change.summary ?? "")
        }
    }

    private var followUpChat: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Pregúntale al asistente", systemImage: "bubble.left.and.bubble.right")
                .font(.subheadline.weight(.semibold))

            if !chatHistory.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(chatHistory.enumerated()), id: \.offset) { _, exchange in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exchange.question)
                                .font(.callout.weight(.medium))
                            Text(exchange.answer)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !chatErrorMessage.isEmpty {
                Text(chatErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(alignment: .top) {
                TextField("Ej: ¿por qué esta habilidad y no otra?", text: $chatInput, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .onSubmit { Task { await askFollowUp() } }
                Button {
                    Task { await askFollowUp() }
                } label: {
                    if isChatLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .disabled(isChatLoading || chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @MainActor
    private func askFollowUp() async {
        guard let decision else { return }
        let recommendation = decision.recommendationForExplanation
        let question = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        chatInput = ""
        isChatLoading = true
        chatErrorMessage = ""
        defer { isChatLoading = false }

        do {
            let backend = try await orchestrator.backend(for: .medium)
            let facade = CoachFacade(backend: backend)
            let answer = try await facade.practiceFollowUp(
                question: question,
                recommendation: recommendation,
                history: chatHistory,
                skills: skills,
                lessons: lessons,
                exercises: LibraryLookup.allExercises(in: modelContext),
                equipment: equipment,
                instruments: instruments,
                pdfReferences: pdfReferences(),
                sessions: sessions,
                tasks: tasks
            )
            chatHistory.append(ProgressChatExchange(question: question, answer: answer))
        } catch {
            chatErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func refresh(trigger: PracticeCoachTrigger) {
        errorMessage = ""
        do {
            _ = try PracticeCoachCoordinator.reevaluate(
                trigger: trigger,
                in: modelContext
            )
        } catch {
            errorMessage = "No se pudo actualizar el entrenador: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func approveChange() {
        do {
            _ = try PracticeCoachCoordinator.approveCurrentChange(in: modelContext)
        } catch {
            errorMessage = "No se pudo aplicar el cambio: \(error.localizedDescription)"
        }
    }

    /// Busca en el texto real de los PDFs importados páginas relacionadas con las habilidades
    /// más débiles, para que el asistente pueda citar páginas concretas en vez de inventarlas.
    private func pdfReferences() -> [String] {
        // Se piden acá y no con `@Query`: los textos completos de los 18 PDFs pesan, y solo hacen
        // falta cuando el asistente arma una recomendación, no cada vez que se abre el Dashboard.
        let books = LibraryLookup.allBooks(in: modelContext)
        guard !books.isEmpty else { return [] }
        let weakest = skills
            .filter { $0.status != .consolidated }
            .prefix(10)

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

    private func startPracticing() {
        guard let decision, let taskID = decision.taskID,
              tasks.contains(where: { $0.id == taskID && !$0.isCompleted })
        else { return }
        timerTaskID = taskID
        showingTimer = true
    }
}
