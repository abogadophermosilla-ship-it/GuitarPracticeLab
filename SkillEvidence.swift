import Foundation
import SwiftData
import SwiftUI

/// Las seis formas complementarias de demostrar una habilidad. Una respuesta de opción múltiple
/// puede aportar conocimiento, pero nunca sustituye ejecución, aplicación o retención.
enum SkillEvidenceDimension: String, CaseIterable, Codable, Identifiable {
    case recognition = "Reconocimiento"
    case understanding = "Comprensión"
    case execution = "Ejecución"
    case musicalApplication = "Aplicación musical"
    case transfer = "Transferencia"
    case retention = "Retención"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .recognition: "eye"
        case .understanding: "brain.head.profile"
        case .execution: "guitars.fill"
        case .musicalApplication: "music.note.list"
        case .transfer: "arrow.triangle.branch"
        case .retention: "clock.arrow.circlepath"
        }
    }

    var color: Color {
        switch self {
        case .recognition: .cyan
        case .understanding: .indigo
        case .execution: .blue
        case .musicalApplication: .purple
        case .transfer: .orange
        case .retention: .green
        }
    }
}

enum SkillEvidenceSourceKind: String, Codable {
    case assessment
    case practiceSession
    case academy
    case earTraining
    case audioAnalysis
    case libraryProgress
    case repertoireProgress
    case teacher
    case hermesChallenge
    case legacy
}

enum SkillEvidenceEvaluator: String, Codable {
    case deterministic
    case selfReport
    case objectiveAudio
    case teacher
    case aiRubric
}

enum SkillProfileConfidence: String, CaseIterable, Codable {
    case low = "Baja"
    case medium = "Media"
    case high = "Alta"

    var color: Color {
        switch self {
        case .low: .orange
        case .medium: .blue
        case .high: .green
        }
    }
}

/// Libro mayor de evidencia. `deduplicationKey` permite actualizar una sesión editada o un estado
/// de catálogo sin contar dos veces la misma señal.
@Model
final class SkillEvidence {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var deduplicationKey: String
    var skillID: UUID
    var dimensionRaw: String
    var sourceKindRaw: String
    var sourceID: UUID?
    var score: Double
    var reliability: Double
    var applicationContextRaw: String
    var occurredAt: Date
    var wasColdCheck: Bool
    var evaluatorRaw: String
    var notes: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        deduplicationKey: String,
        skillID: UUID,
        dimension: SkillEvidenceDimension,
        sourceKind: SkillEvidenceSourceKind,
        sourceID: UUID? = nil,
        score: Double,
        reliability: Double,
        applicationContext: PracticeApplicationContext? = nil,
        occurredAt: Date = .now,
        wasColdCheck: Bool = false,
        evaluator: SkillEvidenceEvaluator,
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.deduplicationKey = deduplicationKey
        self.skillID = skillID
        self.dimensionRaw = dimension.rawValue
        self.sourceKindRaw = sourceKind.rawValue
        self.sourceID = sourceID
        self.score = min(max(score, 0), 1)
        self.reliability = min(max(reliability, 0), 1)
        self.applicationContextRaw = applicationContext?.rawValue ?? ""
        self.occurredAt = occurredAt
        self.wasColdCheck = wasColdCheck
        self.evaluatorRaw = evaluator.rawValue
        self.notes = notes
        self.createdAt = createdAt
    }

    var dimension: SkillEvidenceDimension {
        get { SkillEvidenceDimension(rawValue: dimensionRaw) ?? .recognition }
        set { dimensionRaw = newValue.rawValue }
    }

    var sourceKind: SkillEvidenceSourceKind {
        get { SkillEvidenceSourceKind(rawValue: sourceKindRaw) ?? .legacy }
        set { sourceKindRaw = newValue.rawValue }
    }

    var evaluator: SkillEvidenceEvaluator {
        get { SkillEvidenceEvaluator(rawValue: evaluatorRaw) ?? .deterministic }
        set { evaluatorRaw = newValue.rawValue }
    }

    var applicationContext: PracticeApplicationContext? {
        get { PracticeApplicationContext(rawValue: applicationContextRaw) }
        set { applicationContextRaw = newValue?.rawValue ?? "" }
    }
}

struct SkillDimensionProfile: Identifiable {
    var id: String { dimension.rawValue }
    let dimension: SkillEvidenceDimension
    let score: Double
    let confidence: Double
    let evidenceCount: Int
    let lastEvidenceAt: Date?
}

struct SkillProfile {
    let skillID: UUID
    let dimensions: [SkillDimensionProfile]
    let demonstratedLevel: SkillMasteryLevel
    let confidence: SkillProfileConfidence
    let nextDimension: SkillEvidenceDimension

    func dimension(_ value: SkillEvidenceDimension) -> SkillDimensionProfile {
        dimensions.first(where: { $0.dimension == value })
            ?? SkillDimensionProfile(dimension: value, score: 0, confidence: 0, evidenceCount: 0, lastEvidenceAt: nil)
    }

    var evidenceCount: Int { dimensions.reduce(0) { $0 + $1.evidenceCount } }
}

