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
    private let engine = SourceEngine()
    private let network = NetworkClient.shared

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func search(keyword: String) async {
        guard !keyword.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        await MainActor.run {
            isSearching = true
            results = []
            searchError = nil
            searchedCount = 0
            totalCount = 0
        }

        do {
            let bookSources = try fetchEnabledSources()
            await MainActor.run {
                totalCount = bookSources.count
            }

            await withTaskGroup(of: [(SearchResult, BookSource, LegadoSource)].self) { group in
                for bookSource in bookSources {
                    group.addTask { [self] in
                        do {
                            let legado = try LegadoSourceParser.parse(json: bookSource.ruleJSON, matchingURL: bookSource.sourceURL)
                            guard let searchReq = engine.buildSearchRequest(source: legado, keyword: keyword, page: 1) else {
                                return []
                            }
                            let html = try await network.fetchString(
                                url: searchReq.url,
                                method: searchReq.method,
                                body: searchReq.body,
                                headers: searchReq.headers.isEmpty ? nil : searchReq.headers
                            )
                            guard let searchRule = legado.searchRule else { return [] }
                            let results = try engine.parseSearchResults(response: html, rule: searchRule, baseURL: legado.url)
                            return results.map { ($0, bookSource, legado) }
                        } catch {
                            return []
                        }
                    }
                }
                for await taskResults in group {
                    await MainActor.run {
                        searchedCount += 1
                        mergeResults(taskResults, keyword: keyword)
                    }
                }
            }

            await MainActor.run {
                isSearching = false
            }
        } catch {
            await MainActor.run {
                searchError = error.localizedDescription
                isSearching = false
            }
        }
    }

    private func mergeResults(_ newResults: [(SearchResult, BookSource, LegadoSource)], keyword: String) {
        for (result, bookSource, legado) in newResults {
            let key = "\(result.title)|\(result.author)".lowercased()
            let match = AggregatedSearchResult.SourceMatch(
                sourceName: bookSource.name,
                sourceId: bookSource.id,
                bookURL: result.bookURL,
                source: legado
            )

            if let idx = results.firstIndex(where: { "\($0.title)|\($0.author)".lowercased() == key }) {
                results[idx].sources.append(match)
                if results[idx].coverURL == nil, let cover = result.coverURL, !cover.isEmpty {
                    results[idx].coverURL = engine.resolveURL(cover, base: legado.url)
                }
                if results[idx].intro == nil, let intro = result.intro, !intro.isEmpty {
                    results[idx].intro = intro
                }
            } else {
                let resolvedCover: String?
                if let cover = result.coverURL, !cover.isEmpty {
                    resolvedCover = engine.resolveURL(cover, base: legado.url)
                } else {
                    resolvedCover = nil
                }
                results.append(AggregatedSearchResult(
                    title: result.title,
                    author: result.author,
                    coverURL: resolvedCover,
                    intro: result.intro,
                    sources: [match]
                ))
            }
        }
        sortResults(keyword: keyword)
    }

    private func sortResults(keyword: String) {
        let lk = keyword.lowercased()
        results.sort { a, b in
            let aExact = a.title.lowercased() == lk
            let bExact = b.title.lowercased() == lk
            if aExact != bExact { return aExact }

            let aContains = a.title.lowercased().contains(lk)
            let bContains = b.title.lowercased().contains(lk)
            if aContains != bContains { return aContains }

            if a.sources.count != b.sources.count { return a.sources.count > b.sources.count }

            let aScore = (a.coverURL != nil ? 1 : 0) + (a.intro != nil ? 1 : 0) + (!a.author.isEmpty ? 1 : 0)
            let bScore = (b.coverURL != nil ? 1 : 0) + (b.intro != nil ? 1 : 0) + (!b.author.isEmpty ? 1 : 0)
            return aScore > bScore
        }
    }

    private func fetchEnabledSources() throws -> [BookSource] {
        var descriptor = FetchDescriptor<BookSource>()
        descriptor.predicate = #Predicate<BookSource> { $0.enabled == true }
        return try modelContext.fetch(descriptor)
    }
}
