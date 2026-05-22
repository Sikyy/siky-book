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

@Observable
class SearchService {
    var results: [AggregatedSearchResult] = []
    var isSearching = false
    var searchError: String?
    var searchedCount = 0
    var totalCount = 0

    private let modelContext: ModelContext
    private var searchTask: Task<Void, Never>?

    // Legado-style constants
    private static let maxConcurrency = 50
    private static let sourceTimeoutNanos: UInt64 = 15_000_000_000  // 15s
    private static let uiFlushInterval: CFAbsoluteTime = 1.0        // 1s

    // Throttle buffer (not observed by UI)
    private var pendingResults: [(SearchResult, BookSource, LegadoSource)] = []
    private var lastFlushTime: CFAbsoluteTime = 0

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public API

    func search(keyword: String) {
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Cancel previous search
        searchTask?.cancel()

        searchTask = Task { [weak self] in
            await self?.performSearch(keyword: trimmed)
        }
    }

    func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }

    // MARK: - Search Pipeline

    private func performSearch(keyword: String) async {
        await MainActor.run {
            isSearching = true
            results = []
            searchError = nil
            searchedCount = 0
            totalCount = 0
            pendingResults = []
            lastFlushTime = CFAbsoluteTimeGetCurrent()
        }

        do {
            let bookSources = try fetchEnabledSources()
            await MainActor.run { totalCount = bookSources.count }

            await withTaskGroup(of: [(SearchResult, BookSource, LegadoSource)].self) { group in
                var iterator = bookSources.makeIterator()

                // Seed initial batch (Legado: maxConcurrency = 9)
                for _ in 0..<min(Self.maxConcurrency, bookSources.count) {
                    guard let source = iterator.next() else { break }
                    group.addTask {
                        await Self.searchSingleSource(source, keyword: keyword)
                    }
                }

                // As each finishes, feed the next
                for await taskResults in group {
                    guard !Task.isCancelled else { break }

                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        searchedCount += 1
                        pendingResults.append(contentsOf: taskResults)

                        // Throttle: flush at most once per second
                        let now = CFAbsoluteTimeGetCurrent()
                        if now - lastFlushTime >= Self.uiFlushInterval {
                            flushPendingResults(keyword: keyword)
                        }
                    }

                    if let source = iterator.next() {
                        group.addTask {
                            await Self.searchSingleSource(source, keyword: keyword)
                        }
                    }
                }
            }

            // Final flush
            await MainActor.run { [weak self] in
                guard let self else { return }
                flushPendingResults(keyword: keyword)
                isSearching = false
            }
        } catch {
            await MainActor.run { [weak self] in
                guard let self else { return }
                flushPendingResults(keyword: keyword)
                searchError = error.localizedDescription
                isSearching = false
            }
        }
    }

    // MARK: - Single Source (with 30s timeout + precision filter)

    private static func searchSingleSource(
        _ bookSource: BookSource, keyword: String
    ) async -> [(SearchResult, BookSource, LegadoSource)] {
        // Race: actual work vs 30s timeout
        do {
            return try await withThrowingTaskGroup(
                of: [(SearchResult, BookSource, LegadoSource)].self
            ) { group in
                group.addTask {
                    try await doSearch(bookSource, keyword: keyword)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: sourceTimeoutNanos)
                    throw CancellationError()
                }
                defer { group.cancelAll() }
                return (try await group.next()) ?? []
            }
        } catch {
            return []
        }
    }

    private static func doSearch(
        _ bookSource: BookSource, keyword: String
    ) async throws -> [(SearchResult, BookSource, LegadoSource)] {
        let engine = SourceEngine()
        let legado = try LegadoSourceParser.parse(
            json: bookSource.ruleJSON, matchingURL: bookSource.sourceURL
        )
        guard let searchReq = engine.buildSearchRequest(
            source: legado, keyword: keyword, page: 1
        ) else { return [] }

        let html = try await NetworkClient.shared.fetchString(
            url: searchReq.url,
            method: searchReq.method,
            body: searchReq.body,
            headers: searchReq.headers.isEmpty ? nil : searchReq.headers
        )
        guard let searchRule = legado.searchRule else { return [] }

        var results = try engine.parseSearchResults(
            response: html, rule: searchRule, baseURL: legado.url
        )

        // Pre-resolve cover URLs
        results = results.map { r in
            let resolved = r.coverURL.flatMap { c in
                c.isEmpty ? nil : engine.resolveURL(c, base: legado.url)
            }
            return SearchResult(
                title: r.title, author: r.author, bookURL: r.bookURL,
                coverURL: resolved, kind: r.kind, intro: r.intro
            )
        }

        return results.map { ($0, bookSource, legado) }
    }

    // MARK: - Throttled Merge

    /// Flush pending buffer into `results` — called at most once per second
    private func flushPendingResults(keyword: String) {
        guard !pendingResults.isEmpty else { return }
        mergeResults(pendingResults, keyword: keyword)
        pendingResults = []
        lastFlushTime = CFAbsoluteTimeGetCurrent()
    }

    private func mergeResults(
        _ newResults: [(SearchResult, BookSource, LegadoSource)], keyword: String
    ) {
        var updated = results
        for (result, bookSource, legado) in newResults {
            let key = "\(result.title)|\(result.author)".lowercased()
            let match = AggregatedSearchResult.SourceMatch(
                sourceName: bookSource.name,
                sourceId: bookSource.id,
                bookURL: result.bookURL,
                source: legado
            )

            if let idx = updated.firstIndex(where: {
                "\($0.title)|\($0.author)".lowercased() == key
            }) {
                updated[idx].sources.append(match)
                if updated[idx].coverURL == nil,
                   let cover = result.coverURL, !cover.isEmpty {
                    updated[idx].coverURL = cover
                }
                if updated[idx].intro == nil,
                   let intro = result.intro, !intro.isEmpty {
                    updated[idx].intro = intro
                }
            } else {
                updated.append(AggregatedSearchResult(
                    title: result.title,
                    author: result.author,
                    coverURL: result.coverURL,
                    intro: result.intro,
                    sources: [match]
                ))
            }
        }
        sortResults(&updated, keyword: keyword)
        results = updated
    }

    /// Three-tier sort: exact match > contains keyword > source count > metadata richness
    private func sortResults(_ list: inout [AggregatedSearchResult], keyword: String) {
        let lk = keyword.lowercased()
        list.sort { a, b in
            let aExact = a.title.lowercased() == lk
            let bExact = b.title.lowercased() == lk
            if aExact != bExact { return aExact }

            let aContains = a.title.lowercased().contains(lk)
            let bContains = b.title.lowercased().contains(lk)
            if aContains != bContains { return aContains }

            if a.sources.count != b.sources.count {
                return a.sources.count > b.sources.count
            }

            let aScore = (a.coverURL != nil ? 1 : 0)
                + (a.intro != nil ? 1 : 0)
                + (!a.author.isEmpty ? 1 : 0)
            let bScore = (b.coverURL != nil ? 1 : 0)
                + (b.intro != nil ? 1 : 0)
                + (!b.author.isEmpty ? 1 : 0)
            return aScore > bScore
        }
    }

    // MARK: - Data

    private func fetchEnabledSources() throws -> [BookSource] {
        var descriptor = FetchDescriptor<BookSource>()
        descriptor.predicate = #Predicate<BookSource> { $0.enabled == true }
        return try modelContext.fetch(descriptor)
    }
}
