import AppKit
import SwiftData
import SwiftUI

struct FretboardTrainerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \FretboardNoteProgress.noteClass) private var progressRecords: [FretboardNoteProgress]
    @Query private var profiles: [FretboardTrainingProfile]
    @Query(sort: \PracticeTask.scheduledDate) private var tasks: [PracticeTask]
    @Query(sort: \Instrument.name) private var instruments: [Instrument]

    private enum Phase: Hashable {
        case notStarted
        case requestingMicrophone
        case active
        case finished
    }

    private struct DeferredQuestion {
        let question: FretboardQuestion
        let dueAtAttempt: Int
    }

    private struct FeedbackState {
        let isCorrect: Bool
        let title: String
        let detail: String
    }

    @AppStorage("fretboardSessionMinutes") private var sessionMinutes = DailyPracticeRoutine.fretboardMinutes
    @AppStorage("didMigrateFretboardRoutineToSevenMinutes") private var didMigrateRoutineDuration = false
    @AppStorage("fretboardMetronomeBPM") private var selectedBPM = 40
    @AppStorage("fretboardRhythmicFigure") private var rhythmicFigure = RhythmicFigure.quarterNotes
    @State private var phase = Phase.notStarted
    @State private var detector = GuitarPitchDetector()
    @State private var metronome = MetronomeEngine()
    @State private var referencePlaybackTask: Task<Void, Never>?
    @State private var answerDeadlineTask: Task<Void, Never>?
    @State private var answerWindowIsActive = false
    @State private var activeProfile: FretboardTrainingProfile?
    @State private var progressCache: [String: FretboardNoteProgress] = [:]
    @State private var currentQuestion: FretboardQuestion?
    @State private var currentTargetIndex = 0
    @State private var deferredQuestions: [DeferredQuestion] = []
    @State private var sessionStartedAt = Date.now
    @State private var questionStartedAt = Date.now
    @State private var remainingSeconds = Double(DailyPracticeRoutine.fretboardMinutes * 60)
    @State private var questionElapsed = 0.0
    @State private var sessionAttempts = 0
    @State private var sessionCorrect = 0
    @State private var sessionResponseSeconds = 0.0
    @State private var questionSerial = 0
    @State private var feedback: FeedbackState?
    @State private var isResolving = false
    @State private var microphoneError = ""
    @State private var persistedSession = false

    private var profile: FretboardTrainingProfile? {
        activeProfile ?? profiles.first
    }

    private var weaknesses: [FretboardWeakness] {
        FretboardTrainingScheduler.weaknesses(from: progressRecords)
    }

    private var sessionAccuracy: Double {
        guard sessionAttempts > 0 else { return 0 }
        return Double(sessionCorrect) / Double(sessionAttempts)
    }

    private var expectedPositions: [FretboardPosition] {
        guard let question = currentQuestion else { return [] }
        if question.kind == .allPositions {
            guard question.targets.indices.contains(currentTargetIndex) else { return [] }
            return [question.targets[currentTargetIndex]]
        }
        return question.targets
    }

    var body: some View {
        Group {
            switch phase {
            case .notStarted, .requestingMicrophone:
                startView
            case .active:
                activeView
            case .finished:
                summaryView
            }
        }
        .navigationTitle("Mástil")
        .onAppear {
            loadRecommendedPace()
            detector.refreshInputDeviceName()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { detector.refreshInputDeviceName() }
        }
        .onChange(of: detector.detection?.sequence) { _, _ in handleDetection() }
        .onChange(of: detector.isWaitingForSilence) { wasWaiting, isWaiting in
            if wasWaiting, !isWaiting, phase == .active, !isResolving {
                startAnswerWindow()
            }
        }
        .onChange(of: selectedBPM) { _, _ in
            guard phase == .active else { return }
            restartAnswerPreparation()
        }
        .onChange(of: rhythmicFigure) { _, newValue in
            guard RhythmicFigure.fretboardChoices.contains(newValue) else {
                rhythmicFigure = .quarterNotes
                return
            }
            guard phase == .active else { return }
            restartAnswerPreparation()
        }
        .task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled, phase == .active {
                try? await Task.sleep(for: .milliseconds(100))
                await MainActor.run { updateClocks() }
            }
        }
        .onDisappear { stopAudio() }
    }

    private var startView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Entrenamiento del mástil")
                            .font(.largeTitle.bold())
                        Text("Escucha la nota objetivo, encuéntrala en el mástil y deja que el Mac compruebe afinación y velocidad.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(profile?.hasCompletedAssessment == true ? "Comenzar \(sessionMinutes) min" : "Iniciar evaluación") {
                        requestMicrophoneAndStart()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(phase == .requestingMicrophone)
                }

                if !microphoneError.isEmpty {
                    Label(microphoneError, systemImage: "mic.slash.fill")
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }

                HStack(spacing: 12) {
                    Image(systemName: "mic.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Entrada de audio")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(detector.inputDeviceName)
                            .font(.headline)
                    }
                    Spacer()
                    Text("Predeterminada de macOS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Cambiar…", systemImage: "gearshape") { openSoundInputSettings() }
                        .buttonStyle(.bordered)
                }
                .padding(14)
                .background(PracticeTheme.softSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
                    statusCard
                    paceCard
                    routineCard
                }

                CardContainer {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Cómo progresa")
                        progressionRow(number: "1", title: "Diagnóstico", detail: "18 respuestas de notas naturales repartidas por las seis cuerdas.")
                        progressionRow(number: "2", title: "Refuerzo", detail: "Cada fallo vuelve dos preguntas después, formulado al revés.")
                        progressionRow(number: "3", title: "Fluidez", detail: "Cuando una nota sale limpia y rápida, suben el BPM y la exigencia.")
                        progressionRow(number: "4", title: "Nivel avanzado", detail: "Se desbloquean sostenidos, bemoles y recorridos de la misma nota por las seis cuerdas.")
                    }
                }

                weaknessOverview

                Label(
                    "El audio se procesa localmente. Para obtener resultados estables, usa sonido limpio, toca una sola nota y silencia las demás cuerdas.",
                    systemImage: "waveform.and.mic"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }

    private var statusCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Label("Nivel adaptativo", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                    .foregroundStyle(.indigo)
                if let profile, profile.hasCompletedAssessment {
                    Text("Nivel \(profile.currentLevel)")
                        .font(.title.bold())
                    Text(FretboardTrainingScheduler.levelTitle(profile.currentLevel))
                        .foregroundStyle(.secondary)
                } else {
                    let completed = profile?.diagnosticAttempts ?? 0
                    Text("\(completed)/\(FretboardTrainingScheduler.diagnosticAttemptCount)")
                        .font(.title.bold().monospacedDigit())
                    Text("respuestas de evaluación")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var paceCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Label("Click evaluado", systemImage: "metronome.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)

                HStack {
                    Stepper(value: $selectedBPM, in: 30...120, step: 5) {
                        Text("♩ = \(selectedBPM) BPM")
                            .font(.title2.bold().monospacedDigit())
                    }
                }
                Slider(
                    value: Binding(
                        get: { Double(selectedBPM) },
                        set: { selectedBPM = Int($0.rounded()) }
                    ),
                    in: 30...120,
                    step: 5
                )
                .tint(.orange)
                .accessibilityLabel("Tempo del metrónomo")
                .accessibilityValue("\(selectedBPM) BPM")

                Picker("Figura de la nota", selection: $rhythmicFigure) {
                    ForEach(RhythmicFigure.fretboardChoices) { figure in
                        Text(figure.displayName).tag(figure)
                    }
                }

                Label(
                    "Cada consigna suena como nota + click. El click siguiente abre \(answerWindowSeconds.formatted(.number.precision(.fractionLength(2)))) s para tocar. Figura: \(rhythmicFigure.displayName).",
                    systemImage: "timer"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let profile, profile.recommendedBPM != selectedBPM {
                    Button("Usar recomendación: \(profile.recommendedBPM) BPM") {
                        selectedBPM = profile.recommendedBPM
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var routineCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Label("Rutina diaria", systemImage: "calendar.badge.clock")
                    .font(.headline)
                    .foregroundStyle(.green)
                Stepper(value: $sessionMinutes, in: DailyPracticeRoutine.fretboardMinutes...30) {
                    Text("\(sessionMinutes) min")
                        .font(.title2.bold().monospacedDigit())
                }
                Text("La tarea se completa al cumplir el tiempo; mañana vuelve automáticamente.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var weaknessOverview: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Notas a reforzar",
                    subtitle: weaknesses.isEmpty ? "Aparecerán después de los primeros intentos" : "Ordenadas por precisión y tiempo"
                )
                if weaknesses.isEmpty {
                    Text("Todavía no hay datos suficientes. La evaluación inicial construirá este mapa.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(weaknesses) { weakness in
                        HStack(spacing: 12) {
                            Text(weakness.noteName)
                                .font(.headline.monospaced())
                                .frame(width: 34, alignment: .leading)
                            ProgressView(value: weakness.accuracy)
                                .tint(weakness.accuracy >= 0.8 ? .green : .orange)
                            Text("\(Int((weakness.accuracy * 100).rounded()))%")
                                .font(.caption.monospacedDigit())
                                .frame(width: 38, alignment: .trailing)
                            Text("\(weakness.averageSeconds.formatted(.number.precision(.fractionLength(1)))) s")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private func progressionRow(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.indigo.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var activeView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 16) {
                    Label(formatClock(remainingSeconds), systemImage: "timer")
                        .font(.headline.monospacedDigit())
                    ProgressView(value: remainingSeconds, total: Double(sessionMinutes * 60))
                        .tint(.indigo)
                    StatusPill(
                        text: "\(sessionCorrect)/\(sessionAttempts)",
                        tint: sessionAccuracy >= 0.8 ? .green : .indigo
                    )
                    Button("Finalizar antes") { finishSession(completedRoutine: false) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 14) {
                    Label("1 click = 1 nota", systemImage: "metronome.fill")
                        .font(.callout.weight(.semibold))

                    Stepper(value: $selectedBPM, in: 30...120, step: 5) {
                        Text("♩ = \(selectedBPM)")
                            .font(.headline.monospacedDigit())
                            .frame(width: 82, alignment: .trailing)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(selectedBPM) },
                            set: { selectedBPM = Int($0.rounded()) }
                        ),
                        in: 30...120,
                        step: 5
                    )
                    .tint(.orange)
                    .frame(maxWidth: 220)
                    .accessibilityLabel("Tempo del metrónomo")
                    .accessibilityValue("\(selectedBPM) BPM")

                    Picker("Figura", selection: $rhythmicFigure) {
                        ForEach(RhythmicFigure.fretboardChoices) { figure in
                            Text(figure.displayName).tag(figure)
                        }
                    }
                    .frame(maxWidth: 190)

                    Text("\(answerWindowSeconds.formatted(.number.precision(.fractionLength(2)))) s")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.orange)
                    Spacer()
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(PracticeTheme.windowSurface.opacity(0.92))

            if let question = currentQuestion {
                ScrollView {
                    VStack(spacing: 20) {
                        HStack {
                            StatusPill(text: question.kind.label, tint: .indigo)
                            if question.isDiagnostic {
                                StatusPill(
                                    text: "Evaluación \((profile?.diagnosticAttempts ?? 0) + 1)/\(FretboardTrainingScheduler.diagnosticAttemptCount)",
                                    tint: .purple
                                )
                            }
                            Spacer()
                            Text("\(rhythmicFigure.displayName) · una sola ventana de \(answerWindowSeconds.formatted(.number.precision(.fractionLength(2)))) s")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        CardContainer {
                            VStack(spacing: 16) {
                                TempoPulse(
                                    duration: answerWindowSeconds,
                                    startedAt: questionStartedAt,
                                    isActive: answerWindowIsActive
                                )
                                Text(question.title)
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                                    .multilineTextAlignment(.center)
                                Text(question.instructions)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)

                                if question.kind == .allPositions,
                                   question.targets.indices.contains(currentTargetIndex) {
                                    let target = question.targets[currentTargetIndex]
                                    Label(
                                        "Ahora: \(GuitarFretboard.stringLabel(target.stringNumber)) · posición \(currentTargetIndex + 1) de \(question.targets.count)",
                                        systemImage: "arrow.right.circle.fill"
                                    )
                                    .font(.headline)
                                    .foregroundStyle(.indigo)
                                }

                                ProgressView(
                                    value: answerWindowIsActive ? min(questionElapsed, answerWindowSeconds) : 0,
                                    total: answerWindowSeconds
                                )
                                .tint(answerWindowIsActive ? .orange : .secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }

                        detectionPanel

                        if let feedback {
                            Label(feedback.title, systemImage: feedback.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.headline)
                                .foregroundStyle(feedback.isCorrect ? .green : .red)
                            Text(feedback.detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        HStack {
                            Button("Oír nota", systemImage: "speaker.wave.2.fill") {
                                playCurrentTarget()
                            }
                            .buttonStyle(.bordered)
                            .disabled(isResolving || answerWindowIsActive)
                            Button("No lo sé / omitir", systemImage: "forward.fill") {
                                resolveWrongAnswer(reason: "Omitida")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isResolving)
                        }
                    }
                    .padding(24)
                }
            }
        }
    }

    private var detectionPanel: some View {
        HStack(spacing: 16) {
            Image(systemName: detector.status == .listening ? "mic.fill" : "mic.slash.fill")
                .font(.title2)
                .foregroundStyle(detector.status == .listening ? .green : .red)
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    answerWindowIsActive
                        ? "Toca ahora: solo cuenta esta ventana"
                        : (detector.isWaitingForSilence
                            ? "Prepárate: el click sonará cuando haya silencio"
                            : detector.status.message)
                )
                    .font(.callout.weight(.medium))
                    .foregroundStyle(answerWindowIsActive || detector.isWaitingForSilence ? .orange : .primary)
                Text("Entrada: \(detector.inputDeviceName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: detector.inputLevel)
                    .tint(.green)
                    .frame(width: 150)
            }
            Spacer()
            if answerWindowIsActive {
                Label("Ventana abierta", systemImage: "timer")
                    .foregroundStyle(.orange)
            } else if detector.isWaitingForSilence {
                Label("Esperando el click", systemImage: "speaker.slash.fill")
                    .foregroundStyle(.orange)
            } else if let pitch = detector.detection?.pitch {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(pitch.scientificName)
                        .font(.title2.bold().monospaced())
                    Text("\(pitch.frequency.formatted(.number.precision(.fractionLength(1)))) Hz · \(centsText(pitch.cents))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(abs(pitch.cents) <= 20 ? .green : .orange)
                }
            } else {
                HStack(spacing: 10) {
                    Text("Toca una nota")
                        .foregroundStyle(.secondary)
                    Button { openSoundInputSettings() } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.plain)
                    .help("Cambiar entrada de sonido")
                    .accessibilityLabel("Cambiar entrada de sonido")
                }
            }
        }
        .padding(14)
        .background(PracticeTheme.softSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
    }

    private var summaryView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: persistedSession ? "checkmark.seal.fill" : "pause.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(persistedSession ? .green : .orange)
                Text(persistedSession ? "Rutina de hoy completada" : "Sesión finalizada antes de tiempo")
                    .font(.largeTitle.bold())
                Text(
                    persistedSession
                        ? "La tarea de mañana ya quedó programada con el nuevo nivel."
                        : "Guardamos el progreso por nota, pero la tarea diaria sigue pendiente hasta completar los \(sessionMinutes) minutos."
                )
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

                HStack(spacing: 14) {
                    summaryMetric(title: "Precisión", value: "\(Int((sessionAccuracy * 100).rounded()))%")
                    summaryMetric(title: "Aciertos", value: "\(sessionCorrect)/\(sessionAttempts)")
                    summaryMetric(
                        title: "Respuesta media",
                        value: sessionAttempts == 0
                            ? "—"
                            : "\((sessionResponseSeconds / Double(sessionAttempts)).formatted(.number.precision(.fractionLength(1)))) s"
                    )
                    summaryMetric(title: "Próximo tempo", value: "\(profile?.recommendedBPM ?? selectedBPM) BPM")
                }

                if let profile {
                    StatusPill(
                        text: "Nivel \(profile.currentLevel) · \(FretboardTrainingScheduler.levelTitle(profile.currentLevel))",
                        tint: .indigo
                    )
                }

                Button("Volver al resumen") {
                    phase = .notStarted
                    loadRecommendedPace()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold().monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: 130)
        .padding(14)
        .background(PracticeTheme.softSurface.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
    }

    private var targetSeconds: Double {
        answerWindowSeconds
    }

    private var answerWindowSeconds: Double {
        rhythmicFigure.fretboardWindowSeconds(bpm: selectedBPM)
    }

    private func loadRecommendedPace() {
        guard phase == .notStarted else { return }
        selectedBPM = min(120, max(30, selectedBPM))
        if !RhythmicFigure.fretboardChoices.contains(rhythmicFigure) {
            rhythmicFigure = .quarterNotes
        }
        if !didMigrateRoutineDuration {
            // Diez era el valor predeterminado de versiones anteriores. Solo ese valor se migra;
            // una sesión más larga elegida expresamente por el usuario se conserva.
            if sessionMinutes == 10 { sessionMinutes = DailyPracticeRoutine.fretboardMinutes }
            didMigrateRoutineDuration = true
        }
        sessionMinutes = max(DailyPracticeRoutine.fretboardMinutes, sessionMinutes)
    }

    private func requestMicrophoneAndStart() {
        detector.refreshInputDeviceName()
        phase = .requestingMicrophone
        microphoneError = ""
        Task {
            let started = await detector.start()
            await MainActor.run {
                if started {
                    beginSession()
                } else {
                    microphoneError = detector.status.message + ". Habilítalo en Configuración del Sistema > Privacidad y seguridad > Micrófono."
                    phase = .notStarted
                }
            }
        }
    }

    private func openSoundInputSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension?input") else { return }
        NSWorkspace.shared.open(url)
    }

    private func beginSession() {
        let profile = FretboardTrainingProfile.fetchOrCreate(in: modelContext)
        activeProfile = profile
        progressCache = Dictionary(uniqueKeysWithValues: progressRecords.map { ($0.id, $0) })
        selectedBPM = max(30, min(120, selectedBPM))
        sessionMinutes = max(DailyPracticeRoutine.fretboardMinutes, sessionMinutes)
        sessionStartedAt = .now
        remainingSeconds = Double(sessionMinutes * 60)
        sessionAttempts = 0
        sessionCorrect = 0
        sessionResponseSeconds = 0
        questionSerial = 0
        deferredQuestions = []
        feedback = nil
        isResolving = false
        persistedSession = false
        let audioStarted = metronome.start(
            bpm: selectedBPM,
            beatsPerBar: 1,
            clickIsEnabled: false
        )
        guard audioStarted else {
            detector.stop()
            microphoneError = "No se pudo iniciar la salida de audio: \(metronome.lastStartError ?? "error desconocido")."
            phase = .notStarted
            return
        }
        phase = .active
        presentNextQuestion()
    }

    private func presentNextQuestion() {
        guard let profile else { return }
        if let index = deferredQuestions.firstIndex(where: { $0.dueAtAttempt <= sessionAttempts }) {
            currentQuestion = deferredQuestions.remove(at: index).question
        } else {
            currentQuestion = FretboardTrainingScheduler.nextQuestion(
                profile: profile,
                progress: Array(progressCache.values),
                serial: questionSerial
            )
        }
        questionSerial += 1
        currentTargetIndex = 0
        questionStartedAt = .now
        questionElapsed = 0
        feedback = nil
        isResolving = false
        playCurrentTarget()
    }

    private func handleDetection() {
        guard
            phase == .active,
            answerWindowIsActive,
            !isResolving,
            let pitch = detector.detection?.pitch,
            let question = currentQuestion,
            !expectedPositions.isEmpty
        else { return }

        questionElapsed = min(
            answerWindowSeconds,
            max(0, Date.now.timeIntervalSince(questionStartedAt))
        )

        if expectedPositions.contains(where: { $0.midi == pitch.midi }) {
            let matched = expectedPositions.first { $0.midi == pitch.midi } ?? expectedPositions[0]
            resolveCorrectAnswer(question: question, position: matched)
        } else {
            resolveWrongAnswer(reason: "Sonó \(pitch.scientificName)")
        }
    }

    private func resolveCorrectAnswer(question: FretboardQuestion, position: FretboardPosition) {
        guard !isResolving else { return }
        endAnswerWindow()
        isResolving = true
        record(position: position, isCorrect: true)
        feedback = FeedbackState(
            isCorrect: true,
            title: "Correcto · \(position.scientificName)",
            detail: "Cuerda \(position.stringNumber), traste \(position.fret) · \(questionElapsed.formatted(.number.precision(.fractionLength(1)))) s"
        )

        if question.kind == .allPositions, currentTargetIndex + 1 < question.targets.count {
            currentTargetIndex += 1
            scheduleAdvance(after: 0.65, withinSameQuestion: true)
        } else {
            scheduleAdvance(after: 0.85, withinSameQuestion: false)
        }
    }

    private func resolveWrongAnswer(reason: String) {
        guard
            phase == .active,
            !isResolving,
            let question = currentQuestion,
            let expected = expectedPositions.first ?? question.targets.first
        else { return }
        endAnswerWindow()
        isResolving = true
        record(position: expected, isCorrect: false)
        deferredQuestions.append(
            DeferredQuestion(
                question: question.reframed(around: expected),
                dueAtAttempt: sessionAttempts + 2
            )
        )
        feedback = FeedbackState(
            isCorrect: false,
            title: reason,
            detail: "Respuesta: \(expected.scientificName), cuerda \(expected.stringNumber), traste \(expected.fret). Volverá con otra formulación."
        )
        scheduleAdvance(after: 1.20, withinSameQuestion: false)
    }

    private func record(position: FretboardPosition, isCorrect: Bool) {
        let response = max(0.1, questionElapsed)
        sessionAttempts += 1
        sessionResponseSeconds += response
        if isCorrect { sessionCorrect += 1 }

        let key = FretboardNoteProgress.key(noteClass: position.noteClass, stringNumber: position.stringNumber)
        let progress = progressCache[key] ?? {
            let created = FretboardNoteProgress(noteClass: position.noteClass, stringNumber: position.stringNumber)
            modelContext.insert(created)
            progressCache[key] = created
            return created
        }()
        progress.record(isCorrect: isCorrect, responseSeconds: response, bpm: selectedBPM)
        profile?.recordAttempt(isCorrect: isCorrect, responseSeconds: response, targetSeconds: targetSeconds)
    }

    private func scheduleAdvance(after seconds: Double, withinSameQuestion: Bool) {
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            await MainActor.run {
                guard phase == .active else { return }
                if withinSameQuestion {
                    questionStartedAt = .now
                    questionElapsed = 0
                    feedback = nil
                    isResolving = false
                    playCurrentTarget()
                } else {
                    presentNextQuestion()
                }
            }
        }
    }

    private func updateClocks() {
        guard phase == .active else { return }
        let now = Date.now
        let elapsed = now.timeIntervalSince(sessionStartedAt)
        remainingSeconds = max(0, Double(sessionMinutes * 60) - elapsed)
        questionElapsed = answerWindowIsActive
            ? min(answerWindowSeconds, max(0, now.timeIntervalSince(questionStartedAt)))
            : 0
        if remainingSeconds <= 0 {
            finishSession(completedRoutine: true)
        }
    }

    private func finishSession(completedRoutine: Bool) {
        guard phase == .active else { return }
        stopAudio()
        let elapsed = max(1, Int(Date.now.timeIntervalSince(sessionStartedAt) / 60.0))
        let average = sessionAttempts > 0 ? sessionResponseSeconds / Double(sessionAttempts) : 0

        if completedRoutine, let profile {
            profile.finishSession(
                correct: sessionCorrect,
                attempts: sessionAttempts,
                averageSeconds: average,
                bpm: selectedBPM,
                targetSeconds: answerWindowSeconds
            )
            let result: PracticeResult = sessionAccuracy >= 0.85 ? .targetTempo : (sessionAccuracy >= 0.65 ? .learning : .review)
            let pendingTask = tasks.first { !$0.isCompleted && $0.isDailyFretboardTraining }
            if let pendingTask {
                let next = RecurringPracticeService.completeTask(
                    pendingTask,
                    outcome: PracticeOutcome(
                        result: result,
                        endBPM: selectedBPM,
                        correctRepetitions: sessionCorrect,
                        tensionRating: 1,
                        context: .fromMemory,
                        wasColdCheck: false
                    ),
                    in: modelContext
                )
                next?.targetBPM = profile.recommendedBPM
            }

            let activeInstrument = instruments.first(where: \Instrument.isActive)?.name ?? "Guitarra"
            let weakest = FretboardTrainingScheduler.weaknesses(from: Array(progressCache.values), limit: 3)
                .map(\.noteName)
                .joined(separator: ", ")
            modelContext.insert(PracticeSession(
                durationMinutes: max(sessionMinutes, elapsed),
                instrumentName: activeInstrument,
                category: .theory,
                sourceTitle: "Rutina adaptativa",
                exerciseTitle: "Notas del mástil",
                startBPM: selectedBPM,
                endBPM: profile.recommendedBPM,
                difficulty: profile.currentLevel,
                result: result,
                notes: "\(rhythmicFigure.displayName): un click por nota. Precisión \(Int((sessionAccuracy * 100).rounded()))%. Notas a reforzar: \(weakest.isEmpty ? "por determinar" : weakest).",
                sourceKind: .fretboard,
                correctRepetitions: sessionCorrect,
                practiceContext: .fromMemory,
                rhythmicFigure: rhythmicFigure
            ))
            persistedSession = true
        }
        // También fuerza a disco los intentos de una sesión interrumpida: la tarea continúa
        // pendiente, pero esas debilidades ya observadas deben influir en el próximo intento.
        try? modelContext.save()
        phase = .finished
    }

    private func startAnswerWindow() {
        guard
            phase == .active,
            !isResolving,
            !answerWindowIsActive,
            let question = currentQuestion
        else { return }

        let questionID = question.id
        let targetIndex = currentTargetIndex
        let window = answerWindowSeconds
        questionStartedAt = .now
        questionElapsed = 0
        answerWindowIsActive = true
        metronome.playOneShotClick()

        answerDeadlineTask?.cancel()
        answerDeadlineTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(window))
            } catch {
                return
            }
            guard
                phase == .active,
                answerWindowIsActive,
                !isResolving,
                currentQuestion?.id == questionID,
                currentTargetIndex == targetIndex
            else { return }

            questionElapsed = window
            resolveWrongAnswer(
                reason: "Fuera de tiempo · no sonó la nota durante el único click"
            )
        }
    }

    private func endAnswerWindow() {
        answerDeadlineTask?.cancel()
        answerDeadlineTask = nil
        answerWindowIsActive = false
        detector.suspendDetection()
    }

    private func restartAnswerPreparation() {
        guard phase == .active, !isResolving, currentQuestion != nil else { return }
        // Si todavía suena la referencia, la nueva configuración se aplicará naturalmente al
        // click que se abrirá después; no hay que armar el micrófono antes de tiempo.
        guard referencePlaybackTask == nil else { return }
        answerDeadlineTask?.cancel()
        answerDeadlineTask = nil
        answerWindowIsActive = false
        questionElapsed = 0
        feedback = nil
        detector.rearm(afterSilence: true)
    }

    private func playCurrentTarget() {
        guard
            phase == .active,
            let question = currentQuestion,
            question.targets.indices.contains(
                question.kind == .allPositions ? currentTargetIndex : 0
            )
        else { return }

        let targetIndex = question.kind == .allPositions ? currentTargetIndex : 0
        referencePlaybackTask?.cancel()
        answerDeadlineTask?.cancel()
        answerDeadlineTask = nil
        answerWindowIsActive = false
        // La referencia y el click comparten el mismo motor de salida. El analizador sigue mostrando
        // el nivel de entrada, pero no puede responder la pregunta con el sonido de la propia app.
        detector.suspendDetection()
        feedback = nil
        // La consigna auditiva siempre contiene los dos elementos pedidos: la altura objetivo y
        // un click acentuado que confirma el pulso. Tras el silencio, otro click abre la ventana.
        metronome.playReferenceNote(
            midi: question.targets[targetIndex].midi,
            includeClick: true
        )
        referencePlaybackTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(MetronomeEngine.referenceNoteDuration + 0.1))
            } catch {
                return
            }
            referencePlaybackTask = nil
            guard phase == .active else { return }
            detector.rearm(afterSilence: true)
        }
    }

    private func stopAudio() {
        referencePlaybackTask?.cancel()
        referencePlaybackTask = nil
        answerDeadlineTask?.cancel()
        answerDeadlineTask = nil
        answerWindowIsActive = false
        detector.stop()
        metronome.stop()
    }

    private func formatClock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func centsText(_ cents: Double) -> String {
        let rounded = Int(cents.rounded())
        if abs(rounded) <= 2 { return "afinada" }
        return rounded > 0 ? "+\(rounded) cents" : "\(rounded) cents"
    }
}

private struct TempoPulse: View {
    let duration: Double
    let startedAt: Date
    let isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
            let progress = isActive ? min(1, elapsed / max(0.01, duration)) : 0
            let scale = isActive ? 1 + max(0, 1 - progress * 5) * 0.24 : 1
            Circle()
                .fill((isActive ? Color.orange : Color.secondary).gradient)
                .frame(width: 34, height: 34)
                .scaleEffect(scale)
                .overlay {
                    Image(systemName: "metronome.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
        }
        .frame(height: 44)
        .accessibilityLabel(isActive ? "Ventana de respuesta abierta" : "Esperando el click")
    }
}
