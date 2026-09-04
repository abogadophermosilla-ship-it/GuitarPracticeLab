import XCTest
@testable import GuitarPracticeLab

final class DifficultyClassificationTests: XCTestCase {
    func testIntegralPercentageUsesHalfStarScale() {
        XCTAssertEqual(StudentLevelService.rating(forPercentage: 45.5)?.stars, 4.5)
        XCTAssertEqual(DifficultyRating(stars: 6.26).stars, 6.5)
        XCTAssertEqual(DifficultyRating(stars: 0).stars, 0.5)
        XCTAssertEqual(DifficultyRating(stars: 12).stars, 10)
        XCTAssertTrue(DifficultyRating(stars: 4.5).label.contains("★/10"))
    }

    func testCachedSummaryDropsLegacyThreeBandLabel() {
        let old = "Con un nivel general de 45% (Básico), tienes buena teoría."
        let migrated = DifficultyScaleMigration.rewrittenSummary(old, rating: DifficultyRating(stars: 4.5))
        XCTAssertTrue(migrated.contains("4.5★/10") || migrated.contains("4,5★/10"))
        XCTAssertFalse(migrated.contains("Básico"))
    }

    func testEveryKnownBookHasAProfile() {
        XCTAssertEqual(DifficultyClassifier.bookProfiles.count, 19)
        XCTAssertTrue(DifficultyClassifier.bookProfiles.allSatisfy { $0.floor >= 0.5 })
        XCTAssertTrue(DifficultyClassifier.bookProfiles.allSatisfy { $0.ceiling <= 10 })
        XCTAssertTrue(DifficultyClassifier.bookProfiles.allSatisfy { $0.floor < $0.ceiling })
    }

    func testVolumeTwoDoesNotFallIntoVolumeOneProfile() {
        let rhythm = DifficultyClassifier.profile(forBook: "Metal Rhythm Guitar Volume II")
        XCTAssertEqual(rhythm.floor, 5.0)
        XCTAssertEqual(rhythm.ceiling, 7.5)

        let lead = DifficultyClassifier.profile(forBook: "Heavy Metal Lead Guitar Vol II")
        XCTAssertEqual(lead.floor, 5.5)
        XCTAssertEqual(lead.ceiling, 8.0)
    }

    func testKnownRepertoireUsesSongSpecificRating() {
        let master = SongDifficultyCatalog.assess(title: "Master of Puppets", artist: "Metallica")
        XCTAssertEqual(master.rating.stars, 7.5)
        XCTAssertFalse(master.summary.isEmpty)
        XCTAssertFalse(master.prerequisites.isEmpty)
        XCTAssertFalse(master.practiceFocus.isEmpty)

        let sandman = SongDifficultyCatalog.assess(title: "Enter Sandman", artist: "Metallica")
        XCTAssertTrue(sandman.summary.localizedCaseInsensitiveContains("palm mute"))
        XCTAssertTrue(sandman.practiceFocus.localizedCaseInsensitiveContains("bend"))

        XCTAssertEqual(
            SongDifficultyCatalog.assess(title: "The Dance of Eternity", artist: "Dream Theater").rating.stars,
            10
        )
    }

    func testPersonalSongUsesSectionsAndNotesInSummary() {
        let assessment = SongDifficultyCatalog.assess(
            title: "Tema propio",
            artist: "Kaos Etiliko",
            sections: "Intro, Verso, Preestribillo, Estribillo, Puente, Solo, Outro",
            notes: "El solo tiene galope y armonías a dos guitarras"
        )

        XCTAssertTrue(assessment.summary.contains("7 secciones"))
        XCTAssertTrue(assessment.demands.contains { $0.localizedCaseInsensitiveContains("solo") })
        XCTAssertTrue(assessment.demands.contains { $0.localizedCaseInsensitiveContains("resistencia") })
        XCTAssertFalse(assessment.practiceFocus.isEmpty)
    }

    func testLegacyCatalogLabelRemainsASecondarySignal() {
        let exercise = LibraryExercise(
            collectionName: "Catálogo",
            bookTitle: "Libro desconocido",
            technique: "Escala",
            difficulty: .advanced
        )
        XCTAssertEqual(exercise.legacyCatalogDifficulty, "Avanzado")

        let advanced = DifficultyClassifier.assess(exercise, context: nil).rating
        exercise.difficultyRaw = nil
        let unlabeled = DifficultyClassifier.assess(exercise, context: nil).rating
        XCTAssertGreaterThan(advanced, unlabeled)
    }

