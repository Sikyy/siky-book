import Testing
import SwiftData
@testable import YiYue

@Suite("SourceImport Tests")
struct SourceImportTests {

    @Test @MainActor func importSingleSource() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, BookSource.self, configurations: config)
        let context = container.mainContext

        let json = """
        {
            "bookSourceName": "测试源",
            "bookSourceUrl": "https://test.com",
            "bookSourceGroup": "常用",
            "searchUrl": "/search?q={{key}}",
            "ruleSearch": { "bookList": ".item", "name": ".title@text", "author": ".author@text", "bookUrl": "a@href" },
            "ruleToc": { "chapterList": "#list a", "chapterName": "@text", "chapterUrl": "@href" },
            "ruleContent": { "content": "#content@text" }
        }
        """
        let service = SourceImportService(modelContext: context)
        let count = try service.importJSON(json)
        #expect(count == 1)

        let sources = try context.fetch(FetchDescriptor<BookSource>())
        #expect(sources.count == 1)
        #expect(sources[0].name == "测试源")
        #expect(sources[0].sourceURL == "https://test.com")
        #expect(sources[0].enabled == true)
    }

    @Test @MainActor func importBatchSources() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, BookSource.self, configurations: config)
        let context = container.mainContext

        let json = """
        [
            { "bookSourceName": "源A", "bookSourceUrl": "https://a.com", "ruleSearch": {}, "ruleToc": {}, "ruleContent": {} },
            { "bookSourceName": "源B", "bookSourceUrl": "https://b.com", "ruleSearch": {}, "ruleToc": {}, "ruleContent": {} }
        ]
        """
        let service = SourceImportService(modelContext: context)
        let count = try service.importJSON(json)
        #expect(count == 2)
    }

    @Test @MainActor func importStoresIndividualJSON() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, BookSource.self, configurations: config)
        let context = container.mainContext

        let json = """
        [
            { "bookSourceName": "源A", "bookSourceUrl": "https://a.com", "searchUrl": "/s?q={{key}}", "ruleSearch": {}, "ruleToc": {}, "ruleContent": {} },
            { "bookSourceName": "源B", "bookSourceUrl": "https://b.com", "ruleSearch": {}, "ruleToc": {}, "ruleContent": {} }
        ]
        """
        let service = SourceImportService(modelContext: context)
        _ = try service.importJSON(json)

        let sources = try context.fetch(FetchDescriptor<BookSource>())
        for source in sources {
            let parsed = try LegadoSourceParser.parse(json: source.ruleJSON)
            #expect(parsed.name == source.name)
            #expect(parsed.url == source.sourceURL)
        }
    }

    @Test @MainActor func importSkipsDuplicateURL() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, BookSource.self, configurations: config)
        let context = container.mainContext

        let json = """
        { "bookSourceName": "源A", "bookSourceUrl": "https://a.com", "ruleSearch": {}, "ruleToc": {}, "ruleContent": {} }
        """
        let service = SourceImportService(modelContext: context)
        _ = try service.importJSON(json)
        let count = try service.importJSON(json)
        #expect(count == 0)

        let sources = try context.fetch(FetchDescriptor<BookSource>())
        #expect(sources.count == 1)
    }
}
