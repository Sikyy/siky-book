import SwiftUI
import SwiftData

/// A source found during live search that can serve this book.
private struct FoundSource: Identifiable {
    let id: UUID
    let sourceName: String
    let sourceId: UUID
    let bookURL: String
    let ruleJSON: String
    let sourceURL: String
    let chapterCount: Int   // 0 = invalid
}

struct ChangeSourceView: View {
    let book: Book
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Search state
    @State private var foundSources: [FoundSource] = []
    @State private var isSearching = false
    @State private var searchedCount = 0
    @State private var totalCount = 0

    // Switch state
    @State private var isSwitching = false
    @State private var switchingSourceId: UUID?
    @State private var error: String?
    @State private var hasSearched = false

    // Pinned / blocked IDs for quick lookup
    private var pinnedIds: Set<String> {
        Set(book.pinnedSources.map { $0.sourceId })
    }
    private var blockedIds: Set<String> {
        book.blockedSourceIds
    }

    /// Search results excluding current, pinned, and blocked sources
    private var searchResults: [FoundSource] {
        foundSources.filter { source in
            let sid = source.sourceId.uuidString
            return source.sourceId != book.sourceId &&
                   !pinnedIds.contains(sid) &&
                   !blockedIds.contains(sid)
        }
    }

    private var blockedCount: Int {
        blockedIds.count
    }

    var body: some View {
        NavigationStack {
            List {
                currentSourceSection
                pinnedSourcesSection
                searchButtonSection
                searchProgressSection
                searchResultsSection
                blockedSourcesSection
                errorSection
            }
            .navigationTitle("换源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                // Only auto-search first time (no cached pinned/blocked data)
                if book.pinnedSources.isEmpty && book.blockedSourceIds.isEmpty {
                    await searchAllSources()
                }
            }
        }
    }

    // MARK: - Current Source

    private var currentSourceSection: some View {
        Section("当前来源") {
            HStack {
                Text(book.sourceName ?? currentSourceNameFromDB)
                    .font(.body)
                Spacer()
                Image(systemName: "checkmark")
                    .foregroundStyle(.green)
            }
        }
    }

    private var currentSourceNameFromDB: String {
        guard let sid = book.sourceId else { return "未知来源" }
        let descriptor = FetchDescriptor<BookSource>(
            predicate: #Predicate<BookSource> { $0.id == sid }
        )
        return (try? modelContext.fetch(descriptor).first?.name) ?? "未知来源"
    }

    // MARK: - Pinned Sources

    @ViewBuilder
    private var pinnedSourcesSection: some View {
        let pinned = book.pinnedSources
        if !pinned.isEmpty {
            Section("收藏来源（\(pinned.count)个）") {
                ForEach(pinned) { source in
                    pinnedRow(source)
                }
            }
        }
    }

