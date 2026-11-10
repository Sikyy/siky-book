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

    func importEPUB(from url: URL) throws -> Book {
        let data = try Data(contentsOf: url)
        let fallback = url.deletingPathExtension().lastPathComponent
        let parsed = try EPUBParser.parse(data: data, fallbackTitle: fallback)

        let book = Book(
            title: parsed.title,
            author: parsed.author,
            sourceType: .localFile,
            totalChapters: parsed.chapters.count
        )
        if let cover = parsed.coverData, let dir = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("EPUBCovers", isDirectory: true) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("\(book.id.uuidString).img")
            if (try? cover.write(to: file)) != nil { book.coverURL = file.absoluteString }
        }
        modelContext.insert(book)
        for (index, raw) in parsed.chapters.enumerated() {
            let chapter = Chapter(index: index, title: raw.title, content: raw.text)
            chapter.book = book
            modelContext.insert(chapter)
        }
        try modelContext.save()
        return book
    }
}
