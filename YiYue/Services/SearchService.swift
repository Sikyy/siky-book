import Foundation
import SwiftData

struct AggregatedSearchResult: Identifiable {
    let id = UUID()
    let title: String
    let author: String
    var coverURL: String?
    var intro: String?
    var sources: [SourceMatch]

    struct SourceMatch: Identifiable {
        let id = UUID()
        let sourceName: String
        let sourceId: UUID
        let bookURL: String
        let source: LegadoSource
    }
}

// Values crossing the task-group boundary must not retain SwiftData models.
private struct SearchSourceSnapshot: Sendable {
    let id: UUID
    let name: String
    let sourceURL: String
    let ruleJSON: String
}

private struct SearchHitSnapshot: Sendable {
    let title: String
    let author: String
    let bookURL: String
    let coverURL: String?
    let intro: String?
    let normalizedKey: String
    let normalizedTitle: String
    let normalizedAuthor: String
}

private struct SourceSearchBatch: Sendable {
    let source: SearchSourceSnapshot
    let parsedSource: LegadoSource?
    let hits: [SearchHitSnapshot]
}

private enum SearchSourceSnapshotWorker {
    /// Builds the frozen value-only source sequence away from MainActor. No
    /// SwiftData model or context escapes the detached worker that calls this.
    static func fetchEnabledSources(in container: ModelContainer) throws -> [SearchSourceSnapshot] {
        let signposter = PerformanceSignposts.search
        let signpostID = signposter.makeSignpostID()
        var intervalResult = "error"
        var intervalCount = 0
        let intervalState = signposter.beginInterval("SearchSnapshotLoad", id: signpostID)
        defer {
            if Task.isCancelled {
                intervalResult = "cancelled"
            }
            signposter.endInterval(
                "SearchSnapshotLoad",
                intervalState,
                "result=\(intervalResult, privacy: .public) count=\(intervalCount)"
            )
        }

        try Task.checkCancellation()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let sources = try context.fetch(FetchDescriptor<BookSource>())
        try Task.checkCancellation()

        // Preserve the fetched order exactly for staged continuation. In
        // particular, a missing quality score never demotes a source.
        let snapshots = sources.compactMap { source -> SearchSourceSnapshot? in
            guard source.enabled else { return nil }
            return SearchSourceSnapshot(
                id: source.id,
                name: source.name,
                sourceURL: source.sourceURL,
                ruleJSON: source.ruleJSON
            )
        }
        try Task.checkCancellation()
        intervalCount = snapshots.count
        intervalResult = "success"
        return snapshots
    }
}

@MainActor
@Observable
final class SearchService {
    var results: [AggregatedSearchResult] = []
    var isSearching = false
    var isPreparingSources = false
    var isSearchPaused = false
    var isSearchFinished = false
    var hasSearchSession = false
    var searchError: String?
    var searchedCount = 0
    var totalCount = 0

    var remainingCount: Int {
        max(totalCount - searchedCount, 0)
    }

    private struct AccumulatedResult {
        var value: AggregatedSearchResult
        let normalizedTitle: String
        let normalizedAuthor: String
        let isExactMatch: Bool
        let containsKeyword: Bool
        var metadataScore: Int
        var sourceKeys: Set<String>
    }

    private let modelContainer: ModelContainer
    private var searchTask: Task<Void, Never>?
    private var searchGeneration: UInt64 = 0
    private var frozenSources: [SearchSourceSnapshot] = []
    private var nextSourceIndex = 0
    private var activeKeyword: String?
    private var normalizedKeyword = ""
    private var pauseRequested = false

    private enum RunMode {
        case staged
        case allRemaining
    }

    // Keep request fan-out bounded. Completed tasks continuously feed the next source.
    private static let maxConcurrency = 9
    private static let stagedSourceLimit = 36
    private static let stagedTimeLimit: CFTimeInterval = 12
    private static let sourceTimeoutNanos: UInt64 = 15_000_000_000
    private static let uiFlushInterval: CFAbsoluteTime = 1.0

    // MainActor-only aggregation buffer. The observed results array is published at most once/sec.
    private var accumulatedResults: [String: AccumulatedResult] = [:]
    private var completedSourceCount = 0
    private var hasUnpublishedResultChanges = false
    private var lastFlushTime: CFAbsoluteTime = 0

    init(modelContext: ModelContext) {
        modelContainer = modelContext.container
    }

    // MARK: - Public API