/// Calcula el perfil sin IA. Limita el peso de repeticiones antiguas y exige evidencia en varias
/// dimensiones antes de permitir las bandas superiores.
enum SkillMasteryEngine {
    static func profile(
        for skill: SkillTopic,
        evidence: [SkillEvidence],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> SkillProfile {
        let relevant = evidence.filter { $0.skillID == skill.id }
        let dimensions = SkillEvidenceDimension.allCases.map { dimension -> SkillDimensionProfile in
            let samples = relevant
                .filter { $0.dimension == dimension }
                .sorted { $0.occurredAt > $1.occurredAt }
                .prefix(6)
            let weighted = samples.map { item -> (score: Double, weight: Double) in
                let age = max(0, calendar.dateComponents([.day], from: item.occurredAt, to: now).day ?? 0)
                let recency: Double
                switch age {
                case 0...14: recency = 1
                case 15...45: recency = 0.85
                case 46...90: recency = 0.70
                default: recency = 0.50
                }
                return (item.score, max(0.05, item.reliability * recency * contextMultiplier(for: item)))
            }
            let weightSum = weighted.reduce(0) { $0 + $1.weight }
            let score = weightSum > 0
                ? weighted.reduce(0) { $0 + $1.score * $1.weight } / weightSum
                : 0
            let sourceVariety = Set(samples.map(\.sourceKindRaw)).count
            let varietyFactor = min(1, 0.7 + Double(max(0, sourceVariety - 1)) * 0.15)
            let confidence = min(1, (weightSum / 2.5) * varietyFactor)
            return SkillDimensionProfile(
                dimension: dimension,
                score: score,
                confidence: confidence,
                evidenceCount: samples.count,
                lastEvidenceAt: samples.map(\.occurredAt).max()
            )
        }

        let weights = dimensionWeights(for: skill.domain)
        let total = dimensions.reduce(0.0) { partial, item in
            partial + item.score * (weights[item.dimension] ?? 0)
        }
        var level = band(for: total, hasEvidence: !relevant.isEmpty)

        // Las bandas altas requieren aplicación y retención; reconocer respuestas no basta.
        let execution = dimensions.first { $0.dimension == .execution }
        let application = dimensions.first { $0.dimension == .musicalApplication }
        let transfer = dimensions.first { $0.dimension == .transfer }
        let retention = dimensions.first { $0.dimension == .retention }
        if skill.domain == .technique, (execution?.evidenceCount ?? 0) == 0 {
            level = capped(level, at: .basic)
        }
        if (application?.evidenceCount ?? 0) == 0 {
            level = capped(level, at: .intermediate)
        }
        if (retention?.evidenceCount ?? 0) == 0 {
            level = capped(level, at: .advanced)
        }
        if level == .consolidated,
           ((transfer?.score ?? 0) < 0.65 || (retention?.score ?? 0) < 0.70 || (application?.score ?? 0) < 0.70) {
            level = .advanced
        }

        let required = requiredDimensions(for: skill.domain)
        let confidenceValue = required
            .map { value in dimensions.first(where: { $0.dimension == value })?.confidence ?? 0 }
            .reduce(0, +) / Double(required.count)
        let confidence: SkillProfileConfidence
        switch confidenceValue {
        case 0.70...: confidence = .high
        case 0.35..<0.70: confidence = .medium
        default: confidence = .low
        }

        return SkillProfile(
            skillID: skill.id,
            dimensions: dimensions,
            demonstratedLevel: level,
            confidence: confidence,
            nextDimension: nextDimension(for: skill.domain, dimensions: dimensions)
        )
    }

    private static func contextMultiplier(for evidence: SkillEvidence) -> Double {
        switch evidence.dimension {
        case .musicalApplication:
            return evidence.applicationContext == .fullPiece || evidence.applicationContext == .backingTrack ? 1 : 0.8
        case .transfer:
            return evidence.applicationContext == .fromMemory ? 1 : 0.85
        case .retention:
            return evidence.wasColdCheck ? 1 : 0.7
        default:
            return 1
        }
    }

    private static func dimensionWeights(for domain: SkillDomain) -> [SkillEvidenceDimension: Double] {
        switch domain {
        case .technique:
            [
                .recognition: 0.10, .understanding: 0.10, .execution: 0.30,
                .musicalApplication: 0.25, .transfer: 0.10, .retention: 0.15
            ]
        case .theory:
            [
                .recognition: 0.20, .understanding: 0.25, .execution: 0.05,
                .musicalApplication: 0.20, .transfer: 0.15, .retention: 0.15
            ]
        }
    }

    private static func requiredDimensions(for domain: SkillDomain) -> [SkillEvidenceDimension] {
        domain == .technique
            ? [.execution, .musicalApplication, .transfer, .retention]
            : [.recognition, .understanding, .musicalApplication, .transfer, .retention]
    }

    private static func nextDimension(
        for domain: SkillDomain,
        dimensions: [SkillDimensionProfile]
    ) -> SkillEvidenceDimension {
        let priority: [SkillEvidenceDimension] = domain == .technique
            ? [.execution, .musicalApplication, .retention, .transfer, .understanding, .recognition]
            : [.understanding, .musicalApplication, .retention, .transfer, .recognition, .execution]
        if let missing = priority.first(where: { value in
            dimensions.first(where: { $0.dimension == value })?.evidenceCount == 0
        }) { return missing }
        return priority.min { lhs, rhs in
            let left = dimensions.first(where: { $0.dimension == lhs })
            let right = dimensions.first(where: { $0.dimension == rhs })
            return (left?.score ?? 0) * (left?.confidence ?? 0) < (right?.score ?? 0) * (right?.confidence ?? 0)
        } ?? .musicalApplication
    }

    private static func band(for score: Double, hasEvidence: Bool) -> SkillMasteryLevel {
        guard hasEvidence else { return .notStarted }
        switch score {
        case 0.85...: return .consolidated
        case 0.70..<0.85: return .advanced
        case 0.52..<0.70: return .intermediate
        case 0.34..<0.52: return .basic
        default: return .initial
        }
    }

    private static func capped(_ level: SkillMasteryLevel, at maximum: SkillMasteryLevel) -> SkillMasteryLevel {
        level.progressWeight > maximum.progressWeight ? maximum : level
    }
}

struct SkillEvidenceDraft {
    let dimension: SkillEvidenceDimension
    let score: Double
    let reliability: Double
    let context: PracticeApplicationContext?
    let wasColdCheck: Bool
    let notes: String
}

enum SkillEvidenceFactory {
    static func practiceDrafts(
        outcome: PracticeOutcome,
        category: PracticeCategory,
        requestedDimension: SkillEvidenceDimension?,
        theoryMode: TheoryTaskMode = .guided
    ) -> [SkillEvidenceDraft] {
        var score: Double
        switch outcome.result {
        case .started: score = 0.20
        case .learning: score = 0.42
        case .reducedTempo: score = 0.65
        case .targetTempo: score = 0.88
        case .review: score = 0.25
        }
        score += min(Double(outcome.correctRepetitions), 5) * 0.02
        score -= Double(max(0, outcome.tensionRating - 2)) * 0.06
        score = min(max(score, 0), 1)

        let inferred: SkillEvidenceDimension = requestedDimension ?? {
            if category == .theory {
                switch theoryMode {
                case .readAndExplain, .writtenSummary: return .understanding
                case .flashcards, .answerQuestions: return .recognition
                case .applyOnGuitar: return .musicalApplication
                case .guided: break
                }
            }
            switch outcome.context {
            case .isolated, .metronome: return .execution
            case .backingTrack, .fullPiece: return .musicalApplication
            case .fromMemory: return .transfer
            }
        }()
        let baseReliability = outcome.isStableSuccess ? 0.80 : 0.65
        var drafts = [SkillEvidenceDraft(
            dimension: inferred,
            score: score,
            reliability: baseReliability,
            context: outcome.context,
            wasColdCheck: outcome.wasColdCheck,
            notes: outcome.result.rawValue
        )]

        if inferred == .musicalApplication || inferred == .transfer {
            drafts.append(SkillEvidenceDraft(
                dimension: .execution,
                score: score,
                reliability: baseReliability * 0.75,
                context: outcome.context,
                wasColdCheck: outcome.wasColdCheck,
                notes: "Ejecución observada dentro de \(outcome.context.rawValue.lowercased())"
            ))
        }
        if outcome.wasColdCheck {
            drafts.append(SkillEvidenceDraft(
                dimension: .retention,
                score: score,
                reliability: outcome.isStableSuccess ? 0.88 : 0.75,
                context: outcome.context,
                wasColdCheck: true,
                notes: "Comprobación en frío"
            ))
        }

        return Dictionary(grouping: drafts, by: \.dimension).compactMap { _, values in
            values.max { $0.reliability < $1.reliability }
        }
    }
}

/// Punto único de escritura de evidencias y de actualización del dominio demostrado.
enum SkillEvidenceService {
    static func recordAssessment(for topic: SkillTopic, runID: UUID, in context: ModelContext) {
        guard let ratio = SkillAssessmentCoachService.assessmentRatio(for: topic) else { return }
        topic.testStatus = SkillAssessmentCoachService.computeStatus(for: topic)
        let values: [(SkillEvidenceDimension, Double)] = [(.recognition, 0.78), (.understanding, 0.62)]
        for (dimension, reliability) in values {
            upsert(
                key: "assessment:\(runID.uuidString):\(topic.id.uuidString):\(dimension.rawValue)",
                skillID: topic.id,
                dimension: dimension,
                sourceKind: .assessment,
                sourceID: runID,
                score: ratio,
                reliability: reliability,
                occurredAt: .now,
                evaluator: .deterministic,
                notes: "Test Integral",
                in: context
            )
        }
        refreshStatus(for: topic, in: context, detail: "Perfil de dominio · Test Integral")
    }

