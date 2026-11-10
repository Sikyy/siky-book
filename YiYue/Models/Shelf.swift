import Foundation
import SwiftData

/// 自定义书架栏:用户自己建、自己命名,书按 shelfID 归到某个书架。
/// 没有 shelfID 的书落在「未分组」。
@Model
final class Shelf {
    var id: UUID
    var name: String
    var createdDate: Date
    var sortIndex: Int

    init(name: String, sortIndex: Int = 0) {
        self.id = UUID()
        self.name = name
        self.createdDate = Date()
        self.sortIndex = sortIndex
    }
}

/// 书架页顶部的筛选:全部 / 未分组 / 某个书架。
enum ShelfFilter: Hashable {
    case all
    case unshelved
    case shelf(UUID)
}
