import Foundation
import SwiftSoup

class RuleExecutor {

    func getElements(html: String, rule: String, baseURL: String = "") throws -> [Element] {
        let doc = try SwiftSoup.parse(html, baseURL)
        let stripped = stripJSFromRule(rule)
        let (cleanRule, _, _) = splitRegex(stripped)
        if isLegadoFormat(cleanRule) {
            return try legadoSelect(root: doc, rule: cleanRule)
        }
        let selector = extractCSSSelector(from: stripped)
        return try doc.select(selector).array()
    }

    func getString(html: String, rule: String, baseURL: String = "") throws -> String? {
        let doc = try SwiftSoup.parse(html, baseURL)
        return try evaluateRule(root: doc, rule: rule, baseURL: baseURL)
    }

    func getString(element: Element, rule: String, baseURL: String = "") throws -> String? {
        return try evaluateRule(root: element, rule: rule, baseURL: baseURL)
    }

    // MARK: - Rule evaluation

    private func stripJSFromRule(_ rule: String) -> String {
        var s = rule
        while let start = s.range(of: "<js>"), let end = s.range(of: "</js>") {
            s = String(s[..<start.lowerBound]) + String(s[end.upperBound...])
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private func evaluateRule(root: Element, rule: String, baseURL: String) throws -> String? {
        let parts = rule.components(separatedBy: "||")
        for part in parts {
            let trimmed = stripJSFromRule(part.trimmingCharacters(in: .whitespaces))
            if trimmed.isEmpty || trimmed.hasPrefix("@js:") { continue }

            var mainRule = trimmed
            var jsPostCode: String?
            if let jsRange = mainRule.range(of: "@js:") {
                jsPostCode = String(mainRule[jsRange.upperBound...])
                mainRule = String(mainRule[..<jsRange.lowerBound])
            }

            let andParts = mainRule.components(separatedBy: "&&")
            var combined = ""
            for (i, andPart) in andParts.enumerated() {
                if let val = try executeSingle(root: root, rule: andPart.trimmingCharacters(in: .whitespaces)), !val.isEmpty {
                    if i > 0 && !combined.isEmpty { combined += " " }
                    combined += val
                }
            }
            if !combined.isEmpty {
                if let jsCode = jsPostCode {
                    if let jsResult = JSExecutor.postProcess(jsCode, result: combined, baseUrl: baseURL) {
                        return jsResult
                    }
                }
                return combined
            }
        }
        return nil
    }

    private func executeSingle(root: Element, rule: String) throws -> String? {
        let (cleanRule, regexPattern, regexReplacement) = splitRegex(rule)

        var text: String
        if isLegadoFormat(cleanRule) {
            text = try legadoGetString(root: root, rule: cleanRule)
        } else {
            text = try cssGetString(root: root, rule: cleanRule)
        }

        if let pattern = regexPattern {
            text = applyRegex(text: text, pattern: pattern, replacement: regexReplacement ?? "")
        }
        return text.isEmpty ? nil : text
    }

    // MARK: - Legado default rule format

    private func isLegadoFormat(_ rule: String) -> Bool {
        let r = rule.trimmingCharacters(in: .whitespaces)
        return r.hasPrefix("tag.") || r.hasPrefix("class.") || r.hasPrefix("id.") ||
               r.contains("@tag.") || r.contains("@class.") || r.contains("@id.")
    }

    private func legadoSelect(root: Element, rule: String) throws -> [Element] {
        let segments = splitLegadoSegments(rule)
        var current: [Element] = [root]

        for seg in segments {
            current = try applyLegadoSelector(elements: current, segment: seg)
        }
        return current
    }

    private func legadoGetString(root: Element, rule: String) throws -> String {
        let segments = splitLegadoSegments(rule)
        guard !segments.isEmpty else { return "" }

        var selectorSegments: [String] = []
        var attrName = "text"

        for (i, seg) in segments.enumerated() {
            if isLegadoSelector(seg) {
                selectorSegments.append(seg)
            } else {
                attrName = seg
                break
            }
            if i == segments.count - 1 {
                attrName = "text"
            }
        }

        var current: [Element] = [root]
        for seg in selectorSegments {
            current = try applyLegadoSelector(elements: current, segment: seg)
        }

        guard let target = current.first else { return "" }
        return try getAttrValue(element: target, attr: attrName)
    }

    private func splitLegadoSegments(_ rule: String) -> [String] {
        var segments: [String] = []
        var current = ""

        let chars = Array(rule)
        var i = 0
        while i < chars.count {
            if chars[i] == "@" && i + 1 < chars.count {
                if !current.isEmpty {
                    segments.append(current)
                    current = ""
                }
            } else {
                current.append(chars[i])
            }
            i += 1
        }
        if !current.isEmpty {
            segments.append(current)
        }
        return segments
    }

    private func isLegadoSelector(_ segment: String) -> Bool {
        return segment.hasPrefix("tag.") || segment.hasPrefix("class.") || segment.hasPrefix("id.")
    }

    private func applyLegadoSelector(elements: [Element], segment: String) throws -> [Element] {
        if segment.hasPrefix("tag.") {
            let rest = String(segment.dropFirst(4))
            let (name, index, range) = parseSelectorPart(rest)
            return try selectByTag(elements: elements, tag: name, index: index, range: range)
        } else if segment.hasPrefix("class.") {
            let rest = String(segment.dropFirst(6))
            let (name, index, range) = parseSelectorPart(rest)
            return try selectByClass(elements: elements, className: name, index: index, range: range)
        } else if segment.hasPrefix("id.") {
            let rest = String(segment.dropFirst(3))
            let (name, index, _) = parseSelectorPart(rest)
            return try selectById(elements: elements, id: name, index: index)
        }
        return elements
    }

    private func parseSelectorPart(_ str: String) -> (name: String, index: Int?, range: (Int, Int)?) {
        if let bracketStart = str.firstIndex(of: "[") {
            let name = String(str[str.startIndex..<bracketStart])
            let end = str.lastIndex(of: "]") ?? str.endIndex
            let content = String(str[str.index(after: bracketStart)..<end])
            if content.contains(":") {
                let parts = content.components(separatedBy: ":")
                if let s = Int(parts[0]), let e = Int(parts[1]) {
                    return (name, nil, (s, e))
                }
            }
            return (name, Int(content), nil)
        }

        let parts = str.components(separatedBy: ".")
        if parts.count >= 2, let idx = Int(parts.last!) {
            let name = parts.dropLast().joined(separator: ".")
            return (name, idx, nil)
        }
        return (str, nil, nil)
    }

    private func selectByTag(elements: [Element], tag: String, index: Int?, range: (Int, Int)?) throws -> [Element] {
        var found: [Element] = []
        for el in elements {
            found.append(contentsOf: try el.getElementsByTag(tag).array())
        }
        return applyIndexOrRange(found, index: index, range: range)
    }

    private func selectByClass(elements: [Element], className: String, index: Int?, range: (Int, Int)?) throws -> [Element] {
        var found: [Element] = []
        for el in elements {
            found.append(contentsOf: try el.getElementsByClass(className).array())
        }
        return applyIndexOrRange(found, index: index, range: range)
    }

    private func selectById(elements: [Element], id: String, index: Int? = nil) throws -> [Element] {
        var found: [Element] = []
        for el in elements {
            if let match = try el.getElementById(id) {
                found.append(match)
            }
        }
        if let idx = index {
            let resolved = idx < 0 ? found.count + idx : idx
            guard resolved >= 0, resolved < found.count else { return [] }
            return [found[resolved]]
        }
        return found
    }

    private func applyIndexOrRange(_ elements: [Element], index: Int?, range: (Int, Int)?) -> [Element] {
        if let idx = index {
            let resolved = idx < 0 ? elements.count + idx : idx
            guard resolved >= 0, resolved < elements.count else { return [] }
            return [elements[resolved]]
        }
        if let (start, end) = range {
            guard !elements.isEmpty else { return [] }
            let s = start < 0 ? elements.count + start : start
            let e = end < 0 ? elements.count + end : end
            if s > e {
                let lower = max(e, 0)
                let upper = min(s, elements.count - 1)
                guard lower <= upper else { return [] }
                return Array(elements[lower...upper].reversed())
            } else {
                let lower = max(s, 0)
                let upper = min(e, elements.count - 1)
                guard lower <= upper else { return [] }
                return Array(elements[lower...upper])
            }
        }
        return elements
    }

    // MARK: - CSS selector path

    private func cssGetString(root: Element, rule: String) throws -> String {
        let (selector, attr) = splitAttribute(rule)

        let target: Element
        if selector.isEmpty || selector == "@" || selector == "body" {
            target = root
        } else {
            guard let found = try root.select(selector).first() else { return "" }
            target = found
        }
        return try getAttrValue(element: target, attr: attr)
    }

    private func extractCSSSelector(from rule: String) -> String {
        let (cssRule, _, _) = splitRegex(rule)
        let (selector, _) = splitAttribute(cssRule)
        return selector
    }

    // MARK: - Common helpers

    private func getAttrValue(element: Element, attr: String) throws -> String {
        switch attr {
        case "text", "textNodes", "":
            return try element.text()
        case "html", "innerHTML":
            return try element.html()
        case "outerHtml":
            return try element.outerHtml()
        default:
            return try element.attr(attr)
        }
    }

    private func splitAttribute(_ rule: String) -> (selector: String, attr: String) {
        guard let atIndex = rule.lastIndex(of: "@") else {
            switch rule {
            case "text", "textNodes", "html", "innerHTML", "outerHtml", "href", "src":
                return ("", rule)
            default:
                return (rule, "text")
            }
        }
        let selector = String(rule[rule.startIndex..<atIndex])
        let attr = String(rule[rule.index(after: atIndex)...])
        return (selector.isEmpty ? "body" : selector, attr)
    }

    private func splitRegex(_ rule: String) -> (mainRule: String, pattern: String?, replacement: String?) {
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
}
