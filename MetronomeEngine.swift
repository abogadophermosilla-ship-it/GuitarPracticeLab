import Foundation
import AVFoundation

/// Metrónomo del timer de práctica.
///
/// El click se sintetiza en el render block de un `AVAudioSourceNode` en vez de programar buffers
/// con un `Timer`: así el pulso queda anclado al reloj de la tarjeta de sonido y no se corre cuando
/// el hilo principal se traba (que es exactamente lo que pasa cuando la app está hablando con el
/// gateway de IA). Cambiar el BPM en caliente tampoco reprograma nada — el render block lee el valor
/// nuevo en el frame siguiente. El entrenador del mástil también puede superponer una nota de
/// referencia en este mismo nodo para conservar una sola ruta de salida.
///
/// Sobre hilos: el render block corre en el hilo de audio en tiempo real, así que no toma locks ni
/// asigna memoria. La UI solo escribe escalares del estado al cambiar el tempo o disparar una nota;
/// el render block los consume sin bloquear el hilo de Core Audio.
final class MetronomeEngine {

    /// Estado compartido entre la UI y el hilo de audio. Los contadores (`frameInBeat`, `beatIndex`,
    /// `clickFrame`) son propiedad exclusiva del hilo de audio: nadie más los toca.
    private final class State: @unchecked Sendable {
        var framesPerBeat: Double = 44_100 / 2
        var beatsPerBar: Int = 4
        var frameInBeat: Double = .greatestFiniteMagnitude
        var beatIndex: Int = -1
        var clickFrame: Int = -1
        var oneShotClickFrame: Int = -1
        var clickIsEnabled = true
        var referenceFrequency: Double = 0
        var referenceFrame: Int = -1
        var referenceTotalFrames: Int = 0
    }

    static let minimumBPM = 30
    static let maximumBPM = 300
    static let referenceNoteDuration = 0.85

    private let engine = AVAudioEngine()
    private let state = State()
    private var sourceNode: AVAudioSourceNode?
    private var sampleRate: Double = 44_100
    private(set) var isRunning = false
    private(set) var lastStartError: String?

    /// Duración del click en segundos — corto para que no se pise con el pulso siguiente ni a 300 BPM.
    private let clickDuration = 0.012
    private let accentFrequency = 1_600.0
    private let beatFrequency = 880.0
    private let amplitude = 0.35
    private let referenceAmplitude = 0.24

    deinit {
        engine.stop()
    }

    // MARK: - Control

    @discardableResult
    func start(bpm: Int, beatsPerBar: Int, clickIsEnabled: Bool = true) -> Bool {
        update(bpm: bpm, beatsPerBar: beatsPerBar)
        state.clickIsEnabled = clickIsEnabled
        guard !isRunning else { return true }

        if sourceNode == nil, !buildGraph() {
            lastStartError = "No se pudo crear la salida de audio del metrónomo."
            return false
        }
        // Que el primer click suene al instante y en el acento, no medio compás después.
        state.frameInBeat = .greatestFiniteMagnitude
        state.beatIndex = -1
        state.clickFrame = -1

        do {
            engine.prepare()
            try engine.start()
            isRunning = true
            lastStartError = nil
            return true
        } catch {
            isRunning = false
            lastStartError = error.localizedDescription
            return false
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.stop()
        state.oneShotClickFrame = -1
        state.referenceFrame = -1
        isRunning = false
    }

    /// Superpone una nota de referencia al pulso sin abrir un segundo dispositivo de salida.
    /// El entrenador del mástil usa esta ruta para que click y nota siempre lleguen al mismo destino.
    func playReferenceNote(midi: Int, includeClick: Bool = false) {
        guard isRunning else { return }
        state.referenceFrequency = 440 * pow(2, Double(midi - 69) / 12)
        state.referenceTotalFrames = Int(Self.referenceNoteDuration * sampleRate)
        state.referenceFrame = 0
        if includeClick {
            state.oneShotClickFrame = 0
        }
    }

    func setClickEnabled(_ enabled: Bool) {
        guard state.clickIsEnabled != enabled else { return }
        state.clickIsEnabled = enabled
        if enabled {
            // Al volver a encenderlo, confirma el tempo con un click inmediato.
            state.frameInBeat = .greatestFiniteMagnitude
            state.beatIndex = -1
            state.clickFrame = -1
        }
    }

    /// Dispara un solo click acentuado sin poner en marcha el pulso continuo. El entrenador del
    /// mástil lo usa como señal de inicio de una única ventana de respuesta.
    func playOneShotClick() {
        guard isRunning else { return }
        state.oneShotClickFrame = 0
    }

    func update(bpm: Int, beatsPerBar: Int) {
        let clamped = min(max(bpm, Self.minimumBPM), Self.maximumBPM)
        state.framesPerBeat = sampleRate * 60.0 / Double(clamped)
        state.beatsPerBar = max(1, beatsPerBar)
    }

    // MARK: - Grafo de audio

    @discardableResult
    private func buildGraph() -> Bool {
        let output = engine.outputNode
        sampleRate = output.inputFormat(forBus: 0).sampleRate
        if sampleRate <= 0 { sampleRate = 44_100 }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else { return false }

        let clickFrames = Int(clickDuration * sampleRate)
        let accent = accentFrequency
        let beat = beatFrequency
        let amplitude = amplitude
        let referenceAmplitude = referenceAmplitude
        let rate = sampleRate
        let state = state

        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let framesPerBeat = state.framesPerBeat
            let beatsPerBar = state.beatsPerBar

            for frame in 0..<Int(frameCount) {
                if state.frameInBeat >= framesPerBeat {
                    state.frameInBeat = state.frameInBeat == .greatestFiniteMagnitude
                        ? 0
                        : state.frameInBeat - framesPerBeat
                    state.beatIndex = (state.beatIndex + 1) % beatsPerBar
                    state.clickFrame = 0
                }

                var sample: Float = 0
                if state.clickIsEnabled && state.clickFrame >= 0 && state.clickFrame < clickFrames {
                    let time = Double(state.clickFrame) / rate
                    let frequency = state.beatIndex == 0 ? accent : beat
                    let envelope = exp(-time * 90)
                    sample = Float(sin(2 * .pi * frequency * time) * envelope * amplitude)
                    state.clickFrame += 1
                }

                if state.oneShotClickFrame >= 0 && state.oneShotClickFrame < clickFrames {
                    let time = Double(state.oneShotClickFrame) / rate
                    let envelope = exp(-time * 90)
                    sample += Float(sin(2 * .pi * accent * time) * envelope * amplitude)
                    state.oneShotClickFrame += 1
                }

                if state.referenceFrame >= 0 && state.referenceFrame < state.referenceTotalFrames {
                    let time = Double(state.referenceFrame) / rate
                    let length = Double(state.referenceTotalFrames) / rate
                    let attack = min(1, time / 0.012)
                    let release = min(1, max(0, length - time) / 0.12)
                    let envelope = attack * release * exp(-time * 1.25)
                    let fundamental = sin(2 * .pi * state.referenceFrequency * time)
                    let harmonic = sin(2 * .pi * state.referenceFrequency * 2 * time) * 0.22
                    sample += Float((fundamental + harmonic) * envelope * referenceAmplitude)
                    state.referenceFrame += 1
                }

                state.frameInBeat += 1

                for buffer in buffers {
                    let pointer = UnsafeMutableBufferPointer<Float>(buffer)
                    if frame < pointer.count { pointer[frame] = sample }
                }
            }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
        sourceNode = node
        return true
    }
}