    static func recordPractice(session: PracticeSession, task: PracticeTask?, in context: ModelContext) {
        let skills = resolvedSkills(session: session, task: task, in: context)
        guard !skills.isEmpty else { return }
        let outcome = PracticeOutcome(
            result: session.result,
            endBPM: session.endBPM,
            correctRepetitions: session.correctRepetitions,
            tensionRating: session.tensionRating,
            context: session.practiceContext,
            wasColdCheck: session.wasColdCheck
        )
        let requestedDimension = session.evidenceDimension ?? task?.evidenceDimension
        let drafts = SkillEvidenceFactory.practiceDrafts(
            outcome: outcome,
            category: session.category,
            requestedDimension: requestedDimension,
            theoryMode: task?.theoryTaskMode ?? .guided
        )
        for skill in skills {
            for draft in drafts {
                upsert(
                    key: "session:\(session.id.uuidString):\(skill.id.uuidString):\(draft.dimension.rawValue)",
                    skillID: skill.id,
                    dimension: draft.dimension,
                    sourceKind: task?.isDiagnosticChallenge == true ? .hermesChallenge : .practiceSession,
                    sourceID: session.id,
                    score: draft.score,
                    reliability: draft.reliability,
                    applicationContext: draft.context,
                    occurredAt: session.date,
                    wasColdCheck: draft.wasColdCheck,
                    evaluator: .selfReport,
                    notes: [session.successCriterion, draft.notes].filter { !$0.isEmpty }.joined(separator: " · "),
                    in: context
                )
            }
            refreshStatus(for: skill, in: context, detail: "Perfil de dominio · Práctica registrada")
        }
    }

