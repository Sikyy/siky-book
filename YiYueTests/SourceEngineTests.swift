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
            chapterUrl: "a@href"
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
            replaceRegex: nil
        )
        let engine = SourceEngine()
        let content = try engine.parseContent(response: html, rule: contentRule, baseURL: "https://example.com")
        #expect(content?.contains("这是第一段") == true)
        #expect(content?.contains("这是第二段") == true)
        #expect(content?.contains("<p>") == false)
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
            replaceRegex: nil
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
    }
}
