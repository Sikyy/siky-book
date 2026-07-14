import SwiftUI
import SwiftData

struct AddBookPersistenceDraft: Sendable {
    struct ChapterDraft: Sendable {
        let index: Int
        let title: String
        let sourceURL: String
    }

    let title: String
    let author: String
    let sourceId: UUID
    let sourceBookURL: String
    let sourceName: String
    let coverURL: String?
    let chapters: [ChapterDraft]
}

private struct AddBookSubmissionSnapshot: Sendable {
    let title: String
    let author: String
    let sourceId: UUID
    let sourceBookURL: String
    let sourceName: String
    let detailCoverURL: String?
    let sourceCoverURL: String?
    let sourceBaseURL: String
    let chapters: [ChapterInfo]
}

private struct AddBookInsertionResult: Sendable {
    let bookId: UUID
    let needsCoverSearch: Bool
}

enum AddBookPersistenceWorker {
    /// Creates and consumes a private ModelContext synchronously. Callers invoke
    /// this from a detached task; neither the context nor any model escapes it.
    static func addBook(
        _ draft: AddBookPersistenceDraft,
        in container: ModelContainer
    ) throws -> UUID {
        let signposter = PerformanceSignposts.cache
        let signpostID = signposter.makeSignpostID()
        let chapterCount = draft.chapters.count
        var intervalResult = "error"
        let intervalState = signposter.beginInterval(
            "AddBookPersistence",
            id: signpostID,
            "chapters=\(chapterCount)"
        )
        defer {
            signposter.endInterval(
                "AddBookPersistence",
                intervalState,
                "result=\(intervalResult, privacy: .public) chapters=\(chapterCount)"
            )
        }

        let context = ModelContext(container)
        context.autosaveEnabled = false

        let book = Book(
            title: draft.title,
            author: draft.author,
            sourceType: .bookSource,
            totalChapters: draft.chapters.count
        )
        book.sourceId = draft.sourceId
        book.sourceBookURL = draft.sourceBookURL
        book.sourceName = draft.sourceName
        book.coverURL = draft.coverURL

        let chapterModels = draft.chapters.map { chapterDraft in
            let chapter = Chapter(index: chapterDraft.index, title: chapterDraft.title)
            chapter.sourceURL = chapterDraft.sourceURL
            return chapter
        }
        book.chapters = chapterModels
        context.insert(book)

        do {
            try context.save()
            intervalResult = "success"
            return book.id
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Best-effort guard against replacing a cover selected after automatic
    /// discovery started. Manual selection normally wins because this refetches
    /// immediately before saving; SwiftData does not expose an atomic compare-
    /// and-set for a property shared by independent contexts.
    static func setCoverIfMissing(
        bookId: UUID,
        coverURL: String,
        in container: ModelContainer
    ) throws -> Bool {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let targetId = bookId
        var descriptor = FetchDescriptor<Book>(
            predicate: #Predicate<Book> { book in
                book.id == targetId
            }
        )
        descriptor.fetchLimit = 1

        guard let book = try context.fetch(descriptor).first,
              book.coverURL == nil else {
            return false
        }

        book.coverURL = coverURL
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            throw error
        }
    }
}

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
    @State private var isAdding = false
    @State private var addError: String?
    @State private var retryLoadTask: Task<Void, Never>?
    @State private var retryLoadGeneration: UUID?

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
        .onDisappear {
            retryLoadGeneration = nil
            retryLoadTask?.cancel()
            retryLoadTask = nil
        }
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
        CachedCoverImage(
            urlString: displayCoverURL,
            targetSize: CGSize(width: 80, height: 110)
        ) {
            coverPlaceholder
        }
        .frame(width: 80, height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                        retryLoadBookDetail()
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

    private var canAdd: Bool {
        !isLoading && !isAdding && chapterCount > 0
    }

    private var addButton: some View {
        VStack(spacing: 8) {
            Button { addToBookshelf() } label: {
                HStack(spacing: 8) {
                    if isAdding {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isAdding ? "正在加入…" : "加入书架")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canAdd || isAdding ? Color.blue : Color.gray)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!canAdd)

            if let addError {
                Text("加入失败：\(addError)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            if !isLoading && chapterCount == 0 && loadError == nil {
                Text("该书源无法获取章节目录，请尝试其他书源")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func retryLoadBookDetail() {
        retryLoadTask?.cancel()
        let generation = UUID()
        retryLoadGeneration = generation
        retryLoadTask = Task {
            defer {
                if retryLoadGeneration == generation {
                    retryLoadGeneration = nil
                    retryLoadTask = nil
                }
            }
            await loadBookDetail()
        }
    }

    private func loadBookDetail() async {
        guard !Task.isCancelled else { return }
        isLoading = true
        loadError = nil

        do {
            let engine = SourceEngine()
            let resolvedURL = engine.resolveURL(bookURL, base: legadoSource.url)
            let response = try await NetworkClient.shared.fetchString(url: resolvedURL)
            try Task.checkCancellation()

            // Parse book info (intro, wordCount, cover)
            if let infoRule = legadoSource.bookInfoRule {
                let ruleExecutor = RuleExecutor()
                if let introRule = infoRule.intro,
                   let text = try? ruleExecutor.getString(html: response, rule: introRule, baseURL: legadoSource.url),
                   !text.isEmpty {
                    try Task.checkCancellation()
                    await MainActor.run { detailIntro = text }
                }
                if let wcRule = infoRule.wordCount,
                   let text = try? ruleExecutor.getString(html: response, rule: wcRule, baseURL: legadoSource.url),
                   !text.isEmpty {
                    try Task.checkCancellation()
                    await MainActor.run { wordCount = text }
                }
                if let coverRule = infoRule.coverUrl,
                   let url = try? ruleExecutor.getString(html: response, rule: coverRule, baseURL: legadoSource.url),
                   !url.isEmpty {
                    let resolved = engine.resolveURL(url, base: legadoSource.url)
                    try Task.checkCancellation()
                    await MainActor.run { detailCoverURL = resolved }
                }
            }

            // Parse TOC — use separate tocUrl if defined, otherwise parse from same page
            if let tocRule = legadoSource.tocRule {
                var tocResponse = response
                var tocBaseURL = resolvedURL
                if let tocUrlRule = legadoSource.bookInfoRule?.tocUrl, !tocUrlRule.isEmpty {
                    let ruleExecutor = RuleExecutor()
                    if let parsedTocUrl = try? ruleExecutor.getString(html: response, rule: tocUrlRule, baseURL: resolvedURL),
                       !parsedTocUrl.isEmpty {
                        let resolvedTocURL = engine.resolveURL(parsedTocUrl, base: resolvedURL)
                        tocResponse = try await NetworkClient.shared.fetchString(url: resolvedTocURL)
                        try Task.checkCancellation()
                        tocBaseURL = resolvedTocURL
                    }
                }

                // Parse first page of chapters
                try Task.checkCancellation()
                var allChapters = try engine.parseChapterList(response: tocResponse, rule: tocRule, baseURL: tocBaseURL)
                    .map { ChapterInfo(title: $0.title, url: engine.resolveURL($0.url, base: tocBaseURL)) }

                // Pagination: follow nextTocUrl links
                if let nextRule = tocRule.nextTocUrl, !nextRule.isEmpty {
                    var visitedUrls: Set<String> = []
                    var currentResponse = tocResponse
                    var currentBaseURL = tocBaseURL
                    let maxPages = 200  // safety limit

                    for _ in 0..<maxPages {
                        try Task.checkCancellation()
                        guard let nextUrl = engine.parseNextTocUrl(response: currentResponse, rule: nextRule, baseURL: currentBaseURL) else { break }
                        let resolvedNext = engine.resolveURL(nextUrl, base: currentBaseURL)
                        guard !visitedUrls.contains(resolvedNext) else { break }
                        visitedUrls.insert(resolvedNext)

                        let nextResponse = try await NetworkClient.shared.fetchString(url: resolvedNext)
                        try Task.checkCancellation()
                        let pageChapters = try engine.parseChapterList(response: nextResponse, rule: tocRule, baseURL: resolvedNext)
                            .map { ChapterInfo(title: $0.title, url: engine.resolveURL($0.url, base: resolvedNext)) }
                        try Task.checkCancellation()
                        guard !pageChapters.isEmpty else { break }
                        allChapters.append(contentsOf: pageChapters)
                        currentResponse = nextResponse
                        currentBaseURL = resolvedNext

                        // Update UI progressively
                        let count = allChapters.count
                        try Task.checkCancellation()
                        await MainActor.run { chapterCount = count }
                    }
                }

                // Deduplicate by title+url
                try Task.checkCancellation()
                var seen = Set<String>()
                let deduplicated = allChapters.filter {
                    let key = "\($0.title)|\($0.url)"
                    return seen.insert(key).inserted
                }

                try Task.checkCancellation()
                await MainActor.run {
                    chapters = deduplicated
                    chapterCount = deduplicated.count
                }
            }

            try Task.checkCancellation()
            await MainActor.run { isLoading = false }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
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

    @MainActor
    private func addToBookshelf() {
        guard !isAdding, !added, !chapters.isEmpty else { return }

        isAdding = true
        addError = nil

        // Capturing these value types is O(1) for the chapter array's
        // copy-on-write storage. URL normalization happens off the main actor.
        let snapshot = AddBookSubmissionSnapshot(
            title: title,
            author: author,
            sourceId: sourceId,
            sourceBookURL: bookURL,
            sourceName: sourceName,
            detailCoverURL: detailCoverURL,
            sourceCoverURL: coverURL,
            sourceBaseURL: legadoSource.url,
            chapters: chapters
        )
        let container = modelContext.container
        let completion = onAdded

        // Clicking "add" is an intentional commit: this unstructured task is
        // not tied to the view lifecycle and continues if the sheet is closed.
        Task { @MainActor in
            do {
                // Everything in this closure is value processing or synchronous
                // access through a context created on the detached executor.
                let result = try await Task.detached(priority: .userInitiated) {
                    let engine = SourceEngine()
                    let resolvedCoverURL: String?
                    if let detailCoverURL = snapshot.detailCoverURL {
                        resolvedCoverURL = detailCoverURL
                    } else if let sourceCoverURL = snapshot.sourceCoverURL {
                        resolvedCoverURL = engine.resolveURL(
                            sourceCoverURL,
                            base: snapshot.sourceBaseURL
                        )
                    } else {
                        resolvedCoverURL = nil
                    }

                    let chapterDrafts = snapshot.chapters.enumerated().map { index, chapter in
                        AddBookPersistenceDraft.ChapterDraft(
                            index: index,
                            title: chapter.title,
                            sourceURL: engine.resolveURL(
                                chapter.url,
                                base: snapshot.sourceBaseURL
                            )
                        )
                    }
                    let draft = AddBookPersistenceDraft(
                        title: snapshot.title,
                        author: snapshot.author,
                        sourceId: snapshot.sourceId,
                        sourceBookURL: snapshot.sourceBookURL,
                        sourceName: snapshot.sourceName,
                        coverURL: resolvedCoverURL,
                        chapters: chapterDrafts
                    )
                    let bookId = try AddBookPersistenceWorker.addBook(
                        draft,
                        in: container
                    )
                    return AddBookInsertionResult(
                        bookId: bookId,
                        needsCoverSearch: resolvedCoverURL == nil
                    )
                }.value

                isAdding = false
                added = true

                if result.needsCoverSearch {
                    Self.searchAndPersistCover(
                        title: snapshot.title,
                        author: snapshot.author,
                        bookId: result.bookId,
                        container: container
                    )
                }

                // The callback may dismiss this view, so invoke it only after
                // all SwiftData inserts and the save have completed.
                completion?()
            } catch {
                isAdding = false
                addError = error.localizedDescription
            }
        }
    }

    nonisolated private static func searchAndPersistCover(
        title: String,
        author: String,
        bookId: UUID,
        container: ModelContainer
    ) {
        Task.detached(priority: .utility) {
            guard let cover = await CoverSearchService.searchCover(
                title: title,
                author: author,
                bookId: bookId
            ) else {
                return
            }

            do {
                // The context is created only after the async network work and
                // is then used synchronously without crossing an await point.
                let applied = try AddBookPersistenceWorker.setCoverIfMissing(
                    bookId: bookId,
                    coverURL: cover,
                    in: container
                )
                if !applied {
                    CoverSearchService.discardDownloadedCover(cover)
                }
            } catch {
                CoverSearchService.discardDownloadedCover(cover)
            }
        }
    }
}