    static func recordTheoryReview(topicID: UUID, isCorrect: Bool, wasDue: Bool, in context: ModelContext) {
        guard let topic = skill(id: topicID, in: context) else { return }
        let attemptID = UUID()
        upsert(
            key: "academy:\(attemptID.uuidString):recognition",
            skillID: topicID,
            dimension: .recognition,
            sourceKind: .academy,
            sourceID: attemptID,
            score: isCorrect ? 1 : 0,
            reliability: 0.72,
            occurredAt: .now,
            evaluator: .deterministic,
            notes: "Repaso de teoría",
            in: context
        )
        if wasDue {
            upsert(
                key: "academy:\(attemptID.uuidString):retention",
                skillID: topicID,
                dimension: .retention,
                sourceKind: .academy,
                sourceID: attemptID,
                score: isCorrect ? 1 : 0,
                reliability: 0.78,
                occurredAt: .now,
                wasColdCheck: true,
                evaluator: .deterministic,
                notes: "Repaso espaciado vencido",
                in: context
            )
        }
        refreshStatus(for: topic, in: context, detail: "Perfil de dominio · Academia")
    }

    static func recordEarTraining(item: EarTrainingItem, isCorrect: Bool, wasDue: Bool, in context: ModelContext) {
        let targetName: String
        switch item {
        case .interval: targetName = "Intervalos"
        case .chord: targetName = "Construcción de tríadas"
        }
        guard let topic = allSkills(in: context).first(where: { $0.name == targetName }) else { return }
        let attemptID = UUID()
        upsert(
            key: "ear:\(attemptID.uuidString):recognition",
            skillID: topic.id,
            dimension: .recognition,
            sourceKind: .earTraining,
            sourceID: attemptID,
            score: isCorrect ? 1 : 0,
            reliability: 0.82,
            occurredAt: .now,
            evaluator: .deterministic,
            notes: "Reconocimiento auditivo · \(item.label)",
            in: context
        )
        if wasDue {
            upsert(
                key: "ear:\(attemptID.uuidString):retention",
                skillID: topic.id,
                dimension: .retention,
                sourceKind: .earTraining,
                sourceID: attemptID,
                score: isCorrect ? 1 : 0,
                reliability: 0.82,
                occurredAt: .now,
                wasColdCheck: true,
                evaluator: .deterministic,
                notes: "Reconocimiento auditivo espaciado",
                in: context
            )
        }
        refreshStatus(for: topic, in: context, detail: "Perfil de dominio · Entrenamiento de oído")
    }

    static func recordObjectiveAudio(
        artifactID: UUID,
        skillID: UUID,
        dimension: SkillEvidenceDimension,
        score: Double,
        reliability: Double,
        notes: String,
        in context: ModelContext
    ) {
        guard let topic = skill(id: skillID, in: context) else { return }
        upsert(
            key: "audio:\(artifactID.uuidString):\(skillID.uuidString):\(dimension.rawValue)",
            skillID: skillID,
            dimension: dimension,
            sourceKind: .audioAnalysis,
            sourceID: artifactID,
            score: score,
            reliability: reliability,
            occurredAt: .now,
            evaluator: .objectiveAudio,
            notes: notes,
            in: context
        )
        refreshStatus(for: topic, in: context, detail: "Perfil de dominio · Análisis objetivo de audio")
    }

    /// Evidencia producida por las pruebas prácticas guiadas. Siempre mide ejecución; una revisión
    /// mensual hecha en frío aporta además retención, sin convertir la misma muestra en dos intentos
    /// independientes ni depender de una autoevaluación del usuario.
    static func recordLiveAudioAssessment(
        runID: UUID,
        skillID: UUID,
        score: Double,
        reliability: Double,
        wasColdCheck: Bool,
        occurredAt: Date,
        notes: String,
        in context: ModelContext
    ) {
        guard let topic = skill(id: skillID, in: context) else { return }
        let dimensions: [SkillEvidenceDimension] = wasColdCheck ? [.execution, .retention] : [.execution]
        for dimension in dimensions {
            upsert(
                key: "live-audio:\(runID.uuidString):\(skillID.uuidString):\(dimension.rawValue)",
                skillID: skillID,
                dimension: dimension,
                sourceKind: .audioAnalysis,
                sourceID: runID,
                score: score,
                reliability: dimension == .retention ? min(reliability, 0.82) : reliability,
                applicationContext: .isolated,
                occurredAt: occurredAt,
                wasColdCheck: wasColdCheck,
                evaluator: .objectiveAudio,
                notes: notes,
                in: context
            )
        }
        refreshStatus(for: topic, in: context, detail: "Perfil de dominio · Evaluación práctica con audio")
    }

