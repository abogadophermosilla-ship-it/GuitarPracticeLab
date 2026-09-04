import Foundation

/// Fachada unificada para todos los servicios de asistencia IA del profesor.
/// Evita el acceso directo a servicios específicos desde vistas y permite inyección de dependencias.
final class CoachFacade {
    private let backend: JSONCompletionBackend
    
    init(backend: JSONCompletionBackend) {
        self.backend = backend
    }
    
    // MARK: - Practice Coach
    
    func practiceRecommendation(
        skills: [SkillTopic],
        lessons: [GuitarLesson],
        exercises: [LibraryExercise],
        equipment: [StudioAsset] = [],
        instruments: [Instrument] = [],
        pdfReferences: [String] = [],
        sessions: [PracticeSession] = [],
        tasks: [PracticeTask] = []
    ) async throws -> PracticeRecommendation {
        try await PracticeCoachService.recommendation(
            skills: skills,
            lessons: lessons,
            exercises: exercises,
            equipment: equipment,
            instruments: instruments,
            pdfReferences: pdfReferences,
            sessions: sessions,
            tasks: tasks,
            backend: backend
        )
    }
    
    func practiceFollowUp(
        question: String,
        recommendation: PracticeRecommendation,
        history: [ProgressChatExchange],
        skills: [SkillTopic],
        lessons: [GuitarLesson],
        exercises: [LibraryExercise],
        equipment: [StudioAsset] = [],
        instruments: [Instrument] = [],
        pdfReferences: [String] = [],
        sessions: [PracticeSession] = [],
        tasks: [PracticeTask] = []
    ) async throws -> String {
        try await PracticeCoachService.followUp(
            question: question,
            recommendation: recommendation,
            history: history,
            skills: skills,
            lessons: lessons,
            exercises: exercises,
            equipment: equipment,
            instruments: instruments,
            pdfReferences: pdfReferences,
            sessions: sessions,
            tasks: tasks,
            backend: backend
        )
    }

    // MARK: - Skill Assessment
    
    func skillAssessmentSummary(
        topics: [SkillTopic],
        overall: SkillAssessmentCoachService.OverallLevelResult,
        source: SkillAssessmentCoachService.OverallLevelSource,
        context: String = "",
        evidenceSummary: String = ""
    ) async throws -> String {
        try await SkillAssessmentCoachService.summarizeOverallLevel(
            topics: topics,
            overall: overall,
            source: source,
            context: context,
            evidenceSummary: evidenceSummary,
            backend: backend
        )
    }
    
    func suggestRepertoire(
        topics: [SkillTopic],
        exercises: [LibraryExercise],
        songs: [Song],
        favoriteBands: [Band] = [],
        musicalTastes: String,
        context: String = "",
        pdfReferences: [String]
    ) async throws -> [AssessmentAnalysis.RepertoireSuggestion] {
        try await SkillAssessmentCoachService.suggestRepertoire(
            topics: topics,
            exercises: exercises,
            songs: songs,
            favoriteBands: favoriteBands,
            musicalTastes: musicalTastes,
            context: context,
            pdfReferences: pdfReferences,
            backend: backend
        )
    }
    
    // MARK: - Song Coach
    
    func suggestSongExercises(
        forWeakness weaknessNotes: String,
        songTitle: String,
        sectionName: String,
        skills: [SkillTopic],
        exercises: [LibraryExercise]
    ) async throws -> [SongExerciseSuggestion] {
        try await SongCoachService.suggestExercises(
            forWeakness: weaknessNotes,
            songTitle: songTitle,
            sectionName: sectionName,
            skills: skills,
            exercises: exercises,
            backend: backend
        )
    }
    
    func suggestSongSkills(
        songTitle: String,
        artist: String,
        sections: String,
        skills: [SkillTopic]
    ) async throws -> [SkillTopic] {
        try await SongCoachService.suggestSkills(
            songTitle: songTitle,
            artist: artist,
            sections: sections,
            skills: skills,
            backend: backend
        )
    }
    
    // MARK: - Weekly Planner
    
    func generateWeeklyPlan(
        weekStart: Date,
        days: Int,
        dailyMinutes: Int,
        context: LearningContextSnapshot
    ) async throws -> GeneratedWeeklyPlan {
        try await WeeklyPracticePlannerService.generate(
            weekStart: weekStart,
            days: days,
            dailyMinutes: dailyMinutes,
            context: context,
            backend: backend
        )
    }
    
    // MARK: - Skill Ladder
    
    func generateSkillLadder(
        goal: String,
        context: LearningContextSnapshot
    ) async throws -> GeneratedSkillLadder {
        try await SkillLadderService.generate(
            goal: goal,
            context: context,
            backend: backend
        )
    }
    
    // MARK: - Routine Coach
    
    func reviewRoutine(
        signals: RoutineSignals,
        exercises: [LibraryExercise] = [],
        songs: [Song] = [],
        concepts: [LibraryConcept] = []
    ) async throws -> GeneratedRoutineReview {
        try await RoutineCoachService.review(
            signals: signals,
            exercises: exercises,
            songs: songs,
            concepts: concepts,
            backend: backend
        )
    }
}
