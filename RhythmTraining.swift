import Foundation

struct RhythmTapMeasurement: Equatable, Identifiable {
    let id: UUID
    let gridIndex: Int
    let offsetMilliseconds: Double

    init(id: UUID = UUID(), gridIndex: Int, offsetMilliseconds: Double) {
        self.id = id
        self.gridIndex = gridIndex
        self.offsetMilliseconds = offsetMilliseconds
    }

    var absoluteOffsetMilliseconds: Double { abs(offsetMilliseconds) }

    var timingLabel: String {
        if abs(offsetMilliseconds) < 1 { return "Justo" }
        return offsetMilliseconds < 0
            ? "\(Int(abs(offsetMilliseconds).rounded())) ms antes"
            : "\(Int(offsetMilliseconds.rounded())) ms después"
    }
}

struct RhythmTrainingSummary: Equatable {
    let averageAbsoluteOffsetMilliseconds: Double
    let accuracy: Double
    let closeTapRatio: Double
    let tapCount: Int

    var percentage: Int { Int((accuracy * 100).rounded()) }

    var label: String {
        switch accuracy {
        case 0.86...: "Pulso sólido"
        case 0.70..<0.86: "Bastante estable"
        case 0.52..<0.70: "En desarrollo"
        default: "Conviene bajar el tempo"
        }
    }
}

/// Matemática pura del entrenador: aproxima cada toque a la rejilla rítmica más cercana y conserva
/// el signo del error (antes/después). El audio solo marca el pulso; no participa en la medición.
enum RhythmTimingAnalyzer {
    static let trainingFigures: [RhythmicFigure] = [
        .quarterNotes,
        .eighthNotes,
        .eighthNoteTriplets,
        .sixteenthNotes,
        .quintuplets,
        .sextuplets
    ]

    static func eventsPerBeat(for figure: RhythmicFigure) -> Double {
        switch figure {
        case .wholeNotes: 0.25
        case .dottedHalfNotes: 1.0 / 3.0
        case .halfNotes: 0.5
        case .dottedQuarterNotes: 2.0 / 3.0
        case .quarterNoteTriplets: 1.5
        case .quarterNotes: 1
        case .eighthNotes, .shuffle, .dottedLongShort, .dottedShortLong: 2
        case .eighthNoteTriplets, .gallop, .reverseGallop: 3
        case .sixteenthNotes: 4
        case .quintuplets: 5
        case .sextuplets: 6
        case .septuplets: 7
        case .thirtySecondNotes: 8
        case .unspecified: 1
        }
    }

    static func measurement(
        tapUptime: TimeInterval,
        startUptime: TimeInterval,
        bpm: Int,
        figure: RhythmicFigure
    ) -> RhythmTapMeasurement? {
        guard bpm > 0, tapUptime >= startUptime else { return nil }
        let gridInterval = 60 / Double(bpm) / eventsPerBeat(for: figure)
        guard gridInterval.isFinite, gridInterval > 0 else { return nil }
        let elapsed = tapUptime - startUptime
        let gridIndex = Int((elapsed / gridInterval).rounded())
        let expected = Double(gridIndex) * gridInterval
        return RhythmTapMeasurement(
            gridIndex: gridIndex,
            offsetMilliseconds: (elapsed - expected) * 1_000
        )
    }

    static func summary(for taps: [RhythmTapMeasurement]) -> RhythmTrainingSummary? {
        guard !taps.isEmpty else { return nil }
        let absoluteOffsets = taps.map(\.absoluteOffsetMilliseconds)
        let average = absoluteOffsets.reduce(0, +) / Double(absoluteOffsets.count)
        let closeCount = absoluteOffsets.filter { $0 <= 60 }.count
        let closeRatio = Double(closeCount) / Double(taps.count)
        let precision = min(max(1 - average / 140, 0), 1)
        return RhythmTrainingSummary(
            averageAbsoluteOffsetMilliseconds: average,
            accuracy: precision * 0.72 + closeRatio * 0.28,
            closeTapRatio: closeRatio,
            tapCount: taps.count
        )
    }
}
