import Foundation

struct DrumStep: Codable, Identifiable {
    var id: UUID = UUID()
    let position: Int
    let kick: Bool
    let snare: Bool
    let hiHat: Bool

    enum CodingKeys: String, CodingKey {
        case position, kick, snare, hiHat
    }
}

struct GroovePattern: Codable {
    let title: String
    let style: String
    let bpm: Int
    let bars: Int
    let explanation: String
    let steps: [DrumStep]
}

enum GrooveGeneratorError: LocalizedError {
    case invalidResponse
    case externalMaterialsUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "El modelo no devolvió un groove válido de 16 pasos."
        case .externalMaterialsUnavailable:
            "Conecta el disco externo para guardar el MIDI dentro de VST/Clases/Proyectos."
        }
    }
}

enum GrooveGeneratorService {
    static func generate(
        request: String,
        bpm: Int,
        bars: Int,
        context: LearningContextSnapshot,
        backend: JSONCompletionBackend
    ) async throws -> GroovePattern {
        let prompt = """
        Diseña un groove de batería para practicar guitarra. Debe ser musical, repetible y fácil de \
        importar en Superior Drummer o Logic Pro. Usa una grilla de 16 semicorcheas de un compás \
        4/4; los pasos van de 0 a 15. La app repetirá esa grilla durante \(bars) compases.

        PEDIDO: \(request)
        TEMPO: \(bpm) BPM
        CONTEXTO DEL ALUMNO:
        \(context.text)

        Responde solo JSON:
        {
          "title": "nombre breve",
          "style": "estilo",
          "explanation": "cómo usarlo para practicar",
          "steps": [
            {"position": 0, "kick": true, "snare": false, "hiHat": true}
          ]
        }
        Incluye exactamente los 16 pasos, incluso cuando un paso esté vacío.
        """
        let raw = try await backend.completeJSON(prompt: prompt)
        let object = try JSONAIParser.object(from: raw)
        let rawSteps = object["steps"] as? [[String: Any]] ?? []
        let steps = rawSteps.compactMap { item -> DrumStep? in
            guard let position = item["position"] as? Int, (0...15).contains(position) else {
                return nil
            }
            return DrumStep(
                position: position,
                kick: item["kick"] as? Bool ?? false,
                snare: item["snare"] as? Bool ?? false,
                hiHat: item["hiHat"] as? Bool ?? false
            )
        }.sorted { $0.position < $1.position }
        guard steps.count == 16, Set(steps.map(\.position)).count == 16 else {
            throw GrooveGeneratorError.invalidResponse
        }
        return GroovePattern(
            title: object["title"] as? String ?? "Groove de práctica",
            style: object["style"] as? String ?? request,
            bpm: min(max(bpm, 30), 240),
            bars: min(max(bars, 1), 16),
            explanation: object["explanation"] as? String ?? "",
            steps: steps
        )
    }

    static func saveMIDI(_ groove: GroovePattern) throws -> URL {
        guard LearningMaterialsService.isAvailable else {
            throw GrooveGeneratorError.externalMaterialsUnavailable
        }
        let folder = LearningMaterialsService.projectsURL
            .appendingPathComponent("IA GuitarPracticeLab", isDirectory: true)
            .appendingPathComponent("Grooves", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeTitle = groove.title
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = folder.appendingPathComponent(
            "\(safeTitle)-\(groove.bpm)bpm-\(formatter.string(from: .now)).mid"
        )
        try MIDIFileWriter.data(for: groove).write(to: url, options: .atomic)
        return url
    }
}

private enum MIDIFileWriter {
    private struct NoteEvent {
        let tick: Int
        let bytes: [UInt8]
        let isNoteOff: Bool
    }

    static func data(for groove: GroovePattern) -> Data {
        let division = 480
        let ticksPerStep = division / 4
        var track: [UInt8] = []
        let microseconds = 60_000_000 / max(groove.bpm, 1)
        appendVariableLength(0, to: &track)
        track += [
            0xFF, 0x51, 0x03,
            UInt8((microseconds >> 16) & 0xFF),
            UInt8((microseconds >> 8) & 0xFF),
            UInt8(microseconds & 0xFF)
        ]
        appendVariableLength(0, to: &track)
        track += [0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08]

        var events: [NoteEvent] = []
        for bar in 0..<groove.bars {
            for step in groove.steps {
                let tick = (bar * 16 + step.position) * ticksPerStep
                if step.kick { appendDrum(note: 36, at: tick, to: &events) }
                if step.snare { appendDrum(note: 38, at: tick, to: &events) }
                if step.hiHat { appendDrum(note: 42, at: tick, velocity: 82, to: &events) }
            }
        }
        events.sort {
            if $0.tick == $1.tick { return $0.isNoteOff && !$1.isNoteOff }
            return $0.tick < $1.tick
        }

        var previousTick = 0
        for event in events {
            appendVariableLength(event.tick - previousTick, to: &track)
            track += event.bytes
            previousTick = event.tick
        }
        appendVariableLength(0, to: &track)
        track += [0xFF, 0x2F, 0x00]

        var bytes: [UInt8] = Array("MThd".utf8)
        bytes += [0x00, 0x00, 0x00, 0x06, 0x00, 0x00, 0x00, 0x01]
        bytes += [UInt8((division >> 8) & 0xFF), UInt8(division & 0xFF)]
        bytes += Array("MTrk".utf8)
        bytes += uint32Bytes(UInt32(track.count))
        bytes += track
        return Data(bytes)
    }

    private static func appendDrum(
        note: UInt8,
        at tick: Int,
        velocity: UInt8 = 104,
        to events: inout [NoteEvent]
    ) {
        events.append(NoteEvent(tick: tick, bytes: [0x99, note, velocity], isNoteOff: false))
        events.append(NoteEvent(tick: tick + 60, bytes: [0x89, note, 0], isNoteOff: true))
    }

    private static func appendVariableLength(_ value: Int, to bytes: inout [UInt8]) {
        var buffer = [UInt8(value & 0x7F)]
        var remaining = value >> 7
        while remaining > 0 {
            buffer.insert(UInt8((remaining & 0x7F) | 0x80), at: 0)
            remaining >>= 7
        }
        bytes += buffer
    }

    private static func uint32Bytes(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
    }
}
