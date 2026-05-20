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
            let name = try ruleExecutor.getString(element: element, rule: rule.chapterName ?? "a@text") ?? ""
            let url = try ruleExecutor.getString(element: element, rule: rule.chapterUrl ?? "a@href") ?? ""
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
