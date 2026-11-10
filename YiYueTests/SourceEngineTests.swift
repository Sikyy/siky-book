import Foundation
import SwiftData
import Testing
@testable import YiYue

@Suite("SourceEngine Tests")
struct SourceEngineTests {

    @Test func buildSearchRequest() {
        let source = LegadoSource(
            name: "Test",
            url: "https://www.example.com",
            group: nil,
            header: nil,
            searchURL: "/search?q={{key}}&page={{page}}",
            searchRule: nil,
            bookInfoRule: nil,
            tocRule: nil,
            contentRule: nil
        )
        let engine = SourceEngine()
        let req = engine.buildSearchRequest(source: source, keyword: "斗破苍穹", page: 1)
        #expect(req?.url == "https://www.example.com/search?q=%E6%96%97%E7%A0%B4%E8%8B%8D%E7%A9%B9&page=1")
        #expect(req?.method == "GET")
        #expect(req?.body == nil)
    }

    @Test func buildSearchRequestWithAbsolute() {
        let source = LegadoSource(
            name: "Test",
            url: "https://www.example.com",
            group: nil,
            header: nil,
            searchURL: "https://search.example.com/s?key={{key}}",
            searchRule: nil,
            bookInfoRule: nil,
            tocRule: nil,
            contentRule: nil
        )
        let engine = SourceEngine()
        let req = engine.buildSearchRequest(source: source, keyword: "test", page: 1)
        #expect(req?.url == "https://search.example.com/s?key=test")
    }

    @Test func buildSearchRequestWithPost() {
        let source = LegadoSource(
            name: "Test",
            url: "https://www.example.com",
            group: nil,
            header: nil,
            searchURL: #"/search,{"method":"POST","body":"keyword={{key}}&page={{page}}"}"#,
            searchRule: nil,
            bookInfoRule: nil,
            tocRule: nil,
            contentRule: nil
        )
        let engine = SourceEngine()
        let req = engine.buildSearchRequest(source: source, keyword: "test", page: 2)
        #expect(req?.url == "https://www.example.com/search")
        #expect(req?.method == "POST")
        #expect(req?.body == "keyword=test&page=2")
    }

    @Test func buildSearchRequestWithJS() {
        let source = LegadoSource(
            name: "Test",
            url: "https://www.example.com",
            group: nil,
            header: nil,
            searchURL: #"@js:var url = baseUrl + "/so/" + key + ".html";url"#,
            searchRule: nil,
            bookInfoRule: nil,
            tocRule: nil,
            contentRule: nil
        )
        let engine = SourceEngine()
        let req = engine.buildSearchRequest(source: source, keyword: "test", page: 1)
        #expect(req != nil)
        #expect(req?.url == "https://www.example.com/so/test.html")
    }

    @Test func parseSearchResults() throws {
        let html = """
        <html><body>
        <div class="result">
            <div class="item">
                <a href="/book/1" class="name">斗破苍穹</a>
                <span class="author">天蚕土豆</span>
                <img src="/cover/1.jpg">
            </div>
            <div class="item">
                <a href="/book/2" class="name">武动乾坤</a>
                <span class="author">天蚕土豆</span>
                <img src="/cover/2.jpg">
            </div>
        </div>
        </body></html>
        """
        let searchRule = LegadoSource.SearchRule(
            bookList: ".item",
            name: ".name@text",
            author: ".author@text",
            bookUrl: ".name@href",
            coverUrl: "img@src",
            kind: nil,
            intro: nil
        )
        let engine = SourceEngine()
        let results = try engine.parseSearchResults(response: html, rule: searchRule, baseURL: "https://example.com")
        #expect(results.count == 2)
        #expect(results[0].title == "斗破苍穹")
        #expect(results[0].author == "天蚕土豆")
        #expect(results[0].bookURL == "/book/1")
        #expect(results[1].title == "武动乾坤")
    }

    @Test func parseChapterList() throws {
        let html = """
        <html><body>
        <div id="list">
            <dd><a href="/chapter/1">第一章 开始</a></dd>
            <dd><a href="/chapter/2">第二章 冒险</a></dd>
            <dd><a href="/chapter/3">第三章 结局</a></dd>
        </div>
        </body></html>
        """
        let tocRule = LegadoSource.TocRule(
            chapterList: "#list dd a",
            chapterName: "a@text",
            chapterUrl: "a@href",
            nextTocUrl: nil
        )
        let engine = SourceEngine()
        let chapters = try engine.parseChapterList(response: html, rule: tocRule, baseURL: "https://example.com")
        #expect(chapters.count == 3)
        #expect(chapters[0].title == "第一章 开始")
        #expect(chapters[0].url == "/chapter/1")
        #expect(chapters[2].title == "第三章 结局")
    }

    @Test func parseContent() throws {
        let html = """
        <html><body>
        <div id="content">
            <p>这是第一段。</p>
            <p>这是第二段。</p>
        </div>
        </body></html>
        """
        let contentRule = LegadoSource.ContentRule(
            content: "#content@html",
            replaceRegex: nil,
            nextContentUrl: nil
        )
        let engine = SourceEngine()
        let content = try engine.parseContent(response: html, rule: contentRule, baseURL: "https://example.com")
        #expect(content?.contains("这是第一段") == true)
        #expect(content?.contains("这是第二段") == true)
        #expect(content?.contains("<p>") == false)
    }

