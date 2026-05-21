import SwiftUI
import SwiftData

struct CacheManageView: View {
    @Query(sort: \Book.addedDate, order: .reverse) private var books: [Book]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingClearAll = false
    @State private var cachingBookId: UUID?
    @State private var cachedCount = 0
    @State private var totalToCache = 0
    @State private var cacheTask: Task<Void, Never>?

    private var sourceBooks: [Book] {
        books.filter { $0.sourceId != nil }
    }

    private var totalCachedChapters: Int {
        sourceBooks.reduce(0) { sum, book in
            sum + book.chapters.filter { $0.isCached }.count
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("已缓存章节")
                        Spacer()
                        Text("\(totalCachedChapters) 章")
                            .foregroundStyle(.secondary)
                    }
                }

                if sourceBooks.isEmpty {
                    Section {
                        Text("暂无书源书籍")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                    }
                } else {
                    Section("按书籍管理") {
                        ForEach(sourceBooks) { book in
                            bookRow(book)
                        }
                    }

                    if totalCachedChapters > 0 {
                        Section {
                            Button("清除全部缓存", role: .destructive) {
                                showingClearAll = true
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }
            .navigationTitle("缓存管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("确认清除", isPresented: $showingClearAll) {
                Button("取消", role: .cancel) {}
                Button("清除全部", role: .destructive) { clearAllCache() }
            } message: {
                Text("将清除所有书籍的缓存章节内容，下次阅读需要重新加载")
            }
        }
    }

    @ViewBuilder
    private func bookRow(_ book: Book) -> some View {
        let cached = book.chapters.filter { $0.isCached }.count
        let total = book.totalChapters
        let uncachedCount = book.chapters.filter { $0.content == nil && $0.sourceURL != nil }.count
        let isCachingThis = cachingBookId == book.id

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(.body)
                    Text("\(cached) / \(total) 章已缓存")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if cached > 0 {
                    Button("清除") {
                        clearCache(for: book)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.red)
                }
            }

            // 缓存进度条 & 操作按钮
            if isCachingThis {
                VStack(spacing: 6) {
                    ProgressView(value: Double(cachedCount), total: Double(totalToCache))
                        .tint(.blue)
                    HStack {
                        Text("缓存中 \(cachedCount)/\(totalToCache)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            cancelCaching()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "pause.fill")
                                    .font(.system(size: 10))
                                Text("暂停")
                                    .font(.caption)
                            }
                            .foregroundStyle(.orange)
                        }
                    }
                }
            } else if uncachedCount > 0 {
                HStack(spacing: 12) {
                    Button {
                        startCaching(book: book, count: nil)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 12))
                            Text("缓存全部")
                                .font(.caption)
                        }
                    }
                    .disabled(cachingBookId != nil)

                    Text("\(uncachedCount) 章未缓存")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if cached > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                    Text("已全部缓存")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 缓存操作

    private func startCaching(book: Book, count: Int?) {
        guard cachingBookId == nil else { return }

        let uncached = book.chapters
            .filter { $0.content == nil && $0.sourceURL != nil }
            .sorted { $0.index < $1.index }
        let toCache = count != nil ? Array(uncached.prefix(count!)) : uncached
        guard !toCache.isEmpty else { return }

        cachingBookId = book.id
        cachedCount = 0
        totalToCache = toCache.count

        guard let sourceId = book.sourceId, let _ = book.sourceBookURL else { return }

        // 获取书源解析信息
        let descriptor = FetchDescriptor<BookSource>(predicate: #Predicate<BookSource> { $0.id == sourceId })
        guard let bookSource = try? modelContext.fetch(descriptor).first else { return }

        let ruleJSON = bookSource.ruleJSON
        let sourceURL = bookSource.sourceURL

        let maxConcurrent = 5
        cacheTask = Task {
            let engine = SourceEngine()

            guard let legado = try? LegadoSourceParser.parse(json: ruleJSON, matchingURL: sourceURL),
                  let contentRule = legado.contentRule else {
                await MainActor.run { cachingBookId = nil }
                return
            }

            await withTaskGroup(of: Void.self) { group in
                for (i, chapter) in toCache.enumerated() {
                    if Task.isCancelled { break }
                    if i >= maxConcurrent { await group.next() }

                    group.addTask {
                        guard !Task.isCancelled else { return }
                        guard let chapterURL = chapter.sourceURL else { return }

                        do {
                            let resolved = engine.resolveURL(chapterURL, base: legado.url)
                            let html = try await NetworkClient.shared.fetchString(url: resolved)
                            if let text = try? engine.parseContent(response: html, rule: contentRule, baseURL: legado.url),
                               !text.isEmpty {
                                await MainActor.run {
                                    chapter.content = text
                                    chapter.isCached = true
                                }
                            }
                        } catch {}
                        await MainActor.run { cachedCount += 1 }
                    }
                }
                await group.waitForAll()
            }

            await MainActor.run {
                try? modelContext.save()
                cachingBookId = nil
                cacheTask = nil
            }
        }
    }

    private func cancelCaching() {
        cacheTask?.cancel()
        cacheTask = nil
        cachingBookId = nil
        try? modelContext.save()
    }

    // MARK: - 清除缓存

    private func clearCache(for book: Book) {
        for chapter in book.chapters where chapter.isCached && chapter.sourceURL != nil {
            chapter.content = nil
            chapter.isCached = false
        }
    }

    private func clearAllCache() {
        for book in sourceBooks {
            clearCache(for: book)
        }
    }
}
