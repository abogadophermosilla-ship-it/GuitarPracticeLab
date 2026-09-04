import XCTest
import SwiftData
@testable import GuitarPracticeLab

final class FretboardTrainingTests: XCTestCase {
    func testDuracionDeRutinasDiarias() {
        XCTAssertEqual(DailyPracticeRoutine.chromaticMinutes, 6)
        XCTAssertEqual(DailyPracticeRoutine.fretboardMinutes, 7)
    }

    func testAfinacionEstandarYPosicionesDeC() {
        XCTAssertEqual(GuitarFretboard.openMIDI(for: 1), 64)
        XCTAssertEqual(GuitarFretboard.openMIDI(for: 6), 40)

        let positions = GuitarFretboard.positions(for: 0)
        XCTAssertEqual(positions.count, 7)
        XCTAssertEqual(positions.map(\.stringNumber), [6, 5, 4, 3, 2, 2, 1])
        XCTAssertEqual(positions.map(\.fret), [8, 3, 10, 5, 1, 13, 8])
        XCTAssertTrue(positions.allSatisfy { $0.noteName == "C" })
    }

    func testPreguntaNotaEnCuerdaAceptaLasDosPosicionesValidas() {
        let question = FretboardQuestion.noteOnString(noteClass: 5, stringNumber: 1)
        XCTAssertEqual(question.targets.map(\.fret), [1, 13])
        XCTAssertEqual(question.targets.map(\.midi), [65, 77])
        XCTAssertTrue(question.title.contains("F"))
        XCTAssertTrue(question.title.contains("cuerda 1"))
    }

    func testUnErrorVuelveComoBusquedaSinRevelarUnTraste() {
        let original = FretboardQuestion.noteOnString(noteClass: 0, stringNumber: 5)
        let reframed = original.reframed()
        XCTAssertEqual(reframed.kind, .noteOnString)
        XCTAssertEqual(reframed.stringNumber, 5)
        XCTAssertEqual(reframed.noteClass, 0)
        XCTAssertTrue(reframed.isRetry)
        XCTAssertTrue(reframed.title.contains("de nuevo"))
        XCTAssertFalse(reframed.title.localizedCaseInsensitiveContains("traste"))
    }

    func testDiagnosticoNuncaPreguntaUnaPosicionEspecifica() {
        let profile = FretboardTrainingProfile()
        var strings = Set<Int>()
        for attempt in 0..<FretboardTrainingScheduler.diagnosticAttemptCount {
            profile.diagnosticAttempts = attempt
            let question = FretboardTrainingScheduler.nextQuestion(
                profile: profile,
                progress: [],
                serial: attempt
            )
            XCTAssertEqual(question.kind, .noteOnString)
            XCTAssertFalse(question.title.localizedCaseInsensitiveContains("traste"))
            XCTAssertTrue(GuitarFretboard.naturalNoteClasses.contains(question.noteClass))
            strings.insert(question.stringNumber ?? 0)
        }
        XCTAssertEqual(strings, Set(GuitarFretboard.stringNumbers))
    }

    func testNivelesInicialesRotanLasSeisCuerdasYUsanSoloNaturales() {
        let profile = FretboardTrainingProfile()
        profile.hasCompletedAssessment = true

        for level in 1...3 {
            profile.currentLevel = level
            let questions = (0..<18).map {
                FretboardTrainingScheduler.nextQuestion(profile: profile, progress: [], serial: $0)
            }
            XCTAssertEqual(Set(questions.compactMap(\.stringNumber)), Set(GuitarFretboard.stringNumbers))
            XCTAssertTrue(questions.allSatisfy {
                GuitarFretboard.naturalNoteClasses.contains($0.noteClass)
            })
        }
    }

    func testNivelAvanzadoIntroduceSostenidosYBemoles() {
        let profile = FretboardTrainingProfile()
        profile.hasCompletedAssessment = true
        profile.currentLevel = 4

        let questions = (0..<96).map {
            FretboardTrainingScheduler.nextQuestion(profile: profile, progress: [], serial: $0)
        }
        let altered = questions.filter {
            !GuitarFretboard.naturalNoteClasses.contains($0.noteClass)
        }

        XCTAssertFalse(altered.isEmpty)
        XCTAssertTrue(altered.contains { $0.displayNoteName.contains("♯") })
        XCTAssertTrue(altered.contains { $0.displayNoteName.contains("♭") })
        XCTAssertFalse(FretboardTrainingScheduler.usesAccidentals(at: 3))
        XCTAssertTrue(FretboardTrainingScheduler.usesAccidentals(at: 4))
    }

    func testEvaluacionInicialAsignaNivelSegunPrecisionYTiempo() {
        XCTAssertEqual(FretboardTrainingScheduler.assessedLevel(accuracy: 0.55, averageSeconds: 8), 1)
        XCTAssertEqual(FretboardTrainingScheduler.assessedLevel(accuracy: 0.70, averageSeconds: 7), 2)
        XCTAssertEqual(FretboardTrainingScheduler.assessedLevel(accuracy: 0.80, averageSeconds: 5), 3)
        XCTAssertEqual(FretboardTrainingScheduler.assessedLevel(accuracy: 0.88, averageSeconds: 4), 4)
        XCTAssertEqual(FretboardTrainingScheduler.assessedLevel(accuracy: 0.95, averageSeconds: 2.5), 5)
    }

