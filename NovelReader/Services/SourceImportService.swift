import Foundation
import SwiftData

class SourceImportService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    func importJSON(_ json: String) throws -> Int {
        let sources = try LegadoSourceParser.parseBatch(json: json)
        let existingURLs = try fetchExistingURLs()
        var imported = 0

        for source in sources where !existingURLs.contains(source.url) {
            let bookSource = BookSource(name: source.name, sourceURL: source.url, ruleJSON: json)
            bookSource.sourceGroup = source.group
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
