# Phase 3: Book Source Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Legado-compatible book source engine so users can search for novels online, pick a source, and add books to the bookshelf with chapter fetching.

**Architecture:** SwiftSoup (SPM) parses HTML with CSS selectors. JavaScriptCore executes JS expressions from rules. A SourceEngine service orchestrates search → book info → chapters → content. URLSession handles network. A 3-step search UI (search → pick source → confirm add) sits on top.

**Tech Stack:** SwiftSoup (SPM), JavaScriptCore (built-in), URLSession, SwiftUI, SwiftData

---

## Task 1: Add SwiftSoup SPM Dependency

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Update project.yml to add SwiftSoup package**

In `project.yml`, add the SPM package and dependency:

```yaml
name: NovelReader
options:
  bundleIdPrefix: com.novelreader
  deploymentTarget:
    iOS: "17.0"
  groupSortPosition: top
packages:
  SwiftSoup:
    url: https://github.com/scinfu/SwiftSoup.git
    from: "2.7.0"
targets:
  NovelReader:
    type: application
    platform: iOS
    sources:
      - path: NovelReader
    info:
      path: NovelReader/App/Info.plist
      properties:
        UILaunchScreen: {}
        CFBundleDocumentTypes:
          - CFBundleTypeName: Text File
            CFBundleTypeRole: Viewer
            LSItemContentTypes:
              - public.plain-text
        NSAppTransportSecurity:
          NSAllowsArbitraryLoads: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.novelreader.app
        MARKETING_VERSION: "1.0.0"
        CURRENT_PROJECT_VERSION: "1"
        SWIFT_VERSION: "5.9"
    dependencies:
      - package: SwiftSoup
  NovelReaderTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: NovelReaderTests
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
    dependencies:
      - target: NovelReader
```

Note the additions:
- `packages:` section with SwiftSoup
- `NSAppTransportSecurity` with `NSAllowsArbitraryLoads: true` (needed for HTTP book source sites)
- `dependencies:` with `- package: SwiftSoup` under the NovelReader target

- [ ] **Step 2: Regenerate Xcode project**

```bash
xcodegen generate
```

- [ ] **Step 3: Resolve packages and build**

```bash
xcodebuild build -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 17' -quiet
```

- [ ] **Step 4: Run tests to verify nothing broke**

```bash
xcodebuild test -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 17' -quiet 2>&1 | tail -5
```

Expected: 28 tests pass.

- [ ] **Step 5: Commit**

```bash
git add project.yml NovelReader.xcodeproj
git commit -m "feat: add SwiftSoup dependency and allow HTTP network access"
```

---

## Task 2: Legado Rule Model

**Files:**
- Create: `NovelReader/Models/LegadoRule.swift`
- Create: `NovelReaderTests/LegadoRuleTests.swift`

- [ ] **Step 1: Write failing test for Legado JSON parsing**

`NovelReaderTests/LegadoRuleTests.swift`:

```swift
import Testing
@testable import NovelReader

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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 17' -quiet 2>&1 | tail -5
```

Expected: compile error (LegadoSourceParser not found).

- [ ] **Step 3: Implement LegadoRule model**

`NovelReader/Models/LegadoRule.swift`:

```swift
import Foundation

struct LegadoSource {
    let name: String
    let url: String
    let group: String?
    let searchURL: String?
    let searchRule: SearchRule?
    let bookInfoRule: BookInfoRule?
    let tocRule: TocRule?
    let contentRule: ContentRule?

    struct SearchRule {
        let bookList: String?
        let name: String?
        let author: String?
        let bookUrl: String?
        let coverUrl: String?
        let kind: String?
        let intro: String?
    }

    struct BookInfoRule {
        let name: String?
        let author: String?
        let intro: String?
        let coverUrl: String?
        let tocUrl: String?
    }

    struct TocRule {
        let chapterList: String?
        let chapterName: String?
        let chapterUrl: String?
    }

    struct ContentRule {
        let content: String?
        let replaceRegex: String?
    }
}

enum LegadoSourceParser {
    static func parse(json: String) throws -> LegadoSource {
        guard let data = json.data(using: .utf8) else {
            throw LegadoParseError.invalidJSON
        }
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return parseObject(obj)
    }

    static func parseBatch(json: String) throws -> [LegadoSource] {
        guard let data = json.data(using: .utf8) else {
            throw LegadoParseError.invalidJSON
        }
        let top = try JSONSerialization.jsonObject(with: data)
        if let array = top as? [[String: Any]] {
            return array.map { parseObject($0) }
        }
        if let obj = top as? [String: Any] {
            return [parseObject(obj)]
        }
        throw LegadoParseError.invalidJSON
    }

    private static func parseObject(_ obj: [String: Any]) -> LegadoSource {
        let search = obj["ruleSearch"] as? [String: Any]
        let info = obj["ruleBookInfo"] as? [String: Any]
        let toc = obj["ruleToc"] as? [String: Any]
        let content = obj["ruleContent"] as? [String: Any]

        return LegadoSource(
            name: obj["bookSourceName"] as? String ?? "",
            url: obj["bookSourceUrl"] as? String ?? "",
            group: obj["bookSourceGroup"] as? String,
            searchURL: obj["searchUrl"] as? String,
            searchRule: search.map {
                LegadoSource.SearchRule(
                    bookList: $0["bookList"] as? String,
                    name: $0["name"] as? String,
                    author: $0["author"] as? String,
                    bookUrl: $0["bookUrl"] as? String,
                    coverUrl: $0["coverUrl"] as? String,
                    kind: $0["kind"] as? String,
                    intro: $0["intro"] as? String
                )
            },
            bookInfoRule: info.map {
                LegadoSource.BookInfoRule(
                    name: $0["name"] as? String,
                    author: $0["author"] as? String,
                    intro: $0["intro"] as? String,
                    coverUrl: $0["coverUrl"] as? String,
                    tocUrl: $0["tocUrl"] as? String
                )
            },
            tocRule: toc.map {
                LegadoSource.TocRule(
                    chapterList: $0["chapterList"] as? String,
                    chapterName: $0["chapterName"] as? String,
                    chapterUrl: $0["chapterUrl"] as? String
                )
            },
            contentRule: content.map {
                LegadoSource.ContentRule(
                    content: $0["content"] as? String,
                    replaceRegex: $0["replaceRegex"] as? String
                )
            }
        )
    }
}

enum LegadoParseError: Error {
    case invalidJSON
}
```

- [ ] **Step 4: Run tests**

```bash
xcodebuild test -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 17' -quiet 2>&1 | tail -5
```

Expected: all tests pass (28 existing + 4 new = 32).

- [ ] **Step 5: Commit**

```bash
git add NovelReader/Models/LegadoRule.swift NovelReaderTests/LegadoRuleTests.swift
git commit -m "feat: add Legado book source JSON parser with rule model"
```

---

## Task 3: Rule Executor (CSS + Regex + JS)

**Files:**
- Create: `NovelReader/Services/RuleExecutor.swift`
- Create: `NovelReaderTests/RuleExecutorTests.swift`

The rule executor parses Legado rule strings and applies them to HTML content. Legado rules use patterns like:
- `.css-selector@text` → select element, get text
- `.css-selector@href` → select element, get attribute
- `tag.class@text` → CSS selector
- `##regex##replacement` → regex replacement on result
- Rules separated by `&&` are chained (apply each in sequence)
- Rules separated by `||` are fallbacks (try first, if empty try next)

- [ ] **Step 1: Write failing tests**

`NovelReaderTests/RuleExecutorTests.swift`:

```swift
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

    @Test func regexReplacement() throws {
        let executor = RuleExecutor()
        let result = try executor.getString(html: sampleHTML, rule: "#content@text##第.*?段##")
        #expect(result == "正文内容。\n正文内容。")
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
}
```

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement RuleExecutor**

`NovelReader/Services/RuleExecutor.swift`:

```swift
import Foundation
import SwiftSoup

class RuleExecutor {

    func getElements(html: String, rule: String, baseURL: String = "") throws -> [Element] {
        let doc = try SwiftSoup.parse(html, baseURL)
        let selector = extractSelector(from: rule)
        return try doc.select(selector).array()
    }

    func getString(html: String, rule: String, baseURL: String = "") throws -> String? {
        let doc = try SwiftSoup.parse(html, baseURL)
        return try getString(doc: doc, rule: rule)
    }

    func getString(element: Element, rule: String) throws -> String? {
        let parts = rule.components(separatedBy: "||")
        for part in parts {
            if let result = try executeSingleRule(element: element, rule: part.trimmingCharacters(in: .whitespaces)), !result.isEmpty {
                return result
            }
        }
        return nil
    }

    private func getString(doc: Document, rule: String) throws -> String? {
        let parts = rule.components(separatedBy: "||")
        for part in parts {
            if let result = try executeSingleRuleOnDoc(doc: doc, rule: part.trimmingCharacters(in: .whitespaces)), !result.isEmpty {
                return result
            }
        }
        return nil
    }

    private func executeSingleRuleOnDoc(doc: Document, rule: String) throws -> String? {
        let (cssRule, regexPattern, regexReplacement) = splitRegex(rule)
        let (selector, attr) = splitAttribute(cssRule)

        let elements = try doc.select(selector)
        guard !elements.isEmpty() else { return nil }

        var text: String
        if attr == "text" || attr.isEmpty {
            text = try elements.array().map { try $0.text() }.joined(separator: "\n")
        } else if attr == "html" || attr == "innerHTML" {
            text = try elements.html()
        } else {
            text = try elements.first()?.attr(attr) ?? ""
        }

        if let pattern = regexPattern {
            text = applyRegex(text: text, pattern: pattern, replacement: regexReplacement ?? "")
        }
        return text.isEmpty ? nil : text
    }

    private func executeSingleRule(element: Element, rule: String) throws -> String? {
        let (cssRule, regexPattern, regexReplacement) = splitRegex(rule)
        let (selector, attr) = splitAttribute(cssRule)

        let target: Element
        if selector.isEmpty || selector == "@" {
            target = element
        } else {
            guard let found = try element.select(selector).first() else { return nil }
            target = found
        }

        var text: String
        if attr == "text" || attr.isEmpty {
            text = try target.text()
        } else if attr == "html" || attr == "innerHTML" {
            text = try target.html()
        } else {
            text = try target.attr(attr)
        }

        if let pattern = regexPattern {
            text = applyRegex(text: text, pattern: pattern, replacement: regexReplacement ?? "")
        }
        return text.isEmpty ? nil : text
    }

    private func extractSelector(from rule: String) -> String {
        let (cssRule, _, _) = splitRegex(rule)
        let (selector, _) = splitAttribute(cssRule)
        return selector
    }

    private func splitAttribute(_ rule: String) -> (selector: String, attr: String) {
        guard let atIndex = rule.lastIndex(of: "@") else {
            return (rule, "text")
        }
        let selector = String(rule[rule.startIndex..<atIndex])
        let attr = String(rule[rule.index(after: atIndex)...])
        return (selector.isEmpty ? "body" : selector, attr)
    }

    private func splitRegex(_ rule: String) -> (cssRule: String, pattern: String?, replacement: String?) {
        let parts = rule.components(separatedBy: "##")
        if parts.count >= 3 {
            return (parts[0], parts[1], parts[2])
        } else if parts.count == 2 {
            return (parts[0], parts[1], "")
        }
        return (rule, nil, nil)
    }

    private func applyRegex(text: String, pattern: String, replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }
}
```

- [ ] **Step 4: Run tests**

Expected: all pass (32 existing + 7 new = 39).

- [ ] **Step 5: Commit**

```bash
git add NovelReader/Services/RuleExecutor.swift NovelReaderTests/RuleExecutorTests.swift
git commit -m "feat: add rule executor with CSS selector, regex, and fallback support"
```

---

## Task 4: SourceEngine Service

**Files:**
- Create: `NovelReader/Services/SourceEngine.swift`
- Create: `NovelReaderTests/SourceEngineTests.swift`

The SourceEngine orchestrates end-to-end flows: build search URL → fetch HTML → parse with rules → return structured results.

- [ ] **Step 1: Write failing tests**

`NovelReaderTests/SourceEngineTests.swift`:

```swift
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
            chapterName: "@text",
            chapterUrl: "@href"
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
            <p>　　这是第一段。</p>
            <p>　　这是第二段。</p>
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
```

- [ ] **Step 2: Implement SourceEngine**

`NovelReader/Services/SourceEngine.swift`:

