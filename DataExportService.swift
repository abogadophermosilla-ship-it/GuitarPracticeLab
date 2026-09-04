import Foundation
import SwiftData

/// Exportación legible y portátil de todo lo que el usuario cargó a mano o generó usando la app.
///
/// Deliberadamente **no** incluye tres cosas, porque harían el archivo enorme sin servir fuera de
/// esta máquina: los textos completos de los PDFs indexados (`LibraryBook.pageTexts`), los recortes
/// de imagen de las preguntas de Academia (`AcademyQuestion.imageData`) y los bookmarks de seguridad
/// de archivos externos, que solo son válidos en este Mac. Todo eso sí está en el respaldo del store
/// que hace `DataBackupService` — ver la nota de esa clase sobre la división entre ambos.
enum DataExportService {

    // MARK: - Formato

    struct Archive: Codable {
        var formatVersion = 7
        var exportedAt: Date
        var sessions: [Session]
        var tasks: [Task]
        var lessons: [Lesson]
        var songs: [Song]
        var bands: [Band]
        var skills: [Skill]
        var exercises: [Exercise]
        var concepts: [Concept]
        var books: [Book]
        var instruments: [Instrument]
        var studioAssets: [StudioAsset]
        var recordings: [Recording]
        var milestones: [Milestone]
        var artifacts: [Artifact]
        var academyQuestions: [AcademyQuestion]
        var academyProgress: [SpacedRepetitionProgress]
        var flashcardProgress: [FlashcardProgress]
        var repertoireSuggestions: [RepertoireSuggestion]
        var teacherConversations: [ChatConversation]
        var teacherChat: [ChatMessage]
        var weeklyPlans: [WeeklyPlan]
        var backlogIdeas: [BacklogIdea]
        var skillEvidence: [Evidence]
        var fretboardProgress: [FretboardProgress] = []
        var fretboardProfiles: [FretboardProfile] = []

        struct Session: Codable {
            var id: UUID
            var date: Date
            var durationMinutes: Int
            var durationSeconds: Int? = nil
            var instrumentName: String
            var category: String
            var sourceTitle: String
            var exerciseTitle: String
            var startBPM: Int
            var endBPM: Int
            var difficulty: Int
            var result: String
            var notes: String
            var sourceKind: String
            var sourceID: UUID?
            var correctRepetitions: Int = 0
            var repertoireRepetitions: Int? = nil
            var repertoireSongDurationSeconds: Int? = nil
            var tensionRating: Int = 1
            var practiceContext: String = PracticeApplicationContext.isolated.rawValue
            var wasColdCheck: Bool = false
            var rhythmicFigure: String? = nil
            var targetSkillID: UUID? = nil
            var evidenceDimension: String? = nil
            var successCriterion: String? = nil
        }

        struct Task: Codable {
            var id: UUID
            var title: String
            var category: String
            var plannedMinutes: Int
            var sourceTitle: String
            var exerciseTitle: String
            var targetBPM: Int
            var priority: Int
            var isCompleted: Bool
            var createdAt: Date
            var scheduledDate: Date
            var instructions: String
            var theoryTaskMode: String
            var rhythmTaskMode: String
            var repertoireTaskMode: String
            var sourceKind: String
            var sourceID: UUID?
            var lastResult: String = PracticeResult.learning.rawValue
            var lastEndBPM: Int = 0
            var lastCorrectRepetitions: Int = 0
            var lastTensionRating: Int = 1
            var lastPracticeContext: String = PracticeApplicationContext.isolated.rawValue
            var lastWasColdCheck: Bool = false
            var successfulReviewCount: Int = 0
            var rhythmicFigure: String? = nil
            var targetSkillID: UUID? = nil
            var evidenceDimension: String? = nil
            var successCriterion: String? = nil
            var isDiagnosticChallenge: Bool = false
        }

        struct Lesson: Codable {
            var id: UUID
            var date: Date
            var teacherName: String
            var topics: String
            var teacherNotes: String
            var nextObjective: String
            var nextLessonDate: Date?
            var attachments: [Attachment]