    static func syncCatalogEvidence(
        for topic: SkillTopic,
        songs: [Song],
        exercises: [LibraryExercise],
        in context: ModelContext
    ) {
        let linkedExercises = SkillAssessmentCoachService.matchingExercises(for: topic, exercises: exercises)
        syncAggregate(
            key: "catalog:library:\(topic.id.uuidString)",
            topic: topic,
            dimension: .execution,
            sourceKind: .libraryProgress,
            weights: linkedExercises.map(\.status.progressWeight),
            note: "Progreso agregado de \(linkedExercises.count) ejercicio(s)",
            in: context
        )
        let linkedSongs = songs.filter { $0.linkedSkillIDs.contains(topic.id) }
        syncAggregate(
            key: "catalog:repertoire:\(topic.id.uuidString)",
            topic: topic,
            dimension: .musicalApplication,
            sourceKind: .repertoireProgress,
            weights: linkedSongs.map(\.status.progressWeight),
            note: "Progreso agregado de \(linkedSongs.count) canción(es)",
            in: context
        )
        refreshStatus(for: topic, in: context, detail: "Perfil de dominio · Material trabajado")
    }

    static func evidence(for skillID: UUID, in context: ModelContext) -> [SkillEvidence] {
        let targetID = skillID
        return (try? context.fetch(FetchDescriptor<SkillEvidence>(
            predicate: #Predicate { $0.skillID == targetID }
        ))) ?? []
    }

    static func refreshAllStatuses(in context: ModelContext) {
        let groupedEvidence = Dictionary(
            grouping: (try? context.fetch(FetchDescriptor<SkillEvidence>())) ?? [],
            by: \.skillID
        )
        for topic in allSkills(in: context) {
            refreshStatus(
                for: topic,
                evidence: groupedEvidence[topic.id, default: []],
                in: context,
                detail: "Perfil de dominio · Revisión de vigencia"
            )
        }
    }

    static func removeEvidence(for session: PracticeSession, in context: ModelContext) {
        let sessionID = session.id
        let practiceKind = SkillEvidenceSourceKind.practiceSession.rawValue
        let challengeKind = SkillEvidenceSourceKind.hermesChallenge.rawValue
        let records = (try? context.fetch(FetchDescriptor<SkillEvidence>(
            predicate: #Predicate {
                $0.sourceID == sessionID &&
                    ($0.sourceKindRaw == practiceKind || $0.sourceKindRaw == challengeKind)
            }
        ))) ?? []
        let affectedIDs = Set(records.map(\.skillID))
        records.forEach(context.delete)
        for topic in allSkills(in: context) where affectedIDs.contains(topic.id) {
            refreshStatus(for: topic, in: context, detail: "Perfil de dominio · Sesión eliminada")
        }
    }

    static func refreshStatus(for topic: SkillTopic, in context: ModelContext, detail: String) {
        refreshStatus(for: topic, evidence: evidence(for: topic.id, in: context), in: context, detail: detail)
    }

    private static func refreshStatus(
        for topic: SkillTopic,
        evidence: [SkillEvidence],
        in context: ModelContext,
        detail: String
    ) {
        let profile = SkillMasteryEngine.profile(for: topic, evidence: evidence)
        topic.demonstratedConfidence = profile.confidence
        guard !topic.statusIsManual, profile.demonstratedLevel != topic.status else { return }
        let previous = topic.status
        topic.status = profile.demonstratedLevel
        ProgressTracker.recordIfLevelUp(
            itemName: topic.name,
            category: topic.domain == .theory ? .theory : .technique,
            previousLabel: previous.rawValue,
            previousWeight: previous.progressWeight,
            newLabel: topic.status.rawValue,
            newWeight: topic.status.progressWeight,
            contextDetail: detail,
            in: context
        )
    }

    fileprivate static func upsert(
        key: String,
        skillID: UUID,
        dimension: SkillEvidenceDimension,
        sourceKind: SkillEvidenceSourceKind,
        sourceID: UUID? = nil,
        score: Double,
        reliability: Double,
        applicationContext: PracticeApplicationContext? = nil,
        occurredAt: Date,
        wasColdCheck: Bool = false,
        evaluator: SkillEvidenceEvaluator,
        notes: String,
        in context: ModelContext
    ) {
        let lookupKey = key
        var descriptor = FetchDescriptor<SkillEvidence>(predicate: #Predicate { $0.deduplicationKey == lookupKey })
        descriptor.fetchLimit = 1
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.skillID = skillID
            existing.dimension = dimension
            existing.sourceKind = sourceKind
            existing.sourceID = sourceID
            existing.score = min(max(score, 0), 1)
            existing.reliability = min(max(reliability, 0), 1)
            existing.applicationContext = applicationContext
            existing.occurredAt = occurredAt
            existing.wasColdCheck = wasColdCheck
            existing.evaluator = evaluator
            existing.notes = notes
        } else {
            context.insert(SkillEvidence(
                deduplicationKey: key,
                skillID: skillID,
                dimension: dimension,
                sourceKind: sourceKind,
                sourceID: sourceID,
                score: score,
                reliability: reliability,
                applicationContext: applicationContext,
                occurredAt: occurredAt,
                wasColdCheck: wasColdCheck,
                evaluator: evaluator,
                notes: notes
            ))
        }
    }

