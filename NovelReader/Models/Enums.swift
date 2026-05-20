import Foundation

enum ReadingStatus: String, Codable {
    case unread
    case reading
    case finished
}

enum SourceType: String, Codable {
    case bookSource
    case localFile
}
