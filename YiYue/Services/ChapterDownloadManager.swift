import Foundation

struct ChapterDownloadConfiguration: Codable, Sendable, Equatable {
    let contentRule: String?
    let replaceRegex: String?
    let nextContentURLRule: String?
    let baseURL: String

    init(rule: LegadoSource.ContentRule, baseURL: String) {
        self.contentRule = rule.content
        self.replaceRegex = rule.replaceRegex
        self.nextContentURLRule = rule.nextContentUrl
        self.baseURL = baseURL
    }

    init(
        contentRule: String?,
        replaceRegex: String?,
        nextContentURLRule: String?,
        baseURL: String
    ) {
        self.contentRule = contentRule
        self.replaceRegex = replaceRegex
        self.nextContentURLRule = nextContentURLRule
        self.baseURL = baseURL
    }

    var legadoRule: LegadoSource.ContentRule {
        LegadoSource.ContentRule(
            content: contentRule,
            replaceRegex: replaceRegex,
            nextContentUrl: nextContentURLRule
        )
    }
}

struct ChapterDownloadJob: Codable, Sendable, Hashable {
    let bookID: UUID
    let chapterID: UUID
    let sourceURL: String
    let nextChapterURL: String?
}

struct ChapterDownloadRequest: Sendable {
    let bookID: UUID
    let bookTitle: String
    let jobs: [ChapterDownloadJob]
    let configuration: ChapterDownloadConfiguration

    init(
        bookID: UUID,
        bookTitle: String,
        jobs: [ChapterDownloadJob],
        configuration: ChapterDownloadConfiguration
    ) {
        self.bookID = bookID
        self.bookTitle = bookTitle
        self.jobs = jobs
        self.configuration = configuration
    }
}

struct ChapterDownloadPreparationToken: Sendable, Equatable {
    fileprivate let bookID: UUID
    fileprivate let revision: UInt64
    fileprivate let globalRevision: UInt64
}

enum ChapterDownloadPhase: String, Codable, Sendable {
    case queued
    case running
    case pausing
    case paused
    case completed
    case failed
    case cancelled

    var isActive: Bool {
        switch self {
        case .queued, .running, .pausing: true
        case .paused, .completed, .failed, .cancelled: false
        }
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: true
        case .queued, .running, .pausing, .paused: false
        }
    }
}

struct ChapterDownloadSnapshot: Sendable, Equatable, Identifiable {
    let id: UUID
    let bookID: UUID
    let bookTitle: String
    let phase: ChapterDownloadPhase
    let targetCount: Int
    let processedCount: Int
    let succeededCount: Int
    let durableStoredCount: Int
    let failedCount: Int
    let inFlightCount: Int
    let queuePosition: Int?
    let lastError: String?
    let updatedAt: Date
}

enum ChapterDownloadManagerError: LocalizedError, Sendable {
    case emptyRequest
    case mixedBookIdentifiers
    case configurationChanged
    case stalePreparation
    case clearingInProgress
    case bootstrapUnavailable(String)
    case persistenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyRequest:
            "没有可缓存的章节"
        case .mixedBookIdentifiers:
            "缓存任务和这本书对不上，已取消"
        case .configurationChanged:
            "书源规则已经变化，请先暂停当前缓存任务后重试"
        case .stalePreparation:
            "书籍状态已变化，已取消过期的缓存准备任务"
        case .clearingInProgress:
            "缓存正在清理，请稍后重试"
        case .bootstrapUnavailable(let message):
            "缓存队列暂不可用：\(message)"
        case .persistenceFailed(let message):
            "无法保存缓存队列：\(message)"
        }
    }
}

