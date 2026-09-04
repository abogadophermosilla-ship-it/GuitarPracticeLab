import SwiftData
import XCTest
@testable import GuitarPracticeLab

final class TeacherConversationTests: XCTestCase {
    @MainActor
    func testLegacyMessagesAreAdoptedInChronologicalOrder() throws {
        let container = try ModelContainer(
            for: TeacherConversation.self, TeacherChatMessage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let later = TeacherChatMessage(role: "assistant", content: "Respuesta", createdAt: Date(timeIntervalSince1970: 20))
        let earlier = TeacherChatMessage(role: "user", content: "Pregunta", createdAt: Date(timeIntervalSince1970: 10))
        context.insert(later)
        context.insert(earlier)

        let conversation = TeacherConversationService.ensureInitialConversation(
            conversations: [],
            messages: [later, earlier],
            in: context
        )

        XCTAssertEqual(conversation.title, "Conversación anterior")
        XCTAssertEqual(conversation.messageIDs, [earlier.id, later.id])
        XCTAssertEqual(
            TeacherConversationService.messages(in: conversation, from: [later, earlier]).map(\.content),
            ["Pregunta", "Respuesta"]
        )
    }

    @MainActor
    func testMessagesStayInsideTheirOwnConversation() throws {
        let container = try ModelContainer(
            for: TeacherConversation.self, TeacherChatMessage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let technique = TeacherConversationService.create(in: context)
        technique.title = "Técnica"
        let theory = TeacherConversationService.create(in: context)
        theory.title = "Teoría"
        let first = TeacherChatMessage(role: "user", content: "Alternate picking")
        let second = TeacherChatMessage(role: "user", content: "Armonía funcional")

        TeacherConversationService.append(first, to: technique, in: context)
        TeacherConversationService.append(second, to: theory, in: context)

        XCTAssertEqual(TeacherConversationService.messages(in: technique, from: [first, second]).map(\.id), [first.id])
        XCTAssertEqual(TeacherConversationService.messages(in: theory, from: [first, second]).map(\.id), [second.id])
    }

    func testSuggestedTitleIsCompactAndNeverEmpty() {
        XCTAssertEqual(TeacherConversationService.suggestedTitle(from: "   \n "), "Nueva conversación")
        let title = TeacherConversationService.suggestedTitle(
            from: "¿Cómo puedo trabajar la sincronización entre ambas manos sin acumular tensión en el antebrazo?"
        )
        XCTAssertLessThanOrEqual(title.count, 50)
        XCTAssertTrue(title.hasSuffix("…"))
    }
}
