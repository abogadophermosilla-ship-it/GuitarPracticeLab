import AVFoundation
import Foundation
import Observation
import SwiftData
import SwiftUI

enum SkillAudioAssessmentMode: String {
    case initial
    case monthly

    var title: String {
        switch self {
        case .initial: "Prueba práctica inicial"
        case .monthly: "Revisión práctica mensual"
        }
    }

    var isColdCheck: Bool { self == .monthly }
}

/// Calendario único de las comprobaciones prácticas. Se usa en Habilidades y en Hoy para que
/// ambos accesos venzan el mismo día y sumar meses de calendario no se convierta en "cada 30 días".
enum SkillAudioAssessmentSchedule {
    static let completionKey = "hasCompletedSkillAudioAssessment"
    static let lastCompletedAtKey = "lastSkillAudioAssessmentDate"

    static func nextDueDate(
        after lastCompletedAt: Date,
        calendar: Calendar = .current
    ) -> Date {
        calendar.date(byAdding: .month, value: 1, to: lastCompletedAt) ?? lastCompletedAt
    }

    static func isMonthlyReviewDue(
        hasCompletedInitial: Bool,
        lastCompletedAt: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard hasCompletedInitial, let lastCompletedAt else { return false }
        return now >= nextDueDate(after: lastCompletedAt, calendar: calendar)
    }
}

enum SkillAudioMetricProfile: String {
    case pulse
    case articulation
    case sustain
    case bend
    case vibrato
}

struct SkillAudioChallenge: Identifiable, Equatable {
    var id: UUID { skillID }
    let skillID: UUID
    let skillName: String
    let title: String
    let instructions: String
    let targetBPM: Int
    let attacksPerBeat: Double
    let duration: TimeInterval
    let metricProfile: SkillAudioMetricProfile
}

/// Selecciona una muestra corta, estable y reproducible. Los fundamentos siempre pueden medirse;
/// las especializaciones solo entran cuando sus prerrequisitos ya llegaron al nivel intermedio.
/// La revisión mensual se restringe además a habilidades con señales de estudio o progreso.
enum SkillAudioAssessmentPlanner {
    private struct Template {
        let title: String
        let instructions: String
        let attacksPerBeat: Double
        let profile: SkillAudioMetricProfile
    }

