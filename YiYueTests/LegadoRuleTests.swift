import Testing
@testable import YiYue

@Suite("LegadoRule Tests")
struct LegadoRuleTests {

    @Test func parseMinimalSource() throws {
        let json = """
        {
            "bookSourceName": "笔趣阁",
            "bookSourceUrl": "https://www.example.com",
            "bookSourceGroup": "常用",
            "bookSourceType": 0,
            "ruleSearch": {
                "bookList": ".result-game-item-detail",
                "name": ".result-item-title a@text",
                "author": ".result-game-item-info span:eq(1) a@text",
                "bookUrl": ".result-item-title a@href",
                "coverUrl": ".result-game-item-pic img@src"
            },
            "ruleToc": {
                "chapterList": "#list dd a",
                "chapterName": "@text",
                "chapterUrl": "@href"
            },
            "ruleContent": {
                "content": "#content@text"
            }
        }
        """
        let source = try LegadoSourceParser.parse(json: json)
        #expect(source.name == "笔趣阁")
        #expect(source.url == "https://www.example.com")
        #expect(source.group == "常用")
        #expect(source.searchRule?.bookList == ".result-game-item-detail")
        #expect(source.searchRule?.name == ".result-item-title a@text")
        #expect(source.tocRule?.chapterList == "#list dd a")
        #expect(source.contentRule?.content == "#content@text")
    }

    @Test func parseSearchURL() throws {
        let json = """
        {
            "bookSourceName": "Test",
            "bookSourceUrl": "https://www.example.com",
            "searchUrl": "/s?q={{key}}&p={{page}}",
            "ruleSearch": {},
            "ruleToc": {},
            "ruleContent": {}
        }
        """
        let source = try LegadoSourceParser.parse(json: json)
        #expect(source.searchURL == "/s?q={{key}}&p={{page}}")
    }

    @Test func parseBatchImport() throws {
        let json = """
        [
            {
                "bookSourceName": "Source A",
                "bookSourceUrl": "https://a.com",
                "ruleSearch": {},
                "ruleToc": {},
                "ruleContent": {}
            },
            {
                "bookSourceName": "Source B",
                "bookSourceUrl": "https://b.com",
                "ruleSearch": {},
                "ruleToc": {},
                "ruleContent": {}
            }
        ]
        """
        let sources = try LegadoSourceParser.parseBatch(json: json)
        #expect(sources.count == 2)
        #expect(sources[0].name == "Source A")
        #expect(sources[1].name == "Source B")
    }

    @Test func parseBookInfoRule() throws {
        let json = """
        {
            "bookSourceName": "Test",
            "bookSourceUrl": "https://www.example.com",
            "ruleSearch": {},
            "ruleBookInfo": {
                "name": ".book-name@text",
                "author": ".book-author@text",
                "intro": "#intro@text",
                "coverUrl": ".book-cover img@src",
                "tocUrl": "@href"
            },
            "ruleToc": {},
            "ruleContent": {}
        }
        """
        let source = try LegadoSourceParser.parse(json: json)
        #expect(source.bookInfoRule?.name == ".book-name@text")
        #expect(source.bookInfoRule?.author == ".book-author@text")
        #expect(source.bookInfoRule?.intro == "#intro@text")
        #expect(source.bookInfoRule?.coverUrl == ".book-cover img@src")
    }
}