            struct Attachment: Codable {
                var fileName: String
                var kind: String
                var externalURL: String
            }
        }

        struct Song: Codable {
            var id: UUID
            var title: String
            var artist: String
            var sections: String
            var status: String
            var targetTempo: Int
            var durationSeconds: Int? = nil
            var notes: String
            var guitarProFileName: String
            var bandName: String
            var linkedSkillIDs: [UUID]
            var sectionProgress: [Section]
            var difficulty: String
            var difficultySource: String? = nil
            var difficultyConfidence: String? = nil

            struct Section: Codable {
                var name: String
                var isLearned: Bool
                var weaknessNotes: String
            }
        }

        struct Band: Codable {
            var id: UUID
            var name: String
            var isFavorite: Bool
            var isTributeProject: Bool
            var notes: String
            var likedSongTitles: [String]
        }

        struct Skill: Codable {
            var id: UUID
            var name: String
            var detail: String
            var domain: String
            var difficulty: String
            var status: String
            var testStatus: String? = nil
            var demonstratedConfidence: String? = nil
            var statusIsManual: Bool
            var resource: String
            var notes: String
            var concept: String
            var correctExecution: String
            var commonErrors: String
            var assessmentQuestions: [Question]
            var approvedRotationPool: [Question]
            var activeRotationQuestions: [Question]

            struct Question: Codable {
                var question: String
                var selectedIndex: Int?
                var options: [Option]

                struct Option: Codable {
                    var text: String
                    var points: Int
                }
            }
        }

        struct Exercise: Codable {
            var id: UUID
            var collectionName: String
            var bookTitle: String
            var chapter: String
            var exerciseNumber: String
            var page: Int
            var technique: String
            var targetBPM: Int
            var status: String
            var notes: String
            var isFavorite: Bool
            var difficulty: String?
        }

        struct Concept: Codable {
            var id: UUID
            var bookTitle: String
            var title: String
            var page: Int
            var category: String
            var difficulty: String
            var summary: String
            var isExercise: Bool
        }

        struct Book: Codable {
            var id: UUID
            var title: String
            var author: String
            var fileName: String
            var pageCount: Int
        }

        struct Instrument: Codable {
            var id: UUID
            var name: String
            var kind: String
            var pickups: String
            var tuning: String
            var notes: String
            var isActive: Bool
        }

        struct StudioAsset: Codable {
            var id: UUID
            var name: String
            var assetType: String
            var category: String
            var usage: String
            var notes: String
        }

        struct Recording: Codable {
            var id: UUID
            var fileName: String
            var relativeFolderPath: String
            var lastModifiedDate: Date
            var firstSeenAt: Date
            var modificationCount: Int
        }

        struct Milestone: Codable {
            var id: UUID
            var date: Date
            var itemName: String
            var category: String
            var previousStatusLabel: String
            var newStatusLabel: String
            var contextDetail: String
        }

        struct Artifact: Codable {
            var id: UUID
            var kind: String
            var title: String
            var body: String
            var sourceName: String
            var filePaths: [String]
            var links: [String]
            var createdAt: Date
        }

        struct AcademyQuestion: Codable {
            var id: UUID
            var topicID: UUID?
            var type: String
            var prompt: String
            var options: [String]
            var correctAnswer: String
            var explanation: String
            var sourceBookTitle: String
            var sourcePage: Int
            var hasImage: Bool
            var createdAt: Date
        }

        struct SpacedRepetitionProgress: Codable {
            var questionID: UUID
            var boxLevel: Int
            var correctCount: Int
            var wrongCount: Int
            var lastReviewedDate: Date?
            var nextReviewDate: Date
        }

        struct FlashcardProgress: Codable {
            var topicID: UUID
            var questionIndex: Int
            var boxLevel: Int
            var correctCount: Int
            var wrongCount: Int
            var lastReviewedDate: Date?
            var nextReviewDate: Date
        }