    @Test func parseContentJoinsMultipleTextNodes() throws {
        let html = """
        <html><body>
        <div id="content">
            <p>这是第一段。</p>
            <p>这是第二段。</p>
            <p>这是第三段。</p>
        </div>
        </body></html>
        """
        let contentRule = LegadoSource.ContentRule(
            content: "#content p@text",
            replaceRegex: nil,
            nextContentUrl: nil
        )
        let engine = SourceEngine()
        let content = try engine.parseContent(response: html, rule: contentRule, baseURL: "https://example.com/book/1.html")
        #expect(content == "这是第一段。\n这是第二段。\n这是第三段。")
    }

    @Test func parseContentAppliesReplaceRegex() throws {
        let html = """
        <html><body>
        <div id="content">
            <p>这是正文。</p>
            <p>广告A</p>
        </div>
        </body></html>
        """
        let contentRule = LegadoSource.ContentRule(
            content: "#content p@text",
            replaceRegex: "广告A",
            nextContentUrl: nil
        )
        let engine = SourceEngine()
        let content = try engine.parseContent(response: html, rule: contentRule, baseURL: "https://example.com/book/1.html")
        #expect(content == "这是正文。")
    }

    @Test func invalidContentDetectsAuthAndCaptchaPages() {
        #expect(SourceEngine.contentValidationError("请登录后继续阅读本章内容") == "章节需要登录")
        #expect(SourceEngine.contentValidationError("请完成验证码验证后继续访问") == "章节需要验证码验证")
        #expect(SourceEngine.contentValidationError("VIP章节，请开通会员后阅读") == "章节需要付费或会员权限")
        let legitimateChapter = String(repeating: "他在404号房回忆旧事，谈到验证码与login这个词。", count: 30)
        #expect(SourceEngine.contentValidationError(legitimateChapter) == nil)
    }

    @Test func bookCacheSummaryReconcilesDiskAndValidLegacyContent() {
        let diskOnlyID = UUID()
        let legacyOnlyID = UUID()
        let diskAndLegacyID = UUID()
        let invalidLegacyID = UUID()
        let uncachedID = UUID()
        let noSourceID = UUID()
        let unknownStoredID = UUID()

        func snapshot(
            id: UUID,
            sourceURL: String?,
            isCached: Bool,
            content: String?
        ) -> BookCacheChapterSnapshot {
            BookCacheChapterSnapshot(
                id: id,
                hasSourceURL: sourceURL != nil,
                hasValidLegacyCache: isCached && SourceEngine.isValidContent(content)
            )
        }

        let result = BookCacheSummaryReconciler.reconcile(
            chapters: [
                snapshot(
                    id: diskOnlyID,
                    sourceURL: "https://example.com/chapter/disk",
                    isCached: false,
                    content: nil
                ),
                snapshot(
                    id: legacyOnlyID,
                    sourceURL: "https://example.com/chapter/legacy",
                    isCached: true,
                    content: "这是仍保存在数据库里的有效正文。"
                ),
                snapshot(
                    id: diskAndLegacyID,
                    sourceURL: "https://example.com/chapter/both",
                    isCached: true,
                    content: "同时存在于磁盘与数据库的有效正文。"
                ),
                snapshot(
                    id: invalidLegacyID,
                    sourceURL: "https://example.com/chapter/invalid",
                    isCached: true,
                    content: "请登录后继续阅读本章内容"
                ),
                snapshot(
                    id: uncachedID,
                    sourceURL: "https://example.com/chapter/uncached",
                    isCached: false,
                    content: "即使正文有效，isCached 为 false 时也不是 legacy 缓存。"
                ),
                snapshot(
                    id: noSourceID,
                    sourceURL: nil,
                    isCached: true,
                    content: "无来源章节不应计入缓存统计。"
                )
            ],
            storedChapterIDs: [diskOnlyID, diskAndLegacyID, noSourceID, unknownStoredID]
        )

        let expectedCachedIDs: Set<UUID> = [diskOnlyID, legacyOnlyID, diskAndLegacyID]
        #expect(result.cachedChapterIDs == expectedCachedIDs)
        #expect(result.summary == BookCacheSummary(cached: 3, uncached: 2))
        #expect(result.summary.cached + result.summary.uncached == 5)
        #expect(!result.cachedChapterIDs.contains(invalidLegacyID))
        #expect(!result.cachedChapterIDs.contains(noSourceID))
        #expect(!result.cachedChapterIDs.contains(unknownStoredID))
    }

