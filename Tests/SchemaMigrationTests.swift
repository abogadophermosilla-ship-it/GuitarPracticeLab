import XCTest
import SwiftData
@testable import GuitarPracticeLab

/// El store real del usuario nació en `SchemaV1` y hoy la app abre `SchemaV7`. Las seis etapas del
/// plan son "ligeras", lo que significa que SwiftData migra sin código propio — pero solo mientras
/// cada versión nueva se limite a agregar modelos o propiedades con valor por defecto. El día que un
/// cambio rompa esa condición, el store no abre y la app arranca en `DatabaseRecoveryView`.
///
/// Esta prueba recorre el camino completo sobre un archivo real: crea un store con `SchemaV1`,
/// escribe datos, lo cierra y lo vuelve a abrir con `SchemaV7` + `AppMigrationPlan`, verificando que
/// los datos siguen ahí. Es la única prueba del target que ejercita el arranque en sí.
final class SchemaMigrationTests: XCTestCase {

    private var storeDirectory: URL!

    override func setUpWithError() throws {
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("migracion-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let storeDirectory, FileManager.default.fileExists(atPath: storeDirectory.path) {
            try FileManager.default.removeItem(at: storeDirectory)
        }
    }

    private var storeURL: URL {
        storeDirectory.appendingPathComponent("GuitarPracticeLab.store")
    }

    func testStoreCreatedWithSchemaV1OpensWithCurrentSchema() throws {
        let sessionID = UUID()
        let songTitle = "Sweet Child O' Mine"

        // 1. Un store como el que ya existe en el disco del usuario.
        try autoreleasepool {
            let schema = Schema(versionedSchema: SchemaV1.self)
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: storeURL)]
            )
            let context = ModelContext(container)
            context.insert(PracticeSession(
                id: sessionID,
                durationMinutes: 45,
                exerciseTitle: "Alternate picking",
                notes: "sesión previa a la migración"
            ))
            context.insert(SkillTopic(name: "Bending", domain: .technique, level: .intermediate))
            context.insert(Song(title: songTitle, artist: "Guns N' Roses"))
            try context.save()
        }

        // 2. El arranque real de la app: esquema actual + plan de migración.
        try autoreleasepool {
            let schema = Schema(versionedSchema: SchemaV7.self)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: AppMigrationPlan.self,
                configurations: [ModelConfiguration(schema: schema, url: storeURL)]
            )
            let context = ModelContext(container)

            let sessions = try context.fetch(FetchDescriptor<PracticeSession>())
            XCTAssertEqual(sessions.count, 1, "La migración no debe perder sesiones")
            XCTAssertEqual(sessions.first?.id, sessionID)
            XCTAssertEqual(sessions.first?.durationMinutes, 45)
            XCTAssertEqual(sessions.first?.exerciseTitle, "Alternate picking")

            let skills = try context.fetch(FetchDescriptor<SkillTopic>())
            XCTAssertEqual(skills.map(\.name), ["Bending"])

            let songs = try context.fetch(FetchDescriptor<Song>())
            XCTAssertEqual(songs.map(\.title), [songTitle])

            // Los modelos que llegaron después de V1 tienen que existir y estar vacíos, no fallar.
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<SkillEvidence>()), 0)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<FretboardNoteProgress>()), 0)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<SongDifficultyRecord>()), 0)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<PracticeCoachStateRecord>()), 0)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<TeacherConversation>()), 0)
        }
    }

    /// Reabrir con el mismo esquema actual no debe disparar ninguna etapa ni alterar los datos.
    func testReopeningCurrentSchemaIsStable() throws {
        let schema = Schema(versionedSchema: SchemaV7.self)

        try autoreleasepool {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: AppMigrationPlan.self,
                configurations: [ModelConfiguration(schema: schema, url: storeURL)]
            )
            let context = ModelContext(container)
            context.insert(SkillTopic(name: "Vibrato", domain: .technique, level: .basic))
            try context.save()
        }

        try autoreleasepool {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: AppMigrationPlan.self,
                configurations: [ModelConfiguration(schema: schema, url: storeURL)]
            )
            let context = ModelContext(container)
            XCTAssertEqual(try context.fetch(FetchDescriptor<SkillTopic>()).map(\.name), ["Vibrato"])
        }
    }

    /// Las etapas declaradas tienen que cubrir la cadena completa sin saltos: si alguien agrega
    /// `SchemaV7` a `schemas` y olvida su `MigrationStage`, esto lo detecta antes que un usuario.
    func testMigrationPlanCoversEveryDeclaredSchema() {
        XCTAssertEqual(
            AppMigrationPlan.stages.count,
            AppMigrationPlan.schemas.count - 1,
            "Falta una etapa de migración para el último esquema declarado"
        )
    }
}

final class BandLibraryTests: XCTestCase {
    func testExistingBandIsReusedAndMarkedAsFavorite() throws {
        let container = try ModelContainer(
            for: Band.self, Song.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let existing = Band(name: "Mötley   Crüe", isFavorite: false)
        context.insert(existing)

        let resolved = BandLibrary.findOrCreateFavorite(
            named: "  motley crue  ",
            among: [existing],
            in: context
        )

        XCTAssertTrue(resolved === existing)
        XCTAssertTrue(existing.isFavorite)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Band>()), 1)
    }

    func testNewArtistCreatesFavoriteBandWithTrimmedName() throws {
        let container = try ModelContainer(
            for: Band.self, Song.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let resolved = BandLibrary.findOrCreateFavorite(
            named: "  Kaos Etíliko  ",
            among: [],
            in: context
        )

        XCTAssertEqual(resolved?.name, "Kaos Etíliko")
        XCTAssertEqual(resolved?.isFavorite, true)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Band>()), 1)
    }
}
