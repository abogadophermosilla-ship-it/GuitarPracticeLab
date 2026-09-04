import XCTest
@testable import GuitarPracticeLab

final class HermesAgentServiceTests: XCTestCase {
    func testNormalizesHostWithV1Suffix() throws {
        let url = try HermesAgentService.normalizedBaseURL(from: "http://127.0.0.1:8642/v1/")
        XCTAssertEqual(url.absoluteString, "http://127.0.0.1:8642")
    }

    func testRejectsUnencryptedRemoteHost() {
        XCTAssertThrowsError(try HermesAgentService.normalizedBaseURL(from: "http://example.com:8642")) { error in
            guard case HermesAgentError.insecureRemoteHost = error else {
                return XCTFail("Se esperaba insecureRemoteHost y llegó \(error)")
            }
        }
    }

    func testParsesRunEvents() {
        XCTAssertEqual(
            HermesAgentService.event(fromSSELine: #"data: {"event":"message.delta","delta":"Hola"}"#),
            .textDelta("Hola")
        )
        XCTAssertEqual(
            HermesAgentService.event(fromSSELine: #"data: {"event":"tool.completed","tool":"web_search","error":false}"#),
            .toolFinished(name: "web_search", failed: false)
        )
        XCTAssertEqual(
            HermesAgentService.event(fromSSELine: #"data: {"event":"run.completed","output":"Listo"}"#),
            .completed("Listo")
        )
    }

    @MainActor
    func testChatStorePersistsConversation() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hermes-chat-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let original = HermesChatMessage(role: "user", content: "¿Qué practico hoy?")
        HermesChatStore(fileURL: url).append(original)

        let reloaded = HermesChatStore(fileURL: url)
        XCTAssertEqual(reloaded.messages, [original])
    }
}
