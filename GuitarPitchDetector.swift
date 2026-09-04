import AVFoundation
import Foundation
import Observation

struct GuitarPitchEstimate: Equatable, Sendable {
    let frequency: Double
    let midi: Int
    let cents: Double
    let confidence: Double
    let rms: Double

    var noteClass: Int { ((midi % 12) + 12) % 12 }
    var noteName: String { GuitarFretboard.noteName(for: noteClass) }
    var octave: Int { midi / 12 - 1 }
    var scientificName: String { "\(noteName)\(octave)" }
}

struct GuitarPitchFrame: Sendable {
    let estimate: GuitarPitchEstimate?
    let rms: Double
}

/// Analizador YIN reducido a la banda útil de la guitarra. Vive separado del motor AVAudioEngine
/// para poder verificarlo con tonos sintéticos y para que el callback de audio solo copie el buffer.
enum GuitarPitchMath {
    static let minimumFrequency = 70.0
    static let maximumFrequency = 900.0
    static let silenceThreshold = 0.008

    static func frequency(forMIDI midi: Int) -> Double {
        440 * pow(2, Double(midi - 69) / 12)
    }

    static func midiAndCents(for frequency: Double) -> (midi: Int, cents: Double)? {
        guard frequency.isFinite, frequency > 0 else { return nil }
        let fractionalMIDI = 69 + 12 * log2(frequency / 440)
        let midi = Int(fractionalMIDI.rounded())
        return (midi, (fractionalMIDI - Double(midi)) * 100)
    }

    static func analyze(samples: [Float], sampleRate: Double) -> GuitarPitchFrame {
        guard samples.count >= 512, sampleRate > 0 else {
            return GuitarPitchFrame(estimate: nil, rms: 0)
        }

        let meanSquare = samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count)
        let rms = sqrt(meanSquare)
        guard rms >= silenceThreshold else { return GuitarPitchFrame(estimate: nil, rms: rms) }

        // Alrededor de 12 kHz conserva holgadamente la banda fundamental de la guitarra y reduce
        // mucho el costo de la función de diferencia de YIN.
        let stride = max(1, Int(sampleRate / 12_000))
        var signal = Swift.stride(from: 0, to: samples.count, by: stride).map { Double(samples[$0]) }
        guard signal.count >= 256 else { return GuitarPitchFrame(estimate: nil, rms: rms) }

        let mean = signal.reduce(0, +) / Double(signal.count)
        for index in signal.indices { signal[index] -= mean }

        let reducedRate = sampleRate / Double(stride)
        let minimumLag = max(2, Int(reducedRate / maximumFrequency))
        let maximumLag = min(signal.count / 2, Int(reducedRate / minimumFrequency))
        guard maximumLag > minimumLag + 2 else { return GuitarPitchFrame(estimate: nil, rms: rms) }

        var difference = Array(repeating: 0.0, count: maximumLag + 1)
        for lag in 1...maximumLag {
            var sum = 0.0
            let count = signal.count - lag
            for index in 0..<count {
                let delta = signal[index] - signal[index + lag]
                sum += delta * delta
            }
            difference[lag] = sum
        }

        var cumulative = Array(repeating: 1.0, count: maximumLag + 1)
        var running = 0.0
        if maximumLag >= 1 {
            for lag in 1...maximumLag {
                running += difference[lag]
                cumulative[lag] = running > 0 ? difference[lag] * Double(lag) / running : 1
            }
        }

        let threshold = 0.18
        var selectedLag: Int?
        var lag = minimumLag
        while lag < maximumLag {
            if cumulative[lag] < threshold {
                while lag + 1 <= maximumLag && cumulative[lag + 1] < cumulative[lag] { lag += 1 }
                selectedLag = lag
                break
            }
            lag += 1
        }

