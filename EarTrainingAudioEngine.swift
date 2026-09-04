import Foundation
import AVFoundation

/// Motor de audio de Entrenamiento de oído — mismo patrón que `MetronomeEngine.swift`: síntesis
/// sample a sample en el render block de un único `AVAudioSourceNode`, sin buffers pregrabados ni
/// archivos. A diferencia del metrónomo (pulso continuo), cada llamada arma una lista fija de
/// eventos — una nota, dos notas en secuencia, o varias notas simultáneas — y el engine se detiene
/// solo cuando terminan.
final class EarTrainingAudioEngine {

    private struct ToneEvent {
        let startFrame: Int
        let endFrame: Int
        let frequencies: [Double]
    }

    /// Igual que en `MetronomeEngine`: el render block corre en el hilo de audio en tiempo real, así
    /// que `events`/`totalFrames` se escriben una sola vez desde el hilo principal antes de arrancar
    /// el engine y no se tocan mientras suena.
    private final class State: @unchecked Sendable {
        var events: [ToneEvent] = []
        var totalFrames: Int = 0
        var frame: Int = 0
    }

    private let engine = AVAudioEngine()
    private let state = State()
    private var sourceNode: AVAudioSourceNode?
    private var sampleRate: Double = 44_100
    private var stopWorkItem: DispatchWorkItem?

    private let amplitude = 0.22
    private let noteDuration = 0.85
    private let melodicGap = 0.12
    private let chordDurationFactor = 1.3
    private let releaseTail = 0.4

    deinit { engine.stop() }

    /// Una sola nota de referencia para ejercicios auditivos que necesiten una altura aislada.
    func playNote(midi: Int) {
        let frequency = EarTrainingMath.frequency(forMidi: midi)
        let frames = Int(noteDuration * sampleRate)
        play(events: [ToneEvent(startFrame: 0, endFrame: frames, frequencies: [frequency])])
    }

    /// Dos notas en secuencia: la raíz y luego raíz + `semitones`.
    func playInterval(rootMidi: Int, semitones: Int) {
        let root = EarTrainingMath.frequency(forMidi: rootMidi)
        let target = EarTrainingMath.frequency(forMidi: rootMidi + semitones)
        let noteFrames = Int(noteDuration * sampleRate)
        let gapFrames = Int(melodicGap * sampleRate)
        play(events: [
            ToneEvent(startFrame: 0, endFrame: noteFrames, frequencies: [root]),
            ToneEvent(startFrame: noteFrames + gapFrames, endFrame: 2 * noteFrames + gapFrames, frequencies: [target])
        ])
    }

    /// Todas las notas del acorde a la vez, a partir de los semitonos relativos a la raíz.
    func playChord(rootMidi: Int, semitoneOffsets: [Int]) {
        let frequencies = semitoneOffsets.map { EarTrainingMath.frequency(forMidi: rootMidi + $0) }
        let frames = Int(noteDuration * chordDurationFactor * sampleRate)
        play(events: [ToneEvent(startFrame: 0, endFrame: frames, frequencies: frequencies)])
    }

    func stop() {
        stopWorkItem?.cancel()
        guard engine.isRunning else { return }
        engine.stop()
    }

    private func play(events: [ToneEvent]) {
        stop()
        if sourceNode == nil { buildGraph() }
        let lastEnd = events.map(\.endFrame).max() ?? 0
        state.events = events
        state.totalFrames = lastEnd + Int(releaseTail * sampleRate)
        state.frame = 0

        do {
            engine.prepare()
            try engine.start()
        } catch {
            return
        }

        let seconds = Double(state.totalFrames) / sampleRate
        let workItem = DispatchWorkItem { [weak self] in self?.engine.stop() }
        stopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: workItem)
    }

    private func buildGraph() {
        let output = engine.outputNode
        sampleRate = output.inputFormat(forBus: 0).sampleRate
        if sampleRate <= 0 { sampleRate = 44_100 }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else { return }

        let amplitude = amplitude
        let rate = sampleRate
        let state = state

        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)

            for frameOffset in 0..<Int(frameCount) {
                var sample: Float = 0
                if state.frame < state.totalFrames {
                    for event in state.events where state.frame >= event.startFrame && state.frame < event.endFrame {
                        let local = state.frame - event.startFrame
                        let time = Double(local) / rate
                        let noteLength = Double(event.endFrame - event.startFrame) / rate
                        let env = EarTrainingMath.envelope(time: time, length: noteLength)
                        var eventSample: Float = 0
                        for frequency in event.frequencies {
                            eventSample += Float(sin(2 * .pi * frequency * time) * env)
                        }
                        if !event.frequencies.isEmpty {
                            eventSample /= Float(event.frequencies.count)
                        }
                        sample += eventSample
                    }
                    sample *= Float(amplitude)
                }
                state.frame += 1

                for buffer in buffers {
                    let pointer = UnsafeMutableBufferPointer<Float>(buffer)
                    if frameOffset < pointer.count { pointer[frameOffset] = sample }
                }
            }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node
    }
}
