import Foundation
import SwiftData

/// A saved passage in a book. `note == nil` is a plain bookmark; a note is the
/// same thing with the reader's own comment attached.
@Model
final class ReadingMark {
    var id: UUID
    var book: Book?
    /// Chapter the passage belongs to.
    var chapterIndex: Int
    /// Paragraph inside that chapter, which is what "jump back" targets.
    var paragraphIndex: Int
    /// The saved passage itself; long paragraphs are truncated to what the list shows.
    var excerpt: String
    var note: String?
    var createdAt: Date

    var isNote: Bool {
        !(note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        chapterIndex: Int,
        paragraphIndex: Int,
        excerpt: String,
        note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.chapterIndex = chapterIndex
        self.paragraphIndex = paragraphIndex
        self.excerpt = excerpt
        self.note = note
        self.createdAt = createdAt
    }
}