    private static let templates: [String: Template] = [
        "Postura, relajación y mecánica general": Template(
            title: "Cromatismo relajado",
            instructions: "Toca 1-2-3-4 en una cuerda, en corcheas. Busca ataques iguales y movimiento pequeño; detente si aparece dolor.",
            attacksPerBeat: 2,
            profile: .pulse
        ),
        "Sincronización entre ambas manos": Template(
            title: "Cuatro notas por cuerda",
            instructions: "Toca 1-2-3-4 y cambia entre dos cuerdas sin detener el flujo. Usa púa alternada y deja sonar cada ataque con claridad.",
            attacksPerBeat: 2,
            profile: .pulse
        ),
        "Ritmo, subdivisión y groove": Template(
            title: "Corcheas estables",
            instructions: "Toca corcheas en una sola nota o cuerda apagada. Mantén el pulso interno y acentúa cada cuatro ataques.",
            attacksPerBeat: 2,
            profile: .pulse
        ),
        "Acordes y guitarra rítmica": Template(
            title: "Cambios sin cortar el pulso",
            instructions: "Alterna dos acordes conocidos con un ataque por pulso. Prioriza entradas juntas y silencios limpios entre cambios.",
            attacksPerBeat: 1,
            profile: .articulation
        ),
        "Muting y palm muting": Template(
            title: "Riff con silencios",
            instructions: "Alterna dos pulsos de palm mute y dos pulsos de silencio. Los cortes deben ser breves y definidos.",
            attacksPerBeat: 2,
            profile: .articulation
        ),
        "Alternate picking": Template(
            title: "Púa abajo-arriba",
            instructions: "Toca semicorcheas en una nota cómoda con púa estrictamente alternada. Iguala el volumen de ambos ataques.",
            attacksPerBeat: 4,
            profile: .pulse
        ),
        "Downpicking, tremolo picking y gallops": Template(
            title: "Galope controlado",
            instructions: "Toca un patrón de galope repetido con palm mute. Mantén hombro y antebrazo sueltos.",
            attacksPerBeat: 3,
            profile: .pulse
        ),
        "Legato": Template(
            title: "Hammer-on y pull-off",
            instructions: "Repite una figura de tres notas con un solo ataque de púa por grupo. Iguala el volumen de las notas ligadas.",
            attacksPerBeat: 3,
            profile: .pulse
        ),
        "Slides y cambios de posición": Template(
            title: "Slides al pulso",
            instructions: "Alterna dos posiciones separadas por al menos tres trastes. Llega a cada nota en el pulso sin cortar el sustain.",
            attacksPerBeat: 1,
            profile: .sustain
        ),
        "Bending": Template(
            title: "Bend de un tono",
            instructions: "Toca la nota de destino, vuelve dos trastes atrás y haz un bend hasta igualarla. Alterna referencia y bend.",
            attacksPerBeat: 1,
            profile: .bend
        ),
        "Vibrato": Template(
            title: "Vibrato uniforme",
            instructions: "Sostén una nota cómoda y aplica un vibrato pequeño y regular. Repite después de un silencio breve.",
            attacksPerBeat: 0.5,
            profile: .vibrato
        ),
        "String skipping": Template(
            title: "Salto entre cuerdas",
            instructions: "Alterna la misma figura entre dos cuerdas no adyacentes sin rozar la cuerda intermedia.",
            attacksPerBeat: 2,
            profile: .pulse
        ),
        "Economy picking": Template(
            title: "Tres notas por cuerda",
            instructions: "Sube y baja una figura de tres notas por cuerda usando el barrido natural en cada cambio.",
            attacksPerBeat: 3,
            profile: .pulse
        ),
        "Sweep picking": Template(
            title: "Arpegio de tres cuerdas",
            instructions: "Barre un arpegio conocido de tres cuerdas, lento y continuo. Separa las notas para que no formen un acorde.",
            attacksPerBeat: 2,
            profile: .articulation
        ),
        "Tapping": Template(
            title: "Célula de tapping",
            instructions: "Repite una célula de tres notas con tap, pull-off y hammer-on. Busca volumen y separación uniformes.",
            attacksPerBeat: 3,
            profile: .pulse
        ),
        "Armónicos": Template(
            title: "Armónico sostenido",
            instructions: "Haz sonar varias veces el mismo armónico natural y deja que cada repetición sostenga con claridad.",
            attacksPerBeat: 0.5,
            profile: .sustain
        ),
        "Hybrid picking, fingerstyle y palanca": Template(
            title: "Púa y dedos",
            instructions: "Alterna una nota grave con púa y dos notas agudas con los dedos. Mantén el patrón parejo.",
            attacksPerBeat: 3,
            profile: .pulse
        ),
        "Aplicación musical, oído, teoría y repertorio": Template(
            title: "Frase musical breve",
            instructions: "Toca un riff o frase real que ya tengas trabajado, sin detener el pulso y con una intención dinámica clara.",
            attacksPerBeat: 2,
            profile: .articulation
        )
    ]

