import Foundation

/// 封面候选项
struct CoverCandidate: Identifiable {
    let id = UUID()
    let title: String
    let author: String
    let picURL: String      // 大图远程 URL
    let thumbURL: String    // 小图远程 URL（用于预览）
    let score: Int
    let source: CoverSource // 来源
    var needsReferer: Bool { source == .douban }
}

enum CoverSource: String {
    case douban = "豆瓣"
    case qidian = "起点"
}

enum CoverSearchService {
    /// 搜索封面并下载到本地，返回本地文件相对路径
    static func searchCover(title: String, author: String, bookId: UUID) async -> String? {
        let candidates = await searchCandidates(title: title, author: author)
        for candidate in candidates {
            if let localPath = await downloadCover(candidate.picURL, bookId: bookId, needsReferer: candidate.needsReferer) {
                return localPath
            }
        }
        return nil
    }

    /// 搜索所有候选封面（豆瓣 + 番茄小说），按匹配度排序返回
    static func searchCandidates(title: String, author: String) async -> [CoverCandidate] {
        // 并发搜索豆瓣和起点
        async let doubanResults = searchDoubanCandidates(title: title, author: author)
        async let qidianResults = searchQidianCandidates(title: title, author: author)

        var candidates = await doubanResults + qidianResults

        // 去重（按图片 URL）
        var seen = Set<String>()
        candidates.removeAll { c in
            if seen.contains(c.picURL) { return true }
            seen.insert(c.picURL)
            return false
        }

        candidates.sort { $0.score > $1.score }
        return candidates
    }

    private static func searchDoubanCandidates(title: String, author: String) async -> [CoverCandidate] {
        let keywords = buildKeywords(from: title)
        var seen = Set<String>()
        var candidates: [CoverCandidate] = []

        for keyword in keywords {
            let results = await fetchDouban(keyword: keyword)
            for book in results {
                guard let pic = book["pic"] as? String, !pic.isEmpty, !isPlaceholder(pic) else { continue }
                let largePic = toLargeCover(pic)
                guard !seen.contains(largePic) else { continue }
                seen.insert(largePic)

                let doubanTitle = book["title"] as? String ?? ""
                let doubanAuthor = book["author_name"] as? String ?? ""
                let score = matchScore(bookTitle: title, bookAuthor: author,
                                       doubanTitle: doubanTitle, doubanAuthor: doubanAuthor)
                candidates.append(CoverCandidate(
                    title: doubanTitle, author: doubanAuthor,
                    picURL: largePic, thumbURL: pic, score: score,
                    source: .douban
                ))
            }
        }
        return candidates
    }

    private static func searchQidianCandidates(title: String, author: String) async -> [CoverCandidate] {
        let results = await fetchQidian(keyword: title)
        var candidates: [CoverCandidate] = []

        for (qTitle, bookId) in results {
            let thumbURL = "https://bookcover.yuewen.com/qdbimg/349573/\(bookId)/180"
            let picURL = "https://bookcover.yuewen.com/qdbimg/349573/\(bookId)/600"
            let score = matchScore(bookTitle: title, bookAuthor: author,
                                   doubanTitle: qTitle, doubanAuthor: "")
            candidates.append(CoverCandidate(
                title: qTitle, author: "",
                picURL: picURL, thumbURL: thumbURL, score: score,
                source: .qidian
            ))
        }
        return candidates
    }

    /// 下载指定封面到本地，返回相对路径
    static func downloadCoverToLocal(_ remoteURL: String, bookId: UUID, needsReferer: Bool = true) async -> String? {
        await downloadCover(remoteURL, bookId: bookId, needsReferer: needsReferer)
    }

    // MARK: - 标题匹配打分

    /// 计算豆瓣结果与书架书名的匹配度（0~100）
    private static func matchScore(bookTitle: String, bookAuthor: String,
                                   doubanTitle: String, doubanAuthor: String) -> Int {
        var score = 0

        // 标准化标题用于比较
        let normBook = normalizeTitle(bookTitle)
        let normDouban = normalizeTitle(doubanTitle)

        // 完全一致
        if normBook == normDouban {
            score += 60
        }
        // 一方包含另一方
        else if normBook.contains(normDouban) || normDouban.contains(normBook) {
            score += 40
        }
        // 系列名 + 卷号匹配
        else {
            let (bookSeries, bookVol) = extractSeriesAndVolume(bookTitle)
            let (doubanSeries, doubanVol) = extractSeriesAndVolume(doubanTitle)
            if !bookSeries.isEmpty, bookSeries == doubanSeries {
                score += 20
                if bookVol > 0, bookVol == doubanVol {
                    score += 20
                }
            }
        }

        // 作者匹配
        if !bookAuthor.isEmpty, !doubanAuthor.isEmpty {
            if doubanAuthor == bookAuthor {
                score += 35 // 精确匹配额外加分
            } else if doubanAuthor.contains(bookAuthor) || bookAuthor.contains(doubanAuthor) {
                score += 30
            }
        }

        return score
    }

