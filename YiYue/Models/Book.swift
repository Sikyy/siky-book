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
    var pinnedDate: Date?
    var seriesName: String?
    var seriesIndex: Int?
    /// 正文改动一次加一。目录百分比那张表靠它判断要不要重算——
    /// 章数和首尾章名都判不出中间某章换了内容,这个数一定变。
    var contentRevision: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \Chapter.book)
    var chapters: [Chapter] = []

    @Relationship(deleteRule: .cascade, inverse: \ReadingMark.book)
    var marks: [ReadingMark] = []

    /// Whole-book reading position, using the same formula as the reader's
    /// footer: (chapter index + position inside that chapter) / total chapters.
    /// Counting whole chapters only made the shelf badge read 0% while the
    /// reader said 17%.
    var progress: Double {
        // 读到哪儿就存下那一刻的全书位置(按字数算的那张表),
        // 书架角标读这个数,和阅读器里的进度数字是同一个。
        if let stored = ReaderProgressStore.stored(id: id) { return stored }
        guard totalChapters > 0 else { return 0 }
        let chapterFraction = min(max(lastReadPosition, 0), 1)
        let overall = (Double(lastReadChapterIndex) + chapterFraction) / Double(totalChapters)
        return min(max(overall, 0), 1)
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


/// 书架角标要显示的全书位置:阅读器算好(按章前累计字数 ÷ 全书字数)存这里,
/// 角标只读,不自己按章序号再算一套。不新增 SwiftData 字段。
enum ReaderProgressStore {
    private static let keyPrefix = "reader.overallProgress."

    static func store(_ value: Double?, for bookID: UUID) {
        let defaults = UserDefaults.standard
        let key = keyPrefix + bookID.uuidString
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    static func stored(id bookID: UUID) -> Double? {
        let defaults = UserDefaults.standard
        let key = keyPrefix + bookID.uuidString
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.double(forKey: key)
    }
}
