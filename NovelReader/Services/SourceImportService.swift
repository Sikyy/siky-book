import Foundation
import SwiftData

class SourceImportService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    func importJSON(_ json: String) throws -> Int {
        guard let data = json.data(using: .utf8) else {
            throw SourceImportError.encodingFailed
        }

        let top = try JSONSerialization.jsonObject(with: data)
        let objects: [[String: Any]]
        if let array = top as? [[String: Any]] {
            objects = array
        } else if let obj = top as? [String: Any] {
            objects = [obj]
        } else {
            throw LegadoParseError.invalidJSON
        }

        let existingURLs = try fetchExistingURLs()
        var imported = 0

        for obj in objects {
            let name = obj["bookSourceName"] as? String ?? ""
            let url = obj["bookSourceUrl"] as? String ?? ""
            let group = obj["bookSourceGroup"] as? String

            guard !url.isEmpty, !existingURLs.contains(url) else { continue }

            let individualData = try JSONSerialization.data(withJSONObject: obj)
            guard let individualJSON = String(data: individualData, encoding: .utf8) else { continue }

            let bookSource = BookSource(name: name, sourceURL: url, ruleJSON: individualJSON)
            bookSource.sourceGroup = group
            modelContext.insert(bookSource)
            imported += 1
        }
        return imported
    }

    func importFromFile(url: URL) throws -> Int {
        let data = try Data(contentsOf: url)
        guard let json = String(data: data, encoding: .utf8) else {
            throw SourceImportError.encodingFailed
        }
        return try importJSON(json)
    }

    private func fetchExistingURLs() throws -> Set<String> {
        let descriptor = FetchDescriptor<BookSource>()
        let existing = try modelContext.fetch(descriptor)
        return Set(existing.map { $0.sourceURL })
    }
}

enum SourceImportError: Error, LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "文件编码错误"
        }
    }
}