    private static func syncAggregate(
        key: String,
        topic: SkillTopic,
        dimension: SkillEvidenceDimension,
        sourceKind: SkillEvidenceSourceKind,
        weights: [Int],
        note: String,
        in context: ModelContext
    ) {
        let lookupKey = key
        let records = (try? context.fetch(FetchDescriptor<SkillEvidence>(
            predicate: #Predicate { $0.deduplicationKey == lookupKey }
        ))) ?? []
        guard !weights.isEmpty else {
            records.filter { $0.deduplicationKey == key }.forEach(context.delete)
            return
        }
        let score = Double(weights.reduce(0, +)) / Double(weights.count * 5)
        upsert(
            key: key,
            skillID: topic.id,
            dimension: dimension,
            sourceKind: sourceKind,
            score: score,
            reliability: min(0.72, 0.42 + Double(weights.count) * 0.04),
            occurredAt: .now,
            evaluator: .deterministic,
            notes: note,
            in: context
        )
    }

    private static func resolvedSkills(session: PracticeSession, task: PracticeTask?, in context: ModelContext) -> [SkillTopic] {
        let skills = allSkills(in: context)
        if let explicitID = session.targetSkillID ?? task?.targetSkillID,
           let explicit = skills.first(where: { $0.id == explicitID }) {
            return [explicit]
        }
        guard let sourceID = session.sourceID else { return [] }
        switch session.sourceKind {
        case .library:
            guard let exercise = LibraryLookup.exercise(id: sourceID, in: context) else { return [] }
            return SkillAssessmentCoachService.matchingSkills(for: exercise, topics: skills)
        case .libraryConcept:
            guard let concept = LibraryLookup.concept(id: sourceID, in: context) else { return [] }
            return SkillAssessmentCoachService.matchingSkills(for: concept, topics: skills)
        case .repertoire:
            var descriptor = FetchDescriptor<Song>(predicate: #Predicate { $0.id == sourceID })
            descriptor.fetchLimit = 1
            guard let song = (try? context.fetch(descriptor))?.first else { return [] }
            return skills.filter { song.linkedSkillIDs.contains($0.id) }
        default:
            return []
        }
    }

    private static func skill(id: UUID, in context: ModelContext) -> SkillTopic? {
        allSkills(in: context).first { $0.id == id }
    }

    private static func allSkills(in context: ModelContext) -> [SkillTopic] {
        (try? context.fetch(FetchDescriptor<SkillTopic>())) ?? []
    }
}

/// Traduce únicamente métricas observables del analizador local. No intenta juzgar musicalidad,
/// elección de notas ni afinación expresiva de bends porque el audio no trae una referencia objetivo.
enum ObjectiveAudioEvidenceScorer {
    struct Result {
        let score: Double
        let reliability: Double
        let summary: String
    }

    static func score(metadataJSON: String, targetBPM: Int) -> Result? {
        guard let data = metadataJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var values: [(Double, Double, String)] = []

        if let notes = root["notes"] as? [String: Any] {
            if let variation = number(notes["attackIntervalVariation"]), variation >= 0 {
                let regularity = min(max(1 - variation / 0.35, 0), 1)
                values.append((regularity, 0.55, "variación entre ataques \(Int((variation * 100).rounded()))%"))
            } else if let count = number(notes["count"]), count > 0 {
                values.append((0.60, 0.20, "\(Int(count)) notas detectadas"))
            }
        }

        if targetBPM > 0,
           let essentia = root["essentia"] as? [String: Any],
           let rhythm = essentia["rhythm"] as? [String: Any],
           let bpm = number(rhythm["bpm"]) {
            let tolerance = max(8, Double(targetBPM) * 0.12)
            let tempoScore = min(max(1 - abs(bpm - Double(targetBPM)) / tolerance, 0), 1)
            values.append((tempoScore, 0.45, "tempo \(Int(bpm.rounded()))/\(targetBPM) BPM"))
        }

        guard !values.isEmpty else { return nil }
        let weight = values.reduce(0) { $0 + $1.1 }
        return Result(
            score: values.reduce(0) { $0 + $1.0 * $1.1 } / weight,
            reliability: values.count >= 2 ? 0.90 : 0.72,
            summary: values.map(\.2).joined(separator: " · ")
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }
}

/// Importación única de los datos existentes al nuevo libro mayor. Las evidencias agregadas de
/// Biblioteca/Repertorio usan claves estables y después siguen sincronizándose cuando cambia el
/// estado del material.
enum SkillEvidenceBackfillService {
    private static let versionKey = "skillEvidenceBackfillVersion"
    private static let currentVersion = 1

