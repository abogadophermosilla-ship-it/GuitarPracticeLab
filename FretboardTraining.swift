import Foundation
import SwiftData

extension RhythmicFigure {
    /// Figuras con una duración uniforme que pueden definir una ventana de una sola nota.
    static let fretboardChoices: [RhythmicFigure] = [
        .wholeNotes,
        .halfNotes,
        .quarterNotes,
        .eighthNotes,
        .eighthNoteTriplets,
        .sixteenthNotes
    ]

    var fretboardQuarterNoteLength: Double {
        switch self {
        case .wholeNotes: 4
        case .halfNotes: 2
        case .eighthNotes: 0.5
        case .eighthNoteTriplets: 1.0 / 3.0
        case .sixteenthNotes: 0.25
        default: 1
        }
    }

    func fretboardWindowSeconds(bpm: Int) -> Double {
        fretboardQuarterNoteLength * 60 / Double(max(30, bpm))
    }
}

struct FretboardPosition: Hashable, Identifiable, Sendable {
    let stringNumber: Int
    let fret: Int
    let midi: Int

    var id: String { "\(stringNumber)-\(fret)" }
    var noteClass: Int { ((midi % 12) + 12) % 12 }
    var noteName: String { GuitarFretboard.noteName(for: noteClass) }
    var octave: Int { midi / 12 - 1 }
    var scientificName: String { "\(noteName)\(octave)" }
}

/// Geometría y afinación usadas por el entrenador. El reconocimiento comprueba altura y octava;
/// como dos posiciones al unísono producen la misma altura, la pantalla también indica la cuerda
/// que se debe usar y el alumno conserva el control de la posición física.
enum GuitarFretboard {
    static let minimumFret = 1
    static let maximumFret = 13
    static let stringNumbers = Array(1...6)
    static let naturalNoteClasses: Set<Int> = [0, 2, 4, 5, 7, 9, 11]

    /// Afinación estándar, de la primera cuerda (E4) a la sexta (E2).
    private static let openMIDIs = [64, 59, 55, 50, 45, 40]
    private static let sharpNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    private static let flatNames = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]

    static func openMIDI(for stringNumber: Int) -> Int? {
        guard stringNumbers.contains(stringNumber) else { return nil }
        return openMIDIs[stringNumber - 1]
    }

    static func position(stringNumber: Int, fret: Int) -> FretboardPosition? {
        guard
            let open = openMIDI(for: stringNumber),
            (minimumFret...maximumFret).contains(fret)
        else { return nil }
        return FretboardPosition(stringNumber: stringNumber, fret: fret, midi: open + fret)
    }

    static func positions(
        for noteClass: Int,
        on stringNumber: Int? = nil,
        fretRange: ClosedRange<Int> = minimumFret...maximumFret
    ) -> [FretboardPosition] {
        let normalized = ((noteClass % 12) + 12) % 12
        let strings = stringNumber.map { [$0] } ?? Array(stringNumbers.reversed())
        return strings.flatMap { string in
            fretRange.compactMap { fret in
                guard let position = position(stringNumber: string, fret: fret) else { return nil }
                return position.noteClass == normalized ? position : nil
            }
        }
    }

    static var allPositions: [FretboardPosition] {
        stringNumbers.flatMap { string in
            (minimumFret...maximumFret).compactMap { position(stringNumber: string, fret: $0) }
        }
    }

    static func noteName(for noteClass: Int, preferFlats: Bool = false) -> String {
        let normalized = ((noteClass % 12) + 12) % 12
        return (preferFlats ? flatNames : sharpNames)[normalized]
    }

    static func stringLabel(_ stringNumber: Int) -> String {
        switch stringNumber {
        case 1: "cuerda 1 (aguda)"
        case 6: "cuerda 6 (grave)"
        default: "cuerda \(stringNumber)"
        }
    }
}

enum FretboardExerciseKind: String, Codable, CaseIterable, Sendable {
    case noteOnString
    case allPositions

    var label: String {
        switch self {
        case .noteOnString: "Nota → cuerda"
        case .allPositions: "Toda la nota"
        }
    }
}