    private func pinnedRow(_ source: PinnedSource) -> some View {
        Button {
            Task { await switchToPinned(source) }
        } label: {
            HStack {
                Text(source.sourceName)
                    .foregroundStyle(.primary)
                Spacer()
                if let count = source.chapterCount, count > 0 {
                    Text("\(count)章")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                if switchingSourceId == UUID(uuidString: source.sourceId) {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(isSwitching)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                blockPinnedSource(source)
            } label: {
                Label("屏蔽", systemImage: "nosign")
            }
            Button {
                unpinSource(source)
            } label: {
                Label("取消收藏", systemImage: "pin.slash")
            }
            .tint(.gray)
        }
    }

    // MARK: - Search Button

    @ViewBuilder
    private var searchButtonSection: some View {
        // Show manual search button when cached data exists (not first time)
        if !isSearching && !hasSearched &&
           !(book.pinnedSources.isEmpty && book.blockedSourceIds.isEmpty) {
            Section {
                Button {
                    Task { await searchAllSources() }
                } label: {
                    HStack {
                        Spacer()
                        Label("搜索新书源", systemImage: "magnifyingglass")
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Search Progress

    @ViewBuilder
    private var searchProgressSection: some View {
        if isSearching {
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("正在搜索可用书源 \(searchedCount)/\(totalCount)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    let total = searchResults.count
                    if total > 0 {
                        Text("已找到 \(total) 个")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchResultsSection: some View {
        let results = searchResults
        if !results.isEmpty {
            Section("搜索结果（\(results.count)个）") {
                ForEach(results) { source in
                    searchResultRow(source)
                }
            }
        } else if !isSearching && hasSearched && book.pinnedSources.isEmpty {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("未找到其他可用书源")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
    }

    private func searchResultRow(_ source: FoundSource) -> some View {
        Button {
            Task { await switchSource(to: source) }
        } label: {
            HStack {
                Text(source.sourceName)
                    .foregroundStyle(.primary)
                Spacer()
                if source.chapterCount > 0 {
                    Text("\(source.chapterCount)章")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("无章节")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if switchingSourceId == source.sourceId {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(isSwitching)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                blockSource(source)
            } label: {
                Label("屏蔽", systemImage: "nosign")
            }
            Button {
                pinSource(source)
            } label: {
                Label("收藏", systemImage: "pin.fill")
            }
            .tint(.orange)
        }
    }

    // MARK: - Blocked Sources

    @ViewBuilder
    private var blockedSourcesSection: some View {
        if blockedCount > 0 {
            Section {
                DisclosureGroup("已屏蔽（\(blockedCount)个）") {
                    // Match blocked IDs against search results to show names
                    let blockedFound = foundSources.filter { blockedIds.contains($0.sourceId.uuidString) }
                    if !blockedFound.isEmpty {
                        ForEach(blockedFound) { source in
                            HStack {
                                Text(source.sourceName)
                                    .foregroundStyle(.secondary)
                                    .strikethrough()
                                Spacer()
                            }
                            .swipeActions(edge: .trailing) {
                                Button {
                                    unblockSource(id: source.sourceId.uuidString)
                                } label: {
                                    Label("取消屏蔽", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.green)
                            }
                        }
                    }
                    Button("取消全部屏蔽") {
                        book.blockedSourceIds = []
                        try? modelContext.save()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Error

    @ViewBuilder
    private var errorSection: some View {
        if let error {
            Section {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    // MARK: - Pin / Unpin / Block

    private func pinSource(_ source: FoundSource) {
        let pinned = PinnedSource(
            sourceName: source.sourceName,
            sourceId: source.sourceId.uuidString,
            bookURL: source.bookURL,
            sourceURL: source.sourceURL,
            chapterCount: source.chapterCount
        )
        var list = book.pinnedSources
        guard !list.contains(where: { $0.sourceId == pinned.sourceId }) else { return }
        list.append(pinned)
        book.pinnedSources = list
        try? modelContext.save()
    }

    private func unpinSource(_ source: PinnedSource) {
        var list = book.pinnedSources
        list.removeAll { $0.sourceId == source.sourceId }
        book.pinnedSources = list
        try? modelContext.save()
    }

    private func blockSource(_ source: FoundSource) {
        var ids = book.blockedSourceIds
        ids.insert(source.sourceId.uuidString)
        book.blockedSourceIds = ids
        try? modelContext.save()
    }

    private func blockPinnedSource(_ source: PinnedSource) {
        // Unpin first, then block
        unpinSource(source)
        var ids = book.blockedSourceIds
        ids.insert(source.sourceId)
        book.blockedSourceIds = ids
        try? modelContext.save()
    }

    private func unblockSource(id: String) {
        var ids = book.blockedSourceIds
        ids.remove(id)
        book.blockedSourceIds = ids
        try? modelContext.save()
    }

    // MARK: - Live search all sources

    private func searchAllSources() async {
        isSearching = true
        searchedCount = 0
        foundSources = []

        do {
            var descriptor = FetchDescriptor<BookSource>()
            descriptor.predicate = #Predicate<BookSource> { $0.enabled == true }
            let bookSources = try modelContext.fetch(descriptor)

            await MainActor.run { totalCount = bookSources.count }

            let snapshots: [(id: UUID, name: String, sourceURL: String, ruleJSON: String)] = bookSources.map {
                ($0.id, $0.name, $0.sourceURL, $0.ruleJSON)
            }

            let bookTitle = book.title
            let bookAuthor = book.author
            let currentSourceId = book.sourceId
            let existingPinnedIds = pinnedIds
            let existingBlockedIds = blockedIds
            let maxConcurrency = 50
            let timeoutNanos: UInt64 = 25_000_000_000  // 25s — includes validation

            await withTaskGroup(of: FoundSource?.self) { group in
                var iterator = snapshots.makeIterator()

                for _ in 0..<min(maxConcurrency, snapshots.count) {
                    guard let snap = iterator.next() else { break }
                    group.addTask {
                        await Self.searchSingleSource(
                            id: snap.id, name: snap.name,
                            sourceURL: snap.sourceURL, ruleJSON: snap.ruleJSON,
                            bookTitle: bookTitle, bookAuthor: bookAuthor,
                            timeoutNanos: timeoutNanos
                        )
                    }
                }

                for await result in group {
                    guard !Task.isCancelled else { break }

                    await MainActor.run {
                        searchedCount += 1
                        if let found = result {
                            let sid = found.sourceId.uuidString
                            guard !foundSources.contains(where: { $0.sourceId == found.sourceId }) else { return }
                            foundSources.append(found)

                            // Auto-categorize (skip current source and already-categorized)
                            if found.sourceId != currentSourceId &&
                               !existingPinnedIds.contains(sid) &&
                               !existingBlockedIds.contains(sid) {
                                if found.chapterCount > 0 {
                                    // Auto-pin valid source
                                    let pinned = PinnedSource(
                                        sourceName: found.sourceName,
                                        sourceId: sid,
                                        bookURL: found.bookURL,
                                        sourceURL: found.sourceURL,
                                        chapterCount: found.chapterCount
                                    )
                                    var list = book.pinnedSources
                                    if !list.contains(where: { $0.sourceId == sid }) {
                                        list.append(pinned)
                                        book.pinnedSources = list
                                    }
                                } else {
                                    // Auto-block invalid source
                                    var ids = book.blockedSourceIds
                                    ids.insert(sid)
                                    book.blockedSourceIds = ids
                                }
                                try? modelContext.save()
                            }
                        }
                    }

                    if let snap = iterator.next() {
                        group.addTask {
                            await Self.searchSingleSource(
                                id: snap.id, name: snap.name,
                                sourceURL: snap.sourceURL, ruleJSON: snap.ruleJSON,
                                bookTitle: bookTitle, bookAuthor: bookAuthor,
                                timeoutNanos: timeoutNanos
                            )
                        }
                    }
                }
            }

            await MainActor.run {
                isSearching = false
                hasSearched = true
            }
        } catch {
            await MainActor.run {
                isSearching = false
                hasSearched = true
            }
        }
    }

    // MARK: - Single source search (static, thread-safe)

    private static func searchSingleSource(
        id: UUID, name: String, sourceURL: String, ruleJSON: String,
        bookTitle: String, bookAuthor: String,
        timeoutNanos: UInt64
    ) async -> FoundSource? {
        do {
            return try await withThrowingTaskGroup(of: FoundSource?.self) { group in
                group.addTask {
                    try await doSearch(
                        id: id, name: name, sourceURL: sourceURL, ruleJSON: ruleJSON,
                        bookTitle: bookTitle, bookAuthor: bookAuthor
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: timeoutNanos)
                    throw CancellationError()
                }
                defer { group.cancelAll() }
                return try await group.next() ?? nil
            }
        } catch {
            return nil
        }
    }

    private static func doSearch(
        id: UUID, name: String, sourceURL: String, ruleJSON: String,
        bookTitle: String, bookAuthor: String
    ) async throws -> FoundSource? {
        let engine = SourceEngine()
        let legado = try LegadoSourceParser.parse(json: ruleJSON, matchingURL: sourceURL)

        // Step 1: Search for the book
        guard let searchReq = engine.buildSearchRequest(source: legado, keyword: bookTitle, page: 1) else {
            return nil
        }

        let html = try await NetworkClient.shared.fetchString(
            url: searchReq.url,
            method: searchReq.method,
            body: searchReq.body,
            headers: searchReq.headers.isEmpty ? nil : searchReq.headers
        )
        guard let searchRule = legado.searchRule else { return nil }

        let results = try engine.parseSearchResults(response: html, rule: searchRule, baseURL: legado.url)

        let titleLower = bookTitle.lowercased()
        let authorLower = bookAuthor.lowercased()

        guard let match = results.first(where: { result in
            let resultTitle = result.title.lowercased()
            if resultTitle == titleLower { return true }
            if resultTitle.contains(titleLower) || titleLower.contains(resultTitle) {
                if !authorLower.isEmpty && !result.author.isEmpty {
                    return result.author.lowercased().contains(authorLower) ||
                           authorLower.contains(result.author.lowercased())
                }
                return true
            }
            return false
        }) else {
            return nil
        }

        // Step 2: Validate — fetch book detail page and parse TOC (first page only)
        var chapterCount = 0
        if let tocRule = legado.tocRule {
            do {
                let bookDetailURL = engine.resolveURL(match.bookURL, base: legado.url)
                let detailHTML = try await NetworkClient.shared.fetchString(url: bookDetailURL)

                var tocResponse = detailHTML
                if let tocUrlRule = legado.bookInfoRule?.tocUrl, !tocUrlRule.isEmpty {
                    let ruleExecutor = RuleExecutor()
                    if let parsedTocUrl = try? ruleExecutor.getString(html: detailHTML, rule: tocUrlRule, baseURL: legado.url),
                       !parsedTocUrl.isEmpty {
                        tocResponse = try await NetworkClient.shared.fetchString(url: engine.resolveURL(parsedTocUrl, base: legado.url))
                    }
                }

                let chapters = try engine.parseChapterList(response: tocResponse, rule: tocRule, baseURL: legado.url)
                chapterCount = chapters.count
            } catch {
                // Validation failed — treat as 0 chapters
                chapterCount = 0
            }
        }

        return FoundSource(
            id: id, sourceName: name, sourceId: id,
            bookURL: match.bookURL, ruleJSON: ruleJSON, sourceURL: sourceURL,
            chapterCount: chapterCount
        )
    }

    // MARK: - Switch source (from search result — ruleJSON in memory)

    private func switchSource(to source: FoundSource) async {
        isSwitching = true
        switchingSourceId = source.sourceId
        error = nil

        do {
            let chapters = try await fetchChapters(ruleJSON: source.ruleJSON, sourceURL: source.sourceURL, bookURL: source.bookURL)
            await applySwitch(sourceId: source.sourceId, sourceName: source.sourceName, bookURL: source.bookURL, ruleJSON: source.ruleJSON, sourceURL: source.sourceURL, chapters: chapters)
        } catch {
            await MainActor.run {
                self.error = describeError(error)
                isSwitching = false
                switchingSourceId = nil
            }
        }
    }

    // MARK: - Switch source (from pinned — need DB lookup for ruleJSON)

    private func switchToPinned(_ source: PinnedSource) async {
        guard let sourceUUID = UUID(uuidString: source.sourceId) else { return }
        isSwitching = true
        switchingSourceId = sourceUUID
        error = nil

        do {
            let descriptor = FetchDescriptor<BookSource>(
                predicate: #Predicate<BookSource> { $0.id == sourceUUID }
            )
            guard let bookSource = try modelContext.fetch(descriptor).first else {
                // Source deleted — auto-unpin
                await MainActor.run {
                    unpinSource(source)
                    self.error = "该书源已被删除，已自动取消收藏"
                    isSwitching = false
                    switchingSourceId = nil
                }
                return
            }

            let chapters = try await fetchChapters(ruleJSON: bookSource.ruleJSON, sourceURL: bookSource.sourceURL, bookURL: source.bookURL)
            await applySwitch(sourceId: sourceUUID, sourceName: source.sourceName, bookURL: source.bookURL, ruleJSON: bookSource.ruleJSON, sourceURL: bookSource.sourceURL, chapters: chapters)
        } catch {
            await MainActor.run {
                self.error = describeError(error)
                isSwitching = false
                switchingSourceId = nil
            }
        }
    }

    // MARK: - Shared: fetch chapters from a source

    private func fetchChapters(ruleJSON: String, sourceURL: String, bookURL: String) async throws -> [ChapterInfo] {
        let legado = try LegadoSourceParser.parse(json: ruleJSON, matchingURL: sourceURL)
        let engine = SourceEngine()
        let resolvedURL = engine.resolveURL(bookURL, base: legado.url)
        let response = try await NetworkClient.shared.fetchString(url: resolvedURL)

        guard let tocRule = legado.tocRule else { throw ChangeSourceError.noTocRule }

        // Separate TOC page
        var tocResponse = response
        if let tocUrlRule = legado.bookInfoRule?.tocUrl, !tocUrlRule.isEmpty {
            let ruleExecutor = RuleExecutor()
            if let parsedTocUrl = try? ruleExecutor.getString(html: response, rule: tocUrlRule, baseURL: legado.url),
               !parsedTocUrl.isEmpty {
                tocResponse = try await NetworkClient.shared.fetchString(url: engine.resolveURL(parsedTocUrl, base: legado.url))
            }
        }

        // First page
        var allChapters = try engine.parseChapterList(response: tocResponse, rule: tocRule, baseURL: legado.url)

        // Pagination
        if let nextRule = tocRule.nextTocUrl, !nextRule.isEmpty {
            var visitedUrls: Set<String> = []
            var currentResponse = tocResponse
            for _ in 0..<200 {
                guard let nextUrl = engine.parseNextTocUrl(response: currentResponse, rule: nextRule, baseURL: legado.url) else { break }
                let resolvedNext = engine.resolveURL(nextUrl, base: legado.url)
                guard !visitedUrls.contains(resolvedNext) else { break }
                visitedUrls.insert(resolvedNext)
                let nextResponse = try await NetworkClient.shared.fetchString(url: resolvedNext)
                let pageChapters = try engine.parseChapterList(response: nextResponse, rule: tocRule, baseURL: legado.url)
                guard !pageChapters.isEmpty else { break }
                allChapters.append(contentsOf: pageChapters)
                currentResponse = nextResponse
            }
        }

        // Deduplicate
        var seen = Set<String>()
        let deduplicated = allChapters.filter { seen.insert("\($0.title)|\($0.url)").inserted }
        guard !deduplicated.isEmpty else { throw ChangeSourceError.noChapters }
        return deduplicated
    }

    // MARK: - Shared: apply chapter switch to Book

    private func applySwitch(sourceId: UUID, sourceName: String, bookURL: String, ruleJSON: String, sourceURL: String, chapters: [ChapterInfo]) async {
        let baseURL: String
        if let legado = try? LegadoSourceParser.parse(json: ruleJSON, matchingURL: sourceURL) {
            baseURL = legado.url
        } else {
            baseURL = sourceURL
        }
        let engine = SourceEngine()

        await MainActor.run {
            // Delete old chapters
            for chapter in book.chapters {
                modelContext.delete(chapter)
            }

            // Create new chapters
            for (i, info) in chapters.enumerated() {
                let ch = Chapter(index: i, title: info.title)
                ch.book = book
                ch.sourceURL = engine.resolveURL(info.url, base: baseURL)
                modelContext.insert(ch)
            }

            // Update book
            book.sourceId = sourceId
            book.sourceBookURL = bookURL
            book.sourceName = sourceName
            book.totalChapters = chapters.count

            if book.lastReadChapterIndex >= chapters.count {
                book.lastReadChapterIndex = max(0, chapters.count - 1)
                book.lastReadPosition = 0
            }

            try? modelContext.save()
            isSwitching = false
            switchingSourceId = nil
        }
    }

    private func describeError(_ error: Error) -> String {
        switch error {
        case ChangeSourceError.noTocRule:  return "该书源没有目录规则"
        case ChangeSourceError.noChapters: return "该书源无法获取章节目录"
        default: return "换源失败：\(error.localizedDescription)"
        }
    }
}

private enum ChangeSourceError: Error {
    case noTocRule
    case noChapters
}
