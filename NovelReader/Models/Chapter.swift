import Foundation
import SwiftData

@Model
final class Chapter {
    var id: UUID
    var book: Book?
    var index: Int
    var title: String
    var content: String?
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