        if selectedLag == nil {
            selectedLag = (minimumLag...maximumLag).min { cumulative[$0] < cumulative[$1] }
            if let selectedLag, cumulative[selectedLag] > 0.35 {
                return GuitarPitchFrame(estimate: nil, rms: rms)
            }
        }
        guard let selectedLag else { return GuitarPitchFrame(estimate: nil, rms: rms) }

        var refinedLag = Double(selectedLag)
        if selectedLag > 1, selectedLag < maximumLag {
            let left = cumulative[selectedLag - 1]
            let center = cumulative[selectedLag]
            let right = cumulative[selectedLag + 1]
            let denominator = left - 2 * center + right
            if abs(denominator) > 0.000_001 {
                refinedLag += 0.5 * (left - right) / denominator
            }
        }

        let frequency = reducedRate / refinedLag
        guard
            (minimumFrequency...maximumFrequency).contains(frequency),
            let pitch = midiAndCents(for: frequency),
            (38...80).contains(pitch.midi)
        else { return GuitarPitchFrame(estimate: nil, rms: rms) }

        return GuitarPitchFrame(
            estimate: GuitarPitchEstimate(
                frequency: frequency,
                midi: pitch.midi,
                cents: pitch.cents,
                confidence: max(0, min(1, 1 - cumulative[selectedLag])),
                rms: rms
            ),
            rms: rms
        )
    }
}

@Observable
final class GuitarPitchDetector {
    enum Status: Equatable {
        case idle
        case requestingPermission
        case listening
        case denied
        case failed(String)

        var message: String {
            switch self {
            case .idle: "Micrófono detenido"
            case .requestingPermission: "Solicitando acceso al micrófono…"
            case .listening: "Escuchando la guitarra"
            case .denied: "Acceso al micrófono denegado"
            case .failed(let message): message
            }
        }
    }

    struct Detection: Equatable {
        let sequence: Int
        let pitch: GuitarPitchEstimate
        /// Instante aproximado del centro del buffer analizado, no el momento posterior en que
        /// terminó YIN. Permite evaluar correctamente una nota tocada justo antes del límite.
        let observedAt: Date
    }

    static let analysisGraceSeconds = 0.08

    var status: Status = .idle
    var detection: Detection?
    var inputLevel: Double = 0
    var inputDeviceName: String = AVCaptureDevice.default(for: .audio)?.localizedName ?? "Sin entrada de audio"
    var isWaitingForSilence = false

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let analysisQueue = DispatchQueue(label: "com.guitarpracticelab.pitch-analysis", qos: .userInitiated)
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var candidateMIDI: Int?
    @ObservationIgnored private var candidateHits = 0
    @ObservationIgnored private var isArmed = true
    @ObservationIgnored private var silenceFrames = 0
    @ObservationIgnored private var smoothedRMS = 0.0
    @ObservationIgnored private var tapInstalled = false
    @ObservationIgnored private var detectionIsSuspended = false

    deinit {
        if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
        engine.stop()
    }

    @MainActor
    func start() async -> Bool {
        guard status != .listening else { return true }
        refreshInputDeviceName()
        status = .requestingPermission
        let granted = await requestMicrophoneAccess()
        guard granted else {
            status = .denied
            return false
        }

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            status = .failed("No se encontró una entrada de audio disponible.")
            return false
        }

        if tapInstalled {
            input.removeTap(onBus: 0)
            tapInstalled = false
        }
        // 2.048 frames conservan suficiente señal para la fundamental grave de la guitarra y
        // reducen la latencia para ventanas breves como corcheas y semicorcheas.
        input.installTap(onBus: 0, bufferSize: 2_048, format: nil) { [weak self] buffer, _ in
            guard
                let self,
                let channel = buffer.floatChannelData?.pointee,
                buffer.frameLength > 0
            else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            let rate = buffer.format.sampleRate
            let observedAt = Date.now.addingTimeInterval(
                -Double(buffer.frameLength) / max(1, rate) / 2
            )
            self.analysisQueue.async { [weak self] in
                let frame = GuitarPitchMath.analyze(samples: samples, sampleRate: rate)
                DispatchQueue.main.async { self?.consume(frame, observedAt: observedAt) }
            }
        }
        tapInstalled = true

