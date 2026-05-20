import Foundation
import SwiftData

@Model
final class BookSource {
    var id: UUID
    var name: String
    var sourceURL: String
    var sourceGroup: String?
    var enabled: Bool
    var ruleJSON: String
    var lastUpdateDate: Date
    var qualityScore: Double?
    var lastTestDate: Date?
    var avgResponseTime: Double?
    var contentValidRate: Double?
    var encodingScore: Double?
    var catalogSize: Int?
    var isQualityVerified: Bool

    init(name: String, sourceURL: String, ruleJSON: String) {
        self.id = UUID()
        self.name = name
        self.sourceURL = sourceURL
        self.ruleJSON = ruleJSON
        self.enabled = true
        self.lastUpdateDate = Date()
        self.isQualityVerified = false
    }
}
