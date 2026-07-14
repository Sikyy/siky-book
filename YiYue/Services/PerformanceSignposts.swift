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
