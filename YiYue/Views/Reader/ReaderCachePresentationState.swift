import Foundation

/// A single presentation model shared by every reader cache entry point.
///
/// `BookCacheSummary` is the authority for whole-book completion. A download
/// snapshot only describes the current (or most recent) request, whose target
/// can be smaller than the book, so terminal task phases deliberately fall
/// back to the persistent summary.
enum ReaderCachePresentationState: Sendable, Equatable {
    case unavailable
    case checking
    case empty(total: Int)
    case partial(cached: Int, total: Int)
    case queued(position: Int?, cached: Int, total: Int)
    case running(processed: Int, target: Int, cached: Int, total: Int)
    case pausing(inFlight: Int, cached: Int, total: Int)
    case paused(cached: Int, total: Int)
    case failed(cached: Int, total: Int, error: String?)
    case complete(total: Int)

    /// Derives UI state from task activity and durable, whole-book cache state.
    ///
    /// Live task phases take precedence over reconciliation so a visible task
    /// remains controllable while a disk scan is running. If the scan has not
    /// produced a summary yet, task counts are used only as a conservative
    /// display fallback; they are never used to infer `.complete`.
    static func derive(
        isAvailable: Bool,
        isChecking: Bool,
        summary: BookCacheSummary?,
        snapshot: ChapterDownloadSnapshot?
    ) -> Self {
        guard isAvailable else { return .unavailable }

        if let snapshot {
            let counts = displayCounts(summary: summary, snapshot: snapshot)
            switch snapshot.phase {
            case .queued:
                return .queued(
                    position: snapshot.queuePosition,
                    cached: counts.cached,
                    total: counts.total
                )
            case .running:
                let target = max(0, snapshot.targetCount)
                return .running(
                    processed: normalizedTaskProgress(snapshot, target: target),
                    target: target,
                    cached: counts.cached,
                    total: counts.total
                )
            case .pausing:
                return .pausing(
                    inFlight: max(0, snapshot.inFlightCount),
                    cached: counts.cached,
                    total: counts.total
                )
            case .paused:
                return .paused(cached: counts.cached, total: counts.total)
            case .failed:
                return .failed(
                    cached: counts.cached,
                    total: counts.total,
                    error: snapshot.lastError
                )
            case .completed, .cancelled:
                break
            }
        }

        guard !isChecking, let summary else { return .checking }
        let counts = normalizedCounts(summary)
        guard counts.total > 0 else { return .empty(total: 0) }
        guard counts.cached > 0 else { return .empty(total: counts.total) }
        guard counts.cached < counts.total else { return .complete(total: counts.total) }
        return .partial(cached: counts.cached, total: counts.total)
    }

    var cachedCount: Int? {
        switch self {
        case .unavailable, .checking:
            return nil
        case .empty:
            return 0
        case .partial(let cached, _),
             .queued(_, let cached, _),
             .running(_, _, let cached, _),
             .pausing(_, let cached, _),
             .paused(let cached, _),
             .failed(let cached, _, _):
            return cached
        case .complete(let total):
            return total
        }
    }

    var totalCount: Int? {
        switch self {
        case .unavailable, .checking:
            return nil
        case .empty(let total),
             .partial(_, let total),
             .queued(_, _, let total),
             .running(_, _, _, let total),
             .pausing(_, _, let total),
             .paused(_, let total),
             .failed(_, let total, _),
             .complete(let total):
            return total
        }
    }

    var taskProgressFraction: Double? {
        guard case .running(let processed, let target, _, _) = self,
              target > 0 else {
            return nil
        }
        return Double(Self.normalizedProgress(processed, target: target)) / Double(target)
    }

    private static func displayCounts(
        summary: BookCacheSummary?,
        snapshot: ChapterDownloadSnapshot
    ) -> (cached: Int, total: Int) {
        if let summary {
            return normalizedCounts(summary)
        }
        let cached = max(0, snapshot.durableStoredCount)
        return (cached, max(cached, max(0, snapshot.targetCount)))
    }

    private static func normalizedCounts(_ summary: BookCacheSummary) -> (cached: Int, total: Int) {
        let cached = max(0, summary.cached)
        let uncached = max(0, summary.uncached)
        return (cached, cached + uncached)
    }

    private static func normalizedProgress(_ processed: Int, target: Int) -> Int {
        guard target > 0 else { return 0 }
        return min(max(0, processed), target)
    }

    /// `processedCount` only covers work attempted after the manager's initial
    /// disk scan. Include chapters already durable within this request so the
    /// task progress starts at, and can reach, the correct position.
    private static func normalizedTaskProgress(
        _ snapshot: ChapterDownloadSnapshot,
        target: Int
    ) -> Int {
        let durable = normalizedProgress(snapshot.durableStoredCount, target: target)
        let remaining = max(0, target - durable)
        return durable + min(max(0, snapshot.processedCount), remaining)
    }
}
