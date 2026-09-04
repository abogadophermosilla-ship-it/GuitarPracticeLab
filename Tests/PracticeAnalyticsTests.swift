import XCTest
import SwiftData
@testable import GuitarPracticeLab

/// Los `@Model` de SwiftData son clases normales hasta que se insertan en un contexto, así que
/// estas pruebas pueden construirlos a mano y ejercitar el cálculo puro sin base de datos.
final class PracticeAnalyticsTests: XCTestCase {

    private func session(daysAgo: Int, minutes: Int, category: PracticeCategory = .technique) -> PracticeSession {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        return PracticeSession(date: date, durationMinutes: minutes, category: category)
    }

    func testMinutosDeLaSemanaSoloCuentanDesdeElInicioDeSemana() {
        let start = PracticeAnalytics.startOfCurrentWeek()
        let daysIntoWeek = Calendar.current.dateComponents([.day], from: start, to: .now).day ?? 0

        let sessions = [
            session(daysAgo: 0, minutes: 30),
            session(daysAgo: daysIntoWeek + 3, minutes: 999)  // semana pasada
        ]

        XCTAssertEqual(PracticeAnalytics.totalMinutesThisWeek(sessions), 30)
    }

    func testDiasPracticadosNoCuentaDosVecesElMismoDia() {
        let sessions = [
            session(daysAgo: 0, minutes: 20),
            session(daysAgo: 0, minutes: 25)
        ]

        XCTAssertEqual(PracticeAnalytics.practicedDaysThisWeek(sessions), 1)
    }

    func testDailyPointsSiempreDevuelveLosSieteDias() {
        XCTAssertEqual(PracticeAnalytics.dailyPoints([]).count, 7)
    }