    /// 标准化标题：去除空白、标点，统一数字格式
    private static func normalizeTitle(_ title: String) -> String {
        var s = title
        // 移除空白
        s = s.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        // 统一分隔符
        s = s.replacingOccurrences(of: #"[·:：—－\-–()（）《》]"#, with: "", options: .regularExpression)
        // 统一数字：罗马数字 → 阿拉伯数字
        for (roman, arabic) in [("Ⅰ","1"),("Ⅱ","2"),("Ⅲ","3"),("Ⅳ","4"),("Ⅴ","5"),
                                 ("Ⅵ","6"),("Ⅶ","7"),("Ⅷ","8"),("Ⅸ","9"),("Ⅹ","10")] {
            s = s.replacingOccurrences(of: roman, with: arabic)
        }
        // 中文数字 → 阿拉伯数字
        for (cn, arabic) in [("一","1"),("二","2"),("三","3"),("四","4"),("五","5"),
                              ("六","6"),("七","7"),("八","8"),("九","9"),("十","10")] {
            s = s.replacingOccurrences(of: cn, with: arabic)
        }
        // 全角数字 → 半角
        s = s.replacingOccurrences(of: #"[０-９]"#, with: "", options: .regularExpression)
        // 转小写
        s = s.lowercased()
        return s
    }

    /// 提取系列名和卷号：
    /// "龙族3·黑月之潮" → ("龙族", 3)
    /// "龙族Ⅲ" → ("龙族", 3)
    /// "斗破苍穹" → ("斗破苍穹", 0)
    private static func extractSeriesAndVolume(_ title: String) -> (String, Int) {
        // 匹配：系列名 + 数字/中文数字/罗马数字
        let pattern = #"^(.+?)\s*[·:：\-－–]?\s*([0-9０-９Ⅰ-Ⅹⅰ-ⅹ一二三四五六七八九十]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) else {
            return (title, 0)
        }

        let seriesRange = Range(match.range(at: 1), in: title)!
        let volRange = Range(match.range(at: 2), in: title)!
        let series = String(title[seriesRange]).trimmingCharacters(in: .whitespaces)
        let volStr = String(title[volRange])

        let vol = parseVolume(volStr)
        return (series, vol)
    }

    /// 把各种数字格式统一解析为 Int
    private static func parseVolume(_ s: String) -> Int {
        // 阿拉伯数字
        if let n = Int(s) { return n }
        // 罗马数字
        let romanMap: [String: Int] = ["Ⅰ":1,"Ⅱ":2,"Ⅲ":3,"Ⅳ":4,"Ⅴ":5,"Ⅵ":6,"Ⅶ":7,"Ⅷ":8,"Ⅸ":9,"Ⅹ":10,
                                        "ⅰ":1,"ⅱ":2,"ⅲ":3,"ⅳ":4,"ⅴ":5,"ⅵ":6,"ⅶ":7,"ⅷ":8,"ⅸ":9,"ⅹ":10]
        if let n = romanMap[s] { return n }
        // 中文数字
        let cnMap: [String: Int] = ["一":1,"二":2,"三":3,"四":4,"五":5,"六":6,"七":7,"八":8,"九":9,"十":10]
        if let n = cnMap[s] { return n }
        return 0
    }

    // MARK: - 关键词生成

    /// "龙族3·黑月之潮" → ["龙族3·黑月之潮", "龙族Ⅲ", "龙族3", "龙族"]
    /// 增加罗马数字变体以覆盖豆瓣不同命名风格
    private static func buildKeywords(from title: String) -> [String] {
        var keywords = [title]

        // 提取系列名和卷号
        let (series, vol) = extractSeriesAndVolume(title)

        // 生成 系列名+罗马数字 变体（豆瓣常用）
        if vol > 0 {
            let romanNumerals = ["","Ⅰ","Ⅱ","Ⅲ","Ⅳ","Ⅴ","Ⅵ","Ⅶ","Ⅷ","Ⅸ","Ⅹ"]
            if vol <= 10 {
                let romanKeyword = series + romanNumerals[vol]
                if !keywords.contains(romanKeyword) { keywords.append(romanKeyword) }
            }
            // 系列名+阿拉伯数字
            let arabicKeyword = series + "\(vol)"
            if !keywords.contains(arabicKeyword) { keywords.append(arabicKeyword) }
        }

        // 纯系列名
        if !series.isEmpty, !keywords.contains(series) {
            keywords.append(series)
        }

        return keywords
    }

    // MARK: - 豆瓣 API

    /// 调用豆瓣 subject_suggest 接口，返回原始结果数组
    private static func fetchDouban(keyword: String) async -> [[String: Any]] {
        guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        let urlString = "https://book.douban.com/j/subject_suggest?q=\(encoded)"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("https://book.douban.com", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return [] }
            guard let results = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
            return results.filter { ($0["type"] as? String) == "b" }
        } catch {
            return []
        }
    }