    static func runIfNeeded(in context: ModelContext, defaults: UserDefaults = .standard) {
        guard defaults.integer(forKey: versionKey) < currentVersion else { return }
        let topics = (try? context.fetch(FetchDescriptor<SkillTopic>())) ?? []
        guard !topics.isEmpty else { return }
        let songs = (try? context.fetch(FetchDescriptor<Song>())) ?? []
        let exercises = (try? context.fetch(FetchDescriptor<LibraryExercise>())) ?? []
        let sessions = (try? context.fetch(FetchDescriptor<PracticeSession>())) ?? []
        let runID = UUID()

        for topic in topics {
            if SkillAssessmentCoachService.assessmentRatio(for: topic) != nil {
                SkillEvidenceService.recordAssessment(for: topic, runID: runID, in: context)
            }
            SkillEvidenceService.syncCatalogEvidence(for: topic, songs: songs, exercises: exercises, in: context)
        }
        for session in sessions {
            SkillEvidenceService.recordPractice(session: session, task: nil, in: context)
        }
        do {
            try context.save()
            // Solo se marca la migración cuando las evidencias realmente llegaron al store. Si el
            // guardado falla, el siguiente arranque vuelve a intentarlo en vez de perder el backfill
            // para siempre.
            defaults.set(currentVersion, forKey: versionKey)
        } catch {
            assertionFailure("No se pudo guardar el backfill de evidencias: \(error.localizedDescription)")
        }
    }
}

/// Prerrequisitos estables del currículo. Las rutas por objetivo y Hermes consultan este grafo; no
/// obliga a seguir un curso lineal, sino que detecta huecos antes de proponer el siguiente reto.
enum SkillGraphService {
    private static let names: [String: [String]] = [
        "Sincronización entre ambas manos": ["Postura, relajación y mecánica general"],
        "Ritmo, subdivisión y groove": ["Postura, relajación y mecánica general"],
        "Acordes y guitarra rítmica": ["Ritmo, subdivisión y groove"],
        "Muting y palm muting": ["Sincronización entre ambas manos"],
        "Alternate picking": ["Sincronización entre ambas manos", "Ritmo, subdivisión y groove"],
        "Downpicking, tremolo picking y gallops": ["Sincronización entre ambas manos", "Ritmo, subdivisión y groove"],
        "Legato": ["Sincronización entre ambas manos"],
        "Slides y cambios de posición": ["Sincronización entre ambas manos"],
        "Bending": ["Postura, relajación y mecánica general"],
        "Vibrato": ["Bending"],
        "String skipping": ["Alternate picking"],
        "Economy picking": ["Alternate picking"],
        "Sweep picking": ["Economy picking", "Arpegios y notas del acorde"],
        "Tapping": ["Legato", "Ritmo, subdivisión y groove"],
        "Armónicos": ["Muting y palm muting"],
        "Hybrid picking, fingerstyle y palanca": ["Acordes y guitarra rítmica", "Sincronización entre ambas manos"],
        "Alteraciones y notas enarmónicas": ["Notas musicales y organización del diapasón"],
        "Intervalos": ["Notas musicales y organización del diapasón"],
        "Escala mayor y tonalidades": ["Intervalos", "Alteraciones y notas enarmónicas"],
        "Escalas menores": ["Escala mayor y tonalidades"],
        "Escalas pentatónicas y blues": ["Escalas menores"],
        "Construcción de tríadas": ["Intervalos", "Escala mayor y tonalidades"],
        "Acordes de séptima y extensiones": ["Construcción de tríadas"],
        "Inversiones, voicings y sistema CAGED": ["Construcción de tríadas", "Notas musicales y organización del diapasón"],
        "Armonización de la escala mayor": ["Escala mayor y tonalidades", "Construcción de tríadas"],
        "Funciones armónicas": ["Armonización de la escala mayor"],
        "Progresiones y cadencias": ["Funciones armónicas"],
        "Arpegios y notas del acorde": ["Construcción de tríadas"],
        "Modos de la escala mayor": ["Escala mayor y tonalidades", "Intervalos"],
        "Voice leading y conducción de voces": ["Inversiones, voicings y sistema CAGED", "Funciones armónicas"],
        "Transporte y afinaciones": ["Intervalos", "Notas musicales y organización del diapasón"],
        "Improvisación y relación acorde-escala": ["Escalas pentatónicas y blues", "Funciones armónicas"],
        "Recursos armónicos no diatónicos": ["Funciones armónicas", "Modos de la escala mayor"],
        "Oído, transcripción, lectura y sonido eléctrico": ["Intervalos", "Acordes de séptima y extensiones"]
    ]

    static func prerequisites(for topic: SkillTopic, among topics: [SkillTopic]) -> [SkillTopic] {
        let expected = Set(names[topic.name] ?? [])
        return topics.filter { expected.contains($0.name) }
    }