```swift
import Foundation

struct SearchResult {
    let title: String
    let author: String
    let bookURL: String
    let coverURL: String?
    let kind: String?
    let intro: String?
}

struct ChapterInfo {
    let title: String
    let url: String
}

class SourceEngine {
    private let ruleExecutor = RuleExecutor()

    func buildSearchURL(source: LegadoSource, keyword: String, page: Int) -> String? {
        guard var template = source.searchURL else { return nil }
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        template = template.replacingOccurrences(of: "{{key}}", with: encoded)
        template = template.replacingOccurrences(of: "{{page}}", with: String(page))

        if template.hasPrefix("http://") || template.hasPrefix("https://") {
            return template
        }
        let base = source.url.hasSuffix("/") ? String(source.url.dropLast()) : source.url
        return base + template
    }

    func parseSearchResults(html: String, rule: LegadoSource.SearchRule, baseURL: String) throws -> [SearchResult] {
        guard let listRule = rule.bookList else { return [] }
        let elements = try ruleExecutor.getElements(html: html, rule: listRule, baseURL: baseURL)
        return try elements.compactMap { element in
            guard let title = try ruleExecutor.getString(element: element, rule: rule.name ?? "@text"),
                  !title.isEmpty else { return nil }
            let author = try ruleExecutor.getString(element: element, rule: rule.author ?? ".author@text") ?? ""
            let bookURL = try ruleExecutor.getString(element: element, rule: rule.bookUrl ?? "a@href") ?? ""
            let coverURL = try ruleExecutor.getString(element: element, rule: rule.coverUrl ?? "img@src")
            let kind = rule.kind != nil ? try ruleExecutor.getString(element: element, rule: rule.kind!) : nil
            let intro = rule.intro != nil ? try ruleExecutor.getString(element: element, rule: rule.intro!) : nil
            return SearchResult(title: title, author: author, bookURL: bookURL, coverURL: coverURL, kind: kind, intro: intro)
        }
    }

    func parseChapterList(html: String, rule: LegadoSource.TocRule, baseURL: String) throws -> [ChapterInfo] {
        guard let listRule = rule.chapterList else { return [] }
        let elements = try ruleExecutor.getElements(html: html, rule: listRule, baseURL: baseURL)
        return try elements.enumerated().compactMap { _, element in
            let name = try ruleExecutor.getString(element: element, rule: rule.chapterName ?? "@text") ?? ""
            let url = try ruleExecutor.getString(element: element, rule: rule.chapterUrl ?? "@href") ?? ""
            guard !name.isEmpty else { return nil }
            return ChapterInfo(title: name, url: url)
        }
    }

    func parseContent(html: String, rule: LegadoSource.ContentRule, baseURL: String = "") throws -> String? {
        guard let contentRule = rule.content else { return nil }
        return try ruleExecutor.getString(html: html, rule: contentRule, baseURL: baseURL)
    }

    func resolveURL(_ url: String, base: String) -> String {
        if url.hasPrefix("http://") || url.hasPrefix("https://") {
            return url
        }
        if url.hasPrefix("//") {
            let scheme = base.hasPrefix("https") ? "https:" : "http:"
            return scheme + url
        }
        let cleanBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        let cleanPath = url.hasPrefix("/") ? url : "/" + url
        return cleanBase + cleanPath
    }
}
```

- [ ] **Step 3: Run tests**

Expected: all pass (32 + 7 + 6 = 45).

- [ ] **Step 4: Commit**

```bash
git add NovelReader/Services/SourceEngine.swift NovelReaderTests/SourceEngineTests.swift
git commit -m "feat: add source engine for search, chapter list, and content parsing"
```

---

## Task 5: Network Client + Source Import

**Files:**
- Create: `NovelReader/Services/NetworkClient.swift`
- Create: `NovelReader/Services/SourceImportService.swift`
- Create: `NovelReaderTests/SourceImportTests.swift`

- [ ] **Step 1: Write failing tests for source import**

`NovelReaderTests/SourceImportTests.swift`:

```swift
import Testing
import SwiftData
@testable import NovelReader

@Suite("SourceImport Tests")
struct SourceImportTests {

    @Test func importSingleSource() throws {
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

    @Test func importBatchSources() throws {
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

    @Test func importSkipsDuplicateURL() throws {
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
```

- [ ] **Step 2: Implement NetworkClient**

`NovelReader/Services/NetworkClient.swift`:

```swift
import Foundation

actor NetworkClient {
    static let shared = NetworkClient()

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.httpMaximumConnectionsPerHost = 5
        self.session = URLSession(configuration: config)
    }

    func fetchString(url: String, encoding: String.Encoding? = nil) async throws -> String {
        guard let requestURL = URL(string: url) else {
            throw NetworkError.invalidURL
        }
        var request = URLRequest(url: requestURL)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.requestFailed
        }

        if let encoding = encoding {
            return String(data: data, encoding: encoding) ?? String(decoding: data, as: UTF8.self)
        }

        let detectedEncoding = detectEncoding(from: httpResponse, data: data)
        return String(data: data, encoding: detectedEncoding) ?? String(decoding: data, as: UTF8.self)
    }

    private func detectEncoding(from response: HTTPURLResponse, data: Data) -> String.Encoding {
        if let contentType = response.value(forHTTPHeaderField: "Content-Type"),
           contentType.lowercased().contains("gbk") || contentType.lowercased().contains("gb2312") || contentType.lowercased().contains("gb18030") {
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        }
        if let head = String(data: data.prefix(1024), encoding: .ascii),
           head.lowercased().contains("charset=gbk") || head.lowercased().contains("charset=gb2312") {
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        }
        return .utf8
    }
}

enum NetworkError: Error, LocalizedError {
    case invalidURL
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的URL"
        case .requestFailed: return "请求失败"
        }
    }
}
```

- [ ] **Step 3: Implement SourceImportService**

`NovelReader/Services/SourceImportService.swift`:

```swift
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
            throw ImportError.encodingFailed
        }
        return try importJSON(json)
    }

    private func fetchExistingURLs() throws -> Set<String> {
        let descriptor = FetchDescriptor<BookSource>()
        let existing = try modelContext.fetch(descriptor)
        return Set(existing.map { $0.sourceURL })
    }

    enum ImportError: Error, LocalizedError {
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .encodingFailed: return "文件编码错误"
            }
        }
    }
}
```