    // MARK: - 起点 API

    /// 通过起点移动端搜索页提取书名和书籍 ID
    private static func fetchQidian(keyword: String) async -> [(String, String)] {
        guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        let urlString = "https://m.qidian.com/soushu/\(encoded).html"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let html = String(data: data, encoding: .utf8) else { return [] }

            // 提取封面图片中的 bookId
            let idPattern = try NSRegularExpression(pattern: #"bookcover\.yuewen\.com/qdbimg/\d+/(\d+)/180"#)
            let idMatches = idPattern.matches(in: html, range: NSRange(html.startIndex..., in: html))
            var bookIds: [String] = []
            var seen = Set<String>()
            for match in idMatches {
                if let range = Range(match.range(at: 1), in: html) {
                    let bid = String(html[range])
                    if !seen.contains(bid) {
                        seen.insert(bid)
                        bookIds.append(bid)
                    }
                }
            }

            // 提取 <h2> 标签中的书名
            let titlePattern = try NSRegularExpression(pattern: #"<h2[^>]*>(.*?)</h2>"#, options: .dotMatchesLineSeparators)
            let titleMatches = titlePattern.matches(in: html, range: NSRange(html.startIndex..., in: html))
            var titles: [String] = []
            let tagPattern = try NSRegularExpression(pattern: #"<[^>]+>"#)
            for match in titleMatches {
                if let range = Range(match.range(at: 1), in: html) {
                    let raw = String(html[range])
                    let clean = tagPattern.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty { titles.append(clean) }
                }
            }

            // 配对返回
            var results: [(String, String)] = []
            for i in 0..<min(bookIds.count, titles.count) {
                results.append((titles[i], bookIds[i]))
            }
            return results
        } catch {
            return []
        }
    }

    // MARK: - 下载图片到本地

    static func downloadCover(_ remoteURL: String, bookId: UUID, needsReferer: Bool = true) async -> String? {
        var urlString = remoteURL
        if urlString.hasPrefix("//") { urlString = "https:" + urlString }
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        if needsReferer {
            request.setValue("https://book.douban.com", forHTTPHeaderField: "Referer")
        }
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            guard data.count > 1000 else { return nil } // 太小的不是有效图片

            let coversDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("covers", isDirectory: true)
            try FileManager.default.createDirectory(at: coversDir, withIntermediateDirectories: true)

            let rawExt = url.pathExtension
            let ext = (rawExt.isEmpty || rawExt == "image") ? "jpg" : rawExt
            let filename = "\(bookId.uuidString).\(ext)"
            let localFile = coversDir.appendingPathComponent(filename)
            try data.write(to: localFile)

            // 存相对路径，避免重装后容器路径变化导致失效
            return "covers/\(filename)"
        } catch {}
        return nil
    }

    /// 判断是否为豆瓣默认占位图
    private static func isPlaceholder(_ url: String) -> Bool {
        url.contains("book-default") || url.contains("default-book") || url.contains("/nophoto/")
    }

    private static func toLargeCover(_ url: String) -> String {
        url.replacingOccurrences(of: "/view/subject/s/", with: "/view/subject/l/")
    }
}
