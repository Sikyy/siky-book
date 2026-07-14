import Foundation
import Testing
@testable import YiYue

@Suite("ChapterDownloadManager Tests")
struct ChapterDownloadManagerTests {
    @Test func limitsConcurrentChapterDownloadsToFive() async throws {
        let workspace = try ChapterDownloadTestWorkspace()
        defer { workspace.remove() }

        let store = ChapterContentStore(rootDirectory: workspace.contentRoot)
        let probe = DownloadConcurrencyProbe()
        let manager = ChapterDownloadManager(
            contentStore: store,
            stateURL: workspace.stateURL,
            maxConcurrent: 5,
            fetchOperation: { _, _ in
                try await probe.fetch()
            }
        )
        let request = makeRequest(chapterCount: 12)

        _ = try await manager.enqueue(request)
        let completed = try await waitForSnapshot(
            manager: manager,
            bookID: request.bookID,
            phase: .completed
        )
        let statistics = await probe.statistics()

        #expect(statistics.peak == 5)
        #expect(statistics.started == 12)
        #expect(completed.targetCount == 12)
        #expect(completed.succeededCount == 12)
        #expect(completed.durableStoredCount == 12)
        #expect(completed.failedCount == 0)
    }

    @Test func enqueueWhileRunningMergesNewChaptersWithoutDroppingWork() async throws {
        let workspace = try ChapterDownloadTestWorkspace()
        defer { workspace.remove() }

        let store = ChapterContentStore(rootDirectory: workspace.contentRoot)
        let gate = MergedDownloadGate()
        let manager = ChapterDownloadManager(
            contentStore: store,
            stateURL: workspace.stateURL,
            maxConcurrent: 5,
            fetchOperation: { job, _ in
                await gate.fetch(chapterID: job.chapterID)
            }
        )
        let initialRequest = makeRequest(chapterCount: 5)

        _ = try await manager.enqueue(initialRequest)
        try await waitUntil {
            await gate.waitingCount() == 5
        }

        let addedJobs = (5..<8).map { index in
            ChapterDownloadJob(
                bookID: initialRequest.bookID,
                chapterID: UUID(),
                sourceURL: "https://example.com/book/\(initialRequest.bookID)/chapter/\(index)",
                nextChapterURL: nil
            )
        }
        let mergedRequest = ChapterDownloadRequest(
            bookID: initialRequest.bookID,
            bookTitle: initialRequest.bookTitle,
            jobs: addedJobs,
            configuration: initialRequest.configuration
        )
        let merged = try await manager.enqueue(mergedRequest)
        #expect(merged.phase == .running)
        #expect(merged.targetCount == 8)

        await gate.open()
        let completed = try await waitForSnapshot(
            manager: manager,
            bookID: initialRequest.bookID,
            phase: .completed
        )
        let expectedIDs = Set((initialRequest.jobs + addedJobs).map(\.chapterID))
        let fetchedIDs = await gate.fetchedIDs()
        let storedIDs = try await store.storedChapterIDs(
            bookID: initialRequest.bookID,
            retention: .userManaged
        )

        #expect(fetchedIDs == expectedIDs)
        #expect(storedIDs == expectedIDs)
        #expect(completed.targetCount == expectedIDs.count)
        #expect(completed.durableStoredCount == expectedIDs.count)
        #expect(completed.failedCount == 0)
    }