struct FretboardQuestion: Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: FretboardExerciseKind
    let noteClass: Int
    let stringNumber: Int?
    let targets: [FretboardPosition]
    let isDiagnostic: Bool
    let isRetry: Bool
    let preferFlats: Bool

    init(
        id: UUID = UUID(),
        kind: FretboardExerciseKind,
        noteClass: Int,
        stringNumber: Int?,
        targets: [FretboardPosition],
        isDiagnostic: Bool = false,
        isRetry: Bool = false,
        preferFlats: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.noteClass = ((noteClass % 12) + 12) % 12
        self.stringNumber = stringNumber
        self.targets = targets
        self.isDiagnostic = isDiagnostic
        self.isRetry = isRetry
        self.preferFlats = preferFlats
    }

    static func noteOnString(
        noteClass: Int,
        stringNumber: Int,
        isDiagnostic: Bool = false,
        isRetry: Bool = false,
        preferFlats: Bool = false
    ) -> FretboardQuestion {
        FretboardQuestion(
            kind: .noteOnString,
            noteClass: noteClass,
            stringNumber: stringNumber,
            targets: GuitarFretboard.positions(for: noteClass, on: stringNumber),
            isDiagnostic: isDiagnostic,
            isRetry: isRetry,
            preferFlats: preferFlats
        )
    }

    static func allPositions(noteClass: Int, preferFlats: Bool = false) -> FretboardQuestion {
        FretboardQuestion(
            kind: .allPositions,
            noteClass: noteClass,
            stringNumber: nil,
            targets: GuitarFretboard.positions(for: noteClass),
            isDiagnostic: false,
            preferFlats: preferFlats
        )
    }

    var displayNoteName: String {
        GuitarFretboard.noteName(for: noteClass, preferFlats: preferFlats)
    }

    var title: String {
        switch kind {
        case .noteOnString:
            isRetry
                ? "Encuentra de nuevo \(displayNoteName) en la \(GuitarFretboard.stringLabel(stringNumber ?? 1))"
                : "Toca un \(displayNoteName) en la \(GuitarFretboard.stringLabel(stringNumber ?? 1))"
        case .allPositions:
            "Toca todos los \(displayNoteName) entre los trastes 1 y 13"
        }
    }

    var instructions: String {
        switch kind {
        case .noteOnString:
            isRetry
                ? "Esta combinación costó antes. Localízala sin recorrer los trastes uno por uno."
                : (targets.count > 1
                ? "Hay más de una posición válida en esa cuerda; cualquiera sirve."
                : "Encuentra la posición sin mirar una respuesta y deja sonar la nota.")
        case .allPositions:
            "Avanza de la cuerda 6 a la 1 y, si una cuerda tiene dos posiciones, tócalas de grave a agudo."
        }
    }

    func reframed(around position: FretboardPosition? = nil) -> FretboardQuestion {
        let target = position ?? targets.first
        switch kind {
        case .noteOnString:
            return FretboardQuestion.noteOnString(
                noteClass: noteClass,
                stringNumber: stringNumber ?? target?.stringNumber ?? 1,
                isRetry: true,
                preferFlats: preferFlats
            )
        case .allPositions:
            return FretboardQuestion.noteOnString(
                noteClass: noteClass,
                stringNumber: target?.stringNumber ?? 6,
                isRetry: true,
                preferFlats: preferFlats
            )
        }
    }
}

@Model
final class FretboardNoteProgress {
    @Attribute(.unique) var id: String
    var noteClass: Int
    var stringNumber: Int
    var attemptCount: Int
    var correctCount: Int
    var wrongCount: Int
    var currentStreak: Int
    var totalResponseSeconds: Double
    var fastestResponseSeconds: Double
    var masteredBPM: Int
    var lastPracticedAt: Date?
    var nextReviewDate: Date