    func testLightweightExerciseRatingMatchesFullAssessment() {
        let exercise = LibraryExercise(
            collectionName: "Catálogo",
            bookTitle: "Guitar Aerobics",
            exerciseNumber: "184",
            page: 60,
            technique: "string skipping, picking alterno",
            targetBPM: 140,
            notes: "Tres notas por cuerda con semicorcheas."
        )
        let context = DifficultyClassifier.BookContext(
            firstPage: 8, lastPage: 112, highestNumber: 365, numberingIsProgressive: true
        )

        XCTAssertEqual(
            DifficultyClassifier.rating(for: exercise, context: context),
            DifficultyClassifier.assess(exercise, context: context).rating
        )
    }

    func testEvidenceTokensDiscardCommonConnectorWords() {
        XCTAssertEqual(
            Set("Ritmo y subdivisión de semicorcheas con metrónomo".evidenceTokens),
            Set(["ritmo", "subdivision", "semicorcheas", "metronomo"])
        )
    }

    func testMaterialIsAdaptedToStudentLevel() {
        let student = DifficultyRating(stars: 4.5)
        XCTAssertEqual(DifficultyRating(stars: 2).fit(forStudentLevel: student), .mastered)
        XCTAssertEqual(DifficultyRating(stars: 4).fit(forStudentLevel: student), .onLevel)
        XCTAssertEqual(DifficultyRating(stars: 6).fit(forStudentLevel: student), .stretch)
        XCTAssertEqual(DifficultyRating(stars: 8).fit(forStudentLevel: student), .tooHard)
    }

    func testExerciseDescriptionProducesPedagogicalSummary() {
        let exercise = LibraryExercise(
            collectionName: "Catálogo",
            bookTitle: "Guitar Aerobics",
            exerciseNumber: "184",
            page: 60,
            technique: "string skipping, picking alterno",
            notes: "Secuencia descendente de escala C mayor con tres notas por cuerda saltando la cuerda 2."
        )
        let context = DifficultyClassifier.BookContext(
            firstPage: 8, lastPage: 112, highestNumber: 365, numberingIsProgressive: true
        )
        let assessment = DifficultyClassifier.assess(exercise, context: context)

        XCTAssertTrue(assessment.summary.contains("Secuencia descendente"))
        XCTAssertTrue(assessment.summary.localizedCaseInsensitiveContains("saltos de cuerda"))
        XCTAssertTrue(assessment.demands.contains { $0.localizedCaseInsensitiveContains("no adyacente") })
        XCTAssertTrue(assessment.prerequisites.contains { $0.localizedCaseInsensitiveContains("muting") })
        XCTAssertFalse(assessment.practiceFocus.isEmpty)
        XCTAssertTrue(assessment.searchableText.localizedCaseInsensitiveContains("cuerda omitida"))
    }

    func testTheorySummaryExplainsMasteryAndHowToStudy() {
        let concept = LibraryConcept(
            bookTitle: "Improvisación para Muñones",
            title: "Dominantes secundarios",
            page: 102,
            category: "Armonía",
            summary: "Los dominantes secundarios crean una resolución temporal hacia un acorde diatónico.",
            isExercise: true
        )
        let assessment = DifficultyClassifier.assess(concept)

        XCTAssertGreaterThanOrEqual(assessment.rating.stars, 8)
        XCTAssertTrue(assessment.summary.localizedCaseInsensitiveContains("dominarlo significa"))
        XCTAssertTrue(assessment.demands.contains { $0.localizedCaseInsensitiveContains("aplicar") })
        XCTAssertTrue(assessment.prerequisites.contains { $0.localizedCaseInsensitiveContains("funciones armónicas") })
        XCTAssertTrue(assessment.practiceFocus.localizedCaseInsensitiveContains("resolución"))
    }

    func testConflictingExerciseNumberFallsBackToPdfPage() {
        let exercise = LibraryExercise(
            collectionName: "Catálogo",
            bookTitle: "Speed Mechanics For The Lead Guitar",
            exerciseNumber: "196b",
            page: 8,
            technique: "solo"
        )
        let context = DifficultyClassifier.BookContext(
            firstPage: 2, lastPage: 77, highestNumber: 196, numberingIsProgressive: true
        )
        let assessment = DifficultyClassifier.assess(exercise, context: context)

        XCTAssertLessThan(assessment.rating.stars, 7.5, "La numeración OCR no debe convertir una página inicial en el final del método")
    }

