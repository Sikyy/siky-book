import Foundation
import Testing
@testable import YiYue

@Suite("Reader cache presentation state")
struct ReaderCachePresentationStateTests {
    @Test func unavailableAlwaysWins() {
        let state = ReaderCachePresentationState.derive(
            isAvailable: false,
            isChecking: true,
            summary: BookCacheSummary(cached: 4, uncached: 6),
            snapshot: makeSnapshot(phase: .running)
        )

        #expect(state == .unavailable)
    }

    @Test func liveTaskRemainsControllableWhilePersistentCacheIsChecking() {
        let state = ReaderCachePresentationState.derive(
            isAvailable: true,
            isChecking: true,
            summary: BookCacheSummary(cached: 250, uncached: 750),
            snapshot: makeSnapshot(
                phase: .running,
                targetCount: 100,
                processedCount: 25,
                durableStoredCount: 20
            )
        )

        #expect(state == .running(processed: 45, target: 100, cached: 250, total: 1_000))
        #expect(state.taskProgressFraction == 0.45)
    }

    @Test func taskUsesConservativeDisplayCountsBeforeSummaryArrives() {
        let state = ReaderCachePresentationState.derive(
            isAvailable: true,
            isChecking: true,
            summary: nil,
            snapshot: makeSnapshot(
                phase: .running,
                targetCount: 100,
                processedCount: 120,
                durableStoredCount: 116
            )
        )

        #expect(state == .running(processed: 100, target: 100, cached: 116, total: 116))
        #expect(state.taskProgressFraction == 1)
    }

    @Test func taskPhasesPreserveTheirDistinctActions() {
        let summary = BookCacheSummary(cached: 40, uncached: 60)

        let queued = ReaderCachePresentationState.derive(
            isAvailable: true,
            isChecking: false,
            summary: summary,
            snapshot: makeSnapshot(phase: .queued, queuePosition: 3)
        )
        let pausing = ReaderCachePresentationState.derive(
            isAvailable: true,
            isChecking: false,
            summary: summary,
            snapshot: makeSnapshot(phase: .pausing, inFlightCount: 4)
        )
        let paused = ReaderCachePresentationState.derive(
            isAvailable: true,
            isChecking: false,
            summary: summary,
            snapshot: makeSnapshot(phase: .paused)
        )
        let failed = ReaderCachePresentationState.derive(
            isAvailable: true,
            isChecking: false,
            summary: summary,
            snapshot: makeSnapshot(phase: .failed, lastError: "网络中断")
        )

        #expect(queued == .queued(position: 3, cached: 40, total: 100))
        #expect(pausing == .pausing(inFlight: 4, cached: 40, total: 100))
        #expect(paused == .paused(cached: 40, total: 100))
        #expect(failed == .failed(cached: 40, total: 100, error: "网络中断"))
    }

    @Test func completedPartialRequestCannotClaimWholeBookCompletion() {
        let state = ReaderCachePresentationState.derive(
            isAvailable: true,
            isChecking: false,
            summary: BookCacheSummary(cached: 100, uncached: 900),
            snapshot: makeSnapshot(
                phase: .completed,
                targetCount: 100,
                processedCount: 100,
                durableStoredCount: 100
            )
        )

        #expect(state == .partial(cached: 100, total: 1_000))
    }

    @Test func terminalTaskWaitsForPersistentSummary() {
        let state = ReaderCachePresentationState.derive(
            isAvailable: true,
            isChecking: false,
            summary: nil,
            snapshot: makeSnapshot(
                phase: .completed,
                targetCount: 100,
                processedCount: 100,
                durableStoredCount: 100
            )
        )

        #expect(state == .checking)
    }

    @Test func persistentSummaryDeterminesIdleStates() {
        let empty = ReaderCachePresentationState.derive(
            isAvailable: true,
            isChecking: false,
            summary: BookCacheSummary(cached: 0, uncached: 10),
            snapshot: nil
        )
        let partial = ReaderCachePresentationState.derive(
            isAvailable: true,
            isChecking: false,
            summary: BookCacheSummary(cached: 4, uncached: 6),
            snapshot: nil
        )
        let complete = ReaderCachePresentationState.derive(
            isAvailable: true,
            isChecking: false,
            summary: BookCacheSummary(cached: 10, uncached: 0),
            snapshot: nil
        )

        #expect(empty == .empty(total: 10))
        #expect(partial == .partial(cached: 4, total: 10))
        #expect(complete == .complete(total: 10))
    }

    private func makeSnapshot(
        phase: ChapterDownloadPhase,
        targetCount: Int = 10,
        processedCount: Int = 0,
        durableStoredCount: Int = 0,
        inFlightCount: Int = 0,
        queuePosition: Int? = nil,
        lastError: String? = nil
    ) -> ChapterDownloadSnapshot {
        ChapterDownloadSnapshot(
            id: UUID(),
            bookID: UUID(),
            bookTitle: "测试书籍",
            phase: phase,
            targetCount: targetCount,
            processedCount: processedCount,
            succeededCount: 0,
            durableStoredCount: durableStoredCount,
            failedCount: 0,
            inFlightCount: inFlightCount,
            queuePosition: queuePosition,
            lastError: lastError,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
