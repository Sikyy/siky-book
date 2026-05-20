import Foundation
import SwiftData

@Model
final class Book {
    var id: UUID
    var title: String
    var author: String
    var coverURL: String?
    var sourceType: SourceType
    var sourceId: UUID?
    var sourceBookURL: String?
    var readingStatus: ReadingStatus
    var lastReadChapterIndex: Int
    var lastReadPosition: Double
    var totalChapters: Int
    var addedDate: Date
    var lastReadDate: Date?
    var seriesName: String?
    var seriesIndex: Int?

    @Relationship(deleteRule: .cascade, inverse: \Chapter.book)
    var chapters: [Chapter] = []

    var progress: Double {
        guard totalChapters > 0 else { return 0 }
        return Double(lastReadChapterIndex) / Double(totalChapters)
    }

    init(
        title: String,
        author: String,
        sourceType: SourceType,
        totalChapters: Int = 0
    ) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.sourceType = sourceType
        self.readingStatus = .unread
        self.lastReadChapterIndex = 0
        self.lastReadPosition = 0
        self.totalChapters = totalChapters
        self.addedDate = Date()
    }
}
