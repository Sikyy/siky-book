import Foundation
import os

/// Coarse-grained Instruments intervals for performance-sensitive pipelines.
/// Metadata must remain bounded and must never include book text, titles, URLs, or source names.
enum PerformanceSignposts {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.mistyislet.yiyue"
    // Instruments' Points of Interest instrument only records this reserved category.
    private static let pointsOfInterestCategory = "PointsOfInterest"

    static let reader = OSSignposter(subsystem: subsystem, category: pointsOfInterestCategory)
    static let search = OSSignposter(subsystem: subsystem, category: pointsOfInterestCategory)
    static let cache = OSSignposter(subsystem: subsystem, category: pointsOfInterestCategory)
}

/// 一次开书的「尾巴」:首屏出来以后才跑完的分页落版、邻章准备、远处预取、
/// 盘存和章表扫描。几件事会重叠,所以用计数,不用布尔。
///
/// 菜单预热只认这个状态,不认「上一帧快不快」的历史:尾巴是一段一段跑的,
/// 段与段之间主线程会空出 0.4 秒,按历史判断正好从缝里钻进去。
/// 预热晚几秒没人看得出来,但它不能在尾巴没干完时抢主线程。
@MainActor
enum OpenTail {
    private static var openHeld = false
    private static var tailCount = 0

    static var isRunning: Bool { openHeld || tailCount > 0 }

    /// 点书那一刻置上;首屏出来 1.5 秒后由阅读页放下,阅读页先退出也放下。
    static func beginOpen() { openHeld = true }
    static func endOpen() { openHeld = false }

    /// 尾巴任务开始/结束各调一次,必须配对。
    static func begin() { tailCount += 1 }
    static func end() { tailCount = max(0, tailCount - 1) }
}
