import Foundation
import SwiftData

@Model
final class GuitarLesson {
    @Attribute(.unique) var id: UUID
    var date: Date
    var teacherName: String
    var topics: String
    var teacherNotes: String
    var nextObjective: String
    var nextLessonDate: Date?
    @Relationship(deleteRule: .cascade) var attachments: [LessonAttachment] = []

    init(
        id: UUID = UUID(),
        date: Date = .now,
        teacherName: String = "",
        topics: String = "",
        teacherNotes: String = "",
        nextObjective: String = "",
        nextLessonDate: Date? = nil
    ) {
        self.id = id
        self.date = date
        self.teacherName = teacherName
        self.topics = topics
        self.teacherNotes = teacherNotes
        self.nextObjective = nextObjective
        self.nextLessonDate = nextLessonDate
    }
}