    @Test func chapterCacheMetadataWorkerPersistsReconciledState() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Book.self, Chapter.self, BookSource.self,
            configurations: configuration
        )
        let setupContext = ModelContext(container)
        setupContext.autosaveEnabled = false

        let book = Book(
            title: "缓存元数据后台合并测试",
            author: "Test",
            sourceType: .bookSource,
            totalChapters: 6
        )
        setupContext.insert(book)

        let storedChapter = Chapter(index: 0, title: "磁盘缓存")
        storedChapter.sourceURL = "https://example.com/chapter/stored"
        let legacyChapter = Chapter(index: 1, title: "Legacy", content: "数据库中保留的有效正文。")
        legacyChapter.sourceURL = "https://example.com/chapter/legacy"
        let invalidLegacyChapter = Chapter(
            index: 2,
            title: "无效 Legacy",
            content: "请登录后继续阅读本章内容"
        )
        invalidLegacyChapter.sourceURL = "https://example.com/chapter/invalid"
        let fallbackChapter = Chapter(index: 3, title: "Fallback")
        fallbackChapter.sourceURL = "https://example.com/chapter/fallback"
        let uncachedChapter = Chapter(index: 4, title: "未缓存")
        uncachedChapter.sourceURL = "https://example.com/chapter/uncached"
        let noSourceChapter = Chapter(index: 5, title: "无来源")

        let chapters = [
            storedChapter,
            legacyChapter,
            invalidLegacyChapter,
            fallbackChapter,
            uncachedChapter,
            noSourceChapter
        ]
        for chapter in chapters {
            chapter.book = book
            setupContext.insert(chapter)
        }
        try setupContext.save()

        let bookID = book.id
        let storedChapterID = storedChapter.id
        let legacyChapterID = legacyChapter.id
        let invalidLegacyChapterID = invalidLegacyChapter.id
        let fallbackChapterID = fallbackChapter.id
        let uncachedChapterID = uncachedChapter.id
        let noSourceChapterID = noSourceChapter.id
        let fallbackContent = "网络下载已成功，磁盘写入结果尚未回传时的回退正文。"

        let result = try await Task.detached {
            try ChapterCacheMetadataWorker.reconcile(
                bookID: bookID,
                storedChapterIDs: [storedChapterID, noSourceChapterID],
                fallbackContents: [fallbackChapterID: fallbackContent],
                in: container
            )
        }.value

        let expectedCachedIDs: Set<UUID> = [
            storedChapterID,
            legacyChapterID,
            fallbackChapterID
        ]
        #expect(result.cachedChapterIDs == expectedCachedIDs)
        #expect(result.summary == BookCacheSummary(cached: 3, uncached: 2))

        let verificationContext = ModelContext(container)
        let persistedChapters = try verificationContext.fetch(FetchDescriptor<Chapter>())
        let persistedByID = Dictionary(
            uniqueKeysWithValues: persistedChapters.map { ($0.id, $0) }
        )

        #expect(persistedByID[storedChapterID]?.isCached == true)
        #expect(persistedByID[storedChapterID]?.content == nil)
        #expect(persistedByID[legacyChapterID]?.isCached == true)
        #expect(persistedByID[legacyChapterID]?.content == "数据库中保留的有效正文。")
        #expect(persistedByID[invalidLegacyChapterID]?.isCached == false)
        #expect(persistedByID[invalidLegacyChapterID]?.content == "请登录后继续阅读本章内容")
        #expect(persistedByID[fallbackChapterID]?.isCached == true)
        #expect(persistedByID[fallbackChapterID]?.content == fallbackContent)
        #expect(persistedByID[uncachedChapterID]?.isCached == false)
        #expect(persistedByID[noSourceChapterID]?.isCached == false)
    }

    @Test func chapterCacheMetadataWorkerClearsRemoteCacheWithoutTouchingLocalContent() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Book.self, Chapter.self, BookSource.self,
            configurations: configuration
        )
        let setupContext = ModelContext(container)
        setupContext.autosaveEnabled = false

        let book = Book(
            title: "缓存元数据清理测试",
            author: "Test",
            sourceType: .bookSource,
            totalChapters: 2
        )
        setupContext.insert(book)

        let remote = Chapter(index: 0, title: "远程章节", content: "需要被清理的回退正文")
        remote.sourceURL = "https://example.com/chapter/remote"
        remote.book = book
        setupContext.insert(remote)

        let local = Chapter(index: 1, title: "本地章节", content: "本地导入正文")
        local.book = book
        setupContext.insert(local)
        try setupContext.save()

        let bookID = book.id
        let remoteID = remote.id
        let localID = local.id
        let summaries = try await Task.detached {
            try ChapterCacheMetadataWorker.clear(bookIDs: [bookID], in: container)
        }.value

        let verificationContext = ModelContext(container)
        let chapters = try verificationContext.fetch(FetchDescriptor<Chapter>())
        let chaptersByID = Dictionary(uniqueKeysWithValues: chapters.map { ($0.id, $0) })
        #expect(chaptersByID[remoteID]?.content == nil)
        #expect(chaptersByID[remoteID]?.isCached == false)
        #expect(chaptersByID[localID]?.content == "本地导入正文")
        #expect(chaptersByID[localID]?.isCached == true)
        #expect(summaries[bookID] == BookCacheSummary(cached: 0, uncached: 1))
    }

    @Test func chapterCacheJobWorkerUsesFreshDiskSnapshotAndBuildsSortedPrefix() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Book.self, Chapter.self, BookSource.self,
            configurations: configuration
        )
        let setupContext = ModelContext(container)
        setupContext.autosaveEnabled = false

        let book = Book(
            title: "缓存队列后台构建测试",
            author: "Test",
            sourceType: .bookSource,
            totalChapters: 6
        )
        setupContext.insert(book)

        let invalidLegacyChapter = Chapter(
            index: 0,
            title: "无效 Legacy",
            content: "请登录后继续阅读本章内容"
        )
        invalidLegacyChapter.sourceURL = "https://example.com/chapter/0"
        let storedChapter = Chapter(index: 1, title: "磁盘已缓存")
        storedChapter.sourceURL = "https://example.com/chapter/1"
        let uncachedMiddleChapter = Chapter(index: 2, title: "待缓存二")
        uncachedMiddleChapter.sourceURL = "https://example.com/chapter/2"
        let validLegacyChapter = Chapter(
            index: 3,
            title: "有效 Legacy",
            content: "数据库中保留的有效正文。"
        )
        validLegacyChapter.sourceURL = "https://example.com/chapter/3"
        let uncachedLastChapter = Chapter(index: 4, title: "待缓存四")
        uncachedLastChapter.sourceURL = "https://example.com/chapter/4"
        let noSourceChapter = Chapter(index: 5, title: "无来源章节")

        // Insert deliberately out of chapter order. makeJobs must derive its
        // queue from persisted indexes rather than relationship array order.
        let chapters = [
            noSourceChapter,
            uncachedLastChapter,
            storedChapter,
            invalidLegacyChapter,
            validLegacyChapter,
            uncachedMiddleChapter
        ]
        for chapter in chapters {
            chapter.book = book
            setupContext.insert(chapter)
        }
        try setupContext.save()

        #expect(storedChapter.content == nil)
        #expect(storedChapter.isCached == false)
        #expect(validLegacyChapter.isCached)
        #expect(invalidLegacyChapter.isCached)
        #expect(!SourceEngine.isValidContent(invalidLegacyChapter.content))

        let bookID = book.id
        let storedChapterID = storedChapter.id
        let expectedChapterIDs = [
            invalidLegacyChapter.id,
            uncachedMiddleChapter.id,
            uncachedLastChapter.id
        ]
        let expectedSourceURLs = [
            "https://example.com/chapter/0",
            "https://example.com/chapter/2",
            "https://example.com/chapter/4"
        ]
        let expectedNextURLs: [String?] = [
            "https://example.com/chapter/1",
            "https://example.com/chapter/3",
            nil
        ]

        let allJobs = try await Task.detached {
            try ChapterCacheJobWorker.makeJobs(
                bookID: bookID,
                storedChapterIDs: [storedChapterID],
                count: nil,
                in: container
            )
        }.value
        let prefixJobs = try await Task.detached {
            try ChapterCacheJobWorker.makeJobs(
                bookID: bookID,
                storedChapterIDs: [storedChapterID],
                count: 2,
                in: container
            )
        }.value
        let emptyPrefix = try await Task.detached {
            try ChapterCacheJobWorker.makeJobs(
                bookID: bookID,
                storedChapterIDs: [storedChapterID],
                count: 0,
                in: container
            )
        }.value

        #expect(allJobs.map(\.bookID).allSatisfy { $0 == bookID })
        #expect(allJobs.map(\.chapterID) == expectedChapterIDs)
        #expect(allJobs.map(\.sourceURL) == expectedSourceURLs)
        #expect(allJobs.map(\.nextChapterURL) == expectedNextURLs)
        #expect(prefixJobs.map(\.chapterID) == Array(expectedChapterIDs.prefix(2)))
        #expect(prefixJobs.map(\.nextChapterURL) == Array(expectedNextURLs.prefix(2)))
        #expect(emptyPrefix.isEmpty)
        #expect(!allJobs.map(\.chapterID).contains(storedChapterID))
        #expect(!allJobs.map(\.chapterID).contains(validLegacyChapter.id))
        #expect(!allJobs.map(\.chapterID).contains(noSourceChapter.id))
    }

    @Test func parseContentStripsScripts() throws {
        let html = """
        <html><body>
        <div id="cont-body" class="cont-body">
            <script>play("code-2");</script>
            <p>Boy in the Thorns</p>
            <p>几十年过去了，他已经成长为领袖。</p>
            <p>柳生十兵卫纵身跃起。</p>
        </div>
        </body></html>
        """
        let contentRule = LegadoSource.ContentRule(
            content: "id.cont-body.0@html",
            replaceRegex: nil,
            nextContentUrl: nil
        )
        let engine = SourceEngine()
        let content = try engine.parseContent(response: html, rule: contentRule, baseURL: "https://example.com")
        #expect(content != nil)
        #expect(content?.contains("script") == false)
        #expect(content?.contains("<p>") == false)
        #expect(content?.contains("Boy in the Thorns") == true)
        #expect(content?.contains("几十年过去了") == true)
        let lines = content!.components(separatedBy: "\n")
        #expect(lines.count >= 3)
    }

    @Test func resolveRelativeURL() {
        let engine = SourceEngine()
        #expect(engine.resolveURL("/book/1", base: "https://example.com") == "https://example.com/book/1")
        #expect(engine.resolveURL("https://other.com/book", base: "https://example.com") == "https://other.com/book")
        #expect(engine.resolveURL("//cdn.example.com/img.jpg", base: "https://example.com") == "https://cdn.example.com/img.jpg")
        #expect(engine.resolveURL("2.html", base: "https://example.com/book/index.html") == "https://example.com/book/2.html")
    }

    @Test func chapterContentStoreRoundTripAndRemoval() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("YiYueChapterContentStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ChapterContentStore(rootDirectory: root)
        let bookID = UUID()
        let chapterID = UUID()
        let orphanBookID = UUID()
        let orphanChapterID = UUID()
        let content = "第一段。\n第二段🙂"

        try await store.store(content, bookID: bookID, chapterID: chapterID, retention: .userManaged)
        try await store.store(
            "孤立缓存",
            bookID: orphanBookID,
            chapterID: orphanChapterID,
            retention: .automatic
        )
        let loaded = await store.load(bookID: bookID, chapterID: chapterID)
        #expect(loaded?.content == content)
        #expect(loaded?.retention == .userManaged)
        #expect(await store.contains(bookID: bookID, chapterID: chapterID))
        #expect(try await store.storedChapterIDs(bookID: bookID, retention: .userManaged) == [chapterID])

        try await store.removeOrphanedBooks(validBookIDs: [bookID])
        #expect(await store.contains(bookID: bookID, chapterID: chapterID))
        #expect(await !store.contains(bookID: orphanBookID, chapterID: orphanChapterID))

        try await store.removeBook(bookID)
        #expect(await !store.contains(bookID: bookID, chapterID: chapterID))
    }

    @Test func chapterContentStoreRejectsWritesStartedBeforeBookRemoval() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "YiYueContentStoreRevisionTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChapterContentStore(rootDirectory: root)
        let bookID = UUID()
        let chapterID = UUID()
        let staleToken = await store.makeWriteToken(bookID: bookID)

        try await store.removeBook(bookID)
        var rejectedStaleWrite = false
        do {
            _ = try await store.store(
                "第一章 这是删除前已开始的网络请求返回的正文。",
                bookID: bookID,
                chapterID: chapterID,
                retention: .automatic,
                writeToken: staleToken
            )
        } catch ChapterContentStoreError.staleWrite {
            rejectedStaleWrite = true
        }
        let staleContent = await store.load(bookID: bookID, chapterID: chapterID)

        #expect(rejectedStaleWrite)
        #expect(staleContent == nil)

        let freshToken = await store.makeWriteToken(bookID: bookID)
        let outcome = try await store.store(
            "第一章 这是清除后由新阅读请求写入的有效正文。",
            bookID: bookID,
            chapterID: chapterID,
            retention: .automatic,
            writeToken: freshToken
        )
        #expect(outcome.isStored)
    }

    @Test func chapterReplacementInvalidatesOnlyOlderWritesForThatChapter() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "YiYueChapterReplacementRevisionTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChapterContentStore(rootDirectory: root)
        let bookID = UUID()
        let replacedChapterID = UUID()
        let otherChapterID = UUID()

        try await store.store(
            "旧书源的主动缓存正文",
            bookID: bookID,
            chapterID: replacedChapterID,
            retention: .userManaged
        )
        let olderDownloadToken = await store.makeWriteToken(bookID: bookID)
        let replacement = try await store.replace(
            "新书源的替换正文",
            bookID: bookID,
            chapterID: replacedChapterID,
            retention: .automatic,
            writeToken: olderDownloadToken
        )

        #expect(replacement.retention == .userManaged)
        #expect(replacement.outcome?.isStored == true)
        #expect(await store.load(
            bookID: bookID,
            chapterID: replacedChapterID
        ) == CachedChapterContent(
            content: "新书源的替换正文",
            retention: .userManaged
        ))

        var rejectedOlderWrite = false
        do {
            _ = try await store.store(
                "旧请求晚到的正文",
                bookID: bookID,
                chapterID: replacedChapterID,
                retention: .userManaged,
                writeToken: olderDownloadToken
            )
        } catch ChapterContentStoreError.staleWrite {
            rejectedOlderWrite = true
        }
        #expect(rejectedOlderWrite)
        #expect(await store.load(
            bookID: bookID,
            chapterID: replacedChapterID
        )?.content == "新书源的替换正文")

        let otherOutcome = try await store.store(
            "同批次其他章节仍可完成",
            bookID: bookID,
            chapterID: otherChapterID,
            retention: .userManaged,
            writeToken: olderDownloadToken
        )
        #expect(otherOutcome.isStored)
    }

    @Test func chapterRemovalRejectsAnOlderInFlightWrite() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "YiYueChapterRemovalRevisionTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChapterContentStore(rootDirectory: root)
        let bookID = UUID()
        let chapterID = UUID()
        let olderToken = await store.makeWriteToken(bookID: bookID)

        try await store.remove(bookID: bookID, chapterID: chapterID)
        var rejectedOlderWrite = false
        do {
            _ = try await store.store(
                "删除动作之前已经开始的请求正文",
                bookID: bookID,
                chapterID: chapterID,
                retention: .automatic,
                writeToken: olderToken
            )
        } catch ChapterContentStoreError.staleWrite {
            rejectedOlderWrite = true
        }

        #expect(rejectedOlderWrite)
        #expect(await store.load(bookID: bookID, chapterID: chapterID) == nil)
    }

    @Test func newerReplacementAndBookRemovalInvalidateOlderReceipts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "YiYueReplacementReceiptTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChapterContentStore(rootDirectory: root)
        let bookID = UUID()
        let chapterID = UUID()
        let initialToken = await store.makeWriteToken(bookID: bookID)

        let first = try await store.replace(
            "第一次替换正文",
            bookID: bookID,
            chapterID: chapterID,
            retention: .automatic,
            writeToken: initialToken
        )
        let second = try await store.replace(
            "第二次替换正文",
            bookID: bookID,
            chapterID: chapterID,
            retention: .automatic,
            writeToken: first.writeToken
        )

        #expect(await !store.isWriteTokenCurrent(
            first.writeToken,
            bookID: bookID,
            chapterID: chapterID
        ))
        #expect(await store.isWriteTokenCurrent(
            second.writeToken,
            bookID: bookID,
            chapterID: chapterID
        ))

        try await store.removeBook(bookID)
        #expect(await !store.isWriteTokenCurrent(
            second.writeToken,
            bookID: bookID,
            chapterID: chapterID
        ))
    }

    @Test func oversizedReplacementDoesNotExposeOldAutomaticBody() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "YiYueOversizedReplacementTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChapterContentStore(
            rootDirectory: root,
            automaticHighWaterBytes: 20,
            automaticLowWaterBytes: 10
        )
        let bookID = UUID()
        let chapterID = UUID()
        try await store.store(
            "旧正文",
            bookID: bookID,
            chapterID: chapterID,
            retention: .automatic
        )
        let token = await store.makeWriteToken(bookID: bookID)

        let replacement = try await store.replace(
            String(repeating: "新", count: 30),
            bookID: bookID,
            chapterID: chapterID,
            retention: .automatic,
            writeToken: token
        )

        #expect(replacement.outcome == .skippedTooLarge)
        #expect(await store.load(bookID: bookID, chapterID: chapterID) == nil)
    }

    @Test func invalidReplacementDoesNotInvalidateAnExistingWriteToken() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "YiYueInvalidReplacementTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChapterContentStore(rootDirectory: root)
        let bookID = UUID()
        let chapterID = UUID()
        let token = await store.makeWriteToken(bookID: bookID)

        var rejectedInvalidContent = false
        do {
            _ = try await store.replace(
                "   ",
                bookID: bookID,
                chapterID: chapterID,
                retention: .automatic,
                writeToken: token
            )
        } catch ChapterContentStoreError.invalidContent {
            rejectedInvalidContent = true
        }
        #expect(rejectedInvalidContent)

        let outcome = try await store.store(
            "无效替换之后原任务仍可落盘",
            bookID: bookID,
            chapterID: chapterID,
            retention: .automatic,
            writeToken: token
        )
        #expect(outcome.isStored)
    }

    @Test func replacementReturnsCurrentFallbackReceiptWhenDiskWriteFails() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "YiYueReplacementFallbackTests-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("占位文件".utf8).write(to: root, options: .atomic)

        let store = ChapterContentStore(rootDirectory: root)
        let bookID = UUID()
        let chapterID = UUID()
        let olderToken = await store.makeWriteToken(bookID: bookID)
        let replacement = try await store.replace(
            "磁盘不可用时交给 SwiftData 的正文",
            bookID: bookID,
            chapterID: chapterID,
            retention: .automatic,
            writeToken: olderToken
        )

        #expect(replacement.outcome == nil)
        #expect(await !store.isWriteTokenCurrent(
            olderToken,
            bookID: bookID,
            chapterID: chapterID
        ))
        #expect(await store.isWriteTokenCurrent(
            replacement.writeToken,
            bookID: bookID,
            chapterID: chapterID
        ))
    }

    @Test func chapterContentStoreSeparatesAndPromotesRetentionTiers() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("YiYueChapterTierTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ChapterContentStore(rootDirectory: root)
        let bookID = UUID()
        let automaticChapterID = UUID()
        let protectedChapterID = UUID()

        try await store.store(
            "临时正文",
            bookID: bookID,
            chapterID: automaticChapterID,
            retention: .automatic
        )
        #expect(await store.load(bookID: bookID, chapterID: automaticChapterID)?.retention == .automatic)
        #expect(try await store.promote(bookID: bookID, chapterID: automaticChapterID))
        #expect(await store.load(bookID: bookID, chapterID: automaticChapterID)?.retention == .userManaged)

        try await store.store(
            "主动正文",
            bookID: bookID,
            chapterID: protectedChapterID,
            retention: .userManaged
        )
        let outcome = try await store.store(
            "不得降级覆盖",
            bookID: bookID,
            chapterID: protectedChapterID,
            retention: .automatic
        )
        #expect(outcome == .alreadyUserManaged)
        #expect(await store.load(bookID: bookID, chapterID: protectedChapterID)?.content == "主动正文")
    }

    @Test func chapterContentStoreTrimsOnlyAutomaticLRU() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("YiYueChapterLRUTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let clock = ChapterCacheTestClock()
        let store = ChapterContentStore(
            rootDirectory: root,
            automaticHighWaterBytes: 25,
            automaticLowWaterBytes: 20,
            now: { clock.next() }
        )
        let bookID = UUID()
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let protected = UUID()
        let oversized = UUID()

        try await store.store("1234567890", bookID: bookID, chapterID: first, retention: .automatic)
        try await store.store("abcdefghij", bookID: bookID, chapterID: second, retention: .automatic)
        _ = await store.load(bookID: bookID, chapterID: first) // Refresh first; second becomes LRU.
        let outcome = try await store.store(
            "ABCDEFGHIJ",
            bookID: bookID,
            chapterID: third,
            retention: .automatic
        )
        try await store.store(
            String(repeating: "P", count: 40),
            bookID: bookID,
            chapterID: protected,
            retention: .userManaged
        )
        let oversizedOutcome = try await store.store(
            String(repeating: "X", count: 30),
            bookID: bookID,
            chapterID: oversized,
            retention: .automatic
        )

        #expect(outcome == .stored(retention: .automatic, evictedAutomaticCount: 1))
        #expect(await store.contains(bookID: bookID, chapterID: first, retention: .automatic))
        #expect(await !store.contains(bookID: bookID, chapterID: second, retention: .automatic))
        #expect(await store.contains(bookID: bookID, chapterID: third, retention: .automatic))
        #expect(await store.contains(bookID: bookID, chapterID: protected, retention: .userManaged))
        #expect(oversizedOutcome == .skippedTooLarge)
        #expect(await !store.contains(bookID: bookID, chapterID: oversized))

        let statistics = try await store.statistics()
        #expect(statistics.automaticBytes == 20)
        #expect(statistics.automaticCount == 2)
        #expect(statistics.userManagedBytes == 40)
        #expect(statistics.userManagedCount == 1)
    }

    @Test func chapterContentStorePreservesAndRepairsInvalidProtectedFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("YiYueChapterRepairTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ChapterContentStore(rootDirectory: root)
        let bookID = UUID()
        let chapterID = UUID()
        try await store.store(
            "原主动正文",
            bookID: bookID,
            chapterID: chapterID,
            retention: .userManaged
        )
        let protectedURL = root
            .appendingPathComponent(bookID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(chapterID.uuidString.lowercased())
            .appendingPathExtension("txt")
        try Data([0xFF, 0xFE]).write(to: protectedURL, options: .atomic)

        #expect(await store.load(bookID: bookID, chapterID: chapterID) == nil)
        #expect(FileManager.default.fileExists(atPath: protectedURL.path))

        try await store.store(
            "可恢复临时正文",
            bookID: bookID,
            chapterID: chapterID,
            retention: .automatic
        )
        #expect(await store.load(bookID: bookID, chapterID: chapterID)?.retention == .automatic)
        #expect(try await store.promote(bookID: bookID, chapterID: chapterID))
        let repaired = await store.load(bookID: bookID, chapterID: chapterID)
        #expect(repaired?.retention == .userManaged)
        #expect(repaired?.content == "可恢复临时正文")
    }

    @Test func chapterContentStoreWarmIndexAvoidsRescanAndRepairsExternalDeletion() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("YiYueChapterIndexTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fileManager = ChapterCacheCountingFileManager()
        let store = ChapterContentStore(rootDirectory: root, fileManager: fileManager)
        let bookID = UUID()
        let chapterID = UUID()
        try await store.store(
            "索引中的有效正文",
            bookID: bookID,
            chapterID: chapterID,
            retention: .userManaged
        )

        #expect(try await store.storedChapterIDs(
            bookID: bookID,
            retention: .userManaged
        ) == [chapterID])
        let scansAfterInitialSnapshot = fileManager.directoryScanCount

        #expect(try await store.storedChapterIDs(
            bookID: bookID,
            retention: .userManaged
        ) == [chapterID])
        #expect(fileManager.directoryScanCount == scansAfterInitialSnapshot)

        let initialStatistics = try await store.statistics()
        #expect(initialStatistics.userManagedCount == 1)
        let scansAfterInitialStatistics = fileManager.directoryScanCount

        let chapterURL = root
            .appendingPathComponent(bookID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(chapterID.uuidString.lowercased())
            .appendingPathExtension("txt")
        try fileManager.removeItem(at: chapterURL)

        let repairedStatistics = try await store.statistics()
        #expect(repairedStatistics.userManagedCount == 0)
        #expect(repairedStatistics.userManagedBytes == 0)
        #expect(fileManager.directoryScanCount > scansAfterInitialStatistics)
        #expect(try await store.storedChapterIDs(
            bookID: bookID,
            retention: .userManaged
        ).isEmpty)
    }

    @Test func chapterContentStoreIndexExcludesInvalidFilesByRetention() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("YiYueChapterInvalidIndexTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ChapterContentStore(rootDirectory: root)
        let bookID = UUID()
        let validProtectedID = UUID()
        let invalidProtectedID = UUID()
        let validAutomaticID = UUID()
        let invalidAutomaticID = UUID()

        try await store.store(
            "保留的主动缓存",
            bookID: bookID,
            chapterID: validProtectedID,
            retention: .userManaged
        )
        try await store.store(
            "稍后损坏的主动缓存",
            bookID: bookID,
            chapterID: invalidProtectedID,
            retention: .userManaged
        )
        try await store.store(
            "保留的自动缓存",
            bookID: bookID,
            chapterID: validAutomaticID,
            retention: .automatic
        )
        try await store.store(
            "稍后损坏的自动缓存",
            bookID: bookID,
            chapterID: invalidAutomaticID,
            retention: .automatic
        )

        let protectedDirectory = root
            .appendingPathComponent(bookID.uuidString.lowercased(), isDirectory: true)
        let automaticDirectory = root
            .appendingPathComponent(".automatic", isDirectory: true)
            .appendingPathComponent(bookID.uuidString.lowercased(), isDirectory: true)
        let invalidProtectedURL = protectedDirectory
            .appendingPathComponent(invalidProtectedID.uuidString.lowercased())
            .appendingPathExtension("txt")
        let invalidAutomaticURL = automaticDirectory
            .appendingPathComponent(invalidAutomaticID.uuidString.lowercased())
            .appendingPathExtension("txt")
        try Data([0xFF, 0xFE]).write(to: invalidProtectedURL, options: .atomic)
        try Data([0xFF, 0xFE]).write(to: invalidAutomaticURL, options: .atomic)

        #expect(try await store.storedChapterIDs(
            bookID: bookID,
            retention: .userManaged
        ) == [validProtectedID])
        #expect(try await store.storedChapterIDs(
            bookID: bookID,
            retention: .automatic
        ) == [validAutomaticID])
        #expect(FileManager.default.fileExists(atPath: invalidProtectedURL.path))
        #expect(!FileManager.default.fileExists(atPath: invalidAutomaticURL.path))

        let statistics = try await store.statistics()
        #expect(statistics.userManagedCount == 1)
        #expect(statistics.automaticCount == 1)
    }

    @Test func chapterContentLoaderCancelsOnlyOneWaiter() async throws {
        let counter = ChapterLoadCounter()
        let loader = ChapterContentLoader { _ in
            await counter.increment()
            try await Task.sleep(nanoseconds: 120_000_000)
            return "共享正文"
        }
        let request = ChapterContentRequest(
            url: "https://example.com/chapter/1",
            rule: LegadoSource.ContentRule(content: "#content@text", replaceRegex: nil, nextContentUrl: nil),
            baseURL: "https://example.com",
            nextChapterURL: nil
        )

        let first = Task { try await loader.fetch(request) }
        let second = Task { try await loader.fetch(request) }
        for _ in 0..<20 {
            if await counter.value == 1 { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        first.cancel()

        do {
            _ = try await first.value
            Issue.record("被取消的等待者不应收到共享请求结果")
        } catch is CancellationError {
            // Expected: the second waiter keeps the underlying request alive.
        }

        #expect(try await second.value == "共享正文")
        #expect(await counter.value == 1)
    }

    @Test func chapterContentLoaderCancelsUnderlyingTaskAfterLastWaiter() async throws {
        let counter = ChapterLoadCounter()
        let loader = ChapterContentLoader { _ in
            await counter.increment()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return "不应完成"
            } catch {
                await counter.markCancelled()
                throw error
            }
        }
        let request = ChapterContentRequest(
            url: "https://example.com/chapter/cancel",
            rule: LegadoSource.ContentRule(content: "#content@text", replaceRegex: nil, nextContentUrl: nil),
            baseURL: "https://example.com",
            nextChapterURL: nil
        )

        let task = Task { try await loader.fetch(request) }
        await counter.waitUntilStarted()
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("最后一个等待者取消后应立即返回 CancellationError")
        } catch is CancellationError {
            // Expected.
        }

        #expect(await counter.waitUntilCancelled())
    }
}

private actor ChapterLoadCounter {
    private(set) var value = 0
    private(set) var wasCancelled = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func increment() {
        value += 1
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func markCancelled() {
        wasCancelled = true
    }

    func waitUntilStarted() async {
        guard value == 0 else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func waitUntilCancelled(timeout: TimeInterval = 30) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if wasCancelled { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return wasCancelled
    }
}

private final class ChapterCacheTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var tick: TimeInterval = 0

    func next() -> Date {
        lock.lock()
        defer { lock.unlock() }
        tick += 1
        return Date(timeIntervalSinceReferenceDate: tick)
    }
}

private final class ChapterCacheCountingFileManager: FileManager, @unchecked Sendable {
    private let scanLock = NSLock()
    private var scans = 0

    var directoryScanCount: Int {
        scanLock.lock()
        defer { scanLock.unlock() }
        return scans
    }

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        scanLock.lock()
        scans += 1
        scanLock.unlock()
        return try super.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: mask
        )
    }
}