    func testCategoryPointsOmiteCategoriasSinMinutos() {
        let sessions = [session(daysAgo: 0, minutes: 40, category: .technique)]
        let points = PracticeAnalytics.categoryPoints(sessions)

        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.category, .technique)
        XCTAssertEqual(points.first?.minutes, 40)
    }

    func testPlanDiarioRespetaPresupuestoYProtegeLosSeisMinutosCromaticos() {
        let now = Date.now
        let chromatic = PracticeTask(
            title: "Cromático · Negras · 1-2-3-4 / 4-3-2-1",
            category: .technique,
            plannedMinutes: DailyPracticeRoutine.chromaticMinutes,
            priority: 0,
            scheduledDate: now,
            sourceKind: .library
        )
        let repertoire = PracticeTask(
            title: "Repertorio",
            category: .repertoire,
            plannedMinutes: 20,
            priority: 0,
            scheduledDate: now
        )
        let extra = PracticeTask(
            title: "Teoría",
            category: .theory,
            plannedMinutes: 20,
            priority: 1,
            scheduledDate: now
        )

        let plan = DailyPracticePlanner.makePlan(
            tasks: [extra, repertoire, chromatic],
            budgetMinutes: 30,
            now: now
        )

        XCTAssertEqual(plan.plannedMinutes, 26)
        XCTAssertTrue(plan.tasks.contains {
            $0.id == chromatic.id && $0.plannedMinutes == DailyPracticeRoutine.chromaticMinutes
        })
        XCTAssertEqual(plan.deferred.map(\.id), [extra.id])
    }

    func testPlanDiarioSiempreReservaUnaTareaDeRepertorio() {
        let now = Date.now
        let chromatic = PracticeTask(
            title: "Cromático diario",
            category: .technique,
            plannedMinutes: DailyPracticeRoutine.chromaticMinutes,
            priority: 0,
            scheduledDate: now,
            sourceKind: .library
        )
        let urgent = PracticeTask(
            title: "Técnica urgente",
            category: .technique,
            plannedMinutes: 20,
            priority: 0,
            scheduledDate: now
        )
        let repertoire = PracticeTask(
            title: "Canción diaria",
            category: .repertoire,
            plannedMinutes: 8,
            priority: 2,
            scheduledDate: now
        )

        let plan = DailyPracticePlanner.makePlan(
            tasks: [chromatic, urgent, repertoire],
            budgetMinutes: 20,
            now: now
        )

        XCTAssertTrue(plan.tasks.contains { $0.id == repertoire.id })
        XCTAssertTrue(plan.deferred.contains { $0.id == urgent.id })
    }

    func testRotacionDeRepertorioEligeLaCancionMenosPracticada() {
        let practiced = Song(title: "Ya practicada", durationSeconds: 240)
        let waiting = Song(title: "Pendiente", durationSeconds: 310)
        let oldSession = PracticeSession(
            date: .now,
            durationMinutes: 4,
            category: .repertoire,
            sourceKind: .repertoire,
            sourceID: practiced.id
        )

        XCTAssertEqual(
            DailyRepertoirePlanner.recommendedSong(
                songs: [practiced, waiting],
                sessions: [oldSession]
            )?.id,
            waiting.id
        )
        XCTAssertEqual(DailyRepertoirePlanner.plannedMinutes(for: waiting), 6)
    }

    func testDuracionExactaYPasadasConservanElCalculo() {
        let session = PracticeSession(
            durationMinutes: 11,
            durationSeconds: 634,
            category: .repertoire,
            repertoireRepetitions: 2,
            repertoireSongDurationSeconds: 317
        )

        XCTAssertEqual(session.formattedDuration, "10:34")
        XCTAssertEqual(session.expectedRepertoireSeconds, 634)
    }

    @MainActor
    func testSchemaV5PersisteDuracionYPasadasDeRepertorio() throws {
        let schema = Schema(versionedSchema: SchemaV5.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let song = Song(title: "Prueba", durationSeconds: 275)
        let session = PracticeSession(
            durationMinutes: 10,
            durationSeconds: 550,
            category: .repertoire,
            sourceKind: .repertoire,
            sourceID: song.id,
            repertoireRepetitions: 2,
            repertoireSongDurationSeconds: song.durationSeconds
        )
        container.mainContext.insert(song)
        container.mainContext.insert(session)
        try container.mainContext.save()

        let storedSong = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<Song>()).first)
        let storedSession = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<PracticeSession>()).first)
        XCTAssertEqual(storedSong.durationSeconds, 275)
        XCTAssertEqual(storedSession.repertoireRepetitions, 2)
        XCTAssertEqual(storedSession.expectedRepertoireSeconds, 550)
    }

    func testExcedenteSeDistribuyeSinSobrecargarElDiaSiguiente() {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: .now)
        let first = PracticeTask(title: "A", category: .technique, plannedMinutes: 20, scheduledDate: now)
        let second = PracticeTask(title: "B", category: .theory, plannedMinutes: 20, scheduledDate: now)

        let assignments = DailyPracticePlanner.redistributedDates(
            for: [first, second],
            among: [first, second],
            budgetMinutes: 30,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(assignments.count, 2)
        XCTAssertNotEqual(
            assignments[first.id].map(calendar.startOfDay(for:)),
            assignments[second.id].map(calendar.startOfDay(for:))
        )
    }

    func testAgregarAEstaSemanaBuscaUnDiaConCapacidadDentroDeSieteDias() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_787_875_200))
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let occupied = PracticeTask(
            title: "Día lleno",
            category: .technique,
            plannedMinutes: 45,
            scheduledDate: today
        )

        let result = WeeklyTaskScheduler.scheduledDate(
            for: 15,
            among: [occupied],
            dailyBudgetMinutes: 45,
            now: today,
            calendar: calendar
        )

        XCTAssertEqual(result, tomorrow)
        XCTAssertTrue(WeeklyTaskScheduler.contains(result, now: today, calendar: calendar))
    }

    @MainActor
    func testPlanSemanalPermiteElMismoEjercicioEnDiasDistintosPeroNoEnElMismoDia() throws {
        let container = try ModelContainer(
            for: PracticeTask.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let calendar = Calendar(identifier: .gregorian)
        let firstDay = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_787_875_200))
        let secondDay = calendar.date(byAdding: .day, value: 1, to: firstDay)!
        context.insert(PracticeTask(
            title: "Alternate picking",
            category: .technique,
            plannedMinutes: 15,
            scheduledDate: firstDay,
            sourceKind: .profesor
        ))
        try context.save()

        let anotherDay = PracticeTaskDeduplication.resolve(
            candidateTitle: "Alternate picking",
            candidateSourceKind: .profesor,
            candidateScheduledDate: secondDay,
            in: context,
            calendar: calendar
        )
        let sameDay = PracticeTaskDeduplication.resolve(
            candidateTitle: "Alternate picking",
            candidateSourceKind: .profesor,
            candidateScheduledDate: firstDay,
            in: context,
            calendar: calendar
        )

        if case .none = anotherDay {} else {
            XCTFail("El mismo ejercicio debe poder repetirse en otro día del plan semanal")
        }
        if case .keepExisting = sameDay {} else {
            XCTFail("No debe duplicarse el mismo ejercicio dentro de un día")
        }
    }

    func testPlanSemanalRecortaRespuestaIAAlPresupuestoEstricto() {
        let day = Date.now
        let items = [
            WeeklyPracticePlanItem(
                scheduledDate: day,
                title: "Canción",
                categoryRaw: PracticeCategory.repertoire.rawValue,
                minutes: 20
            ),
            WeeklyPracticePlanItem(
                scheduledDate: day,
                title: "Técnica",
                categoryRaw: PracticeCategory.technique.rawValue,
                minutes: 20
            )
        ]

        let fitted = WeeklyPracticePlannerService.fitToDailyBudget(items, dailyMinutes: 30)

        XCTAssertEqual(fitted.reduce(0) { $0 + $1.minutes }, 30)
        XCTAssertTrue(fitted.contains { $0.category == .repertoire })
    }

    func testPlanSemanalFijaCromaticosEnSeisMinutos() {
        let day = Date.now
        let items = [
            WeeklyPracticePlanItem(
                scheduledDate: day,
                title: "Calentamiento cromático",
                categoryRaw: PracticeCategory.technique.rawValue,
                minutes: 5
            ),
            WeeklyPracticePlanItem(
                scheduledDate: day,
                title: "Repertorio",
                categoryRaw: PracticeCategory.repertoire.rawValue,
                minutes: 15
            )
        ]

        let fitted = WeeklyPracticePlannerService.fitToDailyBudget(items, dailyMinutes: 15)

        XCTAssertEqual(fitted.reduce(0) { $0 + $1.minutes }, 15)
        XCTAssertEqual(
            fitted.first(where: { $0.title.contains("cromático") })?.minutes,
            DailyPracticeRoutine.chromaticMinutes
        )
    }

    func testPlanSemanalRecortaAntesElFocoDeMenorPrioridad() {
        let day = Date.now
        let band = WeeklyPracticePlanItem(
            scheduledDate: day,
            title: "Ensayo de la banda",
            categoryRaw: PracticeCategory.repertoire.rawValue,
            minutes: 20,
            planningFocusRaw: PracticePlanFocus.band.rawValue
        )
        let enjoyment = WeeklyPracticePlanItem(
            scheduledDate: day,
            title: "Canción por gusto",
            categoryRaw: PracticeCategory.repertoire.rawValue,
            minutes: 20,
            planningFocusRaw: PracticePlanFocus.enjoyment.rawValue
        )
        let preferences = PracticePlanPreferences(band: .high, enjoyment: .low)

        let fitted = WeeklyPracticePlannerService.fitToDailyBudget(
            [band, enjoyment],
            dailyMinutes: 30,
            preferences: preferences
        )

        XCTAssertEqual(fitted.first(where: { $0.planningFocus == .band })?.minutes, 20)
        XCTAssertEqual(fitted.first(where: { $0.planningFocus == .enjoyment })?.minutes, 10)
    }

    func testEnfoqueAltoSeConvierteEnPrioridadAltaDelDashboard() {
        let preferences = PracticePlanPreferences(
            lessons: .low,
            band: .high,
            weakTechniques: .normal
        )

        XCTAssertEqual(preferences.taskPriority(for: .band), 0)
        XCTAssertEqual(preferences.taskPriority(for: .lessons), 2)
        XCTAssertEqual(preferences.taskPriority(for: .weakTechniques), 1)
    }

    func testPlanesGuardadosSinFocoSiguenDecodificando() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "scheduledDate": 0,
          "title": "Plan anterior",
          "categoryRaw": "Técnica",
          "minutes": 15,
          "sourceTitle": "",
          "exerciseTitle": "",
          "targetBPM": 0,
          "instructions": "",
          "isSelected": true,
          "wasAddedToTasks": false
        }
        """

        let item = try JSONDecoder().decode(WeeklyPracticePlanItem.self, from: Data(json.utf8))

        XCTAssertNil(item.planningFocus)
    }
}

final class RoutineAnalyticsTests: XCTestCase {

    private func session(daysAgo: Int) -> PracticeSession {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        return PracticeSession(date: date, durationMinutes: 30)
    }

    func testRachaActualCuentaDiasConsecutivosHaciaAtras() {
        let signals = RoutineAnalytics.computeSignals(
            sessions: [session(daysAgo: 0), session(daysAgo: 1), session(daysAgo: 2), session(daysAgo: 5)],
            milestones: []
        )

        XCTAssertEqual(signals.currentStreakDays, 3)
        XCTAssertEqual(signals.longestStreakDays, 3)
    }

    func testRachaSobreviveAlDiaSinPracticarTodavia() {
        // Ayer y anteayer sí, hoy todavía no: la racha sigue viva.
        let signals = RoutineAnalytics.computeSignals(
            sessions: [session(daysAgo: 1), session(daysAgo: 2)],
            milestones: []
        )

        XCTAssertEqual(signals.currentStreakDays, 2)
    }

    func testHasEnoughDataExigeUnMinimoDeSesiones() {
        let pocas = RoutineAnalytics.computeSignals(sessions: [session(daysAgo: 1)], milestones: [])
        XCTAssertFalse(pocas.hasEnoughData)

        let suficientes = RoutineAnalytics.computeSignals(
            sessions: (0..<5).map { session(daysAgo: $0) },
            milestones: []
        )
        XCTAssertTrue(suficientes.hasEnoughData)
    }
}
