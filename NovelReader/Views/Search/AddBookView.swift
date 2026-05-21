import SwiftUI
import SwiftData

struct AddBookView: View {
    let title: String
    let author: String
    let coverURL: String?
    let intro: String?
    let sourceName: String
    let sourceId: UUID
    let bookURL: String
    let legadoSource: LegadoSource
    var onAdded: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @State private var isLoading = false
    @State private var chapterCount = 0
    @State private var wordCount: String?
    @State private var detailIntro: String?
    @State private var detailCoverURL: String?
    @State private var loadError: String?
    @State private var chapters: [ChapterInfo] = []
    @State private var added = false

    private var displayIntro: String? {
        detailIntro ?? intro
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                bookInfo
                if let text = displayIntro, !text.isEmpty {
                    introSection(text)
                }
                sourceInfo
                Spacer(minLength: 20)
                if added {
                    Label("已加入书架", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                } else {
                    addButton
                }
            }
            .padding(20)
        }
        .navigationTitle("添加到书架")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadBookDetail() }
    }

    private var bookInfo: some View {
        HStack(spacing: 16) {
            bookCover
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title3.bold())
                if !author.isEmpty {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private func introSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("简介")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayCoverURL: String? {
        if let dc = detailCoverURL { return dc }
        if let c = coverURL {
            let engine = SourceEngine()
            return engine.resolveURL(c, base: legadoSource.url)
        }
        return nil
    }

    @ViewBuilder
    private var bookCover: some View {
        if let urlString = displayCoverURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    coverPlaceholder
                }
            }
            .frame(width: 80, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            coverPlaceholder
        }
    }

    private var coverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.systemGray5))
            .frame(width: 80, height: 110)
            .overlay(
                Text(String(title.prefix(2)))
                    .font(.title2)
                    .foregroundStyle(.secondary)
            )
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
                Text("章节")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if loadError != nil {
                    Button {
                        Task { await loadBookDetail() }
                    } label: {
                        HStack(spacing: 4) {
                            Text("加载失败，点击重试")
                                .font(.caption)
                                .foregroundStyle(.red)
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                } else {
                    Text("\(chapterCount) 章")
                        .font(.subheadline)
                }
            }
            if let wc = wordCount, !wc.isEmpty {
                Divider()
                HStack {
                    Text("字数")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatWordCount(wc))
                        .font(.subheadline)
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var addButton: some View {
        Button { addToBookshelf() } label: {
            Text("加入书架")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isLoading ? Color.gray : Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isLoading)
    }

    private func loadBookDetail() async {
        isLoading = true
        loadError = nil

        do {
            let engine = SourceEngine()
            let resolvedURL = engine.resolveURL(bookURL, base: legadoSource.url)
            let response = try await NetworkClient.shared.fetchString(url: resolvedURL)

            if let infoRule = legadoSource.bookInfoRule {
                let ruleExecutor = RuleExecutor()
                if let introRule = infoRule.intro,
                   let text = try? ruleExecutor.getString(html: response, rule: introRule, baseURL: legadoSource.url),
                   !text.isEmpty {
                    await MainActor.run { detailIntro = text }
                }
                if let wcRule = infoRule.wordCount,
                   let text = try? ruleExecutor.getString(html: response, rule: wcRule, baseURL: legadoSource.url),
                   !text.isEmpty {
                    await MainActor.run { wordCount = text }
                }
                if let coverRule = infoRule.coverUrl,
                   let url = try? ruleExecutor.getString(html: response, rule: coverRule, baseURL: legadoSource.url),
                   !url.isEmpty {
                    let resolved = engine.resolveURL(url, base: legadoSource.url)
                    await MainActor.run { detailCoverURL = resolved }
                }
            }

            if let tocRule = legadoSource.tocRule {
                let chapterInfos = try engine.parseChapterList(response: response, rule: tocRule, baseURL: legadoSource.url)
                await MainActor.run {
                    chapters = chapterInfos
                    chapterCount = chapterInfos.count
                }
            }

            await MainActor.run { isLoading = false }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func formatWordCount(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        if let num = Int(digits) {
            if num >= 10000 {
                let wan = Double(num) / 10000.0
                if wan >= 100 {
                    return String(format: "%.0f万字", wan)
                }
                return String(format: "%.1f万字", wan)
            }
            return "\(num)字"
        }
        if raw.contains("万") { return raw }
        return raw + "字"
    }

    private func addToBookshelf() {
        let book = Book(title: title, author: author, sourceType: .bookSource, totalChapters: chapterCount)
        book.sourceId = sourceId
        book.sourceBookURL = bookURL
        let engine = SourceEngine()
        if let dc = detailCoverURL {
            book.coverURL = dc
        } else if let c = coverURL {
            book.coverURL = engine.resolveURL(c, base: legadoSource.url)
        }
        modelContext.insert(book)

        for (i, info) in chapters.enumerated() {
            let chapter = Chapter(index: i, title: info.title)
            chapter.book = book
            chapter.sourceURL = engine.resolveURL(info.url, base: legadoSource.url)
            modelContext.insert(chapter)
        }

        try? modelContext.save()
        added = true

        // 如果没有封面，异步通过书名+作者搜索
        if book.coverURL == nil {
            Task {
                if let cover = await CoverSearchService.searchCover(title: book.title, author: book.author, bookId: book.id) {
                    await MainActor.run {
                        book.coverURL = cover
                        try? modelContext.save()
                    }
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            onAdded?()
        }
    }
}