/// App-lifetime owner of explicit chapter downloads.
///
/// The checkpoint records intent, while `ChapterContentStore` remains the only
/// authority for completed work. A process crash after an atomic chapter write
/// but before the next checkpoint therefore never causes that chapter to be
/// downloaded again.
actor ChapterDownloadManager {
    static let shared = ChapterDownloadManager()

    private enum PauseIntent: Equatable {
        case user
        case system
    }

    private enum PersistedStateLoadError: LocalizedError {
        case io(String)
        case corrupt(String)

        var errorDescription: String? {
            switch self {
            case .io(let message), .corrupt(let message):
                message
            }
        }
    }

    private struct ClearMarker {
        let operationEpoch: UInt64
        let checkpointID: UUID?
    }

    typealias FetchOperation = @Sendable (
        _ job: ChapterDownloadJob,
        _ configuration: ChapterDownloadConfiguration
    ) async throws -> String?

    private struct Checkpoint: Codable, Sendable {
        static let currentVersion = 1

        let version: Int
        let id: UUID
        let bookID: UUID
        var bookTitle: String
        var jobs: [ChapterDownloadJob]
        var configuration: ChapterDownloadConfiguration
        var phase: ChapterDownloadPhase
        var processedCount: Int
        var succeededCount: Int
        var durableStoredCount: Int
        var failedChapterIDs: Set<UUID>
        var lastError: String?
        var autoResume: Bool
        let createdAt: Date
        var updatedAt: Date
    }

    private struct PersistedState: Codable, Sendable {
        static let currentVersion = 1

        let version: Int
        var queue: [UUID]
        var checkpoints: [Checkpoint]
    }

    private enum WorkResult: Sendable {
        case stored(UUID)
        case failed(UUID, String)
        case cancelled(UUID)
    }

    private let contentStore: ChapterContentStore
    private let stateURL: URL
    private let fileManager: FileManager
    private let maxConcurrent: Int
    private let runPriority: TaskPriority
    private let fetchOperation: FetchOperation
    private let now: @Sendable () -> Date

    private var checkpoints: [UUID: Checkpoint] = [:]
    private var queue: [UUID] = []
    private var currentBookID: UUID?
    private var runTask: Task<Void, Never>?
    private var inFlightCounts: [UUID: Int] = [:]
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var isBootstrapped = false
    private var schedulingSuspensionDepth = 0
    private var bootstrapFailure: String?
    private var preparationRevisions: [UUID: UInt64] = [:]
    private var globalPreparationRevision: UInt64 = 0
    private var bookOperationEpochs: [UUID: UInt64] = [:]
    private var systemResumeRevision: UInt64 = 0
    private var clearingBookIDs: Set<UUID> = []
    private var isClearingAll = false

    private var isSchedulingSuspended: Bool {
        schedulingSuspensionDepth > 0
    }

    init(
        contentStore: ChapterContentStore = .shared,
        stateURL: URL? = nil,
        fileManager: FileManager = .default,
        maxConcurrent: Int = 5,
        /// Downloads are background work in the app. Tests lift this so a busy
        /// machine cannot starve the work pieces for tens of seconds.
        runPriority: TaskPriority = .utility,
        now: @escaping @Sendable () -> Date = { Date() },
        fetchOperation: @escaping FetchOperation = { job, configuration in
            try await ChapterContentLoader.shared.fetch(
                ChapterContentRequest(
                    url: job.sourceURL,
                    rule: configuration.legadoRule,
                    baseURL: configuration.baseURL,
                    nextChapterURL: job.nextChapterURL
                )
            )
        }
    ) {
        self.contentStore = contentStore
        self.fileManager = fileManager
        self.maxConcurrent = max(1, maxConcurrent)
        self.runPriority = runPriority
        self.now = now
        self.fetchOperation = fetchOperation
        if let stateURL {
            self.stateURL = stateURL
        } else {
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory
            self.stateURL = applicationSupport
                .appendingPathComponent("YiYue", isDirectory: true)
                .appendingPathComponent("ChapterDownloads", isDirectory: true)
                .appendingPathComponent("v1", isDirectory: true)
                .appendingPathComponent("queue.json", isDirectory: false)
        }
    }

    func bootstrap(autoResume: Bool = true) async {
        guard !isBootstrapped else { return }
        bootstrapFailure = nil

        do {
            try loadPersistedState(autoResume: autoResume)
            isBootstrapped = true
        } catch let error as PersistedStateLoadError {
            bootstrapFailure = error.localizedDescription
            switch error {
            case .corrupt:
                quarantineCorruptStateIfNeeded()
                checkpoints = [:]
                queue = []
                isBootstrapped = true
            case .io:
                // Fail closed. A transient read error must never turn a valid
                // on-disk queue into an empty in-memory queue that a later
                // enqueue can overwrite. Leave bootstrap retryable instead.
                publishAllSnapshots()
                return
            }
        } catch {
            bootstrapFailure = error.localizedDescription
            publishAllSnapshots()
            return
        }

        // Loading and normalizing are intentionally separate. Once a valid
        // durable queue is in memory, a transient rewrite failure must not
        // quarantine it or discard the user's download intent.
        if bootstrapFailure == nil || !checkpoints.isEmpty || !queue.isEmpty {
            do {
                try persistState()
            } catch {
                bootstrapFailure = error.localizedDescription
            }
        }

        publishAllSnapshots()
        startNextIfNeeded()
    }

    func bootstrapErrorDescription() -> String? {
        bootstrapFailure
    }

    @discardableResult
    func makePreparationToken(bookID: UUID) -> ChapterDownloadPreparationToken {
        ChapterDownloadPreparationToken(
            bookID: bookID,
            revision: preparationRevisions[bookID, default: 0],
            globalRevision: globalPreparationRevision
        )
    }

    func enqueue(
        _ request: ChapterDownloadRequest,
        preparationToken: ChapterDownloadPreparationToken? = nil
    ) async throws -> ChapterDownloadSnapshot {
        await bootstrap()
        try requireBootstrapReady()
        try Task.checkCancellation()
        guard !isClearingAll, !clearingBookIDs.contains(request.bookID) else {
            throw ChapterDownloadManagerError.clearingInProgress
        }
        guard !request.jobs.isEmpty else { throw ChapterDownloadManagerError.emptyRequest }
        guard request.jobs.allSatisfy({ $0.bookID == request.bookID }) else {
            throw ChapterDownloadManagerError.mixedBookIdentifiers
        }
        if let preparationToken {
            guard preparationToken.bookID == request.bookID,
                  preparationToken.revision
                    == preparationRevisions[request.bookID, default: 0],
                  preparationToken.globalRevision == globalPreparationRevision else {
                throw ChapterDownloadManagerError.stalePreparation
            }
        }

        // Treat the in-memory mutation and the durable checkpoint as one
        // transaction. A failed write must not leave a runnable job that the
        // caller was told had failed to enqueue.
        let previousCheckpoint = checkpoints[request.bookID]
        let previousQueue = queue

        if var existing = checkpoints[request.bookID], !existing.phase.isTerminal {
            guard existing.configuration == request.configuration else {
                throw ChapterDownloadManagerError.configurationChanged
            }

            var seen = Set(existing.jobs.map(\.chapterID))
            for job in request.jobs where seen.insert(job.chapterID).inserted {
                existing.jobs.append(job)
            }
            existing.bookTitle = request.bookTitle
            // A merge that arrives during drain must not turn an explicit user
            // pause into a system-resumable pause.
            if existing.phase != .pausing {
                existing.autoResume = true
            }
            existing.updatedAt = now()
            if existing.phase == .paused || existing.phase == .failed {
                existing.phase = .queued
                existing.processedCount = 0
                existing.succeededCount = 0
                existing.failedChapterIDs = []
                existing.lastError = nil
                appendToQueueIfNeeded(request.bookID)
            }
            checkpoints[request.bookID] = existing
        } else {
            let timestamp = now()
            checkpoints[request.bookID] = Checkpoint(
                version: Checkpoint.currentVersion,
                id: UUID(),
                bookID: request.bookID,
                bookTitle: request.bookTitle,
                jobs: deduplicated(request.jobs),
                configuration: request.configuration,
                phase: .queued,
                processedCount: 0,
                succeededCount: 0,
                durableStoredCount: 0,
                failedChapterIDs: [],
                lastError: nil,
                autoResume: true,
                createdAt: timestamp,
                updatedAt: timestamp
            )
            appendToQueueIfNeeded(request.bookID)
        }

        do {
            try persistState()
        } catch {
            if let previousCheckpoint {
                checkpoints[request.bookID] = previousCheckpoint
            } else {
                checkpoints.removeValue(forKey: request.bookID)
            }
            queue = previousQueue
            throw ChapterDownloadManagerError.persistenceFailed(error.localizedDescription)
        }
        advanceBookOperationEpoch(bookID: request.bookID)
        publishAllSnapshots()
        startNextIfNeeded()
        guard let snapshot = snapshot(bookID: request.bookID) else {
            throw ChapterDownloadManagerError.persistenceFailed("缓存状态丢了，请重新开始缓存")
        }
        return snapshot
    }

    @discardableResult
    func pause(bookID: UUID) async -> ChapterDownloadSnapshot? {
        await bootstrap()
        guard isBootstrapped else { return nil }
        do {
            return try await pause(bookID: bookID, intent: .user)
        } catch {
            bootstrapFailure = error.localizedDescription
            publishSnapshot(for: bookID)
            return snapshot(bookID: bookID)
        }
    }

    @discardableResult
    private func pause(
        bookID: UUID,
        intent: PauseIntent
    ) async throws -> ChapterDownloadSnapshot? {
        guard var checkpoint = checkpoints[bookID] else { return nil }

        if currentBookID == bookID, checkpoint.phase == .running || checkpoint.phase == .pausing {
            let previousCheckpoint = checkpoint
            checkpoint.phase = .pausing
            switch intent {
            case .user:
                // User intent always wins if it races a system suspension.
                checkpoint.autoResume = false
            case .system:
                // Preserve an already-recorded user pause.
                if previousCheckpoint.phase != .pausing {
                    checkpoint.autoResume = true
                }
            }
            checkpoint.updatedAt = now()
            checkpoints[bookID] = checkpoint
            do {
                // Persist intent before cancellation so a process death during
                // drain can restore user/system semantics correctly.
                try persistState()
            } catch {
                checkpoints[bookID] = previousCheckpoint
                bootstrapFailure = error.localizedDescription
                publishSnapshot(for: bookID)
                throw ChapterDownloadManagerError.persistenceFailed(error.localizedDescription)
            }
            publishSnapshot(for: bookID)
            let task = runTask
            task?.cancel()
            await task?.value
            return snapshot(bookID: bookID)
        }

        if checkpoint.phase == .queued {
            let previousCheckpoint = checkpoint
            let previousQueue = queue
            queue.removeAll { $0 == bookID }
            checkpoint.phase = .paused
            checkpoint.autoResume = intent == .system
            checkpoint.updatedAt = now()
            checkpoints[bookID] = checkpoint
            do {
                try persistState()
            } catch {
                checkpoints[bookID] = previousCheckpoint
                queue = previousQueue
                bootstrapFailure = error.localizedDescription
                publishAllSnapshots()
                throw ChapterDownloadManagerError.persistenceFailed(error.localizedDescription)
            }
            publishAllSnapshots()
        }
        return snapshot(bookID: bookID)
    }

    @discardableResult
    func resume(bookID: UUID) async throws -> ChapterDownloadSnapshot? {
        await bootstrap()
        try requireBootstrapReady()
        guard !isClearingAll, !clearingBookIDs.contains(bookID) else {
            throw ChapterDownloadManagerError.clearingInProgress
        }
        guard var checkpoint = checkpoints[bookID] else { return nil }
        guard checkpoint.phase == .paused || checkpoint.phase == .failed else {
            return snapshot(bookID: bookID)
        }

        let previousCheckpoint = checkpoint
        let previousQueue = queue

        checkpoint.phase = .queued
        checkpoint.processedCount = 0
        checkpoint.succeededCount = 0
        checkpoint.failedChapterIDs = []
        checkpoint.lastError = nil
        checkpoint.autoResume = true
        checkpoint.updatedAt = now()
        checkpoints[bookID] = checkpoint
        appendToQueueIfNeeded(bookID)
        do {
            try persistState()
        } catch {
            checkpoints[bookID] = previousCheckpoint
            queue = previousQueue
            throw ChapterDownloadManagerError.persistenceFailed(error.localizedDescription)
        }
        advanceBookOperationEpoch(bookID: bookID)
        publishAllSnapshots()
        startNextIfNeeded()
        return snapshot(bookID: bookID)
    }

    func cancel(bookID: UUID) async throws {
        await bootstrap()
        try requireBootstrapReady()
        _ = try await pause(bookID: bookID, intent: .user)
        guard var checkpoint = checkpoints[bookID] else { return }
        let previousCheckpoint = checkpoint
        let previousQueue = queue
        queue.removeAll { $0 == bookID }
        checkpoint.phase = .cancelled
        checkpoint.autoResume = false
        checkpoint.updatedAt = now()
        checkpoints[bookID] = checkpoint
        do {
            try persistState()
        } catch {
            checkpoints[bookID] = previousCheckpoint
            queue = previousQueue
            bootstrapFailure = error.localizedDescription
            throw ChapterDownloadManagerError.persistenceFailed(error.localizedDescription)
        }
        publishAllSnapshots()
    }

    func clear(bookID: UUID) async throws {
        guard !isClearingAll, clearingBookIDs.insert(bookID).inserted else {
            throw ChapterDownloadManagerError.clearingInProgress
        }
        beginSchedulingSuspension()
        invalidatePreparations(bookID: bookID)
        let clearEpoch = advanceBookOperationEpoch(bookID: bookID)
        defer {
            // Tokens issued while removeBook was suspended at an actor hop are
            // stale too; only preparations begun after the clear may enqueue.
            invalidatePreparations(bookID: bookID)
            clearingBookIDs.remove(bookID)
            endSchedulingSuspension()
        }
        await bootstrap()
        try requireBootstrapReady()
        try await cancel(bookID: bookID)
        let checkpointID = checkpoints[bookID]?.id
        try await contentStore.removeBook(bookID)

        // The latch rejects enqueue/resume throughout the async clear window;
        // the epoch/session marker remains a final guard against future actor
        // reentrancy paths accidentally mutating this book during the clear.
        guard bookOperationEpochs[bookID] == clearEpoch,
              checkpoints[bookID]?.id == checkpointID else {
            return
        }
        checkpoints.removeValue(forKey: bookID)
        queue.removeAll { $0 == bookID }
        inFlightCounts.removeValue(forKey: bookID)
        do {
            try persistState()
        } catch {
            throw ChapterDownloadManagerError.persistenceFailed(error.localizedDescription)
        }
        publishAllSnapshots()
    }

    func pauseAll() async {
        await bootstrap()
        guard isBootstrapped else { return }
        beginSchedulingSuspension()
        defer { endSchedulingSuspension() }
        let bookIDs = checkpoints.values
            .filter { $0.phase == .queued || $0.phase == .running || $0.phase == .pausing }
            .map(\.bookID)
        for bookID in bookIDs {
            do {
                _ = try await pause(bookID: bookID, intent: .user)
            } catch {
                bootstrapFailure = error.localizedDescription
            }
        }
    }

    /// iOS 17-25 use this when foreground runtime is about to expire. These
    /// sessions are paused with the same drain guarantee as a user pause, but
    /// retain an explicit auto-resume bit so a later foreground/BGProcessing
    /// lease can continue them. A user-triggered pause always clears that bit.
    func suspendForBackground() async {
        await bootstrap()
        guard isBootstrapped else { return }
        // A canceled scene-drain that has not started mutating state should not
        // race a newer foreground resume request.
        guard !Task.isCancelled else { return }
        let resumeRevisionAtStart = systemResumeRevision
        beginSchedulingSuspension()
        defer { endSchedulingSuspension() }
        let bookIDs = checkpoints.values
            .filter { $0.phase == .queued || $0.phase == .running || $0.phase == .pausing }
            .map(\.bookID)
        for bookID in bookIDs {
            do {
                _ = try await pause(bookID: bookID, intent: .system)
            } catch {
                bootstrapFailure = error.localizedDescription
            }
        }
        // Foreground/BGProcessing resume may arrive while one of the above
        // drains is suspended at an actor hop. Consume that wakeup only after
        // every captured job has reached a durable paused state.
        if systemResumeRevision != resumeRevisionAtStart {
            queueSystemPausedWork()
        }
        do {
            try persistState()
        } catch {
            bootstrapFailure = error.localizedDescription
        }
        publishAllSnapshots()
    }

    func resumeSystemSuspended() async {
        await bootstrap()
        guard isBootstrapped else { return }
        systemResumeRevision &+= 1
        queueSystemPausedWork()
        do {
            try persistState()
        } catch {
            bootstrapFailure = error.localizedDescription
        }
        publishAllSnapshots()
        startNextIfNeeded()
    }

    func clearAll() async throws {
        guard !isClearingAll, clearingBookIDs.isEmpty else {
            throw ChapterDownloadManagerError.clearingInProgress
        }
        isClearingAll = true
        beginSchedulingSuspension()
        globalPreparationRevision &+= 1
        var invalidatedBookIDs: [UUID] = []
        defer {
            // Invalidate preparation work created during the clear as well as
            // work that predated it.
            globalPreparationRevision &+= 1
            for bookID in invalidatedBookIDs {
                invalidatePreparations(bookID: bookID)
            }
            isClearingAll = false
            endSchedulingSuspension()
        }
        await bootstrap()
        try requireBootstrapReady()
        let bookIDs = Array(
            Set(checkpoints.keys)
                .union(preparationRevisions.keys)
                .union(bookOperationEpochs.keys)
        )
        invalidatedBookIDs = bookIDs
        var clearMarkers: [UUID: ClearMarker] = [:]
        for bookID in bookIDs {
            invalidatePreparations(bookID: bookID)
            clearMarkers[bookID] = ClearMarker(
                operationEpoch: advanceBookOperationEpoch(bookID: bookID),
                checkpointID: checkpoints[bookID]?.id
            )
        }
        for bookID in bookIDs {
            _ = try await pause(bookID: bookID, intent: .user)
        }
        for bookID in bookIDs {
            try await contentStore.removeBook(bookID)
        }

        var clearedBookIDs: Set<UUID> = []
        for (bookID, marker) in clearMarkers {
            guard bookOperationEpochs[bookID] == marker.operationEpoch,
                  checkpoints[bookID]?.id == marker.checkpointID else {
                continue
            }
            checkpoints.removeValue(forKey: bookID)
            inFlightCounts.removeValue(forKey: bookID)
            clearedBookIDs.insert(bookID)
        }
        queue.removeAll { clearedBookIDs.contains($0) }
        do {
            try persistState()
        } catch {
            throw ChapterDownloadManagerError.persistenceFailed(error.localizedDescription)
        }
        publishAllSnapshots()
    }

    func snapshot(bookID: UUID) -> ChapterDownloadSnapshot? {
        guard let checkpoint = checkpoints[bookID] else { return nil }
        return makeSnapshot(checkpoint)
    }

    func allSnapshots() -> [ChapterDownloadSnapshot] {
        checkpoints.values
            .sorted { $0.createdAt < $1.createdAt }
            .map(makeSnapshot)
    }

    func activeSnapshot() -> ChapterDownloadSnapshot? {
        guard let currentBookID else { return nil }
        return snapshot(bookID: currentBookID)
    }

    func hasRunnableWork() -> Bool {
        currentBookID != nil || !queue.isEmpty
    }

    /// Coalesced invalidations keep observers lossless without buffering every
    /// per-chapter snapshot. Consumers re-read authoritative actor state when
    /// signalled, so one retained event represents any number of updates.
    func updates(replayCurrent: Bool = true) -> AsyncStream<Void> {
        let subscriptionID = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { await self?.removeContinuation(subscriptionID) }
        }
        continuations[subscriptionID] = continuation
        if replayCurrent {
            continuation.yield(())
        }
        return stream
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func startNextIfNeeded() {
        guard !isSchedulingSuspended, runTask == nil else { return }

        while let nextBookID = queue.first {
            queue.removeFirst()
            guard var checkpoint = checkpoints[nextBookID], checkpoint.phase == .queued else {
                continue
            }
            checkpoint.phase = .running
            checkpoint.processedCount = 0
            checkpoint.succeededCount = 0
            checkpoint.failedChapterIDs = []
            checkpoint.lastError = nil
            checkpoint.updatedAt = now()
            checkpoints[nextBookID] = checkpoint
            currentBookID = nextBookID
            try? persistState()
            publishAllSnapshots()

            runTask = Task(priority: runPriority) { [weak self] in
                await self?.run(bookID: nextBookID)
            }
            return
        }
    }

    private func run(bookID: UUID) async {
        guard let initial = checkpoints[bookID] else {
            finishRun(bookID: bookID)
            return
        }

        let storedAtStart: Set<UUID>
        do {
            storedAtStart = try await contentStore.storedChapterIDs(
                bookID: bookID,
                retention: .userManaged
            )
        } catch {
            guard checkpoints[bookID]?.id == initial.id else {
                finishRun(bookID: bookID)
                return
            }
            if Task.isCancelled || checkpoints[bookID]?.phase == .pausing {
                await settlePausedRun(bookID: bookID, sessionID: initial.id)
                return
            }
            failRun(bookID: bookID, message: "无法检查已有缓存：\(error.localizedDescription)")
            return
        }

        guard checkpoints[bookID]?.id == initial.id else {
            finishRun(bookID: bookID)
            return
        }
        guard !Task.isCancelled, checkpoints[bookID]?.phase != .pausing else {
            await settlePausedRun(
                bookID: bookID,
                sessionID: initial.id,
                storedChapterIDs: storedAtStart
            )
            return
        }

        let targetIDs = Set(initial.jobs.map(\.chapterID))
        let pendingJobs = initial.jobs.filter { !storedAtStart.contains($0.chapterID) }
        if var checkpoint = checkpoints[bookID] {
            checkpoint.durableStoredCount = targetIDs.intersection(storedAtStart).count
            checkpoint.updatedAt = now()
            checkpoints[bookID] = checkpoint
            publishSnapshot(for: bookID)
        }

        guard !pendingJobs.isEmpty else {
            if checkpoints[bookID]?.jobs.count != initial.jobs.count {
                queueMergedRun(
                    bookID: bookID,
                    durableCount: targetIDs.intersection(storedAtStart).count
                )
            } else {
                completeRun(bookID: bookID, durableCount: targetIDs.count)
            }
            return
        }

        let configuration = initial.configuration
        let writeToken = await contentStore.makeWriteToken(bookID: bookID)
        guard checkpoints[bookID]?.id == initial.id else {
            finishRun(bookID: bookID)
            return
        }
        guard !Task.isCancelled, checkpoints[bookID]?.phase != .pausing else {
            await settlePausedRun(bookID: bookID, sessionID: initial.id)
            return
        }
        let concurrency = min(maxConcurrent, pendingJobs.count)
        var iterator = pendingJobs.makeIterator()
        var shouldScheduleMore = true
        var resultsSinceCheckpoint = 0
        var lastPublishDate = now()

        await withTaskGroup(of: WorkResult.self) { group in
            for _ in 0..<concurrency {
                guard let job = iterator.next() else { break }
                add(
                    job: job,
                    configuration: configuration,
                    writeToken: writeToken,
                    to: &group
                )
                inFlightCounts[bookID, default: 0] += 1
            }
            publishSnapshot(for: bookID)

            while let result = await group.next() {
                inFlightCounts[bookID] = max(0, (inFlightCounts[bookID] ?? 1) - 1)
                if Task.isCancelled {
                    shouldScheduleMore = false
                    group.cancelAll()
                }

                if var checkpoint = checkpoints[bookID] {
                    switch result {
                    case .stored:
                        checkpoint.processedCount += 1
                        checkpoint.succeededCount += 1
                    case .failed(let chapterID, let message):
                        checkpoint.processedCount += 1
                        checkpoint.failedChapterIDs.insert(chapterID)
                        checkpoint.lastError = message
                    case .cancelled:
                        break
                    }
                    checkpoint.updatedAt = now()
                    checkpoints[bookID] = checkpoint
                }

                resultsSinceCheckpoint += 1
                if resultsSinceCheckpoint >= 10 {
                    try? persistState()
                    resultsSinceCheckpoint = 0
                }
                if resultsSinceCheckpoint == 0
                    || now().timeIntervalSince(lastPublishDate) >= 0.25 {
                    publishSnapshot(for: bookID)
                    lastPublishDate = now()
                }

                if shouldScheduleMore, let nextJob = iterator.next() {
                    add(
                        job: nextJob,
                        configuration: configuration,
                        writeToken: writeToken,
                        to: &group
                    )
                    inFlightCounts[bookID, default: 0] += 1
                }
            }
        }
        inFlightCounts[bookID] = 0

        if Task.isCancelled || checkpoints[bookID]?.phase == .pausing {
            await settlePausedRun(bookID: bookID, sessionID: initial.id)
            return
        }

        let storedAtEnd: Set<UUID>
        do {
            storedAtEnd = try await contentStore.storedChapterIDs(
                bookID: bookID,
                retention: .userManaged
            )
        } catch {
            guard checkpoints[bookID]?.id == initial.id else {
                finishRun(bookID: bookID)
                return
            }
            if Task.isCancelled || checkpoints[bookID]?.phase == .pausing {
                await settlePausedRun(bookID: bookID, sessionID: initial.id)
                return
            }
            failRun(bookID: bookID, message: "无法核对已写入缓存：\(error.localizedDescription)")
            return
        }
        guard checkpoints[bookID]?.id == initial.id else {
            finishRun(bookID: bookID)
            return
        }
        guard !Task.isCancelled, checkpoints[bookID]?.phase != .pausing else {
            await settlePausedRun(
                bookID: bookID,
                sessionID: initial.id,
                storedChapterIDs: storedAtEnd
            )
            return
        }
        let currentTargetIDs = Set(
            (checkpoints[bookID]?.jobs ?? initial.jobs).map(\.chapterID)
        )
        let durableCount = currentTargetIDs.intersection(storedAtEnd).count
        if currentTargetIDs.count > targetIDs.count, durableCount < currentTargetIDs.count {
            queueMergedRun(bookID: bookID, durableCount: durableCount)
        } else if durableCount == currentTargetIDs.count {
            completeRun(bookID: bookID, durableCount: durableCount)
        } else {
            failRun(
                bookID: bookID,
                message: checkpoints[bookID]?.lastError ?? "部分章节缓存失败，可稍后重试",
                durableCount: durableCount
            )
        }
    }

    private func add(
        job: ChapterDownloadJob,
        configuration: ChapterDownloadConfiguration,
        writeToken: ChapterContentWriteToken,
        to group: inout TaskGroup<WorkResult>
    ) {
        let contentStore = contentStore
        let fetchOperation = fetchOperation
        group.addTask {
            do {
                try Task.checkCancellation()
                if try await contentStore.promote(
                    bookID: job.bookID,
                    chapterID: job.chapterID,
                    writeToken: writeToken
                ) {
                    return .stored(job.chapterID)
                }
                let content = try await fetchOperation(job, configuration)
                guard let content, SourceEngine.isValidContent(content) else {
                    return .failed(job.chapterID, "章节正文为空或无效")
                }
                try Task.checkCancellation()
                let outcome = try await contentStore.store(
                    content,
                    bookID: job.bookID,
                    chapterID: job.chapterID,
                    retention: .userManaged,
                    writeToken: writeToken
                )
                guard outcome.isStored else {
                    return .failed(job.chapterID, "这一章没能存到手机上，可能是空间不足")
                }
                return .stored(job.chapterID)
            } catch is CancellationError {
                return .cancelled(job.chapterID)
            } catch {
                return .failed(job.chapterID, error.localizedDescription)
            }
        }
    }

    private func settlePausedRun(
        bookID: UUID,
        sessionID: UUID,
        storedChapterIDs: Set<UUID>? = nil
    ) async {
        guard checkpoints[bookID]?.id == sessionID else {
            finishRun(bookID: bookID)
            return
        }

        var stored = storedChapterIDs
        var storedChapterIDsError: Error?
        if stored == nil {
            do {
                // `runTask` is intentionally cancelled before drain. Perform
                // the final bounded disk reconciliation in a fresh task so
                // ContentStore's cancellation checks do not skip disk truth.
                let contentStore = contentStore
                stored = try await Task.detached(priority: runPriority) {
                    try await contentStore.storedChapterIDs(
                        bookID: bookID,
                        retention: .userManaged
                    )
                }.value
            } catch {
                storedChapterIDsError = error
            }
        }

        // Actor reentrancy permits enqueue/user-pause/system-pause mutations
        // while the disk scan is suspended. Re-read the authoritative
        // checkpoint so merged jobs and the winning pause intent survive.
        guard var checkpoint = checkpoints[bookID],
              checkpoint.id == sessionID,
              checkpoint.phase == .pausing else {
            finishRun(bookID: bookID)
            return
        }
        if let stored {
            checkpoint.durableStoredCount = Set(checkpoint.jobs.map(\.chapterID))
                .intersection(stored)
                .count
        } else if let storedChapterIDsError {
            checkpoint.lastError =
                "暂停后无法核对磁盘缓存：\(storedChapterIDsError.localizedDescription)"
        }
        checkpoint.phase = .paused
        checkpoint.updatedAt = now()
        checkpoints[bookID] = checkpoint
        do {
            try persistState()
        } catch {
            bootstrapFailure = error.localizedDescription
        }
        publishSnapshot(for: bookID)
        finishRun(bookID: bookID)
    }

    private func completeRun(bookID: UUID, durableCount: Int) {
        guard var checkpoint = checkpoints[bookID] else {
            finishRun(bookID: bookID)
            return
        }
        checkpoint.phase = .completed
        checkpoint.durableStoredCount = durableCount
        checkpoint.failedChapterIDs = []
        checkpoint.lastError = nil
        checkpoint.autoResume = false
        checkpoint.updatedAt = now()
        checkpoints[bookID] = checkpoint
        try? persistState()
        publishSnapshot(for: bookID)
        finishRun(bookID: bookID)
    }

    /// A second surface can add targets while this book is already running.
    /// Finish the current bounded batch, persist its disk truth, then put the
    /// same book back at the end of the FIFO instead of silently completing
    /// before the newly merged chapters are handled.
    private func queueMergedRun(bookID: UUID, durableCount: Int) {
        guard var checkpoint = checkpoints[bookID] else {
            finishRun(bookID: bookID)
            return
        }
        checkpoint.phase = .queued
        checkpoint.durableStoredCount = durableCount
        checkpoint.updatedAt = now()
        checkpoints[bookID] = checkpoint
        if !queue.contains(bookID) {
            queue.append(bookID)
        }
        try? persistState()
        publishAllSnapshots()
        finishRun(bookID: bookID)
    }

    private func failRun(bookID: UUID, message: String, durableCount: Int? = nil) {
        guard var checkpoint = checkpoints[bookID] else {
            finishRun(bookID: bookID)
            return
        }
        checkpoint.phase = .failed
        if let durableCount {
            checkpoint.durableStoredCount = durableCount
        }
        checkpoint.lastError = message
        checkpoint.autoResume = false
        checkpoint.updatedAt = now()
        checkpoints[bookID] = checkpoint
        try? persistState()
        publishSnapshot(for: bookID)
        finishRun(bookID: bookID)
    }

    private func finishRun(bookID: UUID) {
        guard currentBookID == bookID else { return }
        currentBookID = nil
        runTask = nil
        inFlightCounts.removeValue(forKey: bookID)
        publishAllSnapshots()
        startNextIfNeeded()
    }

    private func makeSnapshot(_ checkpoint: Checkpoint) -> ChapterDownloadSnapshot {
        ChapterDownloadSnapshot(
            id: checkpoint.id,
            bookID: checkpoint.bookID,
            bookTitle: checkpoint.bookTitle,
            phase: checkpoint.phase,
            targetCount: checkpoint.jobs.count,
            processedCount: checkpoint.processedCount,
            succeededCount: checkpoint.succeededCount,
            durableStoredCount: checkpoint.durableStoredCount,
            failedCount: checkpoint.failedChapterIDs.count,
            inFlightCount: inFlightCounts[checkpoint.bookID] ?? 0,
            queuePosition: queue.firstIndex(of: checkpoint.bookID).map { $0 + 1 },
            lastError: checkpoint.lastError,
            updatedAt: checkpoint.updatedAt
        )
    }

    private func publishSnapshot(for bookID: UUID) {
        guard checkpoints[bookID] != nil else { return }
        for continuation in continuations.values {
            continuation.yield(())
        }
    }

    private func publishAllSnapshots() {
        for continuation in continuations.values {
            continuation.yield(())
        }
    }

    private func appendToQueueIfNeeded(_ bookID: UUID) {
        guard currentBookID != bookID, !queue.contains(bookID) else { return }
        queue.append(bookID)
    }

    private func requireBootstrapReady() throws {
        guard isBootstrapped else {
            throw ChapterDownloadManagerError.bootstrapUnavailable(
                bootstrapFailure ?? "读不到保存的缓存状态，请稍后重试"
            )
        }
    }

    private func beginSchedulingSuspension() {
        schedulingSuspensionDepth &+= 1
    }

    private func endSchedulingSuspension() {
        guard schedulingSuspensionDepth > 0 else { return }
        schedulingSuspensionDepth -= 1
        if schedulingSuspensionDepth == 0 {
            startNextIfNeeded()
        }
    }

    private func queueSystemPausedWork() {
        guard !isClearingAll else { return }
        let resumableBookIDs = checkpoints.values
            .filter {
                $0.phase == .paused
                    && $0.autoResume
                    && !clearingBookIDs.contains($0.bookID)
            }
            .sorted { $0.createdAt < $1.createdAt }
            .map(\.bookID)

        for bookID in resumableBookIDs {
            guard var checkpoint = checkpoints[bookID] else { continue }
            checkpoint.phase = .queued
            checkpoint.processedCount = 0
            checkpoint.succeededCount = 0
            checkpoint.failedChapterIDs = []
            checkpoint.lastError = nil
            checkpoint.updatedAt = now()
            checkpoints[bookID] = checkpoint
            appendToQueueIfNeeded(bookID)
        }
    }

    @discardableResult
    private func advanceBookOperationEpoch(bookID: UUID) -> UInt64 {
        bookOperationEpochs[bookID, default: 0] &+= 1
        return bookOperationEpochs[bookID, default: 0]
    }

    private func invalidatePreparations(bookID: UUID) {
        preparationRevisions[bookID, default: 0] &+= 1
    }

    private func deduplicated(_ jobs: [ChapterDownloadJob]) -> [ChapterDownloadJob] {
        var seen: Set<UUID> = []
        return jobs.filter { seen.insert($0.chapterID).inserted }
    }

    private func persistState() throws {
        let state = PersistedState(
            version: PersistedState.currentVersion,
            queue: queue,
            checkpoints: checkpoints.values.sorted { $0.createdAt < $1.createdAt }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(state)
        let directory = stateURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: stateURL, options: .atomic)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(values)
    }

    private func loadPersistedState(autoResume: Bool) throws {
        guard fileManager.fileExists(atPath: stateURL.path) else { return }
        let data: Data
        do {
            data = try Data(contentsOf: stateURL, options: [.mappedIfSafe])
        } catch {
            throw PersistedStateLoadError.io(
                "无法读取缓存队列：\(error.localizedDescription)"
            )
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let state: PersistedState
        do {
            state = try decoder.decode(PersistedState.self, from: data)
        } catch {
            throw PersistedStateLoadError.corrupt(
                "无法解析缓存队列：\(error.localizedDescription)"
            )
        }
        guard state.version == PersistedState.currentVersion else {
            throw PersistedStateLoadError.corrupt("缓存数据版本太旧，请重新缓存")
        }

        var restoredCheckpoints: [UUID: Checkpoint] = [:]
        var restoredSessionIDs: Set<UUID> = []
        for checkpoint in state.checkpoints {
            guard checkpoint.version == Checkpoint.currentVersion else {
                throw PersistedStateLoadError.corrupt("缓存数据版本太旧，请重新缓存")
            }
            guard !checkpoint.jobs.isEmpty,
                  checkpoint.jobs.allSatisfy({ $0.bookID == checkpoint.bookID }) else {
                throw PersistedStateLoadError.corrupt("缓存数据损坏，请重新缓存")
            }
            guard restoredCheckpoints[checkpoint.bookID] == nil,
                  restoredSessionIDs.insert(checkpoint.id).inserted else {
                throw PersistedStateLoadError.corrupt("缓存任务有重复，已自动跳过")
            }

            var restored = checkpoint
            restored.jobs = deduplicated(restored.jobs)
            switch restored.phase {
            case .running, .queued:
                restored.phase = autoResume && restored.autoResume ? .queued : .paused
            case .pausing:
                restored.phase = autoResume && restored.autoResume ? .queued : .paused
            case .paused:
                if autoResume && restored.autoResume {
                    restored.phase = .queued
                }
            case .completed, .failed, .cancelled:
                break
            }
            restored.processedCount = 0
            restored.succeededCount = 0
            restored.updatedAt = now()
            restoredCheckpoints[restored.bookID] = restored
        }
        checkpoints = restoredCheckpoints

        let queuedBookIDs = Set(
            checkpoints.values
                .filter { $0.phase == .queued }
                .map(\.bookID)
        )
        var seenQueueBookIDs: Set<UUID> = []
        let persistedOrder = state.queue.filter {
            queuedBookIDs.contains($0) && seenQueueBookIDs.insert($0).inserted
        }
        let missing = checkpoints.values
            .filter { $0.phase == .queued && !persistedOrder.contains($0.bookID) }
            .sorted { $0.createdAt < $1.createdAt }
            .map(\.bookID)
        queue = persistedOrder + missing
    }

    private func quarantineCorruptStateIfNeeded() {
        guard fileManager.fileExists(atPath: stateURL.path) else { return }
        let quarantineURL = stateURL
            .deletingPathExtension()
            .appendingPathExtension("corrupt-\(Int(now().timeIntervalSince1970)).json")
        try? fileManager.moveItem(at: stateURL, to: quarantineURL)
    }
}