- [ ] **Step 4: Run tests**

Expected: all pass (45 + 3 = 48).

- [ ] **Step 5: Commit**

```bash
git add NovelReader/Services/NetworkClient.swift NovelReader/Services/SourceImportService.swift NovelReaderTests/SourceImportTests.swift
git commit -m "feat: add network client and book source import service"
```

---

## Task 6: Search Aggregation Service

**Files:**
- Create: `NovelReader/Services/SearchService.swift`

The SearchService coordinates searching across multiple enabled book sources in parallel, deduplicates by title+author, and returns aggregated results.

- [ ] **Step 1: Implement SearchService**

`NovelReader/Services/SearchService.swift`:

```swift
import Foundation
import SwiftData

struct AggregatedSearchResult: Identifiable {
    let id = UUID()
    let title: String
    let author: String
    let coverURL: String?
    var sources: [SourceMatch]

    struct SourceMatch: Identifiable {
        let id = UUID()
        let sourceName: String
        let sourceId: UUID
        let bookURL: String
        let source: LegadoSource
    }
}

@Observable
class SearchService {
    var results: [AggregatedSearchResult] = []
    var isSearching = false
    var searchError: String?

    private let modelContext: ModelContext
    private let engine = SourceEngine()
    private let network = NetworkClient.shared

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func search(keyword: String) async {
        guard !keyword.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        await MainActor.run {
            isSearching = true
            results = []
            searchError = nil
        }

        do {
            let bookSources = try fetchEnabledSources()
            var allResults: [(SearchResult, BookSource, LegadoSource)] = []

            await withTaskGroup(of: [(SearchResult, BookSource, LegadoSource)].self) { group in
                for bookSource in bookSources {
                    group.addTask { [self] in
                        do {
                            let legado = try LegadoSourceParser.parse(json: bookSource.ruleJSON)
                            guard let searchURL = engine.buildSearchURL(source: legado, keyword: keyword, page: 1) else {
                                return []
                            }
                            let html = try await network.fetchString(url: searchURL)
                            guard let searchRule = legado.searchRule else { return [] }
                            let results = try engine.parseSearchResults(html: html, rule: searchRule, baseURL: legado.url)
                            return results.map { ($0, bookSource, legado) }
                        } catch {
                            return []
                        }
                    }
                }
                for await taskResults in group {
                    allResults.append(contentsOf: taskResults)
                }
            }

            let aggregated = aggregateResults(allResults)
            await MainActor.run {
                results = aggregated
                isSearching = false
            }
        } catch {
            await MainActor.run {
                searchError = error.localizedDescription
                isSearching = false
            }
        }
    }

    private func aggregateResults(_ raw: [(SearchResult, BookSource, LegadoSource)]) -> [AggregatedSearchResult] {
        var grouped: [String: AggregatedSearchResult] = [:]

        for (result, bookSource, legado) in raw {
            let key = "\(result.title)|\(result.author)".lowercased()
            let match = AggregatedSearchResult.SourceMatch(
                sourceName: bookSource.name,
                sourceId: bookSource.id,
                bookURL: result.bookURL,
                source: legado
            )
            if var existing = grouped[key] {
                existing.sources.append(match)
                grouped[key] = existing
            } else {
                grouped[key] = AggregatedSearchResult(
                    title: result.title,
                    author: result.author,
                    coverURL: result.coverURL,
                    sources: [match]
                )
            }
        }
        return Array(grouped.values).sorted { $0.sources.count > $1.sources.count }
    }

    private func fetchEnabledSources() throws -> [BookSource] {
        var descriptor = FetchDescriptor<BookSource>()
        descriptor.predicate = #Predicate<BookSource> { $0.enabled == true }
        return try modelContext.fetch(descriptor)
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
xcodebuild build -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 17' -quiet
```

- [ ] **Step 3: Commit**

```bash
git add NovelReader/Services/SearchService.swift
git commit -m "feat: add search aggregation service with parallel source querying"
```

---

## Task 7: Search UI (3-Step Flow)

**Files:**
- Create: `NovelReader/Views/Search/SearchView.swift`
- Create: `NovelReader/Views/Search/SourceSelectView.swift`
- Create: `NovelReader/Views/Search/AddBookView.swift`
- Modify: `NovelReader/Views/Bookshelf/BookshelfView.swift`

- [ ] **Step 1: Create SearchView**

`NovelReader/Views/Search/SearchView.swift`:

```swift
import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""
    @State private var searchService: SearchService?
    @State private var selectedResult: AggregatedSearchResult?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                resultsList
            }
            .background(Color(.systemBackground))
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                if searchService == nil {
                    searchService = SearchService(modelContext: modelContext)
                }
            }
            .sheet(item: $selectedResult) { result in
                SourceSelectView(result: result)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("输入书名搜索", text: $keyword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { performSearch() }
                if !keyword.isEmpty {
                    Button { keyword = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button("搜索") { performSearch() }
                .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var resultsList: some View {
        Group {
            if searchService?.isSearching == true {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                    Text("搜索中...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else if let error = searchService?.searchError {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else if let results = searchService?.results, !results.isEmpty {
                List(results) { result in
                    Button {
                        selectedResult = result
                    } label: {
                        searchResultRow(result)
                    }
                }
                .listStyle(.plain)
            } else if searchService?.results.isEmpty == true {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("未找到相关书籍")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary.opacity(0.3))
                    Text("输入书名开始搜索")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    private func searchResultRow(_ result: AggregatedSearchResult) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: 45, height: 60)
                .overlay(
                    Text(String(result.title.prefix(1)))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(result.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(result.sources.count)个来源")
                .font(.caption)
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }

    private func performSearch() {
        guard !keyword.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task { await searchService?.search(keyword: keyword) }
    }
}
```

- [ ] **Step 2: Create SourceSelectView**

`NovelReader/Views/Search/SourceSelectView.swift`:

```swift
import SwiftUI
import SwiftData

struct SourceSelectView: View {
    let result: AggregatedSearchResult
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddBook = false
    @State private var selectedSource: AggregatedSearchResult.SourceMatch?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.systemGray5))
                            .frame(width: 60, height: 80)
                            .overlay(
                                Text(String(result.title.prefix(1)))
                                    .font(.title)
                                    .foregroundStyle(.secondary)
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.title)
                                .font(.headline)
                            Text(result.author)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("选择来源（\(result.sources.count)个）") {
                    ForEach(result.sources) { source in
                        Button {
                            selectedSource = source
                            showingAddBook = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(source.sourceName)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择来源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAddBook) {
                if let source = selectedSource {
                    AddBookView(
                        title: result.title,
                        author: result.author,
                        coverURL: result.coverURL,
                        sourceName: source.sourceName,
                        sourceId: source.sourceId,
                        bookURL: source.bookURL,
                        legadoSource: source.source
                    )
                }
            }
        }
    }
}
```

- [ ] **Step 3: Create AddBookView**

`NovelReader/Views/Search/AddBookView.swift`:

```swift
import SwiftUI
import SwiftData

struct AddBookView: View {
    let title: String
    let author: String
    let coverURL: String?
    let sourceName: String
    let sourceId: UUID
    let bookURL: String
    let legadoSource: LegadoSource

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var chapterCount = 0
    @State private var loadError: String?
    @State private var chapters: [ChapterInfo] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                bookInfo
                sourceInfo
                Spacer()
                addButton
            }
            .padding(20)
            .navigationTitle("添加到书架")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { await loadChapterInfo() }
        }
    }

    private var bookInfo: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
                .frame(width: 80, height: 110)
                .overlay(
                    Text(String(title.prefix(2)))
                        .font(.title2)
                        .foregroundStyle(.secondary)
                )

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title3.bold())
                Text(author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var sourceInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("来源")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(sourceName)
                    .font(.subheadline)
            }
            Divider()
            HStack {
                Text("章节数")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if let error = loadError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("\(chapterCount)")
                        .font(.subheadline)
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var addButton: some View {
        Button {
            addToBookshelf()
        } label: {
            Text("加入书架")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(chapterCount > 0 ? Color.blue : Color.gray)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(chapterCount == 0 || isLoading)
    }

    private func loadChapterInfo() async {
        isLoading = true
        loadError = nil

        do {
            let resolvedURL = SourceEngine().resolveURL(bookURL, base: legadoSource.url)
            let html = try await NetworkClient.shared.fetchString(url: resolvedURL)
            guard let tocRule = legadoSource.tocRule else {
                loadError = "书源缺少目录规则"
                isLoading = false
                return
            }
            let chapterInfos = try SourceEngine().parseChapterList(html: html, rule: tocRule, baseURL: legadoSource.url)
            await MainActor.run {
                chapters = chapterInfos
                chapterCount = chapterInfos.count
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = "加载失败"
                isLoading = false
            }
        }
    }

    private func addToBookshelf() {
        let book = Book(title: title, author: author, sourceType: .bookSource, totalChapters: chapterCount)
        book.sourceId = sourceId
        book.sourceBookURL = bookURL
        book.coverURL = coverURL
        modelContext.insert(book)

        for (i, info) in chapters.enumerated() {
            let chapter = Chapter(index: i, title: info.title)
            chapter.book = book
            chapter.sourceURL = SourceEngine().resolveURL(info.url, base: legadoSource.url)
            modelContext.insert(chapter)
        }

        dismiss()
    }
}
```