        struct FretboardProgress: Codable {
            var noteClass: Int
            var stringNumber: Int
            var attemptCount: Int
            var correctCount: Int
            var wrongCount: Int
            var currentStreak: Int
            var averageResponseSeconds: Double
            var fastestResponseSeconds: Double
            var masteredBPM: Int
            var lastPracticedAt: Date?
            var nextReviewDate: Date
        }

        struct FretboardProfile: Codable {
            var hasCompletedAssessment: Bool
            var diagnosticAttempts: Int
            var diagnosticCorrect: Int
            var currentLevel: Int
            var recommendedBPM: Int
            var totalAttempts: Int
            var totalCorrect: Int
            var bestFastStreak: Int
            var sessionsCompleted: Int
            var lastSessionDate: Date?
        }

        struct RepertoireSuggestion: Codable {
            var id: UUID
            var title: String
            var artist: String
            var reason: String
            var targetSkill: String
            var createdAt: Date
        }

        struct ChatMessage: Codable {
            var id: UUID
            var role: String
            var content: String
            var citations: [String]
            var createdAt: Date
            var completionSource: AICompletionSource?
            var conversationID: UUID?
        }

        struct ChatConversation: Codable {
            var id: UUID
            var title: String
            var messageIDs: [UUID]
            var createdAt: Date
            var updatedAt: Date
        }

        struct WeeklyPlan: Codable {
            var id: UUID
            var weekStart: Date
            var summary: String
            var createdAt: Date
            var items: [Item]

            struct Item: Codable {
                var title: String
                var category: String
                var minutes: Int
                var scheduledDate: Date
                var sourceTitle: String
                var exerciseTitle: String
                var targetBPM: Int
                var instructions: String
                var wasAddedToTasks: Bool
            }
        }

        struct BacklogIdea: Codable {
            var id: UUID
            var text: String
            var createdAt: Date
        }

        struct Evidence: Codable {
            var id: UUID
            var skillID: UUID
            var dimension: String
            var sourceKind: String
            var sourceID: UUID?
            var score: Double
            var reliability: Double
            var applicationContext: String
            var occurredAt: Date
            var wasColdCheck: Bool
            var evaluator: String
            var notes: String
        }
    }

    // MARK: - Armado

    struct Result {
        var jsonURL: URL
        var csvURL: URL
        var sessionCount: Int
        var totalRecords: Int
    }

    /// Escribe `guitarpracticelab-<fecha>.json` y `sesiones-<fecha>.csv` dentro de `folder`.
    static func export(from context: ModelContext, to folder: URL) throws -> Result {
        let archive = try buildArchive(from: context)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(archive)

        let stamp = fileStampFormatter.string(from: archive.exportedAt)
        let jsonURL = folder.appending(path: "guitarpracticelab-\(stamp).json")
        let csvURL = folder.appending(path: "sesiones-\(stamp).csv")

        try data.write(to: jsonURL, options: .atomic)
        try sessionsCSV(from: archive.sessions).write(to: csvURL, atomically: true, encoding: .utf8)

        return Result(
            jsonURL: jsonURL,
            csvURL: csvURL,
            sessionCount: archive.sessions.count,
            totalRecords: archive.totalRecords
        )
    }

