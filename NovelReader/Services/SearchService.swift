import Foundation
import SwiftData

struct AggregatedSearchResult: Identifiable {
    let id = UUID()
    let title: String
    let author: String
    let coverURL: String?
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
        }

        do {
            let bookSources = try fetchEnabledSources()
            var allResults: [(SearchResult, BookSource, LegadoSource)] = []

            await withTaskGroup(of: [(SearchResult, BookSource, LegadoSource)].self) { group in
                for bookSource in bookSources {
                    group.addTask { [self] in
                        do {
                            let legado = try LegadoSourceParser.parse(json: bookSource.ruleJSON)
                            guard let searchURL = engine.buildSearchURL(source: legado, keyword: keyword, page: 1) else {
                                return []
                            }
                            let html = try await network.fetchString(url: searchURL)
                            guard let searchRule = legado.searchRule else { return [] }
                            let results = try engine.parseSearchResults(html: html, rule: searchRule, baseURL: legado.url)
                            return results.map { ($0, bookSource, legado) }
                        } catch {
                            return []
                        }
                    }
                }
                for await taskResults in group {
                    allResults.append(contentsOf: taskResults)
                }
            }

            let aggregated = aggregateResults(allResults)
            await MainActor.run {
                results = aggregated
                isSearching = false
            }
        } catch {
            await MainActor.run {
                searchError = error.localizedDescription
                isSearching = false
            }
        }
    }

    private func aggregateResults(_ raw: [(SearchResult, BookSource, LegadoSource)]) -> [AggregatedSearchResult] {
        var grouped: [String: AggregatedSearchResult] = [:]

        for (result, bookSource, legado) in raw {
            let key = "\(result.title)|\(result.author)".lowercased()
            let match = AggregatedSearchResult.SourceMatch(
                sourceName: bookSource.name,
                sourceId: bookSource.id,
                bookURL: result.bookURL,
                source: legado
            )
            if var existing = grouped[key] {
                existing.sources.append(match)
                grouped[key] = existing
            } else {
                grouped[key] = AggregatedSearchResult(
                    title: result.title,
                    author: result.author,
                    coverURL: result.coverURL,
                    sources: [match]
                )
            }
        }
        return Array(grouped.values).sorted { $0.sources.count > $1.sources.count }
    }

    private func fetchEnabledSources() throws -> [BookSource] {
        var descriptor = FetchDescriptor<BookSource>()
        descriptor.predicate = #Predicate<BookSource> { $0.enabled == true }
        return try modelContext.fetch(descriptor)
    }
}
