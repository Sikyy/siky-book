import Foundation
import SwiftData

@Model
final class Chapter {
    var id: UUID
    var book: Book?
    var index: Int
    var title: String
    /// Authoritative for local imports; remote chapters use this only as a legacy/failure fallback.
    var content: String?
    /// For remote chapters, indicates user-managed/protected cache (not temporary prefetch).
    var isCached: Bool
    var sourceURL: String?

    init(index: Int, title: String, content: String? = nil) {
        self.id = UUID()
        self.index = index
        self.title = title
        self.content = content
        self.isCached = content != nil
    }
}