    func search(keyword: String) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        searchTask?.cancel()
        searchGeneration &+= 1
        let generation = searchGeneration
        results = []
        searchError = nil
        searchedCount = 0
        totalCount = 0
        isSearching = false
        isPreparingSources = false
        isSearchPaused = false
        isSearchFinished = false
        hasSearchSession = true
        accumulatedResults.removeAll(keepingCapacity: true)
        completedSourceCount = 0
        hasUnpublishedResultChanges = false
        lastFlushTime = CFAbsoluteTimeGetCurrent()
        frozenSources = []
        nextSourceIndex = 0
        activeKeyword = trimmed
        normalizedKeyword = Self.normalize(trimmed)
        pauseRequested = false

        isSearching = true
        isPreparingSources = true
        searchTask = Task { [weak self] in
            await self?.prepareSearch(generation: generation)
        }
    }

    func continueSearch() {
        guard isSearchPaused, !isSearching else { return }
        startStage(mode: .staged)
    }

    func searchAllRemaining() {
        guard isSearchPaused, !isSearching else { return }
        startStage(mode: .allRemaining)
    }

    /// Stops scheduling new sources but lets all in-flight requests finish. This
    /// keeps the frozen cursor resumable without skipping a partially run source.
    func pauseSearch() {
        guard isSearching else { return }
        pauseRequested = true
    }

    func cancelSearch() {
        searchTask?.cancel()
        publishProgressAndResults(force: true)

        // Invalidate any completion/final flush already queued by the cancelled task.
        searchGeneration &+= 1
        searchTask = nil
        isSearching = false
        isPreparingSources = false
        isSearchPaused = false
        isSearchFinished = false
        hasSearchSession = false
        frozenSources = []
        nextSourceIndex = 0
        activeKeyword = nil
        pauseRequested = false
    }

    // MARK: - Search Pipeline

    private func prepareSearch(generation: UInt64) async {
        do {
            let container = modelContainer
            let snapshotTask = Task.detached(priority: .userInitiated) {
                try SearchSourceSnapshotWorker.fetchEnabledSources(in: container)
            }
            let snapshots = try await withTaskCancellationHandler {
                try await snapshotTask.value
            } onCancel: {
                snapshotTask.cancel()
            }
            guard generation == searchGeneration, !Task.isCancelled else { return }

            frozenSources = snapshots
            totalCount = snapshots.count
            isSearching = false
            isPreparingSources = false
            searchTask = nil

            guard !snapshots.isEmpty else {
                isSearchFinished = true
                return
            }
            startStage(mode: .staged)
        } catch is CancellationError {
            return
        } catch {
            guard generation == searchGeneration, !Task.isCancelled else { return }
            searchError = error.localizedDescription
            isSearching = false
            isPreparingSources = false
            searchTask = nil
        }
    }

    private func startStage(mode: RunMode) {
        guard let keyword = activeKeyword,
              nextSourceIndex < frozenSources.count,
              !isSearching else {
            if hasSearchSession, nextSourceIndex >= frozenSources.count {
                isSearchPaused = false
                isSearchFinished = true
            }
            return
        }

        searchGeneration &+= 1
        let generation = searchGeneration
        isSearching = true
        isPreparingSources = false
        isSearchPaused = false
        isSearchFinished = false
        searchError = nil
        pauseRequested = false

        searchTask = Task { [weak self] in
            await self?.performStage(
                keyword: keyword,
                generation: generation,
                mode: mode
            )
        }
    }

    private func performStage(
        keyword: String,
        generation: UInt64,
        mode: RunMode
    ) async {
        let signposter = PerformanceSignposts.search
        let signpostID = signposter.makeSignpostID()
        var intervalResult = "cancelled"
        let intervalTotal = frozenSources.count
        var intervalCompleted = 0
        var intervalSearched = completedSourceCount
        var intervalResults = 0
        let intervalState = signposter.beginInterval("SearchSession", id: signpostID)
        defer {
            signposter.endInterval(
                "SearchSession",
                intervalState,
                "result=\(intervalResult, privacy: .public) total=\(intervalTotal) stageCompleted=\(intervalCompleted) searched=\(intervalSearched) results=\(intervalResults)"
            )
        }
        guard generation == searchGeneration, !Task.isCancelled else { return }

        let stageStartedAt = CFAbsoluteTimeGetCurrent()
        var stageScheduled = 0

        await withTaskGroup(of: SourceSearchBatch.self) { group in
            let initialCount = min(
                Self.maxConcurrency,
                frozenSources.count - nextSourceIndex
            )
            for _ in 0..<initialCount {
                let source = frozenSources[nextSourceIndex]
                nextSourceIndex += 1
                stageScheduled += 1
                group.addTask {
                    await Self.searchSingleSource(source, keyword: keyword)
                }
            }

            for await batch in group {
                guard generation == searchGeneration, !Task.isCancelled else {
                    group.cancelAll()
                    break
                }

                completedSourceCount += 1
                intervalCompleted += 1
                intervalSearched = completedSourceCount
                mergeBatchIntoAccumulator(batch, normalizedKeyword: normalizedKeyword)
                intervalResults = accumulatedResults.count
                publishProgressAndResults(force: false)

                guard nextSourceIndex < frozenSources.count else { continue }

                let canScheduleMore: Bool
                switch mode {
                case .allRemaining:
                    canScheduleMore = !pauseRequested
                case .staged:
                    let withinCountLimit = stageScheduled < Self.stagedSourceLimit
                    let withinTimeLimit = CFAbsoluteTimeGetCurrent() - stageStartedAt
                        < Self.stagedTimeLimit
                    canScheduleMore = !pauseRequested && withinCountLimit && withinTimeLimit
                }

                if canScheduleMore {
                    let source = frozenSources[nextSourceIndex]
                    nextSourceIndex += 1
                    stageScheduled += 1
                    group.addTask {
                        await Self.searchSingleSource(source, keyword: keyword)
                    }
                }
            }
        }

        guard generation == searchGeneration, !Task.isCancelled else { return }
        publishProgressAndResults(force: true)
        let didFinish = nextSourceIndex >= frozenSources.count
        intervalResult = didFinish ? "finished" : "paused"
        isSearching = false
        isSearchPaused = !didFinish
        isSearchFinished = didFinish
        searchTask = nil
        pauseRequested = false
    }

    // MARK: - Single Source

    nonisolated private static func searchSingleSource(
        _ source: SearchSourceSnapshot,
        keyword: String
    ) async -> SourceSearchBatch {
        do {
            return try await withThrowingTaskGroup(of: SourceSearchBatch.self) { group in
                group.addTask {
                    try await doSearch(source, keyword: keyword)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: sourceTimeoutNanos)
                    throw CancellationError()
                }
                defer { group.cancelAll() }
                return try await group.next()
                    ?? SourceSearchBatch(source: source, parsedSource: nil, hits: [])
            }
        } catch {
            return SourceSearchBatch(source: source, parsedSource: nil, hits: [])
        }
    }

    nonisolated private static func doSearch(
        _ source: SearchSourceSnapshot,
        keyword: String
    ) async throws -> SourceSearchBatch {
        let signposter = PerformanceSignposts.search
        let signpostID = signposter.makeSignpostID()
        var intervalResult = "error"
        var hitCount = 0
        let intervalState = signposter.beginInterval("SourceSearch", id: signpostID)
        defer {
            signposter.endInterval(
                "SourceSearch",
                intervalState,
                "result=\(intervalResult, privacy: .public) hits=\(hitCount)"
            )
        }
        try Task.checkCancellation()

        let engine = SourceEngine()
        let legado = try LegadoSourceParser.parse(
            json: source.ruleJSON,
            matchingURL: source.sourceURL
        )
        let parsedSource = legado
        guard let searchRequest = engine.buildSearchRequest(
            source: legado,
            keyword: keyword,
            page: 1
        ) else {
            intervalResult = "success"
            return SourceSearchBatch(source: source, parsedSource: parsedSource, hits: [])
        }

        let html = try await NetworkClient.shared.fetchString(
            url: searchRequest.url,
            method: searchRequest.method,
            body: searchRequest.body,
            headers: searchRequest.headers.isEmpty ? nil : searchRequest.headers
        )
        try Task.checkCancellation()

        guard let searchRule = legado.searchRule else {
            intervalResult = "success"
            return SourceSearchBatch(source: source, parsedSource: parsedSource, hits: [])
        }

        let parsedResults = try engine.parseSearchResults(
            response: html,
            rule: searchRule,
            baseURL: legado.url
        )
        try Task.checkCancellation()

        let hits = parsedResults.map { result -> SearchHitSnapshot in
            let resolvedCover = result.coverURL.flatMap { cover in
                cover.isEmpty ? nil : engine.resolveURL(cover, base: legado.url)
            }
            let normalizedTitle = normalize(result.title)
            let normalizedAuthor = normalize(result.author)
            return SearchHitSnapshot(
                title: result.title,
                author: result.author,
                bookURL: result.bookURL,
                coverURL: resolvedCover,
                intro: result.intro,
                normalizedKey: "\(normalizedTitle)\u{1F}\(normalizedAuthor)",
                normalizedTitle: normalizedTitle,
                normalizedAuthor: normalizedAuthor
            )
        }

        intervalResult = "success"
        hitCount = hits.count

        return SourceSearchBatch(
            source: source,
            parsedSource: parsedSource,
            hits: hits
        )
    }

    // MARK: - Throttled Merge

    private func mergeBatchIntoAccumulator(
        _ batch: SourceSearchBatch,
        normalizedKeyword: String
    ) {
        guard !batch.hits.isEmpty, let parsedSource = batch.parsedSource else { return }
        let legado = parsedSource

        for hit in batch.hits {
            let sourceKey = "\(batch.source.id.uuidString)\u{1F}\(hit.bookURL)"

            if var accumulated = accumulatedResults[hit.normalizedKey] {
                guard accumulated.sourceKeys.insert(sourceKey).inserted else { continue }

                accumulated.value.sources.append(AggregatedSearchResult.SourceMatch(
                    sourceName: batch.source.name,
                    sourceId: batch.source.id,
                    bookURL: hit.bookURL,
                    source: legado
                ))
                if accumulated.value.coverURL?.isEmpty != false,
                   let coverURL = hit.coverURL,
                   !coverURL.isEmpty {
                    accumulated.value.coverURL = coverURL
                    accumulated.metadataScore += 1
                }
                if accumulated.value.intro?.isEmpty != false,
                   let intro = hit.intro,
                   !intro.isEmpty {
                    accumulated.value.intro = intro
                    accumulated.metadataScore += 1
                }
                accumulatedResults[hit.normalizedKey] = accumulated
            } else {
                let match = AggregatedSearchResult.SourceMatch(
                    sourceName: batch.source.name,
                    sourceId: batch.source.id,
                    bookURL: hit.bookURL,
                    source: legado
                )
                let value = AggregatedSearchResult(
                    title: hit.title,
                    author: hit.author,
                    coverURL: hit.coverURL,
                    intro: hit.intro,
                    sources: [match]
                )
                let metadataScore = (hit.coverURL?.isEmpty == false ? 1 : 0)
                    + (hit.intro?.isEmpty == false ? 1 : 0)
                    + (!hit.author.isEmpty ? 1 : 0)
                accumulatedResults[hit.normalizedKey] = AccumulatedResult(
                    value: value,
                    normalizedTitle: hit.normalizedTitle,
                    normalizedAuthor: hit.normalizedAuthor,
                    isExactMatch: hit.normalizedTitle == normalizedKeyword,
                    containsKeyword: hit.normalizedTitle.contains(normalizedKeyword),
                    metadataScore: metadataScore,
                    sourceKeys: [sourceKey]
                )
            }
            hasUnpublishedResultChanges = true
        }
    }

    private func publishProgressAndResults(force: Bool) {
        let now = CFAbsoluteTimeGetCurrent()
        guard force || now - lastFlushTime >= Self.uiFlushInterval else { return }

        searchedCount = completedSourceCount
        if hasUnpublishedResultChanges {
            results = accumulatedResults.values.sorted(by: Self.ranksBefore).map(\.value)
            hasUnpublishedResultChanges = false
        }
        lastFlushTime = now
    }

    /// exact match > contains keyword > source count > metadata richness > stable title/author
    private static func ranksBefore(
        _ lhs: AccumulatedResult,
        _ rhs: AccumulatedResult
    ) -> Bool {
        if lhs.isExactMatch != rhs.isExactMatch { return lhs.isExactMatch }
        if lhs.containsKeyword != rhs.containsKeyword { return lhs.containsKeyword }
        if lhs.value.sources.count != rhs.value.sources.count {
            return lhs.value.sources.count > rhs.value.sources.count
        }
        if lhs.metadataScore != rhs.metadataScore {
            return lhs.metadataScore > rhs.metadataScore
        }
        if lhs.normalizedTitle != rhs.normalizedTitle {
            return lhs.normalizedTitle < rhs.normalizedTitle
        }
        return lhs.normalizedAuthor < rhs.normalizedAuthor
    }

    nonisolated private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }

}