    static func challenges(
        topics: [SkillTopic],
        evidence: [SkillEvidence],
        mode: SkillAudioAssessmentMode,
        now: Date = .now
    ) -> [SkillAudioChallenge] {
        let techniques = topics.filter { $0.domain == .technique && templates[$0.name] != nil }
        let effectiveLevels = Dictionary(uniqueKeysWithValues: techniques.map { topic in
            (topic.id, effectiveLevel(for: topic))
        })
        let evidenceBySkill = Dictionary(grouping: evidence, by: \.skillID)
        let fundamentals = Set(SkillAssessmentCoachService.fundamentosSkillNames)

        let eligible = techniques.filter { topic in
            if fundamentals.contains(topic.name) { return true }

            let prerequisitesReady = SkillGraphService.prerequisites(for: topic, among: topics).allSatisfy {
                (effectiveLevels[$0.id] ?? effectiveLevel(for: $0)).progressWeight
                    >= SkillMasteryLevel.intermediate.progressWeight
            }
            guard prerequisitesReady else { return false }

            let ownLevel = effectiveLevels[topic.id] ?? .notStarted
            return ownLevel.progressWeight >= SkillMasteryLevel.basic.progressWeight
                || !(evidenceBySkill[topic.id] ?? []).isEmpty
        }

        let monthlyPool: [SkillTopic]
        if mode == .monthly {
            monthlyPool = eligible.filter { topic in
                let level = effectiveLevels[topic.id] ?? .notStarted
                let records = evidenceBySkill[topic.id] ?? []
                let hasPracticalSignal = records.contains { $0.sourceKind != .assessment }
                return level != .notStarted || hasPracticalSignal
            }
        } else {
            monthlyPool = eligible
        }

        let candidates = monthlyPool.isEmpty ? eligible : monthlyPool
        let curriculumOrder = SkillAssessmentCoachService.fundamentosSkillNames
            + SkillAssessmentCoachService.especializacionSkillNames
        let order = Dictionary(uniqueKeysWithValues: curriculumOrder.enumerated().map { ($0.element, $0.offset) })

        let sorted = candidates.sorted { lhs, rhs in
            if mode == .monthly {
                let leftAudio = lastAudioEvidenceDate(for: lhs.id, evidence: evidenceBySkill[lhs.id] ?? [])
                let rightAudio = lastAudioEvidenceDate(for: rhs.id, evidence: evidenceBySkill[rhs.id] ?? [])
                if leftAudio != rightAudio { return leftAudio < rightAudio }

                let leftLevel = effectiveLevels[lhs.id]?.progressWeight ?? 0
                let rightLevel = effectiveLevels[rhs.id]?.progressWeight ?? 0
                if leftLevel != rightLevel { return leftLevel < rightLevel }
            }
            return (order[lhs.name] ?? .max) < (order[rhs.name] ?? .max)
        }

        let limit = mode == .initial ? 5 : 4
        return sorted.prefix(limit).compactMap { topic in
            guard let template = templates[topic.name] else { return nil }
            return SkillAudioChallenge(
                skillID: topic.id,
                skillName: topic.name,
                title: template.title,
                instructions: template.instructions,
                targetBPM: targetBPM(for: effectiveLevels[topic.id] ?? .notStarted),
                attacksPerBeat: template.attacksPerBeat,
                duration: 12,
                metricProfile: template.profile
            )
        }
    }

    private static func effectiveLevel(for topic: SkillTopic) -> SkillMasteryLevel {
        [topic.status, topic.testStatus, SkillAssessmentCoachService.computeStatus(for: topic)]
            .compactMap { $0 }
            .max { $0.progressWeight < $1.progressWeight } ?? .notStarted
    }

    private static func targetBPM(for level: SkillMasteryLevel) -> Int {
        switch level {
        case .notStarted, .initial: 60
        case .basic: 70
        case .intermediate: 85
        case .advanced: 100
        case .consolidated: 110
        }
    }

    private static func lastAudioEvidenceDate(for skillID: UUID, evidence: [SkillEvidence]) -> Date {
        evidence
            .filter { $0.skillID == skillID && $0.sourceKind == .audioAnalysis }
            .map(\.occurredAt)
            .max() ?? .distantPast
    }
}

struct SkillAudioAssessmentMetrics: Equatable, Sendable {
    let duration: TimeInterval
    let attackCount: Int
    let meanAttackInterval: Double?
    let attackIntervalVariation: Double?
    let activeRatio: Double
    let pitchedRatio: Double
    let pitchRangeSemitones: Double?
}

/// Acumulador sin AVFoundation para que la detección de ataques, actividad y pitch pueda probarse
/// con datos sintéticos. No intenta reconocer la técnica por timbre: solo extrae señales que el
/// reto puede comparar de forma honesta.
struct SkillAudioAssessmentAccumulator {
    private(set) var elapsed = 0.0
    private var attackTimes: [Double] = []
    private var pitchedValues: [Double] = []
    private var blockCount = 0
    private var activeBlockCount = 0
    private var previousRMS = 0.0
    private var smoothedRMS = 0.0
    private var lastAttackAt = -Double.greatestFiniteMagnitude

