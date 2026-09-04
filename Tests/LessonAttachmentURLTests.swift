import XCTest
import SwiftData
@testable import GuitarPracticeLab

final class LessonAttachmentURLTests: XCTestCase {
    func testYouTubeLinksAreNormalizedWithOrWithoutScheme() {
        XCTAssertEqual(
            LessonAttachment.normalizedExternalURL(from: "https://youtu.be/video123?si=share")?.absoluteString,
            "https://youtu.be/video123?si=share"
        )
        XCTAssertEqual(
            LessonAttachment.normalizedExternalURL(from: "youtube.com/watch?v=video123")?.absoluteString,
            "https://youtube.com/watch?v=video123"
        )
    }

    func testUnsupportedOrIncompleteURLsAreRejected() {
        XCTAssertNil(LessonAttachment.normalizedExternalURL(from: ""))
        XCTAssertNil(LessonAttachment.normalizedExternalURL(from: "https://"))
        XCTAssertNil(LessonAttachment.normalizedExternalURL(from: "ftp://youtube.com/video123"))
    }

    func testYouTubeHostsAreRecognizedWithoutAcceptingLookalikes() throws {
        XCTAssertTrue(LessonAttachment.isYouTubeURL(try XCTUnwrap(URL(string: "https://music.youtube.com/watch?v=video123"))))
        XCTAssertTrue(LessonAttachment.isYouTubeURL(try XCTUnwrap(URL(string: "https://youtu.be/video123"))))
        XCTAssertFalse(LessonAttachment.isYouTubeURL(try XCTUnwrap(URL(string: "https://notyoutube.com/video123"))))
    }

    func testExternalLinkPersistsAsLessonAttachment() throws {
        let container = try ModelContainer(
            for: GuitarLesson.self, LessonAttachment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let attachment = LessonAttachment(
            kind: .video,
            externalURLString: "https://youtu.be/video123"
        )
        let lesson = GuitarLesson(teacherNotes: "Repasar la clase")

        context.insert(attachment)
        lesson.attachments = [attachment]
        context.insert(lesson)
        try context.save()

        let savedLesson = try XCTUnwrap(context.fetch(FetchDescriptor<GuitarLesson>()).first)
        XCTAssertEqual(savedLesson.attachments.count, 1)
        XCTAssertEqual(savedLesson.attachments.first?.kind, .video)
        XCTAssertEqual(savedLesson.attachments.first?.externalURLString, "https://youtu.be/video123")
    }
}