    static func buildArchive(from context: ModelContext) throws -> Archive {
        func all<T: PersistentModel>(_ type: T.Type) throws -> [T] {
            try context.fetch(FetchDescriptor<T>())
        }

        func questions(_ items: [AssessmentQuestion]) -> [Archive.Skill.Question] {
            items.map { question in
                Archive.Skill.Question(
                    question: question.question,
                    selectedIndex: question.selectedIndex,
                    options: question.options.map { .init(text: $0.text, points: $0.points) }
                )
            }
        }

        let exportedSongs = try all(Song.self)
        let exportedSkills = try all(SkillTopic.self)
        let exportedExercises = try all(LibraryExercise.self)
        let exportedConcepts = try all(LibraryConcept.self)
        // Los tests de compatibilidad también exportan contenedores con esquemas históricos,
        // donde `TeacherConversation` todavía no existe. En esos casos el historial sigue
        // exportándose como mensajes sueltos y la migración lo adoptará al abrir SchemaV7.
        let exportedConversations = (try? all(TeacherConversation.self)) ?? []
        let exerciseContexts = DifficultyClassifier.bookContexts(for: exportedExercises)

        return Archive(
            exportedAt: .now,
            sessions: try all(PracticeSession.self).map {
                .init(
                    id: $0.id, date: $0.date, durationMinutes: $0.durationMinutes,
                    durationSeconds: $0.effectiveDurationSeconds,
                    instrumentName: $0.instrumentName, category: $0.categoryRaw,
                    sourceTitle: $0.sourceTitle, exerciseTitle: $0.exerciseTitle,
                    startBPM: $0.startBPM, endBPM: $0.endBPM, difficulty: $0.difficulty,
                    result: $0.resultRaw, notes: $0.notes,
                    sourceKind: $0.sourceKindRaw, sourceID: $0.sourceID,
                    correctRepetitions: $0.correctRepetitions,
                    repertoireRepetitions: $0.repertoireRepetitions,
                    repertoireSongDurationSeconds: $0.repertoireSongDurationSeconds,
                    tensionRating: $0.tensionRating,
                    practiceContext: $0.practiceContext.rawValue,
                    wasColdCheck: $0.wasColdCheck,
                    rhythmicFigure: $0.rhythmicFigureRaw,
                    targetSkillID: $0.targetSkillID,
                    evidenceDimension: $0.evidenceDimensionRaw,
                    successCriterion: $0.successCriterion
                )
            },
            tasks: try all(PracticeTask.self).map {
                .init(
                    id: $0.id, title: $0.title, category: $0.categoryRaw,
                    plannedMinutes: $0.plannedMinutes, sourceTitle: $0.sourceTitle,
                    exerciseTitle: $0.exerciseTitle, targetBPM: $0.targetBPM,
                    priority: $0.priority, isCompleted: $0.isCompleted,
                    createdAt: $0.createdAt, scheduledDate: $0.scheduledDate,
                    instructions: $0.instructions, theoryTaskMode: $0.theoryTaskModeRaw,
                    rhythmTaskMode: $0.rhythmTaskModeRaw,
                    repertoireTaskMode: $0.repertoireTaskModeRaw,
                    sourceKind: $0.sourceKindRaw, sourceID: $0.sourceID,
                    lastResult: $0.lastResultRaw, lastEndBPM: $0.lastEndBPM,
                    lastCorrectRepetitions: $0.lastCorrectRepetitions,
                    lastTensionRating: $0.lastTensionRating,
                    lastPracticeContext: $0.lastPracticeContextRaw,
                    lastWasColdCheck: $0.lastWasColdCheck,
                    successfulReviewCount: $0.successfulReviewCount,
                    rhythmicFigure: $0.rhythmicFigureRaw,
                    targetSkillID: $0.targetSkillID,
                    evidenceDimension: $0.evidenceDimensionRaw,
                    successCriterion: $0.successCriterion,
                    isDiagnosticChallenge: $0.isDiagnosticChallenge
                )
            },
            lessons: try all(GuitarLesson.self).map { lesson in
                .init(
                    id: lesson.id, date: lesson.date, teacherName: lesson.teacherName,
                    topics: lesson.topics, teacherNotes: lesson.teacherNotes,
                    nextObjective: lesson.nextObjective, nextLessonDate: lesson.nextLessonDate,
                    attachments: lesson.attachments.map {
                        .init(fileName: $0.fileName, kind: $0.kindRaw, externalURL: $0.externalURLString)
                    }
                )
            },
            songs: exportedSongs.map { song in
                let difficulty = SongDifficultyCatalog.assess(song).rating
                return .init(
                    id: song.id, title: song.title, artist: song.artist, sections: song.sections,
                    status: song.statusRaw, targetTempo: song.targetTempo,
                    durationSeconds: song.durationSeconds, notes: song.notes,
                    guitarProFileName: song.gpFileName, bandName: song.band?.name ?? "",
                    linkedSkillIDs: song.linkedSkillIDs,
                    sectionProgress: song.sectionProgress.map {
                        .init(name: $0.name, isLearned: $0.isLearned, weaknessNotes: $0.weaknessNotes)
                    },
                    difficulty: difficulty.label,
                    difficultySource: song.persistedDifficultyProfile?.source.displayName,
                    difficultyConfidence: song.persistedDifficultyProfile?.confidence.displayName
                )
            },
            bands: try all(Band.self).map {
                .init(
                    id: $0.id, name: $0.name, isFavorite: $0.isFavorite,
                    isTributeProject: $0.isTributeProject, notes: $0.notes,
                    likedSongTitles: $0.likedSongTitles
                )
            },
            skills: exportedSkills.map { skill in
                let difficulty = DifficultyClassifier.assess(skillNamed: skill.name).rating
                return .init(
                    id: skill.id, name: skill.name, detail: skill.detail,
                    domain: skill.domainRaw, difficulty: difficulty.label, status: skill.statusRaw,
                    testStatus: skill.testStatusRaw, demonstratedConfidence: skill.demonstratedConfidenceRaw,
                    statusIsManual: skill.statusIsManual, resource: skill.resource, notes: skill.notes,
                    concept: skill.concept, correctExecution: skill.correctExecution,
                    commonErrors: skill.commonErrors,
                    assessmentQuestions: questions(skill.assessmentQuestions),
                    approvedRotationPool: questions(skill.approvedRotationPool),
                    activeRotationQuestions: questions(skill.activeRotationQuestions)
                )
            },
            exercises: exportedExercises.map {
                let difficulty = DifficultyClassifier.assess(
                    $0,
                    context: DifficultyClassifier.context(forBook: $0.bookTitle, in: exerciseContexts)
                ).rating
                return .init(
                    id: $0.id, collectionName: $0.collectionName, bookTitle: $0.bookTitle,
                    chapter: $0.chapter, exerciseNumber: $0.exerciseNumber, page: $0.page,
                    technique: $0.technique, targetBPM: $0.targetBPM, status: $0.statusRaw,
                    notes: $0.notes, isFavorite: $0.isFavorite, difficulty: difficulty.label
                )
            },
            concepts: exportedConcepts.map {
                let difficulty = DifficultyClassifier.assess($0).rating
                return .init(
                    id: $0.id, bookTitle: $0.bookTitle, title: $0.title, page: $0.page,
                    category: $0.category, difficulty: difficulty.label, summary: $0.summary,
                    isExercise: $0.isExercise
                )
            },
            books: try all(LibraryBook.self).map {
                .init(id: $0.id, title: $0.title, author: $0.author, fileName: $0.fileName, pageCount: $0.pageCount)
            },
            instruments: try all(Instrument.self).map {
                .init(
                    id: $0.id, name: $0.name, kind: $0.kind, pickups: $0.pickups,
                    tuning: $0.tuning, notes: $0.notes, isActive: $0.isActive
                )
            },
            studioAssets: try all(StudioAsset.self).map {
                .init(
                    id: $0.id, name: $0.name, assetType: $0.assetTypeRaw,
                    category: $0.category, usage: $0.usage, notes: $0.notes
                )
            },
            recordings: try all(Recording.self).map {
                .init(
                    id: $0.id, fileName: $0.fileName, relativeFolderPath: $0.relativeFolderPath,
                    lastModifiedDate: $0.lastModifiedDate, firstSeenAt: $0.firstSeenAt,
                    modificationCount: $0.modificationLog.count
                )
            },
            milestones: try all(ProgressMilestone.self).map {
                .init(
                    id: $0.id, date: $0.date, itemName: $0.itemName, category: $0.categoryRaw,
                    previousStatusLabel: $0.previousStatusLabel, newStatusLabel: $0.newStatusLabel,
                    contextDetail: $0.contextDetail
                )
            },
            artifacts: try all(AIArtifact.self).map {
                .init(
                    id: $0.id, kind: $0.kindRaw, title: $0.title, body: $0.body,
                    sourceName: $0.sourceName, filePaths: $0.filePaths, links: $0.links,
                    createdAt: $0.createdAt
                )
            },
            academyQuestions: try all(AcademyQuestion.self).map {
                .init(
                    id: $0.id, topicID: $0.topicID, type: $0.typeRaw, prompt: $0.prompt,
                    options: $0.options, correctAnswer: $0.correctAnswer, explanation: $0.explanation,
                    sourceBookTitle: $0.sourceBookTitle, sourcePage: $0.sourcePage,
                    hasImage: $0.imageData != nil, createdAt: $0.createdAt
                )
            },
            academyProgress: try all(AcademyQuestionProgress.self).map {
                .init(
                    questionID: $0.questionID, boxLevel: $0.boxLevel, correctCount: $0.correctCount,
                    wrongCount: $0.wrongCount, lastReviewedDate: $0.lastReviewedDate,
                    nextReviewDate: $0.nextReviewDate
                )
            },
            flashcardProgress: try all(TheoryFlashcardProgress.self).map {
                .init(
                    topicID: $0.topicID, questionIndex: $0.questionIndex, boxLevel: $0.boxLevel,
                    correctCount: $0.correctCount, wrongCount: $0.wrongCount,
                    lastReviewedDate: $0.lastReviewedDate, nextReviewDate: $0.nextReviewDate
                )
            },
            repertoireSuggestions: try all(RepertoireSuggestionRecord.self).map {
                .init(
                    id: $0.id, title: $0.title, artist: $0.artist, reason: $0.reason,
                    targetSkill: $0.targetSkill, createdAt: $0.createdAt
                )
            },
            teacherConversations: exportedConversations.map {
                .init(
                    id: $0.id, title: $0.title, messageIDs: $0.messageIDs,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt
                )
            },
            teacherChat: try all(TeacherChatMessage.self).map { message in
                .init(
                    id: message.id, role: message.role, content: message.content,
                    citations: message.citations, createdAt: message.createdAt,
                    completionSource: message.completionSource,
                    conversationID: exportedConversations.first { $0.messageIDs.contains(message.id) }?.id
                )
            },
            weeklyPlans: try all(WeeklyPracticePlan.self).map { plan in
                .init(
                    id: plan.id, weekStart: plan.weekStart, summary: plan.summary,
                    createdAt: plan.createdAt,
                    items: plan.items.map {
                        .init(
                            title: $0.title, category: $0.categoryRaw, minutes: $0.minutes,
                            scheduledDate: $0.scheduledDate, sourceTitle: $0.sourceTitle,
                            exerciseTitle: $0.exerciseTitle, targetBPM: $0.targetBPM,
                            instructions: $0.instructions, wasAddedToTasks: $0.wasAddedToTasks
                        )
                    }
                )
            },
            backlogIdeas: try all(BacklogIdea.self).map {
                .init(id: $0.id, text: $0.text, createdAt: $0.createdAt)
            },
            skillEvidence: try all(SkillEvidence.self).map {
                .init(
                    id: $0.id, skillID: $0.skillID, dimension: $0.dimensionRaw,
                    sourceKind: $0.sourceKindRaw, sourceID: $0.sourceID,
                    score: $0.score, reliability: $0.reliability,
                    applicationContext: $0.applicationContextRaw, occurredAt: $0.occurredAt,
                    wasColdCheck: $0.wasColdCheck, evaluator: $0.evaluatorRaw, notes: $0.notes
                )
            },
            fretboardProgress: try all(FretboardNoteProgress.self).map {
                .init(
                    noteClass: $0.noteClass, stringNumber: $0.stringNumber,
                    attemptCount: $0.attemptCount, correctCount: $0.correctCount,
                    wrongCount: $0.wrongCount, currentStreak: $0.currentStreak,
                    averageResponseSeconds: $0.averageResponseSeconds,
                    fastestResponseSeconds: $0.fastestResponseSeconds,
                    masteredBPM: $0.masteredBPM, lastPracticedAt: $0.lastPracticedAt,
                    nextReviewDate: $0.nextReviewDate
                )
            },
            fretboardProfiles: try all(FretboardTrainingProfile.self).map {
                .init(
                    hasCompletedAssessment: $0.hasCompletedAssessment,
                    diagnosticAttempts: $0.diagnosticAttempts,
                    diagnosticCorrect: $0.diagnosticCorrect,
                    currentLevel: $0.currentLevel, recommendedBPM: $0.recommendedBPM,
                    totalAttempts: $0.totalAttempts, totalCorrect: $0.totalCorrect,
                    bestFastStreak: $0.bestFastStreak,
                    sessionsCompleted: $0.sessionsCompleted,
                    lastSessionDate: $0.lastSessionDate
                )
            }
        )
    }

