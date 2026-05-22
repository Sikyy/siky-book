import Foundation
import SwiftData

class ImportService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func importTXT(from url: URL, title: String? = nil) throws -> Book {
        let data = try Data(contentsOf: url)
        let text = EncodingDetector.decodeToString(data)
        let rawChapters = ChapterSplitter.split(text)

        let bookTitle = title ?? url.deletingPathExtension().lastPathComponent
        let book = Book(
            title: bookTitle,
            author: "未知",
            sourceType: .localFile,
            totalChapters: rawChapters.count
        )
        modelContext.insert(book)

        for (index, raw) in rawChapters.enumerated() {
            let chapter = Chapter(index: index, title: raw.title, content: raw.content)
            chapter.book = book
            modelContext.insert(chapter)
        }

        try modelContext.save()
        return book
    }
}
