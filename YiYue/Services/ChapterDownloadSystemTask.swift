import BackgroundTasks
import Foundation
import UIKit

/// Bridges the durable chapter queue to the amount of background execution the
/// current OS can actually provide. The system task is only an execution lease;
/// all resumable state remains in `ChapterDownloadManager` and on disk.
@MainActor
final class ChapterDownloadSystemTask {
    static let shared = ChapterDownloadSystemTask()

    private let scheduler = BGTaskScheduler.shared
    private var didRegisterContinuedTask = false
    private var didRegisterProcessingTask = false
    private var isContinuedRequestSubmitted = false
    private var activeContinuedTask: BGTask?
    private var activeProcessingTask: BGProcessingTask?
    private var observationTask: Task<Void, Never>?
    private var observationGeneration: UUID?
    private var observedSessionIDs: Set<UUID> = []
    private var requestedBookIDs: Set<UUID> = []
    private var backgroundDrainTask: Task<Void, Never>?
    private var shortBackgroundTask: UIBackgroundTaskIdentifier = .invalid

    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.mistyislet.yiyue"
    }

    private var continuedIdentifier: String {
        "\(bundleIdentifier).chapter-cache.user"
    }

    private var processingIdentifier: String {
        "\(bundleIdentifier).chapter-cache.resume"
    }

    private init() {}

    /// Must be called once during app launch. The explicit guards are important:
    /// registering the same BackgroundTasks identifier twice terminates the app.
    func register() {
        if #available(iOS 26.0, *), !didRegisterContinuedTask {
            didRegisterContinuedTask = scheduler.register(
                forTaskWithIdentifier: continuedIdentifier,
                using: DispatchQueue.main
            ) { [weak self] rawTask in
                guard let task = rawTask as? BGContinuedProcessingTask else {
                    rawTask.setTaskCompleted(success: false)
                    return
                }
                MainActor.assumeIsolated {
                    self?.handleContinuedTask(task)
                }
            }
        }

        if !didRegisterProcessingTask {
            didRegisterProcessingTask = scheduler.register(
                forTaskWithIdentifier: processingIdentifier,
                using: DispatchQueue.main
            ) { [weak self] rawTask in
                guard let task = rawTask as? BGProcessingTask else {
                    rawTask.setTaskCompleted(success: false)
                    return
                }
                MainActor.assumeIsolated {
                    self?.handleProcessingTask(task)
                }
            }
        }
    }

    /// Called only after a person explicitly asks to cache chapters and the
    /// manager has durably checkpointed that request.
    func submitUserInitiated(bookID: UUID, bookTitle: String) {
        register()
        if #available(iOS 26.0, *) {
            // Remember the durable work this lease represents before asking
            // the scheduler for runtime. This also covers a tiny queue that
            // completes between submission and launch-handler delivery.
            requestedBookIDs.insert(bookID)
            if let task = activeContinuedTask as? BGContinuedProcessingTask {
                task.updateTitle("正在缓存《\(bookTitle)》", subtitle: "准备下一批章节")
                return
            }
            guard !isContinuedRequestSubmitted else { return }

            let request = BGContinuedProcessingTaskRequest(
                identifier: continuedIdentifier,
                title: "正在缓存《\(bookTitle)》",
                subtitle: "正在准备章节队列"
            )
            request.strategy = .queue
            request.requiredResources = []
            do {
                try scheduler.submit(request)
                isContinuedRequestSubmitted = true
            } catch {
                // Foreground execution and the durable checkpoint remain valid.
                // A later launch can restore the queue even if this lease is denied.
                scheduleProcessingRecovery()
            }
        }
        // On iOS 17-25 the queue already runs in the foreground. A recovery
        // request is submitted only if the scene actually enters background
        // with runnable work, avoiding a later no-op system wakeup.
    }

    func sceneDidEnterBackground() {
        guard #unavailable(iOS 26.0) else { return }
        guard shortBackgroundTask == .invalid else { return }

        shortBackgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "ChapterCacheCheckpoint"
        ) { [weak self] in
            // At this point iOS is reclaiming the short foreground-extension
            // lease. Do not start another asynchronous disk reconciliation:
            // cancel the best-effort drain, retain the already durable queue,
            // arrange a later processing lease, and return the UIKit lease now.
            self?.backgroundDrainTask?.cancel()
            self?.backgroundDrainTask = nil
            self?.scheduleProcessingRecovery()
            self?.endShortBackgroundTask()
        }
        backgroundDrainTask?.cancel()
        backgroundDrainTask = Task { [weak self] in
            await ChapterDownloadManager.shared.bootstrap()
            guard await ChapterDownloadManager.shared.hasRunnableWork() else {
                self?.endShortBackgroundTask()
                return
            }
            await ChapterDownloadManager.shared.suspendForBackground()
            guard !Task.isCancelled else { return }
            self?.scheduleProcessingRecovery()
            self?.endShortBackgroundTask()
        }
    }

    func sceneWillEnterForeground() {
        if #unavailable(iOS 26.0) {
            backgroundDrainTask?.cancel()
            backgroundDrainTask = nil
            endShortBackgroundTask()
            // A fresh foreground lease makes an unlaunched recovery request
            // obsolete. If work is backgrounded again, that transition will
            // checkpoint it and submit a new request with a fresh start date.
            scheduler.cancel(taskRequestWithIdentifier: processingIdentifier)
        }
        Task {
            await ChapterDownloadManager.shared.resumeSystemSuspended()
        }
    }

    @available(iOS 26.0, *)
    private func handleContinuedTask(_ task: BGContinuedProcessingTask) {
        if let processingTask = activeProcessingTask {
            processingTask.setTaskCompleted(success: false)
            activeProcessingTask = nil
        }
        scheduler.cancel(taskRequestWithIdentifier: processingIdentifier)
        activeContinuedTask = task
        isContinuedRequestSubmitted = true
        task.progress.totalUnitCount = 1
        task.progress.completedUnitCount = 0
        task.expirationHandler = { [weak self] in
            Task {
                // iOS reports both a person tapping Stop in the system UI and
                // resource-driven expiration through this same callback, with
                // no supported reason value. Treat it as an explicit pause so
                // we never silently restart work that the person cancelled.
                await ChapterDownloadManager.shared.pauseAll()
                await MainActor.run {
                    guard self?.activeContinuedTask === task else { return }
                    self?.finishSystemTasks(success: false)
                }
            }
        }
        startObservingManager()
    }

    private func handleProcessingTask(_ task: BGProcessingTask) {
        guard activeContinuedTask == nil else {
            task.setTaskCompleted(success: false)
            return
        }
        activeProcessingTask = task
        task.expirationHandler = { [weak self] in
            Task {
                await ChapterDownloadManager.shared.suspendForBackground()
                await MainActor.run {
                    guard self?.activeProcessingTask === task else { return }
                    self?.scheduleProcessingRecovery()
                    self?.finishSystemTasks(success: false)
                }
            }
        }
        startObservingManager(resumeSystemSuspended: true)
    }

    private func startObservingManager(resumeSystemSuspended: Bool = false) {
        observationTask?.cancel()
        let generation = UUID()
        observationGeneration = generation
        observedSessionIDs = []
        observationTask = Task { [weak self] in
            // A background launch can invoke this handler before ContentView's
            // bootstrap task. Load durable intent before deciding that there is
            // no runnable work. BGProcessing must also resume its paused lease
            // before the observer is allowed to complete the system task.
            await ChapterDownloadManager.shared.bootstrap()
            guard let self,
                  self.observationGeneration == generation,
                  !Task.isCancelled else { return }
            if resumeSystemSuspended {
                await ChapterDownloadManager.shared.resumeSystemSuspended()
                guard self.observationGeneration == generation,
                      !Task.isCancelled else { return }
            }
            let stream = await ChapterDownloadManager.shared.updates()
            guard self.observationGeneration == generation,
                  !Task.isCancelled else { return }
            await self.refreshSystemProgress(generation: generation)
            for await _ in stream {
                guard self.observationGeneration == generation,
                      !Task.isCancelled else { return }
                await self.refreshSystemProgress(generation: generation)
            }
        }
    }

    private func refreshSystemProgress(generation: UUID) async {
        let snapshots = await ChapterDownloadManager.shared.allSnapshots()
        guard observationGeneration == generation, !Task.isCancelled else { return }

        observedSessionIDs.formUnion(
            snapshots.lazy.filter(\.phase.isActive).map(\.id)
        )
        observedSessionIDs.formUnion(
            snapshots.lazy
                .filter { self.requestedBookIDs.contains($0.bookID) }
                .map(\.id)
        )
        if observedSessionIDs.isEmpty,
           requestedBookIDs.isEmpty,
           let latest = snapshots.max(by: { $0.updatedAt < $1.updatedAt }) {
            observedSessionIDs.insert(latest.id)
        }
        let leaseSnapshots = snapshots.filter { observedSessionIDs.contains($0.id) }
        let runnableSnapshots = snapshots.filter(\.phase.isActive)

        // Derive activity, progress, and completion from one actor snapshot.
        // Separate activeSnapshot()/hasRunnableWork() calls can straddle the
        // running -> completed transition and report a successful lease as a
        // failure using stale running snapshots.
        if let active = runnableSnapshots.first(where: { $0.phase == .running })
            ?? runnableSnapshots.first(where: { $0.phase == .pausing })
            ?? runnableSnapshots.min(by: {
                ($0.queuePosition ?? .max) < ($1.queuePosition ?? .max)
            }) {
            let total = leaseSnapshots.reduce(0) { $0 + $1.targetCount }
            let completed = leaseSnapshots.reduce(0) { partial, snapshot in
                partial + min(
                    snapshot.targetCount,
                    snapshot.durableStoredCount + snapshot.processedCount
                )
            }
            if #available(iOS 26.0, *),
               let task = activeContinuedTask as? BGContinuedProcessingTask {
                task.progress.totalUnitCount = Int64(max(1, total))
                task.progress.completedUnitCount = Int64(max(0, completed))
                task.updateTitle(
                    "正在缓存《\(active.bookTitle)》",
                    subtitle: "总进度 \(completed) / \(total)"
                )
            }
            return
        }

        let success = !leaseSnapshots.isEmpty
            && leaseSnapshots.allSatisfy { $0.phase == .completed }
        finishSystemTasks(success: success, generation: generation)
    }

    private func finishSystemTasks(success: Bool, generation: UUID? = nil) {
        if let generation, observationGeneration != generation { return }
        observationTask?.cancel()
        observationTask = nil
        observationGeneration = nil
        observedSessionIDs = []
        requestedBookIDs = []
        if #available(iOS 26.0, *),
           let task = activeContinuedTask as? BGContinuedProcessingTask {
            task.setTaskCompleted(success: success)
        }
        activeContinuedTask = nil
        isContinuedRequestSubmitted = false

        activeProcessingTask?.setTaskCompleted(success: success)
        activeProcessingTask = nil
        if success {
            scheduler.cancel(taskRequestWithIdentifier: processingIdentifier)
        }
    }

    private func scheduleProcessingRecovery() {
        let request = BGProcessingTaskRequest(identifier: processingIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        try? scheduler.submit(request)
    }

    private func endShortBackgroundTask() {
        guard shortBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(shortBackgroundTask)
        shortBackgroundTask = .invalid
    }
}