    @Test func pauseDrainsInFlightWorkAndDoesNotWriteAfterReturning() async throws {
        let workspace = try ChapterDownloadTestWorkspace()
        defer { workspace.remove() }

        let store = ChapterContentStore(rootDirectory: workspace.contentRoot)
        let gate = PausableDownloadGate()
        let manager = ChapterDownloadManager(
            contentStore: store,
            stateURL: workspace.stateURL,
            maxConcurrent: 5,
            fetchOperation: { job, _ in
                await gate.fetch(chapterID: job.chapterID)
            }
        )
        let request = makeRequest(chapterCount: 12)

        _ = try await manager.enqueue(request)
        try await waitUntil {
            await gate.statistics().waiting == 5
        }

        let pauseTask = Task {
            await manager.pause(bookID: request.bookID)
        }
        try await waitUntil {
            await gate.statistics().cancelled == 5
        }

        // The fetch operations deliberately hold their continuations after
        // cancellation. `pause` must remain in the draining phase and must not
        // fill any of the seven newly available queue slots.
        try await Task.sleep(nanoseconds: 30_000_000)
        let draining = await manager.snapshot(bookID: request.bookID)
        let duringPause = await gate.statistics()
        #expect(draining?.phase == .pausing)
        #expect(duringPause.started == 5)
        #expect(duringPause.active == 5)

        await gate.releaseAll()
        let paused = await pauseTask.value
        let storedWhenPauseReturned = try await store.storedChapterIDs(
            bookID: request.bookID,
            retention: .userManaged
        )

        #expect(paused?.phase == .paused)
        #expect(paused?.inFlightCount == 0)
        #expect(paused?.durableStoredCount == 0)
        #expect(storedWhenPauseReturned.isEmpty)

        try await Task.sleep(nanoseconds: 50_000_000)
        let afterPause = await gate.statistics()
        let storedAfterDelay = try await store.storedChapterIDs(
            bookID: request.bookID,
            retention: .userManaged
        )
        #expect(afterPause.started == 5)
        #expect(afterPause.active == 0)
        #expect(storedAfterDelay == storedWhenPauseReturned)
    }