    mutating func ingest(samples: [Float], sampleRate: Double) {
        guard !samples.isEmpty, sampleRate > 0 else { return }
        let blockSize = 256
        var offset = 0
        while offset < samples.count {
            let end = min(samples.count, offset + blockSize)
            let block = samples[offset..<end]
            let meanSquare = block.reduce(0.0) { $0 + Double($1 * $1) } / Double(block.count)
            let rms = sqrt(meanSquare)
            let time = elapsed + Double(offset) / sampleRate
            blockCount += 1
            if rms >= GuitarPitchMath.silenceThreshold { activeBlockCount += 1 }

            let baseline = max(0.006, smoothedRMS)
            let transient = rms > max(0.014, baseline * 1.42)
                && rms > previousRMS * 1.18
                && time - lastAttackAt >= 0.065
            if transient {
                attackTimes.append(time)
                lastAttackAt = time
            }
            smoothedRMS = smoothedRMS == 0 ? rms : smoothedRMS * 0.82 + rms * 0.18
            previousRMS = rms
            offset = end
        }

        let frame = GuitarPitchMath.analyze(samples: samples, sampleRate: sampleRate)
        if let pitch = frame.estimate, pitch.confidence >= 0.62 {
            pitchedValues.append(Double(pitch.midi) + pitch.cents / 100)
        }
        elapsed += Double(samples.count) / sampleRate
    }

    func metrics() -> SkillAudioAssessmentMetrics {
        let intervals = zip(attackTimes.dropFirst(), attackTimes).map(-)
            .filter { (0.065...2.0).contains($0) }
        let mean = intervals.isEmpty ? nil : intervals.reduce(0, +) / Double(intervals.count)
        let variation: Double? = mean.flatMap { mean in
            guard mean > 0, intervals.count >= 2 else { return nil }
            let variance = intervals.reduce(0) { $0 + pow($1 - mean, 2) } / Double(intervals.count)
            return sqrt(variance) / mean
        }
        let pitchRange: Double? = {
            guard let low = pitchedValues.min(), let high = pitchedValues.max() else { return nil }
            return high - low
        }()
        return SkillAudioAssessmentMetrics(
            duration: elapsed,
            attackCount: attackTimes.count,
            meanAttackInterval: mean,
            attackIntervalVariation: variation,
            activeRatio: blockCount > 0 ? Double(activeBlockCount) / Double(blockCount) : 0,
            pitchedRatio: blockCount > 0 ? Double(pitchedValues.count) / max(1, elapsed * 10) : 0,
            pitchRangeSemitones: pitchRange
        )
    }
}

struct SkillAudioAssessmentScore: Equatable {
    let score: Double
    let reliability: Double
    let summary: String

    var percentage: Int { Int((score * 100).rounded()) }

    var label: String {
        switch score {
        case 0.82...: "Muy estable"
        case 0.65..<0.82: "Estable"
        case 0.45..<0.65: "En desarrollo"
        default: "Necesita base"
        }
    }
}

enum SkillAudioAssessmentScorer {
    static func score(
        metrics: SkillAudioAssessmentMetrics,
        challenge: SkillAudioChallenge
    ) -> SkillAudioAssessmentScore? {
        guard metrics.duration >= 3, metrics.activeRatio >= 0.025 else { return nil }

        let activity = clamp(metrics.activeRatio / 0.28)
        let pitched = clamp(metrics.pitchedRatio / 0.55)
        let regularity = metrics.attackIntervalVariation.map { clamp(1 - $0 / 0.45) } ?? 0.25
        let expectedInterval = 60 / Double(challenge.targetBPM) / max(0.25, challenge.attacksPerBeat)
        let tempo = metrics.meanAttackInterval.map {
            clamp(1 - abs($0 - expectedInterval) / max(0.12, expectedInterval * 0.55))
        } ?? 0.2

        let value: Double
        let detail: String
        switch challenge.metricProfile {
        case .pulse:
            guard metrics.attackCount >= 4 else { return nil }
            value = regularity * 0.50 + tempo * 0.30 + activity * 0.20
            detail = "\(metrics.attackCount) ataques · regularidad \(percent(regularity)) · pulso \(percent(tempo))"
        case .articulation:
            guard metrics.attackCount >= 3 else { return nil }
            let spaceControl = clamp(1 - abs(metrics.activeRatio - 0.48) / 0.48)
            value = regularity * 0.40 + tempo * 0.25 + spaceControl * 0.25 + activity * 0.10
            detail = "\(metrics.attackCount) ataques · regularidad \(percent(regularity)) · cortes \(percent(spaceControl))"
        case .sustain:
            value = pitched * 0.55 + activity * 0.30 + min(1, Double(metrics.attackCount) / 4) * 0.15
            detail = "señal afinada \(percent(pitched)) · continuidad \(percent(activity))"
        case .bend:
            guard let range = metrics.pitchRangeSemitones else { return nil }
            let targetRange = clamp(1 - abs(range - 2) / 2)
            value = targetRange * 0.55 + pitched * 0.30 + activity * 0.15
            detail = "recorrido \(range.formatted(.number.precision(.fractionLength(1)))) semitonos · referencia \(percent(targetRange))"
        case .vibrato:
            guard let range = metrics.pitchRangeSemitones else { return nil }
            let controlledRange = range >= 0.18 && range <= 1.5
                ? 1.0
                : clamp(1 - min(abs(range - 0.18), abs(range - 1.5)) / 1.5)
            value = controlledRange * 0.45 + pitched * 0.35 + activity * 0.20
            detail = "amplitud \(range.formatted(.number.precision(.fractionLength(1)))) semitonos · continuidad \(percent(pitched))"
        }

        let evidenceRichness = min(1, Double(metrics.attackCount) / 12)
        let reliability = min(0.84, 0.58 + activity * 0.12 + evidenceRichness * 0.14)
        return SkillAudioAssessmentScore(
            score: clamp(value),
            reliability: reliability,
            summary: detail
        )
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
    private static func percent(_ value: Double) -> String { "\(Int((clamp(value) * 100).rounded()))%" }
}

private final class SkillAudioCaptureBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var accumulator = SkillAudioAssessmentAccumulator()

