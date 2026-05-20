import Testing
@testable import NovelReader

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
}
