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
            text = try elements.first()?.text() ?? ""
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