    init(noteClass: Int, stringNumber: Int) {
        let normalized = ((noteClass % 12) + 12) % 12
        self.id = Self.key(noteClass: normalized, stringNumber: stringNumber)
        self.noteClass = normalized
        self.stringNumber = stringNumber
        self.attemptCount = 0
        self.correctCount = 0
        self.wrongCount = 0
        self.currentStreak = 0
        self.totalResponseSeconds = 0
        self.fastestResponseSeconds = 0
        self.masteredBPM = 0
        self.lastPracticedAt = nil
        self.nextReviewDate = .distantPast
    }

    static func key(noteClass: Int, stringNumber: Int) -> String {
        "note-\(((noteClass % 12) + 12) % 12)-string-\(stringNumber)"
    }

    var accuracy: Double {
        guard attemptCount > 0 else { return 0 }
        return Double(correctCount) / Double(attemptCount)
    }

    var averageResponseSeconds: Double {
        guard attemptCount > 0 else { return 0 }
        return totalResponseSeconds / Double(attemptCount)
    }

    func record(isCorrect: Bool, responseSeconds: Double, bpm: Int, now: Date = .now) {
        attemptCount += 1
        totalResponseSeconds += max(0, responseSeconds)
        if isCorrect {
            correctCount += 1
            currentStreak += 1
            if fastestResponseSeconds == 0 || responseSeconds < fastestResponseSeconds {
                fastestResponseSeconds = responseSeconds
            }
            if currentStreak >= 3 { masteredBPM = max(masteredBPM, bpm) }
            let interval = currentStreak >= 6 ? 7 : (currentStreak >= 3 ? 3 : 1)
            nextReviewDate = Calendar.current.date(byAdding: .day, value: interval, to: now) ?? now
        } else {
            wrongCount += 1
            currentStreak = 0
            nextReviewDate = now
        }
        lastPracticedAt = now
    }
}

@Model
final class FretboardTrainingProfile {
    @Attribute(.unique) var id: String
    var hasCompletedAssessment: Bool
    var diagnosticAttempts: Int
    var diagnosticCorrect: Int
    var diagnosticResponseSeconds: Double
    var currentLevel: Int
    var recommendedBPM: Int
    var totalAttempts: Int
    var totalCorrect: Int
    var currentFastStreak: Int
    var bestFastStreak: Int
    var sessionsCompleted: Int
    var lastSessionDate: Date?

    init(id: String = "singleton") {
        self.id = id
        self.hasCompletedAssessment = false
        self.diagnosticAttempts = 0
        self.diagnosticCorrect = 0
        self.diagnosticResponseSeconds = 0
        self.currentLevel = 1
        self.recommendedBPM = 40
        self.totalAttempts = 0
        self.totalCorrect = 0
        self.currentFastStreak = 0
        self.bestFastStreak = 0
        self.sessionsCompleted = 0
        self.lastSessionDate = nil
    }

    static func fetchOrCreate(in context: ModelContext) -> FretboardTrainingProfile {
        if let existing = try? context.fetch(FetchDescriptor<FretboardTrainingProfile>()).first {
            return existing
        }
        let created = FretboardTrainingProfile()
        context.insert(created)
        return created
    }

    var overallAccuracy: Double {
        guard totalAttempts > 0 else { return 0 }
        return Double(totalCorrect) / Double(totalAttempts)
    }

    func recordAttempt(isCorrect: Bool, responseSeconds: Double, targetSeconds: Double) {
        totalAttempts += 1
        if isCorrect { totalCorrect += 1 }

        if !hasCompletedAssessment {
            diagnosticAttempts += 1
            diagnosticResponseSeconds += max(0, responseSeconds)
            if isCorrect { diagnosticCorrect += 1 }
            if diagnosticAttempts >= FretboardTrainingScheduler.diagnosticAttemptCount {
                hasCompletedAssessment = true
                let accuracy = Double(diagnosticCorrect) / Double(max(1, diagnosticAttempts))
                let average = diagnosticResponseSeconds / Double(max(1, diagnosticAttempts))
                currentLevel = FretboardTrainingScheduler.assessedLevel(accuracy: accuracy, averageSeconds: average)
                recommendedBPM = FretboardTrainingScheduler.startingBPM(for: currentLevel)
            }
        }

        if isCorrect && responseSeconds <= targetSeconds {
            currentFastStreak += 1
            bestFastStreak = max(bestFastStreak, currentFastStreak)
        } else {
            currentFastStreak = 0
        }
    }