- [ ] **Step 4: Add search button to BookshelfView**

In `NovelReader/Views/Bookshelf/BookshelfView.swift`, add a search button and sheet. Add a `@State private var showingSearch = false` property, add a toolbar button with magnifyingglass icon, and add a `.sheet` for `SearchView`.

Find:
```swift
    @State private var showingFilePicker = false
    @State private var importError: String?
    @State private var showingError = false
```

Replace with:
```swift
    @State private var showingFilePicker = false
    @State private var showingSearch = false
    @State private var importError: String?
    @State private var showingError = false
```

Find:
```swift
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingFilePicker = true }) {
                        Image(systemName: "plus")
                            .foregroundStyle(.white)
                    }
                }
            }
```

Replace with:
```swift
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showingSearch = true }) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.white)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingFilePicker = true }) {
                        Image(systemName: "plus")
                            .foregroundStyle(.white)
                    }
                }
            }
```

Find (the `.sheet(isPresented: $showingFilePicker)` block):
```swift
            .sheet(isPresented: $showingFilePicker) {
```

Add BEFORE it:
```swift
            .sheet(isPresented: $showingSearch) {
                SearchView()
            }
```

- [ ] **Step 5: Build and verify**

```bash
xcodebuild build -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 17' -quiet
```

- [ ] **Step 6: Commit**

```bash
git add NovelReader/Views/Search/ NovelReader/Views/Bookshelf/BookshelfView.swift
git commit -m "feat: add 3-step search UI (search → pick source → add to bookshelf)"
```

---

## Task 8: Source Management UI

**Files:**
- Create: `NovelReader/Views/Sources/SourceListView.swift`
- Modify: `NovelReader/Views/Bookshelf/BookshelfView.swift`

- [ ] **Step 1: Create SourceListView**

`NovelReader/Views/Sources/SourceListView.swift`:

```swift
import SwiftUI
import SwiftData

struct SourceListView: View {
    @Query(sort: \BookSource.name) private var sources: [BookSource]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingImport = false
    @State private var importCount: Int?
    @State private var importError: String?
    @State private var showingResult = false

    var body: some View {
        NavigationStack {
            List {
                if sources.isEmpty {
                    emptyState
                } else {
                    ForEach(sources) { source in
                        sourceRow(source)
                    }
                    .onDelete(perform: deleteSources)
                }
            }
            .navigationTitle("书源管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingImport = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
            }
            .sheet(isPresented: $showingImport) {
                DocumentPicker(contentTypes: [.json, .plainText]) { url in
                    importSourceFile(url: url)
                }
            }
            .alert("导入结果", isPresented: $showingResult) {
                Button("确定") {}
            } message: {
                if let error = importError {
                    Text("导入失败：\(error)")
                } else if let count = importCount {
                    Text("成功导入 \(count) 个书源")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("暂无书源")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("点击右上角导入书源文件")
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .listRowBackground(Color.clear)
    }

    private func sourceRow(_ source: BookSource) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(source.name)
                    .font(.body)
                HStack(spacing: 8) {
                    Text(source.sourceURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let group = source.sourceGroup {
                        Text(group)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { source.enabled },
                set: { source.enabled = $0 }
            ))
            .labelsHidden()
        }
    }

    private func deleteSources(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(sources[index])
        }
    }

    private func importSourceFile(url: URL) {
        let service = SourceImportService(modelContext: modelContext)
        do {
            let count = try service.importFromFile(url: url)
            importCount = count
            importError = nil
        } catch {
            importError = error.localizedDescription
            importCount = nil
        }
        showingResult = true
    }
}
```

- [ ] **Step 2: Update DocumentPicker to support JSON content type**

The existing `DocumentPicker` in `NovelReader/Helpers/DocumentPicker.swift` currently only handles TXT. It needs to accept content types as a parameter. Check the current implementation and update to accept a `contentTypes` parameter with a default of `[.plainText]`:

Current init takes a callback. Update to:

```swift
import SwiftUI
import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let onPick: (URL) -> Void

    init(contentTypes: [UTType] = [.plainText], onPick: @escaping (URL) -> Void) {
        self.contentTypes = contentTypes
        self.onPick = onPick
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentType: contentTypes.first ?? .plainText, asCopy: true)
        if contentTypes.count > 1 {
            let multiPicker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
            multiPicker.delegate = context.coordinator
            return multiPicker
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
```

- [ ] **Step 3: Add source management button to BookshelfView**

In `NovelReader/Views/Bookshelf/BookshelfView.swift`, add `@State private var showingSources = false` and a toolbar item for source management.

Add to the state properties:
```swift
    @State private var showingSources = false
```

