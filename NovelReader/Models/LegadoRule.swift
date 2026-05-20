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
