import Foundation

/// Compara una toma con otra ejecución del mismo pasaje. A diferencia del puntaje genérico de una
/// grabación, acá sí hay una referencia contra la que evaluar alturas y proporciones rítmicas.
enum ReferenceAudioEvidenceScorer {
    struct Result: Equatable {
        let score: Double
        let reliability: Double
        let summary: String
    }

    static func score(performanceMetadataJSON: String, referenceMetadataJSON: String) -> Result? {
        guard let performance = noteData(from: performanceMetadataJSON),
              let reference = noteData(from: referenceMetadataJSON),
              performance.pitches.count >= 3,
              reference.pitches.count >= 3 else { return nil }

        let matched = tolerantLongestCommonSubsequence(performance.pitches, reference.pitches)
        let pitchSimilarity = 2 * Double(matched)
            / Double(performance.pitches.count + reference.pitches.count)
        let completeness = Double(min(performance.pitches.count, reference.pitches.count))
            / Double(max(performance.pitches.count, reference.pitches.count))

        var weighted = pitchSimilarity * 0.78 + completeness * 0.22
        var timingDescription = ""
        if let timing = proportionalTimingSimilarity(
            performance.starts,
            reference.starts
        ) {
            weighted = pitchSimilarity * 0.62 + completeness * 0.18 + timing * 0.20
            timingDescription = " · proporción rítmica \(percent(timing))"
        }

        let evidenceCount = min(performance.pitches.count, reference.pitches.count)
        let reliability = min(0.94, 0.72 + Double(evidenceCount) / 100 * 0.22)
        return Result(
            score: min(max(weighted, 0), 1),
            reliability: reliability,
            summary: "coincidencia de notas \(percent(pitchSimilarity)) · cobertura \(percent(completeness))\(timingDescription)"
        )
    }

    private struct NoteData {
        let pitches: [Int]
        let starts: [Double]
    }

    private static func noteData(from json: String) -> NoteData? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let notes = root["notes"] as? [String: Any] else { return nil }
        let pitches = (notes["pitchSequence"] as? [NSNumber])?.map(\.intValue)
            ?? (notes["pitchSequence"] as? [Int]) ?? []
        let starts = (notes["startTimes"] as? [NSNumber])?.map(\.doubleValue)
            ?? (notes["startTimes"] as? [Double]) ?? []
        return NoteData(pitches: pitches, starts: starts)
    }

    /// LCS con tolerancia de un semitono para absorber pequeñas imprecisiones de Basic Pitch. Usa
    /// dos filas, no una matriz completa, para que una toma larga no multiplique memoria.
    private static func tolerantLongestCommonSubsequence(_ lhs: [Int], _ rhs: [Int]) -> Int {
        var previous = Array(repeating: 0, count: rhs.count + 1)
        for left in lhs {
            var current = Array(repeating: 0, count: rhs.count + 1)
            for (index, right) in rhs.enumerated() {
                current[index + 1] = abs(left - right) <= 1
                    ? previous[index] + 1
                    : max(previous[index + 1], current[index])
            }
            previous = current
        }
        return previous.last ?? 0
    }

    /// Compara razones entre intervalos, no milisegundos absolutos: la referencia puede estar a
    /// otro tempo y aun así comprobar si el fraseo relativo es el mismo.
    private static func proportionalTimingSimilarity(_ lhsStarts: [Double], _ rhsStarts: [Double]) -> Double? {
        let lhs = normalizedIntervals(lhsStarts)
        let rhs = normalizedIntervals(rhsStarts)
        let count = min(min(lhs.count, rhs.count), 128)
        guard count >= 2 else { return nil }
        let similarity = (0..<count).reduce(0.0) { total, index in
            let ratio = max(lhs[index], 0.001) / max(rhs[index], 0.001)
            return total + exp(-abs(log(ratio)))
        }
        return similarity / Double(count)
    }

    private static func normalizedIntervals(_ starts: [Double]) -> [Double] {
        let intervals = zip(starts.dropFirst(), starts)
            .map(-)
            .filter { $0 > 0.01 }
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted()
        let median = sorted[sorted.count / 2]
        guard median > 0 else { return [] }
        return intervals.map { $0 / median }
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }
}