    static func missingPrerequisites(for topic: SkillTopic, among topics: [SkillTopic]) -> [SkillTopic] {
        prerequisites(for: topic, among: topics).filter { $0.status.progressWeight < SkillMasteryLevel.intermediate.progressWeight }
    }
}

enum SkillChallengeBuilder {
    static func makeTask(
        for topic: SkillTopic,
        profile: SkillProfile,
        exercises: [LibraryExercise],
        songs: [Song],
        dimension override: SkillEvidenceDimension? = nil,
        criterion criterionOverride: String? = nil,
        minutes: Int = 8
    ) -> PracticeTask {
        let dimension = override ?? profile.nextDimension
        let matchingExercises = SkillAssessmentCoachService.matchingExercises(for: topic, exercises: exercises)
            .filter { $0.status != .mastered }
        let matchingSongs = songs.filter { $0.linkedSkillIDs.contains(topic.id) && $0.status != .mastered }
        let prefersSong = [.musicalApplication, .transfer, .retention].contains(dimension)
        let song = prefersSong ? matchingSongs.first : nil
        let exercise = song == nil ? matchingExercises.first : nil

        let sourceKind: TaskSourceKind = song != nil ? .repertoire : (exercise != nil ? .library : .profesor)
        let sourceID = song?.id ?? exercise?.id
        let sourceTitle = song?.artist ?? exercise?.bookTitle ?? "Mapa de habilidades"
        let materialTitle = song?.title ?? exercise?.displayName ?? topic.name
        let targetBPM = song?.targetTempo ?? exercise?.targetBPM ?? 0
        let criterion = criterionOverride?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? criterionOverride!
            : criterion(for: dimension, targetBPM: targetBPM)
        let instructions = "Objetivo: \(dimension.rawValue). \(criterion) Registra resultado, repeticiones, tensión y contexto al terminar."
        let category: PracticeCategory = song != nil ? .repertoire : (topic.domain == .theory ? .theory : .technique)

        return PracticeTask(
            title: "Comprobar · \(topic.name)",
            category: category,
            plannedMinutes: min(max(minutes, 5), 30),
            sourceTitle: sourceTitle,
            exerciseTitle: materialTitle,
            targetBPM: targetBPM,
            priority: 0,
            instructions: instructions,
            theoryTaskMode: theoryMode(for: dimension),
            repertoireTaskMode: repertoireMode(for: dimension),
            scheduledDate: .now,
            sourceKind: sourceKind,
            sourceID: sourceID,
            targetSkillID: topic.id,
            evidenceDimension: dimension,
            successCriterion: criterion,
            isDiagnosticChallenge: true
        )
    }

    static func recommendedContext(for dimension: SkillEvidenceDimension) -> PracticeApplicationContext {
        switch dimension {
        case .recognition, .understanding, .execution: .isolated
        case .musicalApplication: .backingTrack
        case .transfer, .retention: .fromMemory
        }
    }

    static func criterion(for dimension: SkillEvidenceDimension, targetBPM: Int) -> String {
        let tempo = targetBPM > 0 ? " a \(targetBPM) BPM" : " a un tempo cómodo y estable"
        switch dimension {
        case .recognition:
            return "Responde o identifica correctamente al menos 8 de 10 ejemplos sin consultar material."
        case .understanding:
            return "Explícalo con tus propias palabras y muestra dos ejemplos distintos en la guitarra."
        case .execution:
            return "Consigue tres repeticiones limpias seguidas\(tempo), con tensión máxima 2/5."
        case .musicalApplication:
            return "Úsalo dentro de una canción o backing track sin detener el pulso y repítelo tres veces."
        case .transfer:
            return "Muévelo a otra tonalidad, cuerda o zona del mástil sin volver a consultar la referencia."
        case .retention:
            return "Haz una pasada en frío, sin calentamiento específico ni consulta, y logra tres repeticiones estables."
        }
    }

    private static func theoryMode(for dimension: SkillEvidenceDimension) -> TheoryTaskMode {
        switch dimension {
        case .recognition: .answerQuestions
        case .understanding: .readAndExplain
        case .musicalApplication, .transfer: .applyOnGuitar
        case .retention: .flashcards
        case .execution: .guided
        }
    }

    private static func repertoireMode(for dimension: SkillEvidenceDimension) -> RepertoireTaskMode {
        switch dimension {
        case .retention, .transfer: .fromMemory
        case .musicalApplication: .fullRun
        default: .bySections
        }
    }
}

struct HermesChallengeProposal: Equatable {
    let skillName: String
    let dimension: SkillEvidenceDimension
    let minutes: Int
    let criterion: String

    static func extract(from text: String) -> (cleanText: String, proposal: HermesChallengeProposal?) {
        guard let start = text.range(of: "[RETO]"),
              let end = text.range(of: "[/RETO]", range: start.upperBound..<text.endIndex) else {
            return (text, nil)
        }
        let block = String(text[start.upperBound..<end.lowerBound])
        var values: [String: String] = [:]
        for line in block.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            values[parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] =
                parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let skill = values["habilidad"] ?? ""
        let dimensionText = values["dimensión"] ?? values["dimension"] ?? ""
        guard !skill.isEmpty,
              let dimension = SkillEvidenceDimension.allCases.first(where: {
                  $0.rawValue.evidenceNormalized == dimensionText.evidenceNormalized
              }) else {
            return (text.replacingCharacters(in: start.lowerBound..<end.upperBound, with: "").trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }
        let minutesText = values["duración"] ?? values["duracion"] ?? "8"
        let minutes = Int(minutesText.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 8
        let criterion = values["criterio"] ?? ""
        let clean = text.replacingCharacters(in: start.lowerBound..<end.upperBound, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (clean, HermesChallengeProposal(
            skillName: skill,
            dimension: dimension,
            minutes: min(max(minutes, 5), 30),
            criterion: criterion
        ))
    }
}

private extension String {
    var evidenceNormalized: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
