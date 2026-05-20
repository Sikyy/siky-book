import Testing
@testable import NovelReader

@Suite("SourceEngine Tests")
struct SourceEngineTests {

    @Test func buildSearchURL() {
        let source = LegadoSource(
            name: "Test",
            url: "https://www.example.com",
            group: nil,
            searchURL: "/search?q={{key}}&page={{page}}",
            searchRule: nil,
            bookInfoRule: nil,
            tocRule: nil,
            contentRule: nil
        )
        let engine = SourceEngine()
        let url = engine.buildSearchURL(source: source, keyword: "斗破苍穹", page: 1)
        #expect(url == "https://www.example.com/search?q=%E6%96%97%E7%A0%B4%E8%8B%8D%E7%A9%B9&page=1")
    }

    @Test func buildSearchURLWithAbsolute() {
        let source = LegadoSource(
            name: "Test",
            url: "https://www.example.com",
            group: nil,
            searchURL: "https://search.example.com/s?key={{key}}",
            searchRule: nil,
            bookInfoRule: nil,
            tocRule: nil,
            contentRule: nil
        )
        let engine = SourceEngine()
        let url = engine.buildSearchURL(source: source, keyword: "test", page: 1)
        #expect(url == "https://search.example.com/s?key=test")
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
        let results = try engine.parseSearchResults(html: html, rule: searchRule, baseURL: "https://example.com")
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
            chapterUrl: "a@href"
        )
        let engine = SourceEngine()
        let chapters = try engine.parseChapterList(html: html, rule: tocRule, baseURL: "https://example.com")
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
            replaceRegex: nil
        )
        let engine = SourceEngine()
        let content = try engine.parseContent(html: html, rule: contentRule, baseURL: "https://example.com")
        #expect(content?.contains("这是第一段") == true)
        #expect(content?.contains("这是第二段") == true)
    }

    @Test func resolveRelativeURL() {
        let engine = SourceEngine()
        #expect(engine.resolveURL("/book/1", base: "https://example.com") == "https://example.com/book/1")
        #expect(engine.resolveURL("https://other.com/book", base: "https://example.com") == "https://other.com/book")
        #expect(engine.resolveURL("//cdn.example.com/img.jpg", base: "https://example.com") == "https://cdn.example.com/img.jpg")
    }
}