        do {
            engine.prepare()
            try engine.start()
            status = .listening
            rearm()
            return true
        } catch {
            input.removeTap(onBus: 0)
            tapInstalled = false
            status = .failed("No se pudo iniciar el micrófono: \(error.localizedDescription)")
            return false
        }
    }

    @MainActor
    func stop() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        status = .idle
        detection = nil
        inputLevel = 0
        resetGate()
    }

    @MainActor
    func rearm(afterSilence: Bool = false) {
        detectionIsSuspended = false
        detection = nil
        isWaitingForSilence = afterSilence
        isArmed = !afterSilence
        candidateMIDI = nil
        candidateHits = 0
        silenceFrames = 0
    }

    /// Mantiene visible la entrada, pero impide que el sonido de referencia de la propia app se
    /// contabilice como respuesta. `rearm(afterSilence:)` vuelve a habilitar la detección.
    @MainActor
    func suspendDetection() {
        detectionIsSuspended = true
        detection = nil
        isWaitingForSilence = true
        isArmed = false
        candidateMIDI = nil
        candidateHits = 0
        silenceFrames = 0
    }

    /// `AVAudioEngine.inputNode` escucha la entrada predeterminada del sistema. Usar la misma
    /// selección de AVFoundation permite mostrarla por nombre antes de abrir el motor y actualizar
    /// el texto si el alumno cambia de interfaz en Configuración del Sistema.
    @MainActor
    func refreshInputDeviceName() {
        inputDeviceName = AVCaptureDevice.default(for: .audio)?.localizedName ?? "Sin entrada de audio"
    }

    @MainActor
    private func consume(_ frame: GuitarPitchFrame, observedAt: Date) {
        inputLevel = min(1, frame.rms * 12)
        guard !detectionIsSuspended else { return }

        if frame.rms < GuitarPitchMath.silenceThreshold {
            silenceFrames += 1
            smoothedRMS *= 0.7
            if silenceFrames >= 2 {
                // Una nota de guitarra puede sostenerse varios segundos. Después de cambiar la
                // consigna no se vuelve a abrir la detección hasta que haya dos buffers de silencio;
                // así la cola de la nota anterior nunca responde la pregunta siguiente.
                isWaitingForSilence = false
                isArmed = true
                candidateMIDI = nil
                candidateHits = 0
            }
            return
        }

        let onset = smoothedRMS > 0 && frame.rms > max(smoothedRMS * 1.45, smoothedRMS + 0.012)
        smoothedRMS = smoothedRMS == 0 ? frame.rms : (smoothedRMS * 0.75 + frame.rms * 0.25)
        silenceFrames = 0
        guard !isWaitingForSilence else { return }
        if onset { isArmed = true }

        guard let estimate = frame.estimate, estimate.confidence >= 0.68 else { return }
        if candidateMIDI == estimate.midi {
            candidateHits += 1
        } else {
            candidateMIDI = estimate.midi
            candidateHits = 1
            isArmed = true
        }

        // Un frame YIN de 2.048 muestras con esta confianza basta para las ventanas rápidas. La
        // compuerta de silencio y el rango de guitarra ya filtran ruido y colas de notas previas.
        guard isArmed, candidateHits >= 1 else { return }
        sequence += 1
        detection = Detection(sequence: sequence, pitch: estimate, observedAt: observedAt)
        isArmed = false
    }

    @MainActor
    private func resetGate() {
        detectionIsSuspended = false
        candidateMIDI = nil
        candidateHits = 0
        isArmed = true
        isWaitingForSilence = false
        silenceFrames = 0
        smoothedRMS = 0
    }

    @MainActor
    private func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}