    func testPartialSongTitleDoesNotClaimCuratedEntry() {
        let partial = SongDifficultyCatalog.assess(title: "Master", artist: "Metallica")
        let exact = SongDifficultyCatalog.assess(title: "Master of Puppets", artist: "Metallica")

        XCTAssertEqual(partial.rating.stars, 5.5, "Una escritura parcial debe usar el perfil del artista, no otra canción")
        XCTAssertEqual(exact.rating.stars, 7.5)
    }

    func testObjectiveDimensionsUseFixedLocalFormula() {
        let dimensions = SongDifficultyDimensions(
            technique: 8, speed: 6, rhythm: 4, endurance: 5, solo: 7, form: 3
        )

        XCTAssertEqual(dimensions.weightedRating.stars, 6.0)
    }

    func testEvolvingCatalogReusesNormalizedExactIdentity() {
        let profile = SongDifficultyProfile(
            title: "Sweet Child O' Mine", artist: "Guns N' Roses", role: .fullArrangement,
            rating: DifficultyRating(stars: 6.5),
            dimensions: SongDifficultyDimensions(
                technique: 7, speed: 6, rhythm: 5, endurance: 6, solo: 8, form: 6
            ),
            source: .gemini, confidence: .high, summary: "Ficha analizada",
            factors: ["evidencia"], demands: [], prerequisites: [], practiceFocus: "Practicar",
            suggestedSections: [], analyzedAt: .now, analysisVersion: 1
        )
        let record = SongDifficultyRecord(profile: profile)

        let reused = SongDifficultyResolver.profile(
            title: "Sweet Child O Mine", artist: "Guns N Roses", records: [record]
        )

        XCTAssertEqual(reused.rating.stars, 6.5)
        XCTAssertEqual(reused.source, .evolvingCatalog)
        XCTAssertEqual(reused.confidence, .high)
    }

    func testPersistedSongDifficultyOverridesLegacyHeuristic() {
        let song = Song(title: "Tema nuevo", artist: "Banda nueva")
        let profile = SongDifficultyProfile(
            title: song.title, artist: song.artist, role: .rhythm,
            rating: DifficultyRating(stars: 7),
            dimensions: SongDifficultyDimensions(
                technique: 7, speed: 7, rhythm: 7, endurance: 7, solo: 7, form: 7
            ),
            source: .manual, confidence: .high, summary: "Confirmada",
            factors: [], demands: [], prerequisites: [], practiceFocus: "",
            suggestedSections: [], analyzedAt: .now, analysisVersion: 1
        )

        song.applyDifficultyProfile(profile)

        XCTAssertEqual(SongDifficultyCatalog.assess(song).rating.stars, 7)
        XCTAssertEqual(song.guitarRole, .rhythm)
    }

    func testAIAnalysisIgnoresInventedFinalAndCalculatesDimensions() async throws {
        let backend = DifficultyJSONBackend(response: """
        {
          "confidence": "high",
          "dimensions": {"technique": 8, "speed": 6, "rhythm": 4, "endurance": 5, "solo": 7, "form": 3},
          "summary": "Análisis específico",
          "evidence": ["riff sincopado"],
          "demands": ["muting limpio"],
          "prerequisites": ["púa alterna"],
          "practice_focus": "Practicar por bloques",
          "sections": ["Intro", "Verso", "Solo"]
        }
        """)

        let profile = try await SongDifficultyAIService.analyzeSong(
            title: "Tema", artist: "Artista", role: .fullArrangement,
            sections: "", notes: "", source: .localAI, backend: backend
        )

        XCTAssertEqual(profile.rating.stars, 6)
        XCTAssertEqual(profile.confidence, .high)
        XCTAssertEqual(profile.suggestedSections, ["Intro", "Verso", "Solo"])
        XCTAssertTrue(profile.factors.contains { $0.contains("fórmula fija") })
    }
}

private struct DifficultyJSONBackend: JSONCompletionBackend {
    let response: String
    func completeJSON(prompt: String) async throws -> String { response }
}
