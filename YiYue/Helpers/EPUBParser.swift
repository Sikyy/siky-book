import Foundation
import SwiftSoup

struct ParsedEPUB {
    struct Chapter { let title: String; let text: String }
    var title: String
    var author: String
    var coverData: Data?
    var chapters: [Chapter]
}

enum EPUBError: LocalizedError {
    case notEPUB, noContent
    var errorDescription: String? {
        switch self {
        case .notEPUB: return "不是有效的 EPUB 文件"
        case .noContent: return "EPUB 里没有可读的正文"
        }
    }
}

enum EPUBParser {
    static func parse(data: Data, fallbackTitle: String) throws -> ParsedEPUB {
        let zip: ZipReader
        do { zip = try ZipReader(data: data) } catch { throw EPUBError.notEPUB }
        guard let containerData = try? zip.read("META-INF/container.xml"),
              let containerXML = String(data: containerData, encoding: .utf8) else { throw EPUBError.notEPUB }
        let container = try SwiftSoup.parse(containerXML, "", Parser.xmlParser())
        guard let opfPath = try container.select("rootfile").first()?.attr("full-path"), !opfPath.isEmpty,
              let opfData = try? zip.read(opfPath) else { throw EPUBError.notEPUB }
        let opf = try SwiftSoup.parse(String(decoding: opfData, as: UTF8.self), "", Parser.xmlParser())
        let opfDir = (opfPath as NSString).deletingLastPathComponent

        func resolve(_ href: String, from dir: String) -> String {
            let clean = (href.removingPercentEncoding ?? href).components(separatedBy: "#")[0]
            var parts = dir.isEmpty ? [] : dir.components(separatedBy: "/")
            for seg in clean.components(separatedBy: "/") {
                if seg == ".." { _ = parts.popLast() } else if seg != "." && !seg.isEmpty { parts.append(seg) }
            }
            return parts.joined(separator: "/")
        }

        let title = (try? opf.select("metadata > dc|title, metadata > title").first()?.text()) ?? nil
        let author = (try? opf.select("metadata > dc|creator, metadata > creator").first()?.text()) ?? nil

        // manifest
        var manifest: [String: (href: String, type: String, props: String)] = [:]
        for item in try opf.select("manifest > item") {
            manifest[try item.attr("id")] = (try item.attr("href"), try item.attr("media-type"), try item.attr("properties"))
        }

        // cover
        var coverData: Data?
        var coverPath: String?
        if let metaCover = try opf.select("meta[name=cover]").first()?.attr("content"), let m = manifest[metaCover] {
            coverPath = resolve(m.href, from: opfDir)
        } else if let m = manifest.values.first(where: { $0.props.contains("cover-image") }) {
            coverPath = resolve(m.href, from: opfDir)
        }
        if let cp = coverPath { coverData = try? zip.read(cp) }

        // TOC titles: nav.xhtml (EPUB3) or toc.ncx (EPUB2)
        var tocTitles: [String: String] = [:]
        if let nav = manifest.values.first(where: { $0.props.contains("nav") }) {
            let navPath = resolve(nav.href, from: opfDir)
            if let d = try? zip.read(navPath),
               let doc = try? SwiftSoup.parse(String(decoding: d, as: UTF8.self)) {
                let navDir = (navPath as NSString).deletingLastPathComponent
                for a in (try? doc.select("nav a[href]").array()) ?? [] {
                    let key = resolve((try? a.attr("href")) ?? "", from: navDir)
                    if tocTitles[key] == nil, let t = try? a.text(), !t.isEmpty { tocTitles[key] = t }
                }
            }
        }
        if tocTitles.isEmpty,
           let ncx = manifest.values.first(where: { $0.type == "application/x-dtbncx+xml" }) {
            let ncxPath = resolve(ncx.href, from: opfDir)
            if let d = try? zip.read(ncxPath),
               let doc = try? SwiftSoup.parse(String(decoding: d, as: UTF8.self), "", Parser.xmlParser()) {
                let ncxDir = (ncxPath as NSString).deletingLastPathComponent
                for p in (try? doc.select("navPoint").array()) ?? [] {
                    guard let src = try? p.select("content").first()?.attr("src"),
                          let label = try? p.select("navLabel > text").first()?.text(), !label.isEmpty else { continue }
                    let key = resolve(src, from: ncxDir)
                    if tocTitles[key] == nil { tocTitles[key] = label }
                }
            }
        }

        // chapters in spine order
        var chapters: [ParsedEPUB.Chapter] = []
        for ref in try opf.select("spine > itemref") {
            guard let item = manifest[try ref.attr("idref")] else { continue }
            guard item.type.contains("html") || item.type.contains("xml") else { continue }
            if item.props.contains("nav") { continue }
            let path = resolve(item.href, from: opfDir)
            guard let d = try? zip.read(path) else { continue }
            let html = String(data: d, encoding: .utf8) ?? EncodingDetector.decodeToString(d)
            guard let doc = try? SwiftSoup.parse(html) else { continue }
            let text = bodyText(doc)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 { continue }
            var chTitle = tocTitles[path]
            if chTitle == nil { chTitle = (try? doc.select("h1, h2, h3").first()?.text()).flatMap { $0.isEmpty ? nil : $0 } }
            if chTitle == nil { chTitle = (try? doc.title()).flatMap { $0.isEmpty ? nil : $0 } }
            chapters.append(.init(title: chTitle ?? "第\(chapters.count + 1)节", text: text))
        }
        guard !chapters.isEmpty else { throw EPUBError.noContent }
        return ParsedEPUB(
            title: (title?.isEmpty == false ? title! : fallbackTitle),
            author: (author?.isEmpty == false ? author! : "未知"),
            coverData: coverData,
            chapters: chapters
        )
    }

    private static func bodyText(_ doc: Document) -> String {
        guard let body = doc.body() else { return "" }
        _ = try? body.select("script, style, svg, img").remove()
        var paragraphs: [String] = []
        let blocks = (try? body.select("p, h1, h2, h3, h4, h5, h6, li, blockquote, pre").array()) ?? []
        if blocks.isEmpty {
            return ((try? body.text()) ?? "")
        }
        for el in blocks {
            // skip containers whose child blocks will be emitted themselves
            if (try? el.select("p, li, blockquote").size()) ?? 0 > 1, el.tagName() == "blockquote" { continue }
            let t = ((try? el.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { paragraphs.append(t) }
        }
        return paragraphs.joined(separator: "\n")
    }
}
