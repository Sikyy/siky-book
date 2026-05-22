import Foundation
import SwiftData

/// A book source pinned by the user for quick access in "换源".
struct PinnedSource: Codable, Identifiable {
    var id: String { sourceId }
    let sourceName: String
    let sourceId: String   // UUID string
    let bookURL: String
    let sourceURL: String  // BookSource.sourceURL for fallback lookup
    var chapterCount: Int?
}

@Model
final class Book {
    var id: UUID
    var title: String
    var author: String
    var coverURL: String?
    var sourceType: SourceType
    var sourceId: UUID?
    var sourceBookURL: String?
    var sourceName: String?
    var alternativeSourcesJSON: String?
    var blockedSourceIdsJSON: String?
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

    /// Pinned sources for quick "换源" access. Stored as JSON in alternativeSourcesJSON.
    var pinnedSources: [PinnedSource] {
        get {
            guard let json = alternativeSourcesJSON,
                  let data = json.data(using: .utf8),
                  let list = try? JSONDecoder().decode([PinnedSource].self, from: data) else {
                return []
            }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                alternativeSourcesJSON = json
            } else {
                alternativeSourcesJSON = nil
            }
        }
    }

    /// Source IDs the user has blocked for this book.
    var blockedSourceIds: Set<String> {
        get {
            guard let json = blockedSourceIdsJSON,
                  let data = json.data(using: .utf8),
                  let list = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return Set(list)
        }
        set {
            if let data = try? JSONEncoder().encode(Array(newValue)),
               let json = String(data: data, encoding: .utf8) {
                blockedSourceIdsJSON = json
            } else {
                blockedSourceIdsJSON = nil
            }
        }
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