    func finishSession(
        correct: Int,
        attempts: Int,
        averageSeconds: Double,
        bpm: Int,
        targetSeconds: Double? = nil
    ) {
        sessionsCompleted += 1
        lastSessionDate = .now
        guard hasCompletedAssessment, attempts >= 6 else { return }

        let accuracy = Double(correct) / Double(max(1, attempts))
        let target = targetSeconds
            ?? FretboardTrainingScheduler.targetSeconds(level: currentLevel, bpm: bpm)
        if accuracy >= 0.85 && averageSeconds <= target * 1.15 {
            recommendedBPM = min(120, max(recommendedBPM, bpm) + 5)
            if currentFastStreak >= 8 || recommendedBPM >= FretboardTrainingScheduler.levelUpBPM(currentLevel) {
                currentLevel = min(5, currentLevel + 1)
                currentFastStreak = 0
            }
        } else if accuracy < 0.60 {
            recommendedBPM = max(30, min(recommendedBPM, bpm) - 5)
        } else {
            recommendedBPM = max(recommendedBPM, bpm)
        }
    }
}

struct FretboardWeakness: Identifiable, Equatable {
    let noteClass: Int
    let attempts: Int
    let accuracy: Double
    let averageSeconds: Double

    var id: Int { noteClass }
    var noteName: String { GuitarFretboard.noteName(for: noteClass) }
}

enum FretboardTrainingScheduler {
    static let diagnosticAttemptCount = 18

    static func levelTitle(_ level: Int) -> String {
        switch level {
        case ...1: "Orientación"
        case 2: "Mapa natural"
        case 3: "Dominio natural"
        case 4: "Alteraciones y conexiones"
        default: "Fluidez cromática"
        }
    }

    /// Las alteraciones se introducen únicamente cuando el alumno ya demostró dominio avanzado
    /// de las notas naturales. La altura reconocida es la misma para nombres enarmónicos; la
    /// consigna alterna la escritura para entrenar tanto sostenidos como bemoles.
    static func usesAccidentals(at level: Int) -> Bool {
        level >= 4
    }

    /// La meta rítmica es siempre una negra por nota. El nivel decide qué notas aparecen, no
    /// cuántos pulsos puede ocupar una respuesta correcta.
    static func targetSeconds(level _: Int, bpm: Int) -> Double {
        60 / Double(max(30, bpm))
    }

    static func timeoutSeconds(level: Int, bpm: Int, isDiagnostic: Bool) -> Double {
        let target = targetSeconds(level: level, bpm: bpm)
        return isDiagnostic ? max(12, target * 2) : max(4, target * 1.8)
    }

    static func assessedLevel(accuracy: Double, averageSeconds: Double) -> Int {
        switch (accuracy, averageSeconds) {
        case let (accuracy, seconds) where accuracy >= 0.93 && seconds <= 3: 5
        case let (accuracy, seconds) where accuracy >= 0.85 && seconds <= 4.5: 4
        case let (accuracy, seconds) where accuracy >= 0.75 && seconds <= 6: 3
        case let (accuracy, _) where accuracy >= 0.60: 2
        default: 1
        }
    }

    static func startingBPM(for level: Int) -> Int {
        switch level {
        case ...1: 40
        case 2: 45
        case 3: 55
        case 4: 65
        default: 75
        }
    }

    static func levelUpBPM(_ level: Int) -> Int {
        switch level {
        case ...1: 50
        case 2: 60
        case 3: 70
        case 4: 85
        default: 120
        }
    }

