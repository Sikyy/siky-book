import Foundation

struct ChapterSplitter {
    struct RawChapter {
        let title: String
        let content: String
    }

    static func split(_ text: String) -> [RawChapter] {
        let pattern = #"^[　\s]*(第[零一二三四五六七八九十百千万0-9]+[章节回集卷部]\s*.+)$"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            return [RawChapter(title: "全文", content: text.trimmingCharacters(in: .whitespacesAndNewlines))]
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        guard !matches.isEmpty else {
            return [RawChapter(title: "全文", content: text.trimmingCharacters(in: .whitespacesAndNewlines))]
        }

        var chapters: [RawChapter] = []

        let firstStart = matches[0].range.location
        if firstStart > 0 {
            let prologue = nsText.substring(with: NSRange(location: 0, length: firstStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !prologue.isEmpty {
                chapters.append(RawChapter(title: "序", content: prologue))
            }
        }

        for i in 0..<matches.count {
            let titleRange = matches[i].range(at: 1)
            let title = nsText.substring(with: titleRange)
                .trimmingCharacters(in: .whitespaces)

            let contentStart = matches[i].range.location + matches[i].range.length
            let contentEnd = (i + 1 < matches.count) ? matches[i + 1].range.location : nsText.length
            let contentRange = NSRange(location: contentStart, length: contentEnd - contentStart)
            let content = nsText.substring(with: contentRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            chapters.append(RawChapter(title: title, content: content))
        }

        return chapters
    }
}
