import Testing
@testable import YiYue

@Suite("RuleExecutor Tests")
struct RuleExecutorTests {

    let sampleHTML = """
    <html><body>
    <div class="book-list">
        <div class="item">
            <a href="/book/1" class="title">斗破苍穹</a>
            <span class="author">天蚕土豆</span>
        </div>
        <div class="item">
            <a href="/book/2" class="title">完美世界</a>
            <span class="author">辰东</span>
        </div>
    </div>
    <div id="content">
        <p>第一段正文内容。</p>
        <p>第二段正文内容。</p>
    </div>
    </body></html>
    """

    @Test func selectSingleText() throws {
        let executor = RuleExecutor()
        let result = try executor.getString(html: sampleHTML, rule: ".title@text", baseURL: "https://example.com")
        #expect(result == "斗破苍穹")
    }

    @Test func selectAttribute() throws {
        let executor = RuleExecutor()
        let result = try executor.getString(html: sampleHTML, rule: ".title@href", baseURL: "https://example.com")
        #expect(result == "/book/1")
    }

    @Test func selectList() throws {
        let executor = RuleExecutor()
        let elements = try executor.getElements(html: sampleHTML, rule: ".item", baseURL: "https://example.com")
        #expect(elements.count == 2)
    }

    @Test func getStringFromElement() throws {
        let executor = RuleExecutor()
        let elements = try executor.getElements(html: sampleHTML, rule: ".item", baseURL: "https://example.com")
        let name = try executor.getString(element: elements[0], rule: ".title@text")
        let author = try executor.getString(element: elements[0], rule: ".author@text")
        #expect(name == "斗破苍穹")
        #expect(author == "天蚕土豆")
    }

    @Test func contentTextJoin() throws {
        let executor = RuleExecutor()
        let result = try executor.getString(html: sampleHTML, rule: "#content p@text")
        #expect(result?.contains("第一段正文内容") == true)
    }

    @Test func fallbackRule() throws {
        let executor = RuleExecutor()
        let result = try executor.getString(html: sampleHTML, rule: ".nonexistent@text||.title@text", baseURL: "https://example.com")
        #expect(result == "斗破苍穹")
    }

    @Test func htmlAttribute() throws {
        let executor = RuleExecutor()
        let result = try executor.getString(html: sampleHTML, rule: "#content@html", baseURL: "https://example.com")
        #expect(result?.contains("<p>") == true)
    }

    let legadoHTML = """
    <html><body>
    <div class="newbox">
        <ul>
            <li>
                <h3><a href="/index.html">首页</a><a href="/book/1.htm">龙族</a></h3>
                <label>江南</label>
                <label>玄幻</label>
                <label>连载</label>
                <a href="/book/1.htm"><img data-src="/cover/1.jpg"></a>
                <p class="ellipsis_2">一个有关龙的故事</p>
            </li>
            <li>
                <h3><a href="/index.html">首页</a><a href="/book/2.htm">龙族II</a></h3>
                <label>江南</label>
                <label>奇幻</label>
                <a href="/book/2.htm"><img data-src="/cover/2.jpg"></a>
            </li>
        </ul>
    </div>
    <div id="catalog">
        <ul>
            <a href="/ch/1.html">第一章</a>
            <a href="/ch/2.html">第二章</a>
            <a href="/ch/3.html">第三章</a>
        </ul>
    </div>
    </body></html>
    """

    @Test func legadoBookList() throws {
        let executor = RuleExecutor()
        let elements = try executor.getElements(html: legadoHTML, rule: "class.newbox.0@tag.ul.0@tag.li")
        #expect(elements.count == 2)
    }

    @Test func legadoBookName() throws {
        let executor = RuleExecutor()
        let elements = try executor.getElements(html: legadoHTML, rule: "class.newbox.0@tag.ul.0@tag.li")
        let name = try executor.getString(element: elements[0], rule: "tag.h3.0@tag.a.1@text")
        #expect(name == "龙族")
    }

    @Test func legadoBookUrl() throws {
        let executor = RuleExecutor()
        let elements = try executor.getElements(html: legadoHTML, rule: "class.newbox.0@tag.ul.0@tag.li")
        let url = try executor.getString(element: elements[0], rule: "tag.h3.0@tag.a.1@href")
        #expect(url == "/book/1.htm")
    }

    @Test func legadoCoverUrl() throws {
        let executor = RuleExecutor()
        let elements = try executor.getElements(html: legadoHTML, rule: "class.newbox.0@tag.ul.0@tag.li")
        let cover = try executor.getString(element: elements[0], rule: "tag.img.0@data-src")
        #expect(cover == "/cover/1.jpg")
    }

    @Test func legadoChapterListReverse() throws {
        let executor = RuleExecutor()
        let elements = try executor.getElements(html: legadoHTML, rule: "id.catalog.0@tag.ul.0@tag.a[-1:0]")
        #expect(elements.count == 3)
        let firstName = try executor.getString(element: elements[0], rule: "text")
        #expect(firstName == "第三章")
    }

    @Test func legadoAndSeparator() throws {
        let executor = RuleExecutor()
        let elements = try executor.getElements(html: legadoHTML, rule: "class.newbox.0@tag.ul.0@tag.li")
        let kind = try executor.getString(element: elements[0], rule: "tag.label.1@text&&tag.label.2@text")
        #expect(kind == "玄幻 连载")
    }

    @Test func bareHrefAttribute() throws {
        let executor = RuleExecutor()
        let elements = try executor.getElements(html: legadoHTML, rule: "id.catalog.0@tag.ul.0@tag.a[-1:0]")
        let url = try executor.getString(element: elements[0], rule: "href")
        #expect(url == "/ch/3.html")
    }

    @Test func bareTextAttribute() throws {
        let executor = RuleExecutor()
        let elements = try executor.getElements(html: legadoHTML, rule: "id.catalog.0@tag.ul.0@tag.a")
        let name = try executor.getString(element: elements[0], rule: "text")
        #expect(name == "第一章")
    }

    @Test func fullSearchToChapterFlow() throws {
        let executor = RuleExecutor()
        let items = try executor.getElements(html: legadoHTML, rule: "class.newbox.0@tag.ul.0@tag.li")
        #expect(items.count == 2)

        let name = try executor.getString(element: items[0], rule: "tag.h3.0@tag.a.1@text")
        let author = try executor.getString(element: items[0], rule: "tag.label.0@text")
        let bookUrl = try executor.getString(element: items[0], rule: "tag.h3.0@tag.a.1@href")
        let cover = try executor.getString(element: items[0], rule: "tag.img.0@data-src")
        let intro = try executor.getString(element: items[0], rule: "class.ellipsis_2.0@text")
        let kind = try executor.getString(element: items[0], rule: "tag.label.1@text&&tag.label.2@text")

        #expect(name == "龙族")
        #expect(author == "江南")
        #expect(bookUrl == "/book/1.htm")
        #expect(cover == "/cover/1.jpg")
        #expect(intro == "一个有关龙的故事")
        #expect(kind == "玄幻 连载")

        let chapters = try executor.getElements(html: legadoHTML, rule: "id.catalog.0@tag.ul.0@tag.a[-1:0]")
        #expect(chapters.count == 3)
        let chName = try executor.getString(element: chapters[0], rule: "text")
        let chUrl = try executor.getString(element: chapters[0], rule: "href")
        #expect(chName == "第三章")
        #expect(chUrl == "/ch/3.html")
    }
}
