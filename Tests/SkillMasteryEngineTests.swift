import XCTest
import SwiftData
@testable import GuitarPracticeLab

final class SkillMasteryEngineTests: XCTestCase {
    private func topic(name: String = "Alternate picking", domain: SkillDomain = .technique) -> SkillTopic {
        SkillTopic(name: name, domain: domain, level: .basic)
    }

    private func evidence(
        for topic: SkillTopic,
        dimension: SkillEvidenceDimension,
        score: Double = 0.9,
        reliability: Double = 0.9,
        index: Int = 0,
        cold: Bool = false
    ) -> SkillEvidence {
        SkillEvidence(
            deduplicationKey: "test:\(topic.id):\(dimension.rawValue):\(index)",
            skillID: topic.id,
            dimension: dimension,
            sourceKind: .practiceSession,
            score: score,
            reliability: reliability,
            applicationContext: dimension == .musicalApplication ? .fullPiece : (dimension == .transfer ? .fromMemory : .isolated),
            wasColdCheck: cold,
            evaluator: .deterministic
        )
    }

    func testElTestSoloNoDemuestraDominioTecnico() {
        let skill = topic()
        let records = [
            evidence(for: skill, dimension: .recognition),
            evidence(for: skill, dimension: .understanding)
        ]

        let profile = SkillMasteryEngine.profile(for: skill, evidence: records)

        XCTAssertLessThanOrEqual(profile.demonstratedLevel.progressWeight, SkillMasteryLevel.basic.progressWeight)
        XCTAssertEqual(profile.nextDimension, .execution)
    }

    func testEvidenciaAmpliaPermiteConsolidar() {
        let skill = topic()
        let records = SkillEvidenceDimension.allCases.flatMap { dimension in
            (0..<4).map {
                evidence(
                    for: skill,
                    dimension: dimension,
                    score: 0.95,
                    reliability: 0.95,
                    index: $0,
                    cold: dimension == .retention
                )
            }
        }

        let profile = SkillMasteryEngine.profile(for: skill, evidence: records)

        XCTAssertEqual(profile.demonstratedLevel, .consolidated)
        XCTAssertEqual(profile.confidence, .high)
    }

    func testPruebaEnFrioGeneraRetencionAdemasDeLaDimensionPedida() {
        let outcome = PracticeOutcome(
            result: .targetTempo,
            endBPM: 120,
            correctRepetitions: 4,
            tensionRating: 1,
            context: .fromMemory,
            wasColdCheck: true
        )

        let drafts = SkillEvidenceFactory.practiceDrafts(
            outcome: outcome,
            category: .technique,
            requestedDimension: .transfer
        )

        XCTAssertTrue(drafts.contains { $0.dimension == .transfer })
        XCTAssertTrue(drafts.contains { $0.dimension == .execution })
        XCTAssertTrue(drafts.contains { $0.dimension == .retention && $0.wasColdCheck })
    }

    func testRetoConservaHabilidadDimensionYCriterio() {
        let skill = topic()
        let profile = SkillMasteryEngine.profile(for: skill, evidence: [])

        let task = SkillChallengeBuilder.makeTask(
            for: skill,
            profile: profile,
            exercises: [],
            songs: [],
            dimension: .transfer,
            criterion: "Mover a tres tonalidades",
            minutes: 9
        )

        XCTAssertEqual(task.targetSkillID, skill.id)
        XCTAssertEqual(task.evidenceDimension, .transfer)
        XCTAssertEqual(task.successCriterion, "Mover a tres tonalidades")
        XCTAssertTrue(task.isDiagnosticChallenge)
        XCTAssertEqual(task.plannedMinutes, 9)
    }

    func testHermesExtraeUnaPropuestaSinDejarMetadatosEnElChat() {
        let text = """
        Conviene comprobarlo en otra zona del mástil.

        [RETO]
        Habilidad: Alternate picking
        Dimensión: Transferencia
        Duración: 7 minutos
        Criterio: Mover el patrón a tres cuerdas sin detener el pulso
        [/RETO]
        """

        let extracted = HermesChallengeProposal.extract(from: text)

        XCTAssertEqual(extracted.proposal?.skillName, "Alternate picking")
        XCTAssertEqual(extracted.proposal?.dimension, .transfer)
        XCTAssertEqual(extracted.proposal?.minutes, 7)
        XCTAssertFalse(extracted.cleanText.contains("[RETO]"))
    }

    func testAudioObjetivoPuntuaTempoYRegularidadSinJuzgarBends() {
        let metadata = """
        {
          "notes": {
            "count": 48,
            "attackIntervalVariation": 0.07,
            "pitchBendEvents": 12
          },
          "essentia": {
            "rhythm": { "bpm": 100.0 }
          }
        }
        """

        let result = ObjectiveAudioEvidenceScorer.score(metadataJSON: metadata, targetBPM: 100)

        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result?.score ?? 0, 0.85)
        XCTAssertEqual(result?.reliability, 0.90)
        XCTAssertFalse(result?.summary.localizedCaseInsensitiveContains("bend") == true)
    }

    @MainActor
    func testSchemaV2PersisteElLibroMayor() throws {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let skill = topic()
        container.mainContext.insert(skill)
        container.mainContext.insert(evidence(for: skill, dimension: .execution))
        try container.mainContext.save()

        let stored = try container.mainContext.fetch(FetchDescriptor<SkillEvidence>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.skillID, skill.id)
        let archive = try DataExportService.buildArchive(from: container.mainContext)
        XCTAssertEqual(archive.formatVersion, 7)
        XCTAssertEqual(archive.skillEvidence.count, 1)
        XCTAssertFalse(try JSONEncoder().encode(archive).isEmpty)
    }

    @MainActor
    func testRetoSinMaterialTambiénProgramaRevisiónEnFrío() throws {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let skillID = UUID()
        let task = PracticeTask(
            title: "Comprobar · Intervalos",
            category: .theory,
            plannedMinutes: 8,
            sourceKind: .profesor,
            targetSkillID: skillID,
            evidenceDimension: .understanding,
            successCriterion: "Explicar tres intervalos",
            isDiagnosticChallenge: true
        )
        container.mainContext.insert(task)

        let next = RecurringPracticeService.completeTask(
            task,
            completedAt: Date(timeIntervalSince1970: 1_800_000_000),
            outcome: PracticeOutcome(
                result: .targetTempo,
                endBPM: 0,
                correctRepetitions: 3,
                tensionRating: 1,
                context: .isolated,
                wasColdCheck: false
            ),
            in: container.mainContext
        )

        XCTAssertEqual(next?.evidenceDimension, .retention)
        XCTAssertTrue(next?.title.contains("Revisión en frío") == true)
        XCTAssertEqual(next?.targetSkillID, skillID)
    }
}
