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
                await MainActor.run {
                    loadError = "书源缺少目录规则"
                    isLoading = false
                }
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
