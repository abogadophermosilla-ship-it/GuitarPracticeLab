import Foundation

/// Funciones puras de Entrenamiento de oído — separadas de `EarTrainingAudioEngine` para poder
/// probarlas sin tocar `AVAudioEngine` (que no es determinístico en tests), mismo motivo por el que
/// el metrónomo no se testea directamente y sí lo testean sus consumidores puros.
enum EarTrainingMath {
    /// Frecuencia en Hz de una nota MIDI en temperamento igual, referencia A4 = 440Hz (MIDI 69).
    static func frequency(forMidi midi: Int) -> Double {
        440.0 * pow(2.0, Double(midi - 69) / 12.0)
    }

    /// Ataque corto + decaimiento exponencial, para que el tono sintetizado suene "pulsado" en vez
    /// de un pitido plano. `length` es la duración total de la nota en segundos.
    static func envelope(time: Double, length: Double) -> Double {
        let attack = 0.01
        if time < attack { return time / attack }
        let decay = time - attack
        let remaining = max(length - attack, 0.001)
        return exp(-3 * decay / remaining)
    }
}