    @Test func systemSuspendDrainsThenResumesOnlyDiskMissingChapters() async throws {
        let workspace = try ChapterDownloadTestWorkspace()
        defer { workspace.remove() }

        let store = ChapterContentStore(rootDirectory: workspace.contentRoot)
        let request = makeRequest(chapterCount: 6)
        let initiallyDurableJobs = Array(request.jobs.prefix(2))
        let initiallyDurableIDs = Set(initiallyDurableJobs.map(\.chapterID))
        let probe = BackgroundSuspensionProbe(immediateIDs: initiallyDurableIDs)
        let manager = ChapterDownloadManager(
            contentStore: store,
            stateURL: workspace.stateURL,
            maxConcurrent: 2,
            fetchOperation: { job, _ in
                await probe.fetch(chapterID: job.chapterID)
            }
        )

        _ = try await manager.enqueue(request)
        try await waitUntil {
            let statistics = await probe.statistics()
            guard statistics.waiting == 2 else { return false }
            for job in initiallyDurableJobs {
                if await !store.contains(
                    bookID: request.bookID,
                    chapterID: job.chapterID,
                    retention: .userManaged
                ) {
                    return false
                }
            }
            return true
        }

        let suspensionTask = Task {
            await manager.suspendForBackground()
        }
        try await waitUntil {
            await probe.statistics().cancelled == 2
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        let draining = await manager.snapshot(bookID: request.bookID)
        let drainingStatistics = await probe.statistics()
        #expect(draining?.phase == .pausing)
        #expect(drainingStatistics.active == 2)

        await probe.releaseCancelledAndOpen()
        await suspensionTask.value

        let suspended = await manager.snapshot(bookID: request.bookID)
        let storedAtSuspend = try await store.storedChapterIDs(
            bookID: request.bookID,
            retention: .userManaged
        )
        let suspendedState = try decodeCheckpointState(at: workspace.stateURL)
        #expect(suspended?.phase == .paused)
        #expect(suspended?.inFlightCount == 0)
        #expect(suspended?.durableStoredCount == initiallyDurableIDs.count)
        #expect(storedAtSuspend == initiallyDurableIDs)
        #expect(suspendedState.checkpoints.first?.phase == .paused)
        #expect(suspendedState.checkpoints.first?.autoResume == true)

        await probe.markResumeBoundary()
        await manager.resumeSystemSuspended()
        let completed = try await waitForSnapshot(
            manager: manager,
            bookID: request.bookID,
            phase: .completed
        )
        let expectedMissingIDs = Set(request.jobs.map(\.chapterID)).subtracting(initiallyDurableIDs)
        let fetchedAfterResume = await probe.fetchedAfterResume()
        let finalStoredIDs = try await store.storedChapterIDs(
            bookID: request.bookID,
            retention: .userManaged
        )

        #expect(fetchedAfterResume == expectedMissingIDs)
        #expect(finalStoredIDs == Set(request.jobs.map(\.chapterID)))
        #expect(completed.succeededCount == expectedMissingIDs.count)
        #expect(completed.durableStoredCount == request.jobs.count)
        #expect(completed.failedCount == 0)
    }

    @Test func foregroundResumeDuringSystemDrainIsNotLost() async throws {
        let workspace = try ChapterDownloadTestWorkspace()
        defer { workspace.remove() }

        let store = ChapterContentStore(rootDirectory: workspace.contentRoot)
        let request = makeRequest(chapterCount: 4)
        let probe = BackgroundSuspensionProbe(immediateIDs: [])
        let manager = ChapterDownloadManager(
            contentStore: store,
            stateURL: workspace.stateURL,
            maxConcurrent: 2,
            fetchOperation: { job, _ in
                await probe.fetch(chapterID: job.chapterID)
            }
        )

        _ = try await manager.enqueue(request)
        try await waitUntil {
            await probe.statistics().waiting == 2
        }

        let suspensionTask = Task {
            await manager.suspendForBackground()
        }
        try await waitUntil {
            await probe.statistics().cancelled == 2
        }

        // Foreground arrives before the cancelled fetches release their
        // continuations. The resume must be remembered until drain settles.
        await probe.markResumeBoundary()
        await manager.resumeSystemSuspended()
        let stillDraining = await manager.snapshot(bookID: request.bookID)
        #expect(stillDraining?.phase == .pausing)

        await probe.releaseCancelledAndOpen()
        await suspensionTask.value
        let completed = try await waitForSnapshot(
            manager: manager,
            bookID: request.bookID,
            phase: .completed
        )
        let fetchedAfterResume = await probe.fetchedAfterResume()
        let expectedIDs = Set(request.jobs.map(\.chapterID))

        #expect(fetchedAfterResume == expectedIDs)
        #expect(completed.durableStoredCount == expectedIDs.count)
    }

    @Test func runningCheckpointRestartsAndFetchesOnlyDiskMissingChapters() async throws {
        let workspace = try ChapterDownloadTestWorkspace()
        defer { workspace.remove() }

        let store = ChapterContentStore(rootDirectory: workspace.contentRoot)
        let request = makeRequest(chapterCount: 6)
        let alreadyStored = Array(request.jobs.prefix(2))
        for job in alreadyStored {
            try await store.store(
                validChapterContent,
                bookID: request.bookID,
                chapterID: job.chapterID,
                retention: .userManaged
            )
        }
        try writeRunningCheckpoint(for: request, to: workspace.stateURL)

        let probe = DownloadIDProbe()
        let manager = ChapterDownloadManager(
            contentStore: store,
            stateURL: workspace.stateURL,
            maxConcurrent: 5,
            fetchOperation: { job, _ in
                await probe.record(job.chapterID)
                return validChapterContent
            }
        )

        await manager.bootstrap(autoResume: true)
        let completed = try await waitForSnapshot(
            manager: manager,
            bookID: request.bookID,
            phase: .completed
        )
        let fetchedIDs = await probe.recordedIDs()
        let expectedMissingIDs = Set(request.jobs.dropFirst(2).map(\.chapterID))
        let persisted = try decodeCheckpointState(at: workspace.stateURL)

        #expect(fetchedIDs == expectedMissingIDs)
        #expect(completed.succeededCount == expectedMissingIDs.count)
        #expect(completed.durableStoredCount == request.jobs.count)
        #expect(persisted.checkpoints.first?.phase == .completed)
        #expect(persisted.checkpoints.first?.durableStoredCount == request.jobs.count)
    }

    @Test(arguments: [true, false])
    func pausingCheckpointRestoresPersistedPauseIntent(autoResume: Bool) async throws {
        let workspace = try ChapterDownloadTestWorkspace()
        defer { workspace.remove() }

        let request = makeRequest(chapterCount: 2)
        try writePausingCheckpoint(
            for: request,
            autoResume: autoResume,
            to: workspace.stateURL
        )
        let probe = DownloadIDProbe()
        let manager = ChapterDownloadManager(
            contentStore: ChapterContentStore(rootDirectory: workspace.contentRoot),
            stateURL: workspace.stateURL,
            fetchOperation: { job, _ in
                await probe.record(job.chapterID)
                return validChapterContent
            }
        )

        await manager.bootstrap(autoResume: true)
        if autoResume {
            let completed = try await waitForSnapshot(
                manager: manager,
                bookID: request.bookID,
                phase: .completed
            )
            let fetchedIDs = await probe.recordedIDs()
            #expect(fetchedIDs == Set(request.jobs.map(\.chapterID)))
            #expect(completed.durableStoredCount == request.jobs.count)
        } else {
            try await Task.sleep(nanoseconds: 50_000_000)
            let paused = await manager.snapshot(bookID: request.bookID)
            let fetchedIDs = await probe.recordedIDs()
            #expect(paused?.phase == .paused)
            #expect(fetchedIDs.isEmpty)
        }
    }

    @Test func promotesAutomaticChapterWithoutNetworkFetch() async throws {
        let workspace = try ChapterDownloadTestWorkspace()
        defer { workspace.remove() }

        let store = ChapterContentStore(rootDirectory: workspace.contentRoot)
        let request = makeRequest(chapterCount: 1)
        let job = try #require(request.jobs.first)
        try await store.store(
            validChapterContent,
            bookID: request.bookID,
            chapterID: job.chapterID,
            retention: .automatic
        )
        let probe = DownloadIDProbe()
        let manager = ChapterDownloadManager(
            contentStore: store,
            stateURL: workspace.stateURL,
            maxConcurrent: 5,
            fetchOperation: { job, _ in
                await probe.record(job.chapterID)
                return validChapterContent
            }
        )

        _ = try await manager.enqueue(request)
        let completed = try await waitForSnapshot(
            manager: manager,
            bookID: request.bookID,
            phase: .completed
        )
        let fetchedIDs = await probe.recordedIDs()
        let cached = await store.load(bookID: request.bookID, chapterID: job.chapterID)

        #expect(fetchedIDs.isEmpty)
        #expect(cached?.retention == .userManaged)
        #expect(completed.succeededCount == 1)
        #expect(completed.durableStoredCount == 1)
    }

    @Test func storageFailureIsNeverReportedAsSuccess() async throws {
        let workspace = try ChapterDownloadTestWorkspace()
        defer { workspace.remove() }

        let store = ChapterContentStore(rootDirectory: workspace.contentRoot)
        let request = makeRequest(chapterCount: 1)
        let job = try #require(request.jobs.first)
        let blockingBookURL = workspace.contentRoot.appendingPathComponent(
            request.bookID.uuidString.lowercased(),
            isDirectory: false
        )
        let probe = FailingStoreFetchProbe(blockingBookURL: blockingBookURL)
        let manager = ChapterDownloadManager(
            contentStore: store,
            stateURL: workspace.stateURL,
            maxConcurrent: 5,
            fetchOperation: { _, _ in
                try await probe.fetch()
            }
        )

        _ = try await manager.enqueue(request)
        let failed = try await waitForSnapshot(
            manager: manager,
            bookID: request.bookID,
            phase: .failed
        )
        let fetchCount = await probe.fetchCount()
        let cached = await store.load(bookID: request.bookID, chapterID: job.chapterID)

        #expect(fetchCount == 1)
        #expect(failed.processedCount == 1)
        #expect(failed.succeededCount == 0)
        #expect(failed.durableStoredCount == 0)
        #expect(failed.failedCount == 1)
        #expect(cached == nil)
    }

    @Test func duplicatePersistedCheckpointsAreQuarantinedWithoutStartingWork() async throws {
        let workspace = try ChapterDownloadTestWorkspace()
        defer { workspace.remove() }

        let request = makeRequest(chapterCount: 2)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let checkpoint = DownloadCheckpointFixture(
            version: 1,
            id: UUID(),
            bookID: request.bookID,
            bookTitle: request.bookTitle,
            jobs: request.jobs,
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
        var duplicate = checkpoint
        duplicate.updatedAt = timestamp.addingTimeInterval(1)
        try writeCheckpointState(
            PersistedDownloadStateFixture(
                version: 1,
                queue: [request.bookID],
                checkpoints: [checkpoint, duplicate]
            ),
            to: workspace.stateURL
        )

        let probe = DownloadIDProbe()
        let manager = ChapterDownloadManager(
            contentStore: ChapterContentStore(rootDirectory: workspace.contentRoot),
            stateURL: workspace.stateURL,
            fetchOperation: { job, _ in
                await probe.record(job.chapterID)
                return validChapterContent
            }
        )

        await manager.bootstrap(autoResume: true)
        try await Task.sleep(nanoseconds: 30_000_000)
        let snapshots = await manager.allSnapshots()
        let bootstrapError = await manager.bootstrapErrorDescription()
        let fetchedIDs = await probe.recordedIDs()
        let quarantinedFiles = try FileManager.default.contentsOfDirectory(
            at: workspace.stateURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains(".corrupt-") }

        #expect(snapshots.isEmpty)
        #expect(bootstrapError != nil)
        #expect(fetchedIDs.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: workspace.stateURL.path))
        #expect(quarantinedFiles.count == 1)
    }

    @Test func failedCheckpointWriteRollsBackEnqueueInMemory() async throws {
        let workspace = try ChapterDownloadTestWorkspace()
        defer { workspace.remove() }

        let blockingParent = workspace.directory.appendingPathComponent(
            "state-is-a-file",
            isDirectory: false
        )
        try Data("not a directory".utf8).write(to: blockingParent, options: .atomic)
        let stateURL = blockingParent.appendingPathComponent("queue.json")
        let probe = DownloadIDProbe()
        let manager = ChapterDownloadManager(
            contentStore: ChapterContentStore(rootDirectory: workspace.contentRoot),
            stateURL: stateURL,
            fetchOperation: { job, _ in
                await probe.record(job.chapterID)
                return validChapterContent
            }
        )
        let request = makeRequest(chapterCount: 2)

        var didThrow = false
        do {
            _ = try await manager.enqueue(request)
        } catch {
            didThrow = true
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        let snapshot = await manager.snapshot(bookID: request.bookID)
        let hasRunnableWork = await manager.hasRunnableWork()
        let fetchedIDs = await probe.recordedIDs()

        #expect(didThrow)
        #expect(snapshot == nil)
        #expect(!hasRunnableWork)
        #expect(fetchedIDs.isEmpty)
    }

    @Test func transientBootstrapReadFailureIsRetryableAndCannotOverwriteQueue() async throws {
        let workspace = try ChapterDownloadTestWorkspace()
        defer { workspace.remove() }

        // A directory at queue.json deterministically makes Data(contentsOf:)
        // fail without looking like corrupt JSON. The manager must fail closed
        // instead of persisting an empty replacement over that path.
        try FileManager.default.createDirectory(
            at: workspace.stateURL,
            withIntermediateDirectories: true
        )
        let request = makeRequest(chapterCount: 2)
        let probe = DownloadIDProbe()
        let manager = ChapterDownloadManager(
            contentStore: ChapterContentStore(rootDirectory: workspace.contentRoot),
            stateURL: workspace.stateURL,
            fetchOperation: { job, _ in
                await probe.record(job.chapterID)
                return validChapterContent
            }
        )

        await manager.bootstrap(autoResume: true)
        var rejectedWhileUnreadable = false
        do {
            _ = try await manager.enqueue(request)
        } catch ChapterDownloadManagerError.bootstrapUnavailable(_) {
            rejectedWhileUnreadable = true
        }
        var isDirectory: ObjCBool = false
        let unreadableStateStillExists = FileManager.default.fileExists(
            atPath: workspace.stateURL.path,
            isDirectory: &isDirectory
        )

        #expect(rejectedWhileUnreadable)
        #expect(unreadableStateStillExists && isDirectory.boolValue)
        #expect(await probe.recordedIDs().isEmpty)

        // Once the transient condition is repaired, the same manager retries
        // bootstrap and restores the durable work rather than staying poisoned.
        try FileManager.default.removeItem(at: workspace.stateURL)
        try writeRunningCheckpoint(for: request, to: workspace.stateURL)
        await manager.bootstrap(autoResume: true)
        let completed = try await waitForSnapshot(
            manager: manager,
            bookID: request.bookID,
            phase: .completed
        )

        #expect(completed.durableStoredCount == request.jobs.count)
        #expect(await probe.recordedIDs() == Set(request.jobs.map(\.chapterID)))
    }

    @Test func clearInvalidatesAnOlderQueuePreparation() async throws {
        let workspace = try ChapterDownloadTestWorkspace()
        defer { workspace.remove() }

        let probe = DownloadIDProbe()
        let manager = ChapterDownloadManager(
            contentStore: ChapterContentStore(rootDirectory: workspace.contentRoot),
            stateURL: workspace.stateURL,
            fetchOperation: { job, _ in
                await probe.record(job.chapterID)
                return validChapterContent
            }
        )
        let request = makeRequest(chapterCount: 2)
        let preparation = await manager.makePreparationToken(bookID: request.bookID)

        try await manager.clear(bookID: request.bookID)
        var rejectedAsStale = false
        do {
            _ = try await manager.enqueue(request, preparationToken: preparation)
        } catch ChapterDownloadManagerError.stalePreparation {
            rejectedAsStale = true
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        let snapshot = await manager.snapshot(bookID: request.bookID)
        let fetchedIDs = await probe.recordedIDs()

        #expect(rejectedAsStale)
        #expect(snapshot == nil)
        #expect(fetchedIDs.isEmpty)
    }

    @Test func clearRejectsEnqueueAndResumeUntilRunningWorkDrains() async throws {
        let workspace = try ChapterDownloadTestWorkspace()
        defer { workspace.remove() }

        let gate = PausableDownloadGate()
        let manager = ChapterDownloadManager(
            contentStore: ChapterContentStore(rootDirectory: workspace.contentRoot),
            stateURL: workspace.stateURL,
            maxConcurrent: 5,
            fetchOperation: { job, _ in
                await gate.fetch(chapterID: job.chapterID)
            }
        )
        let request = makeRequest(chapterCount: 5)

        _ = try await manager.enqueue(request)
        try await waitUntil {
            await gate.statistics().waiting == 5
        }
        let clearTask = Task {
            try await manager.clear(bookID: request.bookID)
        }
        try await waitUntil {
            await gate.statistics().cancelled == 5
        }

        var enqueueWasRejected = false
        do {
            _ = try await manager.enqueue(request)
        } catch ChapterDownloadManagerError.clearingInProgress {
            enqueueWasRejected = true
        }
        var resumeWasRejected = false
        do {
            _ = try await manager.resume(bookID: request.bookID)
        } catch ChapterDownloadManagerError.clearingInProgress {
            resumeWasRejected = true
        }
        #expect(enqueueWasRejected)
        #expect(resumeWasRejected)

        await gate.releaseAll()
        try await clearTask.value
        let snapshot = await manager.snapshot(bookID: request.bookID)
        #expect(snapshot == nil)
    }
}

private let validChapterContent = "第一章正文，足够用于测试缓存的持久写入。"

private func makeRequest(chapterCount: Int) -> ChapterDownloadRequest {
    let bookID = UUID()
    let jobs = (0..<chapterCount).map { index in
        ChapterDownloadJob(
            bookID: bookID,
            chapterID: UUID(),
            sourceURL: "https://example.com/book/\(bookID)/chapter/\(index)",
            nextChapterURL: nil
        )
    }
    return ChapterDownloadRequest(
        bookID: bookID,
        bookTitle: "下载测试",
        jobs: jobs,
        configuration: ChapterDownloadConfiguration(
            contentRule: "#content@text",
            replaceRegex: nil,
            nextContentURLRule: nil,
            baseURL: "https://example.com"
        )
    )
}

private func waitForSnapshot(
    manager: ChapterDownloadManager,
    bookID: UUID,
    phase: ChapterDownloadPhase,
    attempts: Int = 500
) async throws -> ChapterDownloadSnapshot {
    for _ in 0..<attempts {
        if let snapshot = await manager.snapshot(bookID: bookID), snapshot.phase == phase {
            return snapshot
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw ChapterDownloadTestError.timedOut("等待缓存状态 \(phase.rawValue)")
}

private func waitUntil(
    attempts: Int = 500,
    condition: () async -> Bool
) async throws {
    for _ in 0..<attempts {
        if await condition() { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw ChapterDownloadTestError.timedOut("等待异步测试条件")
}

private enum ChapterDownloadTestError: Error {
    case timedOut(String)
}

private struct ChapterDownloadTestWorkspace {
    let directory: URL
    let contentRoot: URL
    let stateURL: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "YiYueChapterDownloadManagerTests-\(UUID().uuidString)",
            isDirectory: true
        )
        contentRoot = directory.appendingPathComponent("content", isDirectory: true)
        stateURL = directory
            .appendingPathComponent("downloads", isDirectory: true)
            .appendingPathComponent("queue.json", isDirectory: false)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private actor DownloadConcurrencyProbe {
    private var active = 0
    private var peak = 0
    private var started = 0

    func fetch() async throws -> String? {
        active += 1
        started += 1
        peak = max(peak, active)
        defer { active -= 1 }
        try await Task.sleep(nanoseconds: 40_000_000)
        return validChapterContent
    }

    func statistics() -> (active: Int, peak: Int, started: Int) {
        (active, peak, started)
    }
}

private actor MergedDownloadGate {
    private var isOpen = false
    private var continuations: [UUID: CheckedContinuation<String?, Never>] = [:]
    private var fetched: Set<UUID> = []

    func fetch(chapterID: UUID) async -> String? {
        fetched.insert(chapterID)
        if isOpen {
            return validChapterContent
        }
        return await withCheckedContinuation { continuation in
            continuations[chapterID] = continuation
        }
    }

    func open() {
        isOpen = true
        let waiting = continuations.values
        continuations.removeAll()
        for continuation in waiting {
            continuation.resume(returning: validChapterContent)
        }
    }

    func waitingCount() -> Int {
        continuations.count
    }

    func fetchedIDs() -> Set<UUID> {
        fetched
    }
}

private actor PausableDownloadGate {
    private var continuations: [UUID: CheckedContinuation<String?, Never>] = [:]
    private var startedIDs: Set<UUID> = []
    private var cancelledIDs: Set<UUID> = []
    private var active = 0

    func fetch(chapterID: UUID) async -> String? {
        startedIDs.insert(chapterID)
        active += 1
        defer { active -= 1 }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                continuations[chapterID] = continuation
            }
        } onCancel: {
            Task { await self.recordCancellation(chapterID) }
        }
    }

    func releaseAll() {
        let waiting = continuations.values
        continuations.removeAll()
        for continuation in waiting {
            continuation.resume(returning: validChapterContent)
        }
    }

    func statistics() -> (started: Int, waiting: Int, cancelled: Int, active: Int) {
        (startedIDs.count, continuations.count, cancelledIDs.count, active)
    }

    private func recordCancellation(_ chapterID: UUID) {
        cancelledIDs.insert(chapterID)
    }
}

private actor BackgroundSuspensionProbe {
    private let immediateIDs: Set<UUID>
    private var isOpen = false
    private var isAfterResumeBoundary = false
    private var continuations: [UUID: CheckedContinuation<String?, Never>] = [:]
    private var cancelledIDs: Set<UUID> = []
    private var afterResumeIDs: Set<UUID> = []
    private var active = 0

    init(immediateIDs: Set<UUID>) {
        self.immediateIDs = immediateIDs
    }

    func fetch(chapterID: UUID) async -> String? {
        active += 1
        defer { active -= 1 }
        if isAfterResumeBoundary {
            afterResumeIDs.insert(chapterID)
        }
        if immediateIDs.contains(chapterID) || isOpen {
            return validChapterContent
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                continuations[chapterID] = continuation
            }
        } onCancel: {
            Task { await self.recordCancellation(chapterID) }
        }
    }

    func releaseCancelledAndOpen() {
        isOpen = true
        let waiting = continuations.values
        continuations.removeAll()
        for continuation in waiting {
            continuation.resume(returning: validChapterContent)
        }
    }

    func markResumeBoundary() {
        isAfterResumeBoundary = true
    }

    func statistics() -> (waiting: Int, cancelled: Int, active: Int) {
        (continuations.count, cancelledIDs.count, active)
    }

    func fetchedAfterResume() -> Set<UUID> {
        afterResumeIDs
    }

    private func recordCancellation(_ chapterID: UUID) {
        cancelledIDs.insert(chapterID)
    }
}

private actor DownloadIDProbe {
    private var ids: Set<UUID> = []

    func record(_ id: UUID) {
        ids.insert(id)
    }

    func recordedIDs() -> Set<UUID> {
        ids
    }
}

private actor FailingStoreFetchProbe {
    private let blockingBookURL: URL
    private var count = 0

    init(blockingBookURL: URL) {
        self.blockingBookURL = blockingBookURL
    }

    func fetch() throws -> String? {
        count += 1
        try FileManager.default.createDirectory(
            at: blockingBookURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-a-directory".utf8).write(to: blockingBookURL, options: .atomic)
        return validChapterContent
    }

    func fetchCount() -> Int {
        count
    }
}

private struct PersistedDownloadStateFixture: Codable {
    let version: Int
    let queue: [UUID]
    let checkpoints: [DownloadCheckpointFixture]
}

private struct DownloadCheckpointFixture: Codable {
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

private func writeRunningCheckpoint(
    for request: ChapterDownloadRequest,
    to stateURL: URL
) throws {
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let state = PersistedDownloadStateFixture(
        version: 1,
        queue: [],
        checkpoints: [
            DownloadCheckpointFixture(
                version: 1,
                id: UUID(),
                bookID: request.bookID,
                bookTitle: request.bookTitle,
                jobs: request.jobs,
                configuration: request.configuration,
                phase: .running,
                processedCount: 2,
                succeededCount: 2,
                durableStoredCount: 0,
                failedChapterIDs: [],
                lastError: nil,
                autoResume: true,
                createdAt: timestamp,
                updatedAt: timestamp
            )
        ]
    )
    try writeCheckpointState(state, to: stateURL)
}

private func writePausingCheckpoint(
    for request: ChapterDownloadRequest,
    autoResume: Bool,
    to stateURL: URL
) throws {
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let state = PersistedDownloadStateFixture(
        version: 1,
        queue: [],
        checkpoints: [
            DownloadCheckpointFixture(
                version: 1,
                id: UUID(),
                bookID: request.bookID,
                bookTitle: request.bookTitle,
                jobs: request.jobs,
                configuration: request.configuration,
                phase: .pausing,
                processedCount: 1,
                succeededCount: 1,
                durableStoredCount: 0,
                failedChapterIDs: [],
                lastError: nil,
                autoResume: autoResume,
                createdAt: timestamp,
                updatedAt: timestamp
            )
        ]
    )
    try writeCheckpointState(state, to: stateURL)
}

private func writeCheckpointState(
    _ state: PersistedDownloadStateFixture,
    to stateURL: URL
) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .millisecondsSince1970
    let data = try encoder.encode(state)
    try FileManager.default.createDirectory(
        at: stateURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: stateURL, options: .atomic)
}

private func decodeCheckpointState(at stateURL: URL) throws -> PersistedDownloadStateFixture {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return try decoder.decode(
        PersistedDownloadStateFixture.self,
        from: Data(contentsOf: stateURL)
    )
}