    func testTempoDelMastilCalculaUnaVentanaPorFigura() {
        XCTAssertEqual(FretboardTrainingScheduler.targetSeconds(level: 1, bpm: 60), 1)
        XCTAssertEqual(RhythmicFigure.wholeNotes.fretboardWindowSeconds(bpm: 60), 4)
        XCTAssertEqual(RhythmicFigure.halfNotes.fretboardWindowSeconds(bpm: 60), 2)
        XCTAssertEqual(RhythmicFigure.quarterNotes.fretboardWindowSeconds(bpm: 60), 1)
        XCTAssertEqual(RhythmicFigure.eighthNotes.fretboardWindowSeconds(bpm: 60), 0.5)
        XCTAssertEqual(RhythmicFigure.eighthNoteTriplets.fretboardWindowSeconds(bpm: 60), 1.0 / 3.0)
        XCTAssertEqual(RhythmicFigure.sixteenthNotes.fretboardWindowSeconds(bpm: 60), 0.25)
        XCTAssertEqual(RhythmicFigure.fretboardChoices.first, .wholeNotes)
        XCTAssertEqual(RhythmicFigure.fretboardChoices.last, .sixteenthNotes)
    }

    func testPerfilCompletaDiagnosticoYSubeTempoConSesionSolida() {
        let profile = FretboardTrainingProfile()
        for _ in 0..<FretboardTrainingScheduler.diagnosticAttemptCount {
            profile.recordAttempt(isCorrect: true, responseSeconds: 2.5, targetSeconds: 6)
        }

        XCTAssertTrue(profile.hasCompletedAssessment)
        XCTAssertEqual(profile.currentLevel, 5)
        XCTAssertEqual(profile.recommendedBPM, 75)

        profile.finishSession(correct: 18, attempts: 20, averageSeconds: 0.75, bpm: 75)
        XCTAssertEqual(profile.recommendedBPM, 80)
    }

    func testProgresoPriorizaComoDebilidadLaNotaConMasErrores() {
        let c = FretboardNoteProgress(noteClass: 0, stringNumber: 6)
        c.record(isCorrect: false, responseSeconds: 8, bpm: 40)
        c.record(isCorrect: false, responseSeconds: 7, bpm: 40)

        let g = FretboardNoteProgress(noteClass: 7, stringNumber: 6)
        g.record(isCorrect: true, responseSeconds: 2, bpm: 40)
        g.record(isCorrect: true, responseSeconds: 2, bpm: 40)

        let weaknesses = FretboardTrainingScheduler.weaknesses(from: [g, c])
        XCTAssertEqual(weaknesses.first?.noteClass, 0)
        XCTAssertEqual(weaknesses.first?.accuracy, 0)
    }

    func testYINReconoceFundamentalesDeGuitarraConArmonicos() {
        let sampleRate = 48_000.0
        for midi in [40, 57, 72, 77] {
            let frequency = GuitarPitchMath.frequency(forMIDI: midi)
            let samples = (0..<8_192).map { index -> Float in
                let time = Double(index) / sampleRate
                let fundamental = 0.65 * sin(2 * .pi * frequency * time)
                let second = 0.22 * sin(2 * .pi * frequency * 2 * time)
                let third = 0.10 * sin(2 * .pi * frequency * 3 * time)
                return Float(fundamental + second + third)
            }
            let frame = GuitarPitchMath.analyze(samples: samples, sampleRate: sampleRate)
            XCTAssertEqual(frame.estimate?.midi, midi, "Falló MIDI \(midi)")
            XCTAssertLessThan(abs(frame.estimate?.cents ?? 100), 5)
            XCTAssertGreaterThan(frame.estimate?.confidence ?? 0, 0.7)
        }
    }

    func testAnalizadorIgnoraSilencio() {
        let frame = GuitarPitchMath.analyze(samples: Array(repeating: 0, count: 4_096), sampleRate: 48_000)
        XCTAssertNil(frame.estimate)
    }

    @MainActor
    func testSchemaV3PersisteProgresoYLaRutinaVuelveAlDiaSiguiente() throws {
        let schema = Schema(versionedSchema: SchemaV3.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let profile = FretboardTrainingProfile()
        let progress = FretboardNoteProgress(noteClass: 0, stringNumber: 5)
        progress.record(isCorrect: true, responseSeconds: 2, bpm: 40)
        let task = PracticeTask(
            title: "Notas del mástil · sesión adaptativa",
            category: .theory,
            plannedMinutes: 10,
            sourceKind: .fretboard
        )
        context.insert(profile)
        context.insert(progress)
        context.insert(task)
        try context.save()

        let completedAt = Date(timeIntervalSince1970: 1_780_000_000)
        let next = RecurringPracticeService.completeTask(task, completedAt: completedAt, in: context)
        XCTAssertTrue(task.isCompleted)
        XCTAssertEqual(next?.sourceKind, .fretboard)
        XCTAssertEqual(next?.plannedMinutes, 10)
        XCTAssertEqual(
            Calendar.current.dateComponents([.day], from: completedAt, to: next?.scheduledDate ?? completedAt).day,
            1
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<FretboardNoteProgress>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<FretboardTrainingProfile>()).count, 1)

        let archive = try DataExportService.buildArchive(from: context)
        XCTAssertEqual(archive.formatVersion, 7)
        XCTAssertEqual(archive.fretboardProgress.count, 1)
        XCTAssertEqual(archive.fretboardProgress.first?.noteClass, 0)
        XCTAssertEqual(archive.fretboardProfiles.count, 1)
    }
}