In the toolbar, add a new item between the search and plus buttons:
```swift
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button(action: { showingSources = true }) {
                            Image(systemName: "list.bullet.rectangle")
                                .foregroundStyle(.white)
                        }
                        Button(action: { showingFilePicker = true }) {
                            Image(systemName: "plus")
                                .foregroundStyle(.white)
                        }
                    }
                }
```

And add the sheet:
```swift
            .sheet(isPresented: $showingSources) {
                SourceListView()
            }
```

- [ ] **Step 4: Build and verify**

```bash
xcodebuild build -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 17' -quiet
```

- [ ] **Step 5: Run all tests**

```bash
xcodebuild test -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 17' -quiet 2>&1 | tail -5
```

- [ ] **Step 6: Commit**

```bash
git add NovelReader/Views/Sources/ NovelReader/Views/Bookshelf/BookshelfView.swift NovelReader/Helpers/DocumentPicker.swift
git commit -m "feat: add source management UI with import and enable/disable toggle"
```

---

## Task 9: Chapter Content Fetching in Reader

**Files:**
- Modify: `NovelReader/Views/Reader/ReaderView.swift`

When reading a book from a book source (not local file), the reader needs to fetch chapter content on demand via the network + SourceEngine.

- [ ] **Step 1: Update ReaderView to fetch content for book source chapters**

In `NovelReader/Views/Reader/ReaderView.swift`, add content fetching logic. When `currentChapter?.content` is nil and `currentChapter?.sourceURL` is non-nil, fetch and cache the content.

Add after the existing `@State` properties:
```swift
    @State private var isLoadingContent = false
    @State private var loadError: String?
```

Add a method:
```swift
    private func fetchChapterContentIfNeeded() {
        guard let chapter = currentChapter,
              chapter.content == nil,
              let sourceURL = chapter.sourceURL,
              !isLoadingContent else { return }

        isLoadingContent = true
        loadError = nil

        Task {
            do {
                let html = try await NetworkClient.shared.fetchString(url: sourceURL)
                if let sourceId = book.sourceId {
                    let descriptor = FetchDescriptor<BookSource>(predicate: #Predicate<BookSource> { $0.id == sourceId })
                    if let bookSource = try? modelContext.fetch(descriptor).first {
                        let legado = try LegadoSourceParser.parse(json: bookSource.ruleJSON)
                        if let contentRule = legado.contentRule {
                            let content = try SourceEngine().parseContent(html: html, rule: contentRule, baseURL: legado.url)
                            await MainActor.run {
                                chapter.content = content
                                chapter.isCached = true
                                isLoadingContent = false
                            }
                            return
                        }
                    }
                }
                await MainActor.run {
                    loadError = "无法解析内容"
                    isLoadingContent = false
                }
            } catch {
                await MainActor.run {
                    loadError = "加载失败"
                    isLoadingContent = false
                }
            }
        }
    }
```

Add a loading overlay to `readingContent`. In the `readingContent` view, wrap the existing `ScrollView` with a check:

```swift
    private var readingContent: some View {
        ZStack {
            if isLoadingContent {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("加载中...")
                        .font(.subheadline)
                        .foregroundStyle(settings.theme.textColor.opacity(0.6))
                }
            } else if let error = loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(settings.theme.textColor.opacity(0.5))
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(settings.theme.textColor.opacity(0.6))
                    Button("重试") { fetchChapterContentIfNeeded() }
                        .foregroundStyle(.blue)
                }
            } else {
                // existing ScrollView content
            }
        }
        .onAppear { fetchChapterContentIfNeeded() }
        .onChange(of: currentChapterIndex) { _, _ in fetchChapterContentIfNeeded() }
    }
```

Keep all existing `readingContent` ScrollView code inside the `else` branch.

- [ ] **Step 2: Build and verify**

```bash
xcodebuild build -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 17' -quiet
```

- [ ] **Step 3: Run all tests**

```bash
xcodebuild test -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 17' -quiet 2>&1 | tail -5
```

Expected: all existing tests pass.

- [ ] **Step 4: Commit**

```bash
git add NovelReader/Views/Reader/ReaderView.swift
git commit -m "feat: add on-demand chapter content fetching for book source books"
```

---

## Summary

After completing all 9 tasks, the app adds:

- **SwiftSoup dependency** for HTML/CSS parsing
- **Legado rule parser** — parse Legado JSON format into Swift structs
- **Rule executor** — CSS selectors, regex, fallback rules via SwiftSoup
- **Source engine** — search results, chapter list, content parsing
- **Network client** — URLSession with encoding detection, GBK support
- **Source import** — import Legado JSON files, dedup by URL
- **Search aggregation** — parallel search across all enabled sources, dedup by title+author
- **3-step search UI** — search → pick source → confirm & add to bookshelf
- **Source management** — list, enable/disable, delete, import sources
- **On-demand content fetch** — reader fetches chapter content from source when not cached