    func reset() {
        lock.lock()
        accumulator = SkillAudioAssessmentAccumulator()
        lock.unlock()
    }

    func ingest(samples: [Float], sampleRate: Double) -> Double {
        lock.lock()
        accumulator.ingest(samples: samples, sampleRate: sampleRate)
        let meanSquare = samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(1, samples.count))
        lock.unlock()
        return min(1, sqrt(meanSquare) * 12)
    }

    func metrics() -> SkillAudioAssessmentMetrics {
        lock.lock()
        let result = accumulator.metrics()
        lock.unlock()
        return result
    }
}

@Observable
@MainActor
final class SkillAudioAssessmentEngine {
    enum State: Equatable {
        case idle
        case requestingPermission
        case listening
        case failed(String)
    }

    var state: State = .idle
    var inputLevel = 0.0
    var remainingSeconds = 0.0
    var inputDeviceName = AVCaptureDevice.default(for: .audio)?.localizedName ?? "Sin entrada de audio"

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let analysisQueue = DispatchQueue(label: "com.guitarpracticelab.skill-audio-assessment", qos: .userInitiated)
    @ObservationIgnored private let capture = SkillAudioCaptureBuffer()
    @ObservationIgnored private var tapInstalled = false
    @ObservationIgnored private var activeRunID: UUID?

    deinit {
        if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
        engine.stop()
    }

    func measure(duration: TimeInterval) async throws -> SkillAudioAssessmentMetrics {
        stop()
        inputDeviceName = AVCaptureDevice.default(for: .audio)?.localizedName ?? "Sin entrada de audio"
        state = .requestingPermission
        guard await requestMicrophoneAccess() else {
            state = .failed("Acceso al micrófono denegado")
            throw SkillAudioAssessmentEngineError.microphoneDenied
        }

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            state = .failed("No se encontró una entrada de audio")
            throw SkillAudioAssessmentEngineError.noAudioInput
        }

        capture.reset()
        let capture = capture
        input.installTap(onBus: 0, bufferSize: 4_096, format: nil) { [weak self] buffer, _ in
            guard let channel = buffer.floatChannelData?.pointee, buffer.frameLength > 0 else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            let rate = buffer.format.sampleRate
            self?.analysisQueue.async { [weak self] in
                let level = capture.ingest(samples: samples, sampleRate: rate)
                DispatchQueue.main.async { self?.inputLevel = level }
            }
        }
        tapInstalled = true

        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            tapInstalled = false
            state = .failed("No se pudo iniciar el micrófono")
            throw error
        }

        let runID = UUID()
        activeRunID = runID
        remainingSeconds = duration
        state = .listening
        let startedAt = Date()
        while activeRunID == runID {
            let elapsed = Date().timeIntervalSince(startedAt)
            remainingSeconds = max(0, duration - elapsed)
            if elapsed >= duration { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard activeRunID == runID else { throw CancellationError() }

        shutdownAudio()
        analysisQueue.sync {}
        let result = capture.metrics()
        activeRunID = nil
        remainingSeconds = 0
        state = .idle
        return result
    }

    func stop() {
        activeRunID = nil
        shutdownAudio()
        inputLevel = 0
        remainingSeconds = 0
        if state == .listening || state == .requestingPermission { state = .idle }
    }

    private func shutdownAudio() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
    }

    private func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            true
        case .notDetermined:
            await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
            }
        case .denied, .restricted:
            false
        @unknown default:
            false
        }
    }
}

