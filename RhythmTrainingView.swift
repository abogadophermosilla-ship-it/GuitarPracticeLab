import Combine
import SwiftData
import SwiftUI

struct RhythmTrainingView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var bpm = 70
    @State private var beatsPerBar = 4
    @State private var bars = 8
    @State private var figure = RhythmicFigure.eighthNoteTriplets
    @State private var silenceEveryFourthBar = true
    @State private var metronome = MetronomeEngine()
    @State private var isRunning = false
    @State private var startUptime: TimeInterval?
    @State private var elapsed: TimeInterval = 0
    @State private var taps: [RhythmTapMeasurement] = []
    @State private var clickIsEnabled = true
    @State private var isSaved = false
    @State private var errorMessage = ""

    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var duration: TimeInterval {
        Double(bars * beatsPerBar) * 60 / Double(bpm)
    }

    private var currentBar: Int {
        min(bars, Int(elapsed / (60 / Double(bpm) * Double(beatsPerBar))) + 1)
    }

    private var summary: RhythmTrainingSummary? {
        RhythmTimingAnalyzer.summary(for: taps)
    }

    private var lastTap: RhythmTapMeasurement? { taps.last }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                intro
                controls
                trainingPanel
                if let summary { results(summary) }
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onReceive(timer) { _ in updateRun() }
        .onDisappear { metronome.stop() }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Laboratorio de ritmo")
                .font(.title2.bold())
            Text("Toca la barra espaciadora o el botón al ejecutar cada subdivisión. La app mide si llegas antes o después de la rejilla y apaga el click cada cuatro compases para comprobar tu pulso interno.")
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    BPMField(label: "Tempo:", value: $bpm, range: 40...180)
                    Picker("Compás", selection: $beatsPerBar) {
                        Text("2/4").tag(2)
                        Text("3/4").tag(3)
                        Text("4/4").tag(4)
                    }
                    .frame(width: 140)
                    Stepper("\(bars) compases", value: $bars, in: 4...16, step: 4)
                }
                Picker("Subdivisión", selection: $figure) {
                    ForEach(RhythmTimingAnalyzer.trainingFigures) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                Toggle("Silenciar cada cuarto compás", isOn: $silenceEveryFourthBar)
                Text(figure.countingGuide)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(isRunning)
        }
    }

    private var trainingPanel: some View {
        CardContainer {
            VStack(spacing: 18) {
                HStack {
                    Label(isRunning ? "Compás \(currentBar) de \(bars)" : "Listo para empezar", systemImage: "metronome")
                        .font(.headline)
                    Spacer()
                    Text("\(Int(max(0, duration - elapsed).rounded(.up))) s")
                        .font(.title2.bold().monospacedDigit())
                }

                ProgressView(value: min(elapsed, duration), total: duration)
                    .tint(clickIsEnabled ? PracticeTheme.accent : .orange)

                if isRunning && !clickIsEnabled {
                    Label("Compás sin click: conserva el pulso", systemImage: "speaker.slash.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                Button {
                    registerTap()
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "hand.tap.fill").font(.system(size: 34))
                        Text(lastTap?.timingLabel ?? "Tocar subdivisión")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isRunning)
                .keyboardShortcut(.space, modifiers: [])
                .accessibilityIdentifier("rhythm.tap")

                HStack {
                    if isRunning {
                        Button("Detener", systemImage: "stop.fill", role: .destructive) { finish() }
                    } else {
                        Button(taps.isEmpty ? "Comenzar" : "Repetir", systemImage: "play.fill") { start() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .accessibilityIdentifier("rhythm.start")
                    }
                    Spacer()
                    Text("\(taps.count) ataques medidos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private func results(_ summary: RhythmTrainingSummary) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(summary.label).font(.headline)
                        Text("Error medio: \(Int(summary.averageAbsoluteOffsetMilliseconds.rounded())) ms · cerca de la rejilla: \(Int((summary.closeTapRatio * 100).rounded()))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(summary.percentage)%")
                        .font(.largeTitle.bold().monospacedDigit())
                }
                if isSaved {
                    Label("Sesión guardada", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if !isRunning && summary.tapCount >= 4 {
                    Button("Guardar sesión", systemImage: "square.and.arrow.down") { save(summary) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func start() {
        errorMessage = ""
        taps = []
        elapsed = 0
        isSaved = false
        clickIsEnabled = true
        guard metronome.start(bpm: bpm, beatsPerBar: beatsPerBar) else {
            errorMessage = metronome.lastStartError ?? "No se pudo iniciar el metrónomo."
            return
        }
        startUptime = ProcessInfo.processInfo.systemUptime
        isRunning = true
    }

    private func registerTap() {
        guard isRunning, let startUptime,
              let measurement = RhythmTimingAnalyzer.measurement(
                tapUptime: ProcessInfo.processInfo.systemUptime,
                startUptime: startUptime,
                bpm: bpm,
                figure: figure
              ) else { return }
        taps.append(measurement)
    }

    private func updateRun() {
        guard isRunning, let startUptime else { return }
        elapsed = max(0, ProcessInfo.processInfo.systemUptime - startUptime)
        if elapsed >= duration {
            elapsed = duration
            finish()
            return
        }
        let secondsPerBar = 60 / Double(bpm) * Double(beatsPerBar)
        let zeroBasedBar = Int(elapsed / secondsPerBar)
        let shouldClick = !silenceEveryFourthBar || zeroBasedBar % 4 != 3
        if shouldClick != clickIsEnabled {
            clickIsEnabled = shouldClick
            metronome.setClickEnabled(shouldClick)
        }
    }

    private func finish() {
        if let startUptime {
            elapsed = min(duration, max(elapsed, ProcessInfo.processInfo.systemUptime - startUptime))
        }
        metronome.stop()
        isRunning = false
        self.startUptime = nil
        clickIsEnabled = true
    }

    private func save(_ summary: RhythmTrainingSummary) {
        let seconds = max(1, Int(elapsed.rounded()))
        let result: PracticeResult = summary.accuracy >= 0.82
            ? .targetTempo
            : summary.accuracy >= 0.62 ? .reducedTempo : .learning
        let session = PracticeSession(
            durationMinutes: max(1, Int(ceil(Double(seconds) / 60))),
            durationSeconds: seconds,
            category: .rhythm,
            sourceTitle: "Academia · Laboratorio de ritmo",
            exerciseTitle: figure.displayName,
            startBPM: bpm,
            endBPM: bpm,
            difficulty: summary.accuracy >= 0.7 ? 3 : 4,
            result: result,
            notes: "Precisión \(summary.percentage)% · error medio \(Int(summary.averageAbsoluteOffsetMilliseconds.rounded())) ms · \(summary.tapCount) ataques.",
            sourceKind: .academia,
            correctRepetitions: Int((summary.closeTapRatio * Double(summary.tapCount)).rounded()),
            practiceContext: .metronome,
            rhythmicFigure: figure
        )
        modelContext.insert(session)
        SkillEvidenceService.recordPractice(session: session, task: nil, in: modelContext)
        BadgeEvaluator.evaluate(context: modelContext)
        do {
            try modelContext.save()
            isSaved = true
        } catch {
            errorMessage = "No se pudo guardar la sesión: \(error.localizedDescription)"
        }
    }
}