    // MARK: - CSV

    /// Solo las sesiones, que es lo que tiene sentido abrir en una planilla para hacer cuentas
    /// propias. El resto vive en el JSON.
    static func sessionsCSV(from sessions: [Archive.Session]) -> String {
        let header = [
            "Fecha", "Minutos", "Segundos exactos", "Instrumento", "Categoría", "Origen", "Ejercicio",
            "BPM inicial", "BPM final", "Figura rítmica", "Esfuerzo percibido (1-5)", "Resultado",
            "Repeticiones correctas", "Pasadas completas", "Duración canción (s)",
            "Tensión (1-5)", "Contexto", "Prueba en frío",
            "Dimensión evaluada", "Criterio de éxito", "Notas"
        ]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        let rows = sessions.sorted { $0.date < $1.date }.map { session in
            [
                formatter.string(from: session.date),
                String(session.durationMinutes),
                String(session.durationSeconds ?? session.durationMinutes * 60),
                session.instrumentName,
                session.category,
                session.sourceTitle,
                session.exerciseTitle,
                String(session.startBPM),
                String(session.endBPM),
                session.rhythmicFigure.flatMap { RhythmicFigure(rawValue: $0)?.displayName } ?? "",
                String(session.difficulty),
                session.result,
                String(session.correctRepetitions),
                String(session.repertoireRepetitions ?? 0),
                String(session.repertoireSongDurationSeconds ?? 0),
                String(session.tensionRating),
                session.practiceContext,
                session.wasColdCheck ? "Sí" : "No",
                session.evidenceDimension ?? "",
                session.successCriterion ?? "",
                session.notes
            ].map(escapeCSV).joined(separator: ",")
        }

        return ([header.map(escapeCSV).joined(separator: ",")] + rows).joined(separator: "\n") + "\n"
    }

    private static func escapeCSV(_ field: String) -> String {
        let cleaned = field.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        guard cleaned.contains(",") || cleaned.contains("\"") else { return cleaned }
        return "\"\(cleaned.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static let fileStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()
}

extension DataExportService.Archive {
    /// Cuántos registros se exportaron, para poder confirmarle al usuario que el archivo no salió
    /// vacío sin que tenga que abrirlo.
    var totalRecords: Int {
        sessions.count + tasks.count + lessons.count + songs.count + bands.count + skills.count
            + exercises.count + concepts.count + books.count + instruments.count + studioAssets.count
            + recordings.count + milestones.count + artifacts.count + academyQuestions.count
            + academyProgress.count + flashcardProgress.count + repertoireSuggestions.count
            + teacherConversations.count + teacherChat.count + weeklyPlans.count + backlogIdeas.count
            + skillEvidence.count + fretboardProgress.count + fretboardProfiles.count
    }
}
