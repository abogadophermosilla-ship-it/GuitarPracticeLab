import Foundation
import SwiftData

/// Registro interno que da identidad propia al esquema que introdujo la medición de repertorio.
/// Los modelos históricos de este proyecto comparten sus clases Swift actuales; sin un modelo
/// exclusivo, SwiftData ve V4 y V5 con la misma huella y rechaza el plan de migración.
@Model
final class RepertoirePracticeSchemaRecord {
    @Attribute(.unique) var key: String
    var createdAt: Date

    init(key: String = "repertoire-duration-v1", createdAt: Date = .now) {
        self.key = key
        self.createdAt = createdAt
    }
}

/// Versión 1 del esquema — la que había en producción cuando se empezó a versionar (2026-08-07).
///
/// Hasta acá los cambios de modelo se venían apoyando en la migración ligera implícita de SwiftData,
/// que alcanza mientras solo se agreguen propiedades con valor por defecto. En cuanto haga falta algo
/// que la migración ligera no cubre —renombrar una propiedad, volver obligatoria una opcional,
/// dividir un modelo— hay que crear `SchemaV2` con los modelos nuevos y agregar la etapa
/// correspondiente en `AppMigrationPlan.stages`. Sin eso, el store viejo no abre y la app queda sin
/// datos hasta restaurar un respaldo.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            PracticeSession.self,
            GuitarLesson.self,
            PracticeTask.self,
            LibraryExercise.self,
            LibraryConcept.self,
            Instrument.self,
            StudioAsset.self,
            Song.self,
            Band.self,
            SkillTopic.self,
            TheoryFlashcardProgress.self,
            AcademyQuestion.self,
            AcademyQuestionProgress.self,
            LibraryBook.self,
            RepertoireSuggestionRecord.self,
            LessonAttachment.self,
            ProgressMilestone.self,
            Recording.self,
            RecordingsLibraryRoot.self,
            AIArtifact.self,
            TeacherChatMessage.self,
            WeeklyPracticePlan.self,
            BacklogIdea.self,
            EarnedBadge.self,
            EarTrainingProgress.self,
            EarTrainingStats.self,
            SkillLadder.self,
            WeeklySummary.self
        ]
    }
}

/// Introduce el libro mayor de evidencia y separa el resultado del test del dominio demostrado.
/// Los campos nuevos de `SkillTopic`, `PracticeTask` y `PracticeSession` tienen valores por defecto,
/// por lo que la transición es compatible con migración ligera.
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        SchemaV1.models + [SkillEvidence.self]
    }
}

/// Agrega el perfil adaptativo y el detalle nota/cuerda del entrenador del mástil. Son modelos
/// nuevos, por lo que el store existente migra de forma ligera sin transformar datos anteriores.
enum SchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        SchemaV2.models + [FretboardNoteProgress.self, FretboardTrainingProfile.self]
    }
}

/// Agrega el catálogo evolutivo de dificultad. Los campos cacheados nuevos de `Song` son opcionales
/// o tienen valor por defecto, por lo que las canciones existentes se conservan y se evalúan de forma
/// provisional hasta que entren al catálogo.
enum SchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    static var models: [any PersistentModel.Type] {
        SchemaV3.models + [SongDifficultyRecord.self]
    }
}

/// Registra duraciones exactas y pasadas completas de repertorio. Todos los campos tienen un valor
/// por defecto, por lo que las canciones y sesiones anteriores se conservan mediante migración
/// ligera; sus minutos históricos siguen funcionando como respaldo.
enum SchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    static var models: [any PersistentModel.Type] {
        SchemaV4.models + [RepertoirePracticeSchemaRecord.self]
    }
}

/// Agrega el estado canónico del entrenador adaptativo. Es un modelo nuevo y sus campos tienen
/// valores por defecto, así que la transición conserva íntegro el store de V5.
enum SchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }

    static var models: [any PersistentModel.Type] {
        SchemaV5.models + [PracticeCoachStateRecord.self]
    }
}

/// Separa el historial del Profesor IA en conversaciones independientes. Los mensajes anteriores
/// no cambian de modelo: `TeacherConversation` los agrupa por ID y el primer acceso adopta todo el
/// historial heredado dentro de una conversación conservada.
enum SchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(7, 0, 0) }

    static var models: [any PersistentModel.Type] {
        SchemaV6.models + [TeacherConversation.self]
    }
}

/// Plan explícito y continuo de migración. Cada modelo nuevo se agrega mediante una transición
/// ligera para conservar los stores ya instalados.
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self, SchemaV6.self, SchemaV7.self]
    }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
            .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self),
            .lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self),
            .lightweight(fromVersion: SchemaV4.self, toVersion: SchemaV5.self),
            .lightweight(fromVersion: SchemaV5.self, toVersion: SchemaV6.self),
            .lightweight(fromVersion: SchemaV6.self, toVersion: SchemaV7.self)
        ]
    }
}