    static func nextQuestion(
        profile: FretboardTrainingProfile,
        progress: [FretboardNoteProgress],
        serial: Int
    ) -> FretboardQuestion {
        if !profile.hasCompletedAssessment {
            return diagnosticQuestion(at: profile.diagnosticAttempts)
        }

        let level = min(5, max(1, profile.currentLevel))
        let cells = rankedCells(progress: progress, level: level)
        let safeSerial = serial == Int.min ? 0 : abs(serial)
        let stringOrder = [6, 1, 5, 2, 4, 3]
        let targetString = stringOrder[safeSerial % stringOrder.count]
        let cellsOnString = cells.filter { $0.stringNumber == targetString }
        let round = safeSerial / stringOrder.count
        let cell = cellsOnString[round % min(8, cellsOnString.count)]
        let preferFlats = !GuitarFretboard.naturalNoteClasses.contains(cell.noteClass)
            && safeSerial.isMultiple(of: 2)

        if level >= 4 && serial > 0 && serial.isMultiple(of: level == 4 ? 5 : 3) {
            return .allPositions(noteClass: cell.noteClass, preferFlats: preferFlats)
        }

        return .noteOnString(
            noteClass: cell.noteClass,
            stringNumber: cell.stringNumber,
            preferFlats: preferFlats
        )
    }

    static func weaknesses(from progress: [FretboardNoteProgress], limit: Int = 5) -> [FretboardWeakness] {
        let attempted = progress.filter { $0.attemptCount > 0 }
        let grouped = Dictionary(grouping: attempted, by: \FretboardNoteProgress.noteClass)
        return grouped.map { noteClass, records in
            let attempts = records.reduce(0) { $0 + $1.attemptCount }
            let correct = records.reduce(0) { $0 + $1.correctCount }
            let seconds = records.reduce(0) { $0 + $1.totalResponseSeconds }
            return FretboardWeakness(
                noteClass: noteClass,
                attempts: attempts,
                accuracy: Double(correct) / Double(max(1, attempts)),
                averageSeconds: seconds / Double(max(1, attempts))
            )
        }
        .sorted {
            if $0.accuracy != $1.accuracy { return $0.accuracy < $1.accuracy }
            if $0.averageSeconds != $1.averageSeconds { return $0.averageSeconds > $1.averageSeconds }
            return $0.attempts > $1.attempts
        }
        .prefix(limit)
        .map { $0 }
    }

    private struct Cell {
        let noteClass: Int
        let stringNumber: Int
        let weakness: Double
    }

    private static func rankedCells(progress: [FretboardNoteProgress], level: Int) -> [Cell] {
        let byID = Dictionary(uniqueKeysWithValues: progress.map { ($0.id, $0) })
        let strings = GuitarFretboard.stringNumbers
        let noteClasses = usesAccidentals(at: level)
            ? Array(0..<12)
            : GuitarFretboard.naturalNoteClasses.sorted()
        let now = Date.now

        return strings.flatMap { string in
            noteClasses.map { noteClass in
                let record = byID[FretboardNoteProgress.key(noteClass: noteClass, stringNumber: string)]
                let weakness: Double
                if let record, record.attemptCount > 0 {
                    let errorWeight = (1 - record.accuracy) * 5
                    let speedWeight = min(3, record.averageResponseSeconds / 3)
                    let dueWeight = record.nextReviewDate <= now ? 1.5 : 0
                    weakness = errorWeight + speedWeight + dueWeight + 0.25 / Double(record.attemptCount)
                } else {
                    weakness = 4
                }
                return Cell(noteClass: noteClass, stringNumber: string, weakness: weakness)
            }
        }
        .sorted {
            if $0.weakness != $1.weakness { return $0.weakness > $1.weakness }
            if $0.stringNumber != $1.stringNumber { return $0.stringNumber > $1.stringNumber }
            return $0.noteClass < $1.noteClass
        }
    }

    private static func diagnosticQuestion(at index: Int) -> FretboardQuestion {
        let strings = [6, 1, 5, 2, 4, 3]
        let noteClasses = [0, 7, 5, 2, 9, 4, 11, 2, 9, 4, 0, 7, 5, 11, 0, 5, 2, 9]
        let safeIndex = ((index % diagnosticAttemptCount) + diagnosticAttemptCount) % diagnosticAttemptCount
        let string = strings[safeIndex % strings.count]
        let noteClass = noteClasses[safeIndex]
        return .noteOnString(noteClass: noteClass, stringNumber: string, isDiagnostic: true)
    }
}
