import Foundation
import SwiftSoup

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

struct SearchRequest {
    let url: String
    let method: String
    let body: String?
    let headers: [String: String]
    let charset: String?
}

class SourceEngine {
    private let ruleExecutor = RuleExecutor()

    func buildSearchRequest(source: LegadoSource, keyword: String, page: Int) -> SearchRequest? {
        guard var searchUrl = source.searchURL,
              !searchUrl.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        searchUrl = stripJSTags(searchUrl)

        let trimmed = searchUrl.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("@js:") {
            let jsCode = String(trimmed.dropFirst(4))
            guard let jsResult = JSExecutor.evalSearchUrl(jsCode, baseUrl: source.url, keyword: keyword, page: page) else {
                return nil
            }
            searchUrl = jsResult
        }

        if searchUrl.contains("\n") {
            let lines = searchUrl.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            var picked: String?
            for line in lines {
                if !line.hasPrefix("@js:") {
                    picked = line
                    break
                }
            }
            if picked == nil, let jsLine = lines.first(where: { $0.hasPrefix("@js:") }) {
                let jsCode = String(jsLine.dropFirst(4))
                if let jsResult = JSExecutor.evalSearchUrl(jsCode, baseUrl: source.url, keyword: keyword, page: page) {
                    picked = jsResult
                }
            }
            guard let first = picked else { return nil }
            searchUrl = first
        }

        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        searchUrl = searchUrl.replacingOccurrences(of: "baseUrl", with: source.url)
        searchUrl = searchUrl.replacingOccurrences(of: "{{key}}", with: encoded)
        searchUrl = searchUrl.replacingOccurrences(of: "{{page}}", with: String(page))

        var urlPart = searchUrl
        var method = "GET"
        var body: String?
        var headers: [String: String] = [:]
        var charset: String?

        if let sepRange = searchUrl.range(of: ",{") {
            urlPart = String(searchUrl[..<sepRange.lowerBound])
            var jsonStr = String(searchUrl[searchUrl.index(after: sepRange.lowerBound)...])
            jsonStr = fixLegadoJSON(jsonStr)
            if let data = jsonStr.data(using: .utf8),
               let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                method = (config["method"] as? String)?.uppercased() ?? "GET"
                if var b = config["body"] as? String {
                    b = b.replacingOccurrences(of: "{{key}}", with: encoded)
                    b = b.replacingOccurrences(of: "{{page}}", with: String(page))
                    body = b
                }
                charset = config["charset"] as? String
                if let h = config["headers"] as? [String: String] {
                    headers = h
                }
            }
        }

        if let headerJSON = source.header,
           let hData = headerJSON.data(using: .utf8),
           let hDict = try? JSONSerialization.jsonObject(with: hData) as? [String: Any] {
            for (key, value) in hDict {
                guard headers[key] == nil, let strValue = value as? String else { continue }
                headers[key] = strValue.replacingOccurrences(of: "baseUrl", with: source.url)
            }
        }

        let resolvedURL: String
        if urlPart.hasPrefix("http://") || urlPart.hasPrefix("https://") {
            resolvedURL = urlPart
        } else {
            let base = source.url.hasSuffix("/") ? String(source.url.dropLast()) : source.url
            resolvedURL = base + (urlPart.hasPrefix("/") ? urlPart : "/" + urlPart)
        }

