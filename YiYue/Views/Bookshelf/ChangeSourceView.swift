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

@MainActor
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
    @State private var searchTask: Task<Void, Never>?
    @State private var sourceSwitchTask: Task<Void, Never>?
    @State private var searchGeneration: UUID?
    @State private var switchGeneration: UUID?
    @State private var isViewActive = true
    @State private var isCommittingSwitch = false

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
                    Button("关闭") { close() }
                        .disabled(isCommittingSwitch)
                }
            }
            .task {
                // Only auto-search first time (no cached pinned/blocked data)
                if book.pinnedSources.isEmpty && book.blockedSourceIds.isEmpty {
                    startSearch()
                }
            }
        }
        .interactiveDismissDisabled(isCommittingSwitch)
        .onAppear { isViewActive = true }
        .onDisappear { cancelOwnedTasks() }
    }

    // MARK: - Task lifetime

    private func close() {
        guard !isCommittingSwitch else { return }
        cancelOwnedTasks()
        dismiss()
    }

    private func cancelOwnedTasks() {
        isViewActive = false
        searchGeneration = nil
        switchGeneration = nil
        searchTask?.cancel()
        sourceSwitchTask?.cancel()
        searchTask = nil
        sourceSwitchTask = nil
        isSearching = false
        isSwitching = false
        switchingSourceId = nil
        isCommittingSwitch = false
    }

    private func cancelSearch() {
        searchGeneration = nil
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }

    private func ensureCurrentSearch(_ generation: UUID) throws {
        try Task.checkCancellation()
        guard isViewActive, searchGeneration == generation else {
            throw CancellationError()
        }
    }

    private func ensureCurrentSwitch(_ generation: UUID) throws {
        try Task.checkCancellation()
        guard isViewActive, switchGeneration == generation else {
            throw CancellationError()
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
            startSwitch(to: source)
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
                    startSearch()
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
            startSwitch(to: source)
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

    private func startSearch() {
        guard isViewActive, !isSearching, !isSwitching else { return }
        searchTask?.cancel()

        let generation = UUID()
        searchGeneration = generation
        isSearching = true
        searchedCount = 0
        totalCount = 0
        foundSources = []
        error = nil

        searchTask = Task {
            await searchAllSources(generation: generation)
        }
    }

    private func searchAllSources(generation: UUID) async {
        defer {
            if searchGeneration == generation {
                isSearching = false
                searchGeneration = nil
                searchTask = nil
            }
        }

        do {
            try ensureCurrentSearch(generation)
            var descriptor = FetchDescriptor<BookSource>()
            descriptor.predicate = #Predicate<BookSource> { $0.enabled == true }
            let bookSources = try modelContext.fetch(descriptor)
            try ensureCurrentSearch(generation)

            totalCount = bookSources.count

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
                    guard !Task.isCancelled,
                          searchGeneration == generation,
                          let snap = iterator.next() else { break }
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
                    guard !Task.isCancelled,
                          isViewActive,
                          searchGeneration == generation else {
                        group.cancelAll()
                        break
                    }

                    searchedCount += 1
                    if let found = result {
                        let sid = found.sourceId.uuidString
                        if !foundSources.contains(where: { $0.sourceId == found.sourceId }) {
                            foundSources.append(found)

                            // Auto-categorize (skip current source and already-categorized).
                            // Generation is checked immediately before this model mutation;
                            // there is no suspension until the save finishes.
                            if found.sourceId != currentSourceId &&
                               !existingPinnedIds.contains(sid) &&
                               !existingBlockedIds.contains(sid) {
                                if found.chapterCount > 0 {
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
                                    var ids = book.blockedSourceIds
                                    ids.insert(sid)
                                    book.blockedSourceIds = ids
                                }
                                try? modelContext.save()
                            }
                        }
                    }

                    if !Task.isCancelled,
                       searchGeneration == generation,
                       let snap = iterator.next() {
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

            try ensureCurrentSearch(generation)
            hasSearched = true
        } catch is CancellationError {
            return
        } catch {
            guard isViewActive, searchGeneration == generation else { return }
            hasSearched = true
            self.error = "搜索书源失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Single source search (static, thread-safe)

    private static func searchSingleSource(
        id: UUID, name: String, sourceURL: String, ruleJSON: String,
        bookTitle: String, bookAuthor: String,
        timeoutNanos: UInt64
    ) async -> FoundSource? {
        do {
            try Task.checkCancellation()
            let result = try await withThrowingTaskGroup(of: FoundSource?.self) { group in
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
            try Task.checkCancellation()
            return result
        } catch {
            return nil
        }
    }

    private static func doSearch(
        id: UUID, name: String, sourceURL: String, ruleJSON: String,
        bookTitle: String, bookAuthor: String
    ) async throws -> FoundSource? {
        try Task.checkCancellation()
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
        try Task.checkCancellation()
        guard let searchRule = legado.searchRule else { return nil }

        let results = try engine.parseSearchResults(response: html, rule: searchRule, baseURL: legado.url)
        try Task.checkCancellation()

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
                try Task.checkCancellation()

                var tocResponse = detailHTML
                var tocBaseURL = bookDetailURL
                if let tocUrlRule = legado.bookInfoRule?.tocUrl, !tocUrlRule.isEmpty {
                    let ruleExecutor = RuleExecutor()
                    if let parsedTocUrl = try? ruleExecutor.getString(html: detailHTML, rule: tocUrlRule, baseURL: bookDetailURL),
                       !parsedTocUrl.isEmpty {
                        tocBaseURL = engine.resolveURL(parsedTocUrl, base: bookDetailURL)
                        tocResponse = try await NetworkClient.shared.fetchString(url: tocBaseURL)
                        try Task.checkCancellation()
                    }
                }

                let chapters = try engine.parseChapterList(response: tocResponse, rule: tocRule, baseURL: tocBaseURL)
                try Task.checkCancellation()
                chapterCount = chapters.count
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Validation failed — treat as 0 chapters
                chapterCount = 0
            }
        }

        try Task.checkCancellation()
        return FoundSource(
            id: id, sourceName: name, sourceId: id,
            bookURL: match.bookURL, ruleJSON: ruleJSON, sourceURL: sourceURL,
            chapterCount: chapterCount
        )
    }

    // MARK: - Switch source (from search result — ruleJSON in memory)

    private func startSwitch(to source: FoundSource) {
        guard isViewActive, !isSwitching else { return }
        cancelSearch()

        let generation = UUID()
        switchGeneration = generation
        isSwitching = true
        switchingSourceId = source.sourceId
        error = nil

        sourceSwitchTask = Task {
            await switchSource(to: source, generation: generation)
        }
    }

    private func switchSource(to source: FoundSource, generation: UUID) async {
        defer { finishSwitchIfCurrent(generation) }
        do {
            try ensureCurrentSwitch(generation)
            let chapters = try await fetchChapters(
                ruleJSON: source.ruleJSON,
                sourceURL: source.sourceURL,
                bookURL: source.bookURL,
                generation: generation
            )
            try ensureCurrentSwitch(generation)
            try await applySwitch(
                sourceId: source.sourceId,
                sourceName: source.sourceName,
                bookURL: source.bookURL,
                ruleJSON: source.ruleJSON,
                sourceURL: source.sourceURL,
                chapters: chapters,
                generation: generation
            )
        } catch is CancellationError {
            return
        } catch {
            guard isViewActive, switchGeneration == generation else { return }
            self.error = describeError(error)
        }
    }

    // MARK: - Switch source (from pinned — need DB lookup for ruleJSON)

    private func startSwitch(to source: PinnedSource) {
        guard isViewActive, !isSwitching else { return }
        guard let sourceUUID = UUID(uuidString: source.sourceId) else {
            error = "收藏的书源标识无效"
            return
        }
        cancelSearch()

        let generation = UUID()
        switchGeneration = generation
        isSwitching = true
        switchingSourceId = sourceUUID
        error = nil

        sourceSwitchTask = Task {
            await switchToPinned(source, sourceUUID: sourceUUID, generation: generation)
        }
    }

    private func switchToPinned(
        _ source: PinnedSource,
        sourceUUID: UUID,
        generation: UUID
    ) async {
        defer { finishSwitchIfCurrent(generation) }
        do {
            try ensureCurrentSwitch(generation)
            let descriptor = FetchDescriptor<BookSource>(
                predicate: #Predicate<BookSource> { $0.id == sourceUUID }
            )
            guard let bookSource = try modelContext.fetch(descriptor).first else {
                try ensureCurrentSwitch(generation)
                // Source deleted — auto-unpin
                unpinSource(source)
                self.error = "该书源已被删除，已自动取消收藏"
                return
            }

            let ruleJSON = bookSource.ruleJSON
            let sourceURL = bookSource.sourceURL
            try ensureCurrentSwitch(generation)
            let chapters = try await fetchChapters(
                ruleJSON: ruleJSON,
                sourceURL: sourceURL,
                bookURL: source.bookURL,
                generation: generation
            )
            try ensureCurrentSwitch(generation)
            try await applySwitch(
                sourceId: sourceUUID,
                sourceName: source.sourceName,
                bookURL: source.bookURL,
                ruleJSON: ruleJSON,
                sourceURL: sourceURL,
                chapters: chapters,
                generation: generation
            )
        } catch is CancellationError {
            return
        } catch {
            guard isViewActive, switchGeneration == generation else { return }
            self.error = describeError(error)
        }
    }

    private func finishSwitchIfCurrent(_ generation: UUID) {
        guard switchGeneration == generation else { return }
        isSwitching = false
        switchingSourceId = nil
        isCommittingSwitch = false
        switchGeneration = nil
        sourceSwitchTask = nil
    }

    // MARK: - Shared: fetch chapters from a source

    private func fetchChapters(
        ruleJSON: String,
        sourceURL: String,
        bookURL: String,
        generation: UUID
    ) async throws -> [ChapterInfo] {
        try ensureCurrentSwitch(generation)
        let legado = try LegadoSourceParser.parse(json: ruleJSON, matchingURL: sourceURL)
        let engine = SourceEngine()
        let resolvedURL = engine.resolveURL(bookURL, base: legado.url)
        let response = try await NetworkClient.shared.fetchString(url: resolvedURL)
        try ensureCurrentSwitch(generation)

        guard let tocRule = legado.tocRule else { throw ChangeSourceError.noTocRule }

        // Separate TOC page
        var tocResponse = response
        var tocBaseURL = resolvedURL
        if let tocUrlRule = legado.bookInfoRule?.tocUrl, !tocUrlRule.isEmpty {
            let ruleExecutor = RuleExecutor()
            if let parsedTocUrl = try? ruleExecutor.getString(html: response, rule: tocUrlRule, baseURL: resolvedURL),
               !parsedTocUrl.isEmpty {
                let resolvedTocURL = engine.resolveURL(parsedTocUrl, base: resolvedURL)
                tocResponse = try await NetworkClient.shared.fetchString(url: resolvedTocURL)
                try ensureCurrentSwitch(generation)
                tocBaseURL = resolvedTocURL
            }
        }

        // First page
        var allChapters = try engine.parseChapterList(response: tocResponse, rule: tocRule, baseURL: tocBaseURL)
            .map { ChapterInfo(title: $0.title, url: engine.resolveURL($0.url, base: tocBaseURL)) }
        try ensureCurrentSwitch(generation)

        // Pagination
        if let nextRule = tocRule.nextTocUrl, !nextRule.isEmpty {
            var visitedUrls: Set<String> = []
            var currentResponse = tocResponse
            var currentBaseURL = tocBaseURL
            for _ in 0..<200 {
                try ensureCurrentSwitch(generation)
                guard let nextUrl = engine.parseNextTocUrl(response: currentResponse, rule: nextRule, baseURL: currentBaseURL) else { break }
                let resolvedNext = engine.resolveURL(nextUrl, base: currentBaseURL)
                guard !visitedUrls.contains(resolvedNext) else { break }
                visitedUrls.insert(resolvedNext)
                let nextResponse = try await NetworkClient.shared.fetchString(url: resolvedNext)
                try ensureCurrentSwitch(generation)
                let pageChapters = try engine.parseChapterList(response: nextResponse, rule: tocRule, baseURL: resolvedNext)
                    .map { ChapterInfo(title: $0.title, url: engine.resolveURL($0.url, base: resolvedNext)) }
                try ensureCurrentSwitch(generation)
                guard !pageChapters.isEmpty else { break }
                allChapters.append(contentsOf: pageChapters)
                currentResponse = nextResponse
                currentBaseURL = resolvedNext
            }
        }

        // Deduplicate
        var seen = Set<String>()
        let deduplicated = allChapters.filter { seen.insert("\($0.title)|\($0.url)").inserted }
        try ensureCurrentSwitch(generation)
        guard !deduplicated.isEmpty else { throw ChangeSourceError.noChapters }
        return deduplicated
    }

    // MARK: - Shared: apply chapter switch to Book

    private func applySwitch(
        sourceId: UUID,
        sourceName: String,
        bookURL: String,
        ruleJSON: String,
        sourceURL: String,
        chapters: [ChapterInfo],
        generation: UUID
    ) async throws {
        try ensureCurrentSwitch(generation)
        let baseURL: String
        if let legado = try? LegadoSourceParser.parse(json: ruleJSON, matchingURL: sourceURL) {
            baseURL = legado.url
        } else {
            baseURL = sourceURL
        }
        let engine = SourceEngine()
        let bookID = book.id
        guard try persistedBook(withID: bookID) != nil else {
            throw ChangeSourceError.bookUnavailable
        }

        // This is the commit boundary. User-driven dismissal stays available
        // while networking, then is disabled until cache cleanup and the
        // synchronous SwiftData transaction have both finished.
        try ensureCurrentSwitch(generation)
        isCommittingSwitch = true

        // Source URLs and rules are embedded in persisted jobs. Drain and
        // discard that intent before replacing the chapter list.
        do {
            try await ChapterDownloadManager.shared.clear(bookID: bookID)
        } catch {
            try ensureCurrentSwitch(generation)
            throw ChangeSourceError.cacheClearFailed(error.localizedDescription)
        }

        try ensureCurrentSwitch(generation)
        guard let currentBook = try persistedBook(withID: bookID) else {
            throw ChangeSourceError.bookUnavailable
        }

        // There is no suspension from this point through save, so dismissal
        // cannot interleave with mutations of Book, Chapter, or ModelContext.
        for chapter in currentBook.chapters {
            modelContext.delete(chapter)
        }

        for (index, info) in chapters.enumerated() {
            let chapter = Chapter(index: index, title: info.title)
            chapter.book = currentBook
            chapter.sourceURL = engine.resolveURL(info.url, base: baseURL)
            modelContext.insert(chapter)
        }

        currentBook.sourceId = sourceId
        currentBook.sourceBookURL = bookURL
        currentBook.sourceName = sourceName
        currentBook.totalChapters = chapters.count

        if currentBook.lastReadChapterIndex >= chapters.count {
            currentBook.lastReadChapterIndex = max(0, chapters.count - 1)
            currentBook.lastReadPosition = 0
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw ChangeSourceError.saveFailed(error.localizedDescription)
        }
    }

    private func persistedBook(withID bookID: UUID) throws -> Book? {
        let targetID = bookID
        var descriptor = FetchDescriptor<Book>(
            predicate: #Predicate<Book> { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func describeError(_ error: Error) -> String {
        switch error {
        case ChangeSourceError.noTocRule:  return "该书源没有目录规则"
        case ChangeSourceError.noChapters: return "该书源无法获取章节目录"
        case ChangeSourceError.bookUnavailable:
            return "书籍已不存在，换源已取消"
        case ChangeSourceError.cacheClearFailed(let detail):
            return "无法清理旧缓存，已保留原书源：\(detail)"
        case ChangeSourceError.saveFailed(let detail):
            return "无法保存换源结果：\(detail)"
        default: return "换源失败：\(error.localizedDescription)"
        }
    }
}

private enum ChangeSourceError: Error {
    case noTocRule
    case noChapters
    case bookUnavailable
    case cacheClearFailed(String)
    case saveFailed(String)
}
