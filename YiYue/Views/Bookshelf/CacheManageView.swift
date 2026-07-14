import SwiftUI
import SwiftData

@MainActor
struct CacheManageView: View {
    @Query(sort: \Book.addedDate, order: .reverse) private var books: [Book]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingClearAll = false
    @State private var cacheTask: Task<Void, Never>?
    @State private var cacheGeneration: UUID?
    @State private var maintenanceTask: Task<Void, Never>?
    @State private var maintenanceGeneration: UUID?
    @State private var isPausing = false
    @State private var preparingBookId: UUID?
    @State private var isPreparingCacheSummaries = true
    @State private var cacheSummaries: [UUID: BookCacheSummary] = [:]
    @State private var cachedChapterIDsByBook: [UUID: Set<UUID>] = [:]
    @State private var downloadSnapshots: [UUID: ChapterDownloadSnapshot] = [:]
    @State private var reconciledDownloadMarkers: [UUID: String] = [:]
    @State private var isReconcilingDownload = false
    @State private var operationError: CacheOperationError?
    @State private var isClearing = false
    @State private var cacheStatistics = ChapterCacheStatistics(
        automaticBytes: 0,
        automaticCount: 0,
        userManagedBytes: 0,
        userManagedCount: 0
    )

    private var sourceBooks: [Book] {
        books.filter { $0.sourceId != nil }
    }

    private var totalCachedChapters: Int {
        sourceBooks.reduce(0) { $0 + summary(for: $1).cached }
    }

    private var hasActiveDownload: Bool {
        downloadSnapshots.values.contains { $0.phase.isActive }
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
                    HStack {
                        Text("主动缓存占用")
                        Spacer()
                        Text(formattedBytes(cacheStatistics.userManagedBytes))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("临时缓存占用")
                        Spacer()
                        Text("\(formattedBytes(cacheStatistics.automaticBytes)) / 256 MB")
                            .foregroundStyle(.secondary)
                    }
                    Text("临时缓存由阅读和预取产生，超过上限后按最近使用时间自动回收；主动缓存不会自动删除。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if cacheStatistics.automaticCount > 0 {
                        Button("清除临时缓存") { clearAutomaticCache() }
                            .disabled(
                                isClearing || cacheTask != nil || hasActiveDownload
                                    || isPreparingCacheSummaries || isReconcilingDownload
                            )
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
                        if isPreparingCacheSummaries {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("正在检查已有缓存…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(sourceBooks) { book in
                            bookRow(book)
                        }
                    }

                    if totalCachedChapters > 0 {
                        Section {
                            Button("清除全部缓存", role: .destructive) {
                                showingClearAll = true
                            }
                            .disabled(
                                isClearing || cacheTask != nil || hasActiveDownload
                                    || isPreparingCacheSummaries || isReconcilingDownload
                            )
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
                        .disabled(isClearing || isReconcilingDownload)
                }
            }
            .alert("确认清除", isPresented: $showingClearAll) {
                Button("取消", role: .cancel) {}
                Button("清除全部", role: .destructive) { clearAllCache() }
            } message: {
                Text("将清除所有书籍的缓存章节内容，下次阅读需要重新加载")
            }
            .alert(item: $operationError) { error in
                Alert(
                    title: Text("缓存操作失败"),
                    message: Text(error.message),
                    dismissButton: .default(Text("确定"))
                )
            }
            .task {
                await prepareCacheStateAndObserveDownloads()
            }
            .onDisappear {
                // Preparing a queue belongs to this presentation, but an
                // already-enqueued download belongs to the app and continues.
                cacheTask?.cancel()
                maintenanceTask?.cancel()
                maintenanceGeneration = nil
                try? modelContext.save()
            }
            .interactiveDismissDisabled(isClearing || isReconcilingDownload)
        }
    }