        return SearchRequest(url: resolvedURL, method: method, body: body, headers: headers, charset: charset)
    }

    private func fixLegadoJSON(_ str: String) -> String {
        var result = ""
        var inDoubleQuote = false
        for ch in str {
            if ch == "\"" { inDoubleQuote.toggle() }
            if ch == "'" && !inDoubleQuote {
                result.append("\"")
            } else {
                result.append(ch)
            }
        }
        return result
    }

    func stripJSTags(_ str: String) -> String {
        var s = str
        if let start = s.range(of: "<js>"), let end = s.range(of: "</js>") {
            let content = String(s[start.upperBound..<end.lowerBound])
            s = String(s[..<start.lowerBound]) + content + String(s[end.upperBound...])
        }
        let semicolonSuffix = s.range(of: ";result")
        if let r = semicolonSuffix {
            s = String(s[..<r.lowerBound])
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    func parseSearchResults(response: String, rule: LegadoSource.SearchRule, baseURL: String) throws -> [SearchResult] {
        guard let listRule = rule.bookList else { return [] }
        if isJSONRule(listRule) || isJSONResponse(response) {
            let jsonResults = parseJSONSearchResults(json: response, rule: rule, baseURL: baseURL)
            if !jsonResults.isEmpty || isJSONResponse(response) { return jsonResults }
        }
        let elements = try ruleExecutor.getElements(html: response, rule: listRule, baseURL: baseURL)
        return try elements.compactMap { element in
            guard let title = try ruleExecutor.getString(element: element, rule: rule.name ?? "@text", baseURL: baseURL),
                  !title.isEmpty else { return nil }
            let author = try ruleExecutor.getString(element: element, rule: rule.author ?? ".author@text", baseURL: baseURL) ?? ""
            let bookURL = try ruleExecutor.getString(element: element, rule: rule.bookUrl ?? "a@href", baseURL: baseURL) ?? ""
            let coverURL = try ruleExecutor.getString(element: element, rule: rule.coverUrl ?? "img@src", baseURL: baseURL)
            let kind = rule.kind != nil ? try ruleExecutor.getString(element: element, rule: rule.kind!, baseURL: baseURL) : nil
            let intro = rule.intro != nil ? try ruleExecutor.getString(element: element, rule: rule.intro!, baseURL: baseURL) : nil
            return SearchResult(title: title, author: author, bookURL: bookURL, coverURL: coverURL, kind: kind, intro: intro)
        }
    }

    func parseChapterList(response: String, rule: LegadoSource.TocRule, baseURL: String) throws -> [ChapterInfo] {
        guard let listRule = rule.chapterList else { return [] }
        if isJSONRule(listRule) || isJSONResponse(response) {
            let jsonResult = parseJSONChapterList(json: response, rule: rule, baseURL: baseURL)
            if !jsonResult.isEmpty || isJSONResponse(response) { return jsonResult }
        }
        do {
            let elements = try ruleExecutor.getElements(html: response, rule: listRule, baseURL: baseURL)
            return try elements.enumerated().compactMap { _, element in
                let name = try ruleExecutor.getString(element: element, rule: rule.chapterName ?? "a@text", baseURL: baseURL) ?? ""
                let url = try ruleExecutor.getString(element: element, rule: rule.chapterUrl ?? "a@href", baseURL: baseURL) ?? ""
                guard !name.isEmpty else { return nil }
                return ChapterInfo(title: name, url: url)
            }
        } catch {
            let jsonFallback = parseJSONChapterList(json: response, rule: rule, baseURL: baseURL)
            if !jsonFallback.isEmpty { return jsonFallback }
            throw error
        }
    }

    /// Parse nextTocUrl from a TOC page for pagination
    func parseNextTocUrl(response: String, rule: String, baseURL: String) -> String? {
        if isJSONRule(rule) || isJSONResponse(response) {
            if let data = response.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data),
               let val = evaluateJSONPath(rule, in: json) {
                let str = stringValue(val)
                return str.isEmpty ? nil : str
            }
        }
        guard let url = try? ruleExecutor.getString(html: response, rule: rule, baseURL: baseURL),
              !url.isEmpty else {
            return nil
        }
        return url
    }

    func parseContent(response: String, rule: LegadoSource.ContentRule, baseURL: String = "") throws -> String? {
        guard let contentRule = rule.content else { return nil }
        if isJSONRule(contentRule) || isJSONResponse(response) {
            if let data = response.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data),
               let result = jsonString(from: json, rule: contentRule, baseUrl: baseURL) {
                return Self.removeAdLines(cleanContentText(result))
            }
            if isJSONResponse(response) { return nil }
        }
        let raw = try ruleExecutor.getString(html: response, rule: contentRule, baseURL: baseURL)
        guard let raw else { return nil }
        return Self.removeAdLines(cleanContentText(raw))
    }

    private func cleanContentText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("<") else { return trimmed }
        guard let doc = try? SwiftSoup.parseBodyFragment(trimmed),
              let body = doc.body() else { return trimmed }

        try? body.select("script, style").remove()

        var paragraphs: [String] = []
        for node in body.getChildNodes() {
            if let element = node as? Element {
                if let t = try? element.text(), !t.trimmingCharacters(in: .whitespaces).isEmpty {
                    paragraphs.append(t.trimmingCharacters(in: .whitespaces))
                }
            } else if let textNode = node as? TextNode {
                let t = textNode.text().trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty {
                    paragraphs.append(t)
                }
            }
        }

        if paragraphs.isEmpty {
            return (try? body.text()) ?? trimmed
        }
        return paragraphs.joined(separator: "\n")
    }

    /// Remove common ad/promotional lines injected by book sources
    static func removeAdLines(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let filtered = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return true }
            return !isAdLine(trimmed)
        }
        return filtered.joined(separator: "\n")
    }

    private static func isAdLine(_ line: String) -> Bool {
        // Known ad prefixes — very high confidence
        let adPrefixes = [
            "最新网址", "本站网址", "本站域名", "手机阅读网址",
            "天才一秒记住", "一秒记住", "新笔趣阁", "笔趣阁",
            "请收藏本站", "请记住本站", "最快更新",
        ]
        for prefix in adPrefixes {
            if line.hasPrefix(prefix) { return true }
        }

        // Check if line contains a URL
        let lower = line.lowercased()
        let hasURL = lower.contains("www.") ||
                     lower.contains("http://") ||
                     lower.contains("https://")
        guard hasURL else { return false }

        // URL + promotional keyword = ad
        let adKeywords = ["网址", "域名", "收藏", "记住", "访问", "书签"]
        for keyword in adKeywords {
            if line.contains(keyword) { return true }
        }

        // Short line that's mostly a URL (no story-text punctuation)
        if !line.contains("。") && !line.contains("，") &&
           !line.contains("\u{201C}") && !line.contains("\u{201D}") &&
           line.count < 100 {
            return true
        }

        return false
    }

    private func isJSONResponse(_ response: String) -> Bool {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
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

    // MARK: - JSONPath

    private func isJSONRule(_ rule: String) -> Bool {
        let trimmed = rule.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("$.") || trimmed.hasPrefix("$[") || trimmed.contains("{{$.")
    }

    private func evaluateJSONPath(_ path: String, in json: Any) -> Any? {
        let clean: String
        if path.hasPrefix("$.") {
            clean = String(path.dropFirst(2))
        } else if path.hasPrefix("$[") {
            clean = String(path.dropFirst(1))
        } else {
            return nil
        }
        guard !clean.isEmpty else { return json }

        var current: Any = json
        for part in splitJSONPath(clean) {
            if let idx = Int(part) {
                guard let arr = current as? [Any], idx >= 0, idx < arr.count else { return nil }
                current = arr[idx]
            } else {
                guard let dict = current as? [String: Any], let val = dict[part] else { return nil }
                current = val
            }
        }
        return current
    }

    private func splitJSONPath(_ path: String) -> [String] {
        var parts: [String] = []
        var buf = ""
        for ch in path {
            if ch == "." || ch == "[" {
                if !buf.isEmpty { parts.append(buf); buf = "" }
            } else if ch == "]" {
                if !buf.isEmpty { parts.append(buf); buf = "" }
            } else {
                buf.append(ch)
            }
        }
        if !buf.isEmpty { parts.append(buf) }
        return parts
    }

    private func jsonString(from json: Any, rule: String, baseUrl: String = "") -> String? {
        let parts = rule.components(separatedBy: "||")
        for part in parts {
            var trimmed = part.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("@js:") {
                let jsCode = String(trimmed.dropFirst(4))
                let input = stringValue(json)
                if let jsResult = JSExecutor.postProcess(jsCode, result: input, baseUrl: baseUrl) {
                    return jsResult
                }
                continue
            }

            var jsPostCode: String?
            if let jsRange = trimmed.range(of: "@js:") {
                jsPostCode = String(trimmed[jsRange.upperBound...])
                trimmed = String(trimmed[..<jsRange.lowerBound])
            }

            let (pathRule, regexPattern, regexReplacement) = splitRegex(trimmed)

            var result: String?
            if pathRule.contains("{{$.") {
                result = expandTemplate(pathRule, element: json)
            } else if isJSONRule(pathRule) {
                if let val = evaluateJSONPath(pathRule, in: json) {
                    result = stringValue(val)
                }
            }

            if var text = result, !text.isEmpty {
                if let pattern = regexPattern {
                    text = applyRegex(text: text, pattern: pattern, replacement: regexReplacement ?? "")
                }
                if let jsCode = jsPostCode {
                    if let jsResult = JSExecutor.postProcess(jsCode, result: text, baseUrl: baseUrl) {
                        return jsResult
                    }
                }
                return text
            }
        }
        return nil
    }

    private func expandTemplate(_ template: String, element: Any) -> String? {
        var result = template
        let regex = try? NSRegularExpression(pattern: #"\{\{\$\.([^}]+)\}\}"#)
        let nsString = template as NSString
        let matches = regex?.matches(in: template, range: NSRange(location: 0, length: nsString.length)) ?? []
        for match in matches.reversed() {
            let fullRange = match.range(at: 0)
            let pathRange = match.range(at: 1)
            let path = nsString.substring(with: pathRange)
            let value: String
            if let val = evaluateJSONPath("$." + path, in: element) {
                value = stringValue(val)
            } else {
                value = ""
            }
            result = (result as NSString).replacingCharacters(in: fullRange, with: value)
        }
        return result.isEmpty ? nil : result
    }

    private func stringValue(_ val: Any) -> String {
        if let s = val as? String { return s }
        if let n = val as? NSNumber { return n.stringValue }
        if val is NSNull { return "" }
        return "\(val)"
    }

    private func splitRegex(_ rule: String) -> (path: String, pattern: String?, replacement: String?) {
        let parts = rule.components(separatedBy: "##")
        if parts.count >= 3 { return (parts[0], parts[1], parts[2]) }
        if parts.count == 2 { return (parts[0], parts[1], "") }
        return (rule, nil, nil)
    }

    private func applyRegex(text: String, pattern: String, replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }

    // MARK: - JSON Parsing

    private func parseJSONSearchResults(json: String, rule: LegadoSource.SearchRule, baseURL: String) -> [SearchResult] {
        guard let listRule = rule.bookList,
              let data = json.data(using: .utf8),
              let jsonObj = try? JSONSerialization.jsonObject(with: data) else { return [] }

        guard let elements = evaluateJSONPath(listRule, in: jsonObj) as? [Any] else { return [] }

        return elements.compactMap { element in
            guard let title = jsonString(from: element, rule: rule.name ?? "$.name", baseUrl: baseURL),
                  !title.isEmpty else { return nil }
            let author = jsonString(from: element, rule: rule.author ?? "$.author", baseUrl: baseURL) ?? ""
            let bookURL = jsonString(from: element, rule: rule.bookUrl ?? "", baseUrl: baseURL) ?? ""
            let coverURL = jsonString(from: element, rule: rule.coverUrl ?? "", baseUrl: baseURL)
            let kind = rule.kind != nil ? jsonString(from: element, rule: rule.kind!, baseUrl: baseURL) : nil
            let intro = rule.intro != nil ? jsonString(from: element, rule: rule.intro!, baseUrl: baseURL) : nil
            return SearchResult(title: title, author: author, bookURL: bookURL, coverURL: coverURL, kind: kind, intro: intro)
        }
    }

    private func parseJSONChapterList(json: String, rule: LegadoSource.TocRule, baseURL: String) -> [ChapterInfo] {
        guard let listRule = rule.chapterList,
              let data = json.data(using: .utf8),
              let jsonObj = try? JSONSerialization.jsonObject(with: data) else { return [] }

        guard let elements = evaluateJSONPath(listRule, in: jsonObj) as? [Any] else { return [] }

        return elements.compactMap { element in
            let name = jsonString(from: element, rule: rule.chapterName ?? "$.name", baseUrl: baseURL) ?? ""
            let url = jsonString(from: element, rule: rule.chapterUrl ?? "$.url", baseUrl: baseURL) ?? ""
            guard !name.isEmpty else { return nil }
            return ChapterInfo(title: name, url: url)
        }
    }
}
