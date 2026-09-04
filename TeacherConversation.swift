import Foundation
import SwiftData

/// Contenedor liviano para separar los historiales del Profesor IA. Los mensajes conservan su
/// modelo histórico y la conversación guarda sus IDs; de este modo la migración no necesita
/// modificar cada `TeacherChatMessage` existente.
@Model
final class TeacherConversation {
    @Attribute(.unique) var id: UUID
    var title: String
    var messageIDs: [UUID]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "Nueva conversación",
        messageIDs: [UUID] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.messageIDs = messageIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isUntitled: Bool {
        title == "Nueva conversación" || title == "Conversación anterior"
    }
}

enum TeacherConversationService {
    /// Crea el contenedor inicial y adopta los mensajes anteriores a SchemaV7. Si ya existen
    /// conversaciones, cualquier mensaje huérfano se recupera en una conversación aparte.
    @MainActor
    static func ensureInitialConversation(
        conversations: [TeacherConversation],
        messages: [TeacherChatMessage],
        in context: ModelContext
    ) -> TeacherConversation {
        let assigned = Set(conversations.flatMap(\.messageIDs))
        let orphaned = messages.filter { !assigned.contains($0.id) }

        if conversations.isEmpty {
            let conversation = TeacherConversation(
                title: orphaned.isEmpty ? "Nueva conversación" : "Conversación anterior",
                messageIDs: orphaned.sorted { $0.createdAt < $1.createdAt }.map(\.id),
                createdAt: orphaned.first?.createdAt ?? .now,
                updatedAt: orphaned.last?.createdAt ?? .now
            )
            context.insert(conversation)
            return conversation
        }

        if !orphaned.isEmpty {
            let recovered = TeacherConversation(
                title: "Conversación recuperada",
                messageIDs: orphaned.sorted { $0.createdAt < $1.createdAt }.map(\.id),
                createdAt: orphaned.first?.createdAt ?? .now,
                updatedAt: orphaned.last?.createdAt ?? .now
            )
            context.insert(recovered)
            return recovered
        }

        return conversations.sorted { $0.updatedAt > $1.updatedAt }.first!
    }

    @MainActor
    static func create(in context: ModelContext, at date: Date = .now) -> TeacherConversation {
        let conversation = TeacherConversation(createdAt: date, updatedAt: date)
        context.insert(conversation)
        return conversation
    }

    static func messages(
        in conversation: TeacherConversation?,
        from allMessages: [TeacherChatMessage]
    ) -> [TeacherChatMessage] {
        guard let conversation else { return [] }
        let ids = Set(conversation.messageIDs)
        return allMessages.filter { ids.contains($0.id) }.sorted { $0.createdAt < $1.createdAt }
    }

    @MainActor
    static func append(
        _ message: TeacherChatMessage,
        to conversation: TeacherConversation,
        in context: ModelContext
    ) {
        if !conversation.messageIDs.contains(message.id) {
            conversation.messageIDs.append(message.id)
        }
        conversation.updatedAt = max(conversation.updatedAt, message.createdAt)
        context.insert(message)
    }

    static func suggestedTitle(from firstQuestion: String) -> String {
        let compact = firstQuestion
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard compact.count > 52 else { return compact.isEmpty ? "Nueva conversación" : compact }
        let end = compact.index(compact.startIndex, offsetBy: 49)
        return String(compact[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    @MainActor
    static func clear(
        _ conversation: TeacherConversation,
        messages: [TeacherChatMessage],
        in context: ModelContext
    ) {
        let ids = Set(conversation.messageIDs)
        messages.filter { ids.contains($0.id) }.forEach(context.delete)
        conversation.messageIDs = []
        conversation.updatedAt = .now
    }

    @MainActor
    static func delete(
        _ conversation: TeacherConversation,
        messages: [TeacherChatMessage],
        in context: ModelContext
    ) {
        clear(conversation, messages: messages, in: context)
        context.delete(conversation)
    }
}