enum SkillAudioAssessmentEngineError: LocalizedError {
    case microphoneDenied
    case noAudioInput

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "La app no tiene permiso para usar el micrófono. Habilítalo en Privacidad y seguridad > Micrófono."
        case .noAudioInput:
            "No se encontró una entrada de audio. Revisa tu interfaz o la entrada elegida en macOS."
        }
    }
}

struct SkillAudioAssessmentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SkillTopic.name) private var topics: [SkillTopic]
    @Query(sort: \SkillEvidence.occurredAt, order: .reverse) private var evidence: [SkillEvidence]
    @AppStorage(SkillAudioAssessmentSchedule.completionKey) private var hasCompletedInitial = false
    @AppStorage(SkillAudioAssessmentSchedule.lastCompletedAtKey) private var lastCompletedAt = 0.0

    let mode: SkillAudioAssessmentMode

    @State private var analyzer = SkillAudioAssessmentEngine()
    @State private var metronome = MetronomeEngine()
    @State private var challenges: [SkillAudioChallenge] = []
    @State private var results: [UUID: SkillAudioAssessmentScore] = [:]
    @State private var currentIndex = 0
    @State private var hasStarted = false
    @State private var isShowingSummary = false
    @State private var useClick = false
    @State private var errorMessage = ""
    @State private var isSaving = false
    private let runID = UUID()

    private var currentChallenge: SkillAudioChallenge? {
        challenges.indices.contains(currentIndex) ? challenges[currentIndex] : nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if challenges.isEmpty {
                    ContentUnavailableView(
                        "Aún no hay técnicas para comprobar",
                        systemImage: "waveform.slash",
                        description: Text("Responde algunas preguntas del Test Integral o registra práctica para que la app elija retos acordes a tu recorrido.")
                    )
                } else if isShowingSummary {
                    summary
                } else if hasStarted {
                    activeChallenge
                } else {
                    overview
                }
            }
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .onAppear {
            if challenges.isEmpty {
                challenges = SkillAudioAssessmentPlanner.challenges(
                    topics: topics,
                    evidence: evidence,
                    mode: mode
                )
            }
        }
        .onDisappear {
            analyzer.stop()
            metronome.stop()
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Label(mode == .initial ? "Una línea base tocando" : "Comprobación en frío", systemImage: "waveform.badge.mic")
                    .font(.title2.bold())
                Text(mode == .initial
                     ? "La app escuchará una muestra corta por técnica y medirá pulso, regularidad, continuidad y recorrido de afinación cuando corresponda."
                     : "Se eligieron habilidades ya iniciadas, débiles o sin audio reciente. No aparecerán especializaciones cuyos prerrequisitos aún no estén listos.")
                    .foregroundStyle(.secondary)
                Text("El análisis es local. No intenta adivinar musicalidad ni penaliza notas sin una referencia fiable.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            List(challenges) { challenge in
                HStack(spacing: 12) {
                    Image(systemName: "guitars.fill")
                        .foregroundStyle(PracticeTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(challenge.skillName).font(.subheadline.weight(.medium))
                        Text("\(challenge.title) · \(challenge.targetBPM) BPM · \(Int(challenge.duration)) s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.inset)

            HStack {
                Label("Entrada: \(analyzer.inputDeviceName)", systemImage: "mic")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Comenzar", systemImage: "play.fill") {
                    hasStarted = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(24)
    }

    private var activeChallenge: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let challenge = currentChallenge {
                ProgressView(value: Double(currentIndex + 1), total: Double(challenges.count))
                Text("Prueba \(currentIndex + 1) de \(challenges.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text(challenge.skillName)
                        .font(.headline)
                        .foregroundStyle(PracticeTheme.accent)
                    Text(challenge.title).font(.largeTitle.bold())
                    Text(challenge.instructions)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    HStack {
                        Label("\(challenge.targetBPM) BPM", systemImage: "metronome")
                        Label("\(Int(challenge.duration)) segundos", systemImage: "timer")
                    }
                    .font(.callout.weight(.medium))
                }

                Toggle("Click de referencia (usa audífonos)", isOn: $useClick)
                    .disabled(analyzer.state == .listening)
                Text("Sin audífonos, el click puede entrar por el micrófono y falsear los ataques.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(analyzer.state == .listening ? "Escuchando" : "Nivel de entrada", systemImage: "mic.fill")
                        Spacer()
                        if analyzer.state == .listening {
                            Text("\(Int(ceil(analyzer.remainingSeconds))) s")
                                .font(.title2.bold().monospacedDigit())
                        }
                    }
                    ProgressView(value: analyzer.inputLevel)
                        .tint(analyzer.inputLevel > 0.92 ? .red : .green)
                }
                .padding(14)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                if let result = results[challenge.id] {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(result.label, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(result.score >= 0.65 ? .green : .orange)
                            Spacer()
                            Text("\(result.percentage)%").font(.title2.bold())
                        }
                        Text(result.summary).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }

                Spacer()
                HStack {
                    Button(results[challenge.id] == nil ? "Escuchar muestra" : "Repetir", systemImage: "waveform.badge.mic") {
                        measure(challenge)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(analyzer.state == .listening || analyzer.state == .requestingPermission)

                    if analyzer.state == .listening {
                        Button("Detener") {
                            analyzer.stop()
                            metronome.stop()
                        }
                    }

                    Spacer()
                    if results[challenge.id] != nil {
                        Button(currentIndex == challenges.count - 1 ? "Ver resultados" : "Siguiente", systemImage: "arrow.right") {
                            if currentIndex == challenges.count - 1 {
                                isShowingSummary = true
                            } else {
                                currentIndex += 1
                                errorMessage = ""
                            }
                        }
                        .controlSize(.large)
                    }
                }
            }
        }
        .padding(28)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode == .initial ? "Línea base práctica" : "Progreso comprobado este mes")
                .font(.largeTitle.bold())
            Text("Estos resultados se guardarán como evidencia objetiva de ejecución. En una revisión mensual también comprobarán retención en frío.")
                .foregroundStyle(.secondary)

            List {
                ForEach(challenges) { challenge in
                    if let result = results[challenge.id] {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(challenge.skillName).font(.subheadline.weight(.medium))
                                Text(result.summary).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("\(result.percentage)%").font(.headline.monospacedDigit())
                                Text(result.label).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)

            if !errorMessage.isEmpty {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Button("Volver a las pruebas") { isShowingSummary = false }
                Spacer()
                Button("Guardar evaluación", systemImage: "checkmark") { saveResults() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(results.isEmpty || isSaving)
            }
        }
        .padding(24)
    }

    private func measure(_ challenge: SkillAudioChallenge) {
        errorMessage = ""
        if useClick { metronome.start(bpm: challenge.targetBPM, beatsPerBar: 4) }
        Task {
            do {
                let metrics = try await analyzer.measure(duration: challenge.duration)
                metronome.stop()
                if let score = SkillAudioAssessmentScorer.score(metrics: metrics, challenge: challenge) {
                    results[challenge.id] = score
                } else {
                    errorMessage = "No hubo señal suficiente para medir esta prueba. Revisa la entrada, toca más cerca del micrófono y repítela."
                }
            } catch is CancellationError {
                metronome.stop()
            } catch {
                metronome.stop()
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func saveResults() {
        isSaving = true
        errorMessage = ""
        let completedAt = Date()
        for challenge in challenges {
            guard let result = results[challenge.id] else { continue }
            SkillEvidenceService.recordLiveAudioAssessment(
                runID: runID,
                skillID: challenge.skillID,
                score: result.score,
                reliability: result.reliability,
                wasColdCheck: mode.isColdCheck,
                occurredAt: completedAt,
                notes: "\(mode.title) · \(challenge.title) · \(result.summary)",
                in: modelContext
            )
        }
        BadgeEvaluator.evaluate(context: modelContext)
        do {
            try modelContext.save()
            _ = try? PracticeCoachCoordinator.reevaluate(trigger: .assessmentCompleted, in: modelContext)
            hasCompletedInitial = true
            lastCompletedAt = completedAt.timeIntervalSince1970
            dismiss()
        } catch {
            errorMessage = "No se pudieron guardar los resultados: \(error.localizedDescription)"
            isSaving = false
        }
    }
}
