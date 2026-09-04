import XCTest
@testable import GuitarPracticeLab

final class DataBackupServiceTests: XCTestCase {

    /// Regresión: la primera versión usaba `appendingPathExtension`, que genera `default.store.wal`
    /// en vez de `default.store-wal`. El respaldo se creaba igual, sin error, pero copiaba solo el
    /// archivo principal y dejaba afuera todas las escrituras que vivían en el WAL.
    func testLosComponentesDelStoreUsanElSufijoConGuion() {
        let store = URL(fileURLWithPath: "/tmp/prueba/default.store")
        let components = DataBackupService.storeComponents(for: store)

        XCTAssertEqual(components.map(\.lastPathComponent), [
            "default.store",
            "default.store-wal",
            "default.store-shm"
        ])
    }

    func testRespaldoAtomicoCopiaLosTresArchivosYGeneraUnManifiestoValido() throws {
        let fileManager = FileManager.default
        let sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "backup-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sandbox) }

        let store = sandbox.appending(path: "default.store")
        try "base".write(to: store, atomically: true, encoding: .utf8)
        try "escrituras-pendientes".write(
            to: sandbox.appending(path: "default.store-wal"), atomically: true, encoding: .utf8
        )
        try "indice".write(
            to: sandbox.appending(path: "default.store-shm"), atomically: true, encoding: .utf8
        )

        let respaldos = sandbox.appending(path: "respaldos", directoryHint: .isDirectory)
        let entry = try DataBackupService.makeBackup(of: store, in: respaldos)

        let copiados = try fileManager.contentsOfDirectory(atPath: entry.url.path).sorted()
        XCTAssertEqual(copiados, ["default.store", "default.store-shm", "default.store-wal", "manifest.json"])
        XCTAssertEqual(DataBackupService.list(in: respaldos).map(\.id), [entry.id])
        XCTAssertNoThrow(try DataBackupService.validate(entry))

        let wal = try String(contentsOf: entry.url.appending(path: "default.store-wal"), encoding: .utf8)
        XCTAssertEqual(wal, "escrituras-pendientes")
    }

    func testValidacionRechazaUnRespaldoAlterado() throws {
        let fileManager = FileManager.default
        let sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "backup-tamper-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: sandbox) }

        let store = sandbox.appending(path: "default.store")
        try "base".write(to: store, atomically: true, encoding: .utf8)
        let entry = try DataBackupService.makeBackup(
            of: store,
            in: sandbox.appending(path: "respaldos", directoryHint: .isDirectory)
        )

        try "contenido-alterado".write(
            to: entry.url.appending(path: "default.store"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(try DataBackupService.validate(entry)) { error in
            guard case DataBackupService.BackupError.invalidBackup = error else {
                return XCTFail("Se esperaba invalidBackup y se recibió \(error)")
            }
        }
    }
}