    @ViewBuilder
    private func bookRow(_ book: Book) -> some View {
        let cacheSummary = summary(for: book)
        let cached = cacheSummary.cached
        let total = book.totalChapters
        let uncachedCount = cacheSummary.uncached
        let downloadSnapshot = downloadSnapshots[book.id]
        let isCachingThis = downloadSnapshot?.phase.isActive == true
        let isPreparingThis = preparingBookId == book.id
        let processedCount = downloadSnapshot.map(downloadProgressCount) ?? 0
        let targetCount = downloadSnapshot?.targetCount ?? 0

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
                    .buttonStyle(.borderless)
                    .disabled(
                        isClearing || cacheTask != nil || hasActiveDownload
                            || isPreparingCacheSummaries || isReconcilingDownload
                    )
                }
            }

            // 缓存进度条 & 操作按钮
            if isPreparingThis {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在核对磁盘缓存…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if isCachingThis {
                VStack(spacing: 6) {
                    ProgressView(value: Double(processedCount), total: Double(max(1, targetCount)))
                        .tint(.blue)
                    HStack {
                        Text(downloadProgressText(downloadSnapshot))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            pauseCaching(bookID: book.id)
                        } label: {
                            HStack(spacing: 3) {
                                if isPausing {
                                    ProgressView()
                                        .controlSize(.mini)
                                } else {
                                    Image(systemName: "pause.fill")
                                        .font(.system(size: 10))
                                }
                                Text(isPausing ? "暂停中…" : "暂停")
                                    .font(.caption)
                            }
                            .foregroundStyle(.orange)
                        }
                        .buttonStyle(.borderless)
                        .disabled(isPausing || downloadSnapshot?.phase == .pausing)
                    }
                }
            } else if downloadSnapshot?.phase == .paused || downloadSnapshot?.phase == .failed {
                HStack(spacing: 12) {
                    Button {
                        resumeCaching(bookID: book.id)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.clockwise.circle")
                                .font(.system(size: 12))
                            Text(downloadSnapshot?.phase == .failed ? "重试" : "继续缓存")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(
                        cacheTask != nil || isClearing || hasActiveDownload
                            || isPreparingCacheSummaries || isReconcilingDownload
                    )

                    Text("已持久缓存 \(downloadSnapshot?.durableStoredCount ?? 0) / \(downloadSnapshot?.targetCount ?? 0)")
                        .font(.caption)
                        .foregroundStyle(downloadSnapshot?.phase == .failed ? .red : .secondary)
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
                    .buttonStyle(.borderless)
                    .disabled(
                        cacheTask != nil
                            || hasActiveDownload
                            || isClearing
                            || isPausing
                            || isPreparingCacheSummaries
                            || isReconcilingDownload
                    )

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
        guard cacheTask == nil,
              !hasActiveDownload,
              preparingBookId == nil,
              !isClearing,
              !isPausing,
              !isPreparingCacheSummaries,
              !isReconcilingDownload else { return }
        guard let sourceId = book.sourceId, book.sourceBookURL != nil else { return }

        let descriptor = FetchDescriptor<BookSource>(predicate: #Predicate<BookSource> { $0.id == sourceId })
        guard let bookSource = try? modelContext.fetch(descriptor).first,
              let legado = try? LegadoSourceParser.parse(
                json: bookSource.ruleJSON,
                matchingURL: bookSource.sourceURL
              ),
              let contentRule = legado.contentRule else { return }

        let bookID = book.id
        let bookTitle = book.title
        let modelContainer = modelContext.container
        let generation = UUID()
        cacheGeneration = generation
        preparingBookId = bookID
        cacheTask = Task {
            defer {
                if cacheGeneration == generation {
                    cacheGeneration = nil
                    preparingBookId = nil
                    cacheTask = nil
                }
            }

            let preparationToken = await ChapterDownloadManager.shared
                .makePreparationToken(bookID: bookID)
            guard !Task.isCancelled, cacheGeneration == generation else { return }

            let storedChapterIDs: Set<UUID>
            do {
                storedChapterIDs = try await ChapterContentStore.shared.storedChapterIDs(
                    bookID: bookID,
                    retention: .userManaged
                )
            } catch is CancellationError {
                return
            } catch {
                guard cacheGeneration == generation else { return }
                operationError = CacheOperationError(
                    message: "无法检查《\(bookTitle)》的已有缓存：\(error.localizedDescription)"
                )
                return
            }
            guard !Task.isCancelled, cacheGeneration == generation else { return }

            let jobs: [ChapterCacheJob]
            do {
                let worker = Task.detached(priority: .userInitiated) {
                    try ChapterCacheJobWorker.makeJobs(
                        bookID: bookID,
                        storedChapterIDs: storedChapterIDs,
                        count: count,
                        in: modelContainer
                    )
                }
                jobs = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
            } catch {
                guard !Task.isCancelled else { return }
                operationError = CacheOperationError(
                    message: "无法准备《\(bookTitle)》的缓存任务：\(error.localizedDescription)"
                )
                return
            }
            guard !Task.isCancelled, cacheGeneration == generation else { return }

            guard !jobs.isEmpty else {
                await reconcileCacheSummary(
                    for: book,
                    fallbackContents: [:],
                    modelContainer: modelContainer
                )
                await refreshDiskStatistics()
                return
            }

            let request = ChapterDownloadRequest(
                bookID: bookID,
                bookTitle: bookTitle,
                jobs: jobs.map {
                    ChapterDownloadJob(
                        bookID: $0.bookID,
                        chapterID: $0.chapterID,
                        sourceURL: $0.sourceURL,
                        nextChapterURL: $0.nextChapterURL
                    )
                },
                configuration: ChapterDownloadConfiguration(
                    rule: contentRule,
                    baseURL: legado.url
                )
            )

            do {
                try Task.checkCancellation()
                let snapshot = try await ChapterDownloadManager.shared.enqueue(
                    request,
                    preparationToken: preparationToken
                )
                downloadSnapshots[bookID] = snapshot
                ChapterDownloadSystemTask.shared.submitUserInitiated(
                    bookID: bookID,
                    bookTitle: bookTitle
                )
            } catch is CancellationError {
                return
            } catch {
                guard cacheGeneration == generation else { return }
                operationError = CacheOperationError(
                    message: "无法启动《\(bookTitle)》的缓存：\(error.localizedDescription)"
                )
            }
        }
    }

    private func prepareCacheStateAndObserveDownloads() async {
        // Subscribe first. The stream carries a coalesced invalidation, while
        // every refresh below reads authoritative actor state.
        let stream = await ChapterDownloadManager.shared.updates(replayCurrent: false)
        let initialSnapshots = await ChapterDownloadManager.shared.allSnapshots()
        downloadSnapshots = Dictionary(
            uniqueKeysWithValues: initialSnapshots.map { ($0.bookID, $0) }
        )

        isPreparingCacheSummaries = true
        await refreshCacheSummaries()
        isPreparingCacheSummaries = false
        guard !Task.isCancelled else { return }

        // The full refresh already reconciled these historical terminal states.
        // Seeding their markers avoids a second O(chapters) metadata pass.
        for snapshot in initialSnapshots where snapshot.phase == .paused
            || snapshot.phase == .completed
            || snapshot.phase == .failed {
            reconciledDownloadMarkers[snapshot.bookID] = downloadMarker(snapshot)
        }

        // Capture anything that changed while the full disk pass was running.
        await synchronizeDownloadSnapshots(
            await ChapterDownloadManager.shared.allSnapshots()
        )

        for await _ in stream {
            guard !Task.isCancelled else { return }
            await synchronizeDownloadSnapshots(
                await ChapterDownloadManager.shared.allSnapshots()
            )
        }
    }

    private func synchronizeDownloadSnapshots(
        _ snapshots: [ChapterDownloadSnapshot]
    ) async {
        downloadSnapshots = Dictionary(
            uniqueKeysWithValues: snapshots.map { ($0.bookID, $0) }
        )

        for snapshot in snapshots {
            guard snapshot.phase == .paused
                    || snapshot.phase == .completed
                    || snapshot.phase == .failed else { continue }
            let marker = downloadMarker(snapshot)
            guard reconciledDownloadMarkers[snapshot.bookID] != marker else { continue }

            if let book = sourceBooks.first(where: { $0.id == snapshot.bookID }) {
                isReconcilingDownload = true
                await reconcileCacheSummary(
                    for: book,
                    fallbackContents: [:],
                    modelContainer: modelContext.container
                )
                await refreshDiskStatistics()
                isReconcilingDownload = false
            }
            guard !Task.isCancelled else { return }
            reconciledDownloadMarkers[snapshot.bookID] = marker
            if snapshot.phase == .failed, let lastError = snapshot.lastError {
                operationError = CacheOperationError(
                    message: "《\(snapshot.bookTitle)》缓存未完成：\(lastError)"
                )
            }
        }
    }

    private func downloadMarker(_ snapshot: ChapterDownloadSnapshot) -> String {
        "\(snapshot.id.uuidString)-\(snapshot.phase.rawValue)-\(snapshot.updatedAt.timeIntervalSince1970)"
    }

    private func pauseCaching(bookID: UUID) {
        guard !isPausing else { return }
        isPausing = true
        Task {
            defer { isPausing = false }
            if let snapshot = await ChapterDownloadManager.shared.pause(bookID: bookID) {
                downloadSnapshots[bookID] = snapshot
            }
        }
    }

    private func resumeCaching(bookID: UUID) {
        guard !hasActiveDownload,
              !isClearing,
              !isPreparingCacheSummaries,
              !isReconcilingDownload else { return }
        Task {
            do {
                if let snapshot = try await ChapterDownloadManager.shared.resume(bookID: bookID) {
                    downloadSnapshots[bookID] = snapshot
                    ChapterDownloadSystemTask.shared.submitUserInitiated(
                        bookID: bookID,
                        bookTitle: snapshot.bookTitle
                    )
                }
            } catch {
                operationError = CacheOperationError(
                    message: "无法继续缓存：\(error.localizedDescription)"
                )
            }
        }
    }

    private func downloadProgressText(_ snapshot: ChapterDownloadSnapshot?) -> String {
        guard let snapshot else { return "正在准备缓存…" }
        switch snapshot.phase {
        case .queued:
            return "等待缓存，队列第 \(snapshot.queuePosition ?? 1) 位"
        case .pausing:
            return "暂停中，正在等待 \(snapshot.inFlightCount) 个在途任务收口…"
        case .running:
            let durableCount = min(
                snapshot.targetCount,
                snapshot.durableStoredCount + snapshot.succeededCount
            )
            return "进度 \(downloadProgressCount(snapshot))/\(snapshot.targetCount)，已持久缓存 \(durableCount)"
        case .paused, .completed, .failed, .cancelled:
            return "已持久缓存 \(snapshot.durableStoredCount)/\(snapshot.targetCount)"
        }
    }

    private func downloadProgressCount(_ snapshot: ChapterDownloadSnapshot) -> Int {
        min(
            snapshot.targetCount,
            snapshot.durableStoredCount + snapshot.processedCount
        )
    }

    // MARK: - 清除缓存

    private func clearCache(for book: Book) {
        guard !isClearing,
              cacheTask == nil,
              maintenanceTask == nil,
              !hasActiveDownload,
              !isPreparingCacheSummaries,
              !isReconcilingDownload else { return }
        let generation = UUID()
        let bookID = book.id
        let bookTitle = book.title
        maintenanceGeneration = generation
        isClearing = true
        maintenanceTask = Task {
            defer {
                if maintenanceGeneration == generation {
                    maintenanceGeneration = nil
                    maintenanceTask = nil
                    isClearing = false
                }
            }
            do {
                try await ChapterDownloadManager.shared.clear(bookID: bookID)
            } catch {
                guard !Task.isCancelled, maintenanceGeneration == generation else { return }
                operationError = CacheOperationError(
                    message: "无法清除《\(bookTitle)》：\(error.localizedDescription)"
                )
                return
            }
            guard !Task.isCancelled, maintenanceGeneration == generation else { return }
            var metadataError: Error?
            var metadataSummaries: [UUID: BookCacheSummary] = [:]
            do {
                metadataSummaries = try await clearCacheMetadata(
                    bookIDs: [bookID],
                    modelContainer: modelContext.container
                )
            } catch is CancellationError {
                return
            } catch {
                metadataError = error
            }
            guard !Task.isCancelled, maintenanceGeneration == generation else { return }
            cachedChapterIDsByBook[bookID] = []
            cacheSummaries[bookID] = metadataSummaries[bookID]
                ?? BookCacheSummary(cached: 0, uncached: max(0, book.totalChapters))
            downloadSnapshots.removeValue(forKey: bookID)
            reconciledDownloadMarkers.removeValue(forKey: bookID)
            if let metadataError {
                operationError = CacheOperationError(
                    message: "缓存已从磁盘清除，但章节状态保存失败：\(metadataError.localizedDescription)"
                )
            }
            await refreshDiskStatistics()
        }
    }

    private func clearAllCache() {
        guard !isClearing,
              cacheTask == nil,
              maintenanceTask == nil,
              !hasActiveDownload,
              !isPreparingCacheSummaries,
              !isReconcilingDownload else { return }
        let generation = UUID()
        maintenanceGeneration = generation
        isClearing = true
        let booksToClear = sourceBooks
        maintenanceTask = Task {
            defer {
                if maintenanceGeneration == generation {
                    maintenanceGeneration = nil
                    maintenanceTask = nil
                    isClearing = false
                }
            }
            var failedBooks: [String] = []
            var failedBookIDs: Set<UUID> = []
            for book in booksToClear {
                guard !Task.isCancelled, maintenanceGeneration == generation else { return }
                do {
                    try await ChapterDownloadManager.shared.clear(bookID: book.id)
                } catch {
                    failedBooks.append(book.title)
                    failedBookIDs.insert(book.id)
                    continue
                }
            }
            guard !Task.isCancelled, maintenanceGeneration == generation else { return }

            let clearedBooks = booksToClear.filter { !failedBookIDs.contains($0.id) }
            var metadataError: Error?
            var metadataSummaries: [UUID: BookCacheSummary] = [:]
            do {
                metadataSummaries = try await clearCacheMetadata(
                    bookIDs: clearedBooks.map(\.id),
                    modelContainer: modelContext.container
                )
            } catch is CancellationError {
                return
            } catch {
                metadataError = error
            }
            guard !Task.isCancelled, maintenanceGeneration == generation else { return }

            for book in clearedBooks {
                cachedChapterIDsByBook[book.id] = []
                cacheSummaries[book.id] = metadataSummaries[book.id]
                    ?? BookCacheSummary(cached: 0, uncached: max(0, book.totalChapters))
                downloadSnapshots.removeValue(forKey: book.id)
                reconciledDownloadMarkers.removeValue(forKey: book.id)
            }
            await refreshDiskStatistics()

            var messages: [String] = []
            if let metadataError {
                messages.append(
                    "部分磁盘缓存已清除，但章节状态保存失败：\(metadataError.localizedDescription)"
                )
            }
            if !failedBooks.isEmpty {
                messages.append("以下书籍未能清除：\(failedBooks.joined(separator: "、"))")
            }
            if !messages.isEmpty {
                operationError = CacheOperationError(
                    message: messages.joined(separator: "\n")
                )
            }
        }
    }

    private func clearAutomaticCache() {
        guard !isClearing,
              cacheTask == nil,
              maintenanceTask == nil,
              !hasActiveDownload,
              !isPreparingCacheSummaries,
              !isReconcilingDownload else { return }
        let generation = UUID()
        maintenanceGeneration = generation
        isClearing = true
        maintenanceTask = Task {
            defer {
                if maintenanceGeneration == generation {
                    maintenanceGeneration = nil
                    maintenanceTask = nil
                    isClearing = false
                }
            }
            do {
                try await ChapterContentStore.shared.clearAutomaticCache()
                guard !Task.isCancelled, maintenanceGeneration == generation else { return }
                await refreshDiskStatistics()
            } catch {
                guard !Task.isCancelled, maintenanceGeneration == generation else { return }
                operationError = CacheOperationError(
                    message: "无法清除临时缓存：\(error.localizedDescription)"
                )
            }
        }
    }

    private func hasCachedContent(_ chapter: Chapter, bookID: UUID) -> Bool {
        if let cachedChapterIDs = cachedChapterIDsByBook[bookID] {
            return cachedChapterIDs.contains(chapter.id)
        }
        return chapter.isCached
    }

    private func calculateSummary(for book: Book) -> BookCacheSummary {
        var cached = 0
        var uncached = 0
        for chapter in book.chapters where chapter.sourceURL != nil {
            if hasCachedContent(chapter, bookID: book.id) {
                cached += 1
            } else {
                uncached += 1
            }
        }
        return BookCacheSummary(cached: cached, uncached: uncached)
    }

    private func summary(for book: Book) -> BookCacheSummary {
        cacheSummaries[book.id] ?? calculateSummary(for: book)
    }

    private func reconcileCacheSummary(
        for book: Book,
        fallbackContents: [UUID: String],
        modelContainer: ModelContainer
    ) async {
        let storedIDs: Set<UUID>
        do {
            storedIDs = try await ChapterContentStore.shared.storedChapterIDs(
                bookID: book.id,
                retention: .userManaged
            )
        } catch {
            // Disk is the durable source of truth. If it cannot be enumerated,
            // preserve the last known state instead of reconciling against an
            // invented empty set and clearing otherwise-valid metadata.
            for chapter in book.chapters {
                guard let fallbackContent = fallbackContents[chapter.id] else { continue }
                chapter.content = fallbackContent
                chapter.isCached = true
            }
            var preservedIDs = cachedChapterIDsByBook[book.id] ?? Set(
                book.chapters.lazy
                    .filter { $0.sourceURL != nil && $0.isCached }
                    .map(\.id)
            )
            preservedIDs.formUnion(fallbackContents.keys)
            cachedChapterIDsByBook[book.id] = preservedIDs
            cacheSummaries[book.id] = BookCacheSummaryReconciler.reconcile(
                chapters: book.chapters.map(BookCacheChapterSnapshot.init),
                storedChapterIDs: preservedIDs
            ).summary
            try? modelContext.save()
            operationError = CacheOperationError(
                message: "无法重新核对《\(book.title)》的磁盘缓存：\(error.localizedDescription)"
            )
            return
        }
        let bookID = book.id
        do {
            let worker = Task.detached(priority: .utility) {
                try ChapterCacheMetadataWorker.reconcile(
                    bookID: bookID,
                    storedChapterIDs: storedIDs,
                    fallbackContents: fallbackContents,
                    in: modelContainer
                )
            }
            let result = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled else { return }
            cachedChapterIDsByBook[bookID] = result.cachedChapterIDs
            cacheSummaries[bookID] = result.summary
        } catch {
            // A metadata save failure must not hide successfully written files.
            // Keep the row correct and repair SwiftData on the next refresh.
            let result = BookCacheSummaryReconciler.reconcile(
                chapters: book.chapters.map(BookCacheChapterSnapshot.init),
                storedChapterIDs: storedIDs.union(fallbackContents.keys)
            )
            cachedChapterIDsByBook[bookID] = result.cachedChapterIDs
            cacheSummaries[bookID] = result.summary
        }
    }

    private func refreshCacheSummaries() async {
        var summaries: [UUID: BookCacheSummary] = [:]
        var cachedIDsByBook: [UUID: Set<UUID>] = [:]
        var unreadableBooks: [String] = []
        let modelContainer = modelContext.container
        for book in sourceBooks {
            guard !Task.isCancelled else { return }
            let storedIDs: Set<UUID>
            do {
                storedIDs = try await ChapterContentStore.shared.storedChapterIDs(
                    bookID: book.id,
                    retention: .userManaged
                )
            } catch {
                // Keep the last known UI/model state when the directory cannot
                // be read. Treating this as an empty directory would turn a
                // transient I/O error into a destructive metadata reset.
                unreadableBooks.append(book.title)
                if let existingIDs = cachedChapterIDsByBook[book.id] {
                    cachedIDsByBook[book.id] = existingIDs
                }
                summaries[book.id] = cacheSummaries[book.id] ?? calculateSummary(for: book)
                continue
            }
            let bookID = book.id
            do {
                let worker = Task.detached(priority: .utility) {
                    try ChapterCacheMetadataWorker.reconcile(
                        bookID: bookID,
                        storedChapterIDs: storedIDs,
                        fallbackContents: [:],
                        in: modelContainer
                    )
                }
                let result = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled else { return }
                cachedIDsByBook[bookID] = result.cachedChapterIDs
                summaries[bookID] = result.summary
            } catch {
                guard !Task.isCancelled else { return }
                let result = BookCacheSummaryReconciler.reconcile(
                    chapters: book.chapters.map(BookCacheChapterSnapshot.init),
                    storedChapterIDs: storedIDs
                )
                cachedIDsByBook[bookID] = result.cachedChapterIDs
                summaries[bookID] = result.summary
            }
        }
        guard !Task.isCancelled else { return }
        cachedChapterIDsByBook = cachedIDsByBook
        cacheSummaries = summaries
        await refreshDiskStatistics()
        if !unreadableBooks.isEmpty {
            operationError = CacheOperationError(
                message: "无法读取以下书籍的磁盘缓存，已保留原状态：\(unreadableBooks.joined(separator: "、"))"
            )
        }
    }

    private func refreshDiskStatistics() async {
        if let statistics = try? await ChapterContentStore.shared.statistics() {
            cacheStatistics = statistics
        }
    }

    private func clearCacheMetadata(
        bookIDs: [UUID],
        modelContainer: ModelContainer
    ) async throws -> [UUID: BookCacheSummary] {
        guard !bookIDs.isEmpty else { return [:] }
        let worker = Task.detached(priority: .utility) {
            try ChapterCacheMetadataWorker.clear(
                bookIDs: bookIDs,
                in: modelContainer
            )
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

}

struct BookCacheSummary: Sendable, Equatable {
    var cached: Int
    var uncached: Int
}

struct BookCacheChapterSnapshot: Sendable, Equatable {
    let id: UUID
    let hasSourceURL: Bool
    let hasValidLegacyCache: Bool

    @MainActor
    init(_ chapter: Chapter) {
        id = chapter.id
        hasSourceURL = chapter.sourceURL != nil
        hasValidLegacyCache = chapter.isCached
            && SourceEngine.isValidContent(chapter.content)
    }

    init(id: UUID, hasSourceURL: Bool, hasValidLegacyCache: Bool) {
        self.id = id
        self.hasSourceURL = hasSourceURL
        self.hasValidLegacyCache = hasValidLegacyCache
    }
}

struct BookCacheReconciliationResult: Sendable, Equatable {
    let cachedChapterIDs: Set<UUID>
    let summary: BookCacheSummary
}

enum BookCacheSummaryReconciler {
    static func reconcile(
        chapters: [BookCacheChapterSnapshot],
        storedChapterIDs: Set<UUID>
    ) -> BookCacheReconciliationResult {
        let eligibleChapters = chapters.filter(\.hasSourceURL)
        var cachedChapterIDs = Set(
            eligibleChapters.lazy
                .map(\.id)
                .filter { storedChapterIDs.contains($0) }
        )
        for chapter in eligibleChapters where chapter.hasValidLegacyCache {
            cachedChapterIDs.insert(chapter.id)
        }
        return BookCacheReconciliationResult(
            cachedChapterIDs: cachedChapterIDs,
            summary: BookCacheSummary(
                cached: cachedChapterIDs.count,
                uncached: max(0, eligibleChapters.count - cachedChapterIDs.count)
            )
        )
    }
}

enum ChapterCacheMetadataWorker {
    /// Reconciles SwiftData with the disk cache using a private context that is
    /// created, used, and saved entirely on the caller's background executor.
    /// No model instance escapes this function.
    static func reconcile(
        bookID: UUID,
        storedChapterIDs: Set<UUID>,
        fallbackContents: [UUID: String],
        in container: ModelContainer
    ) throws -> BookCacheReconciliationResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let targetID = bookID
        var descriptor = FetchDescriptor<Book>(
            predicate: #Predicate<Book> { book in
                book.id == targetID
            }
        )
        descriptor.fetchLimit = 1

        guard let book = try context.fetch(descriptor).first else {
            return BookCacheReconciliationResult(
                cachedChapterIDs: [],
                summary: BookCacheSummary(cached: 0, uncached: 0)
            )
        }

        var cachedChapterIDs: Set<UUID> = []
        var eligibleCount = 0
        for (index, chapter) in book.chapters.enumerated() where chapter.sourceURL != nil {
            if index.isMultiple(of: 50) {
                try Task.checkCancellation()
            }
            eligibleCount += 1
            if let fallbackContent = fallbackContents[chapter.id],
               SourceEngine.isValidContent(fallbackContent) {
                chapter.content = fallbackContent
                chapter.isCached = true
            }

            let hasValidLegacyCache = chapter.isCached
                && SourceEngine.isValidContent(chapter.content)
            let shouldBeCached = storedChapterIDs.contains(chapter.id)
                || hasValidLegacyCache
            if chapter.isCached != shouldBeCached {
                chapter.isCached = shouldBeCached
            }
            if shouldBeCached {
                cachedChapterIDs.insert(chapter.id)
            }
        }

        do {
            try Task.checkCancellation()
            if context.hasChanges {
                try context.save()
            }
        } catch {
            context.rollback()
            throw error
        }

        return BookCacheReconciliationResult(
            cachedChapterIDs: cachedChapterIDs,
            summary: BookCacheSummary(
                cached: cachedChapterIDs.count,
                uncached: max(0, eligibleCount - cachedChapterIDs.count)
            )
        )
    }

    /// Clears remote cache flags/content in a private context. Large books no
    /// longer require thousands of main-actor mutations, and a failed save is
    /// rolled back as one transaction while disk remains the source of truth.
    static func clear(
        bookIDs: [UUID],
        in container: ModelContainer
    ) throws -> [UUID: BookCacheSummary] {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var summaries: [UUID: BookCacheSummary] = [:]

        do {
            for (bookOffset, bookID) in bookIDs.enumerated() {
                if bookOffset.isMultiple(of: 10) {
                    try Task.checkCancellation()
                }
                let targetID = bookID
                var descriptor = FetchDescriptor<Book>(
                    predicate: #Predicate<Book> { book in
                        book.id == targetID
                    }
                )
                descriptor.fetchLimit = 1
                guard let book = try context.fetch(descriptor).first else { continue }

                var eligibleCount = 0
                for (chapterOffset, chapter) in book.chapters.enumerated()
                    where chapter.sourceURL != nil {
                    if chapterOffset.isMultiple(of: 50) {
                        try Task.checkCancellation()
                    }
                    eligibleCount += 1
                    chapter.content = nil
                    chapter.isCached = false
                }
                summaries[bookID] = BookCacheSummary(cached: 0, uncached: eligibleCount)
            }

            try Task.checkCancellation()
            if context.hasChanges {
                try context.save()
            }
            return summaries
        } catch {
            context.rollback()
            throw error
        }
    }
}

enum ChapterCacheJobWorker {
    /// Builds an immutable cache queue in a private SwiftData context. The
    /// caller supplies a fresh disk snapshot so already stored chapters are
    /// excluded even when UI or SwiftData metadata is temporarily stale.
    static func makeJobs(
        bookID: UUID,
        storedChapterIDs: Set<UUID>,
        count: Int?,
        in container: ModelContainer
    ) throws -> [ChapterCacheJob] {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let targetID = bookID
        var descriptor = FetchDescriptor<Book>(
            predicate: #Predicate<Book> { book in
                book.id == targetID
            }
        )
        descriptor.fetchLimit = 1

        guard let book = try context.fetch(descriptor).first else { return [] }

        try Task.checkCancellation()
        let chapters = book.chapters
            .filter { $0.sourceURL != nil }
            .sorted { $0.index < $1.index }
        var sourceURLByIndex: [Int: String] = [:]
        for (index, chapter) in chapters.enumerated() {
            if index.isMultiple(of: 50) {
                try Task.checkCancellation()
            }
            if let sourceURL = chapter.sourceURL {
                sourceURLByIndex[chapter.index] = sourceURL
            }
        }

        let uncached = chapters.filter { chapter in
            guard !storedChapterIDs.contains(chapter.id) else { return false }
            let hasValidLegacyCache = chapter.isCached
                && SourceEngine.isValidContent(chapter.content)
            return !hasValidLegacyCache
        }
        let selected: ArraySlice<Chapter>
        if let count {
            selected = uncached.prefix(max(0, count))
        } else {
            selected = uncached[...]
        }

        try Task.checkCancellation()
        return selected.compactMap { chapter in
            guard let sourceURL = chapter.sourceURL else { return nil }
            return ChapterCacheJob(
                bookID: bookID,
                chapterID: chapter.id,
                sourceURL: sourceURL,
                nextChapterURL: sourceURLByIndex[chapter.index + 1]
            )
        }
    }
}

private struct CacheOperationError: Identifiable {
    let id = UUID()
    let message: String
}

struct ChapterCacheJob: Sendable {
    let bookID: UUID
    let chapterID: UUID
    let sourceURL: String
    let nextChapterURL: String?
}
