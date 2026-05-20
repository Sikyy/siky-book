import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""
    @State private var searchService: SearchService?
    @State private var selectedResult: AggregatedSearchResult?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                resultsList
            }
            .background(Color(.systemBackground))
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                if searchService == nil {
                    searchService = SearchService(modelContext: modelContext)
                }
            }
            .sheet(item: $selectedResult) { result in
                SourceSelectView(result: result)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("输入书名搜索", text: $keyword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { performSearch() }
                if !keyword.isEmpty {
                    Button { keyword = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button("搜索") { performSearch() }
                .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var resultsList: some View {
        Group {
            if searchService?.isSearching == true {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                    Text("搜索中...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else if let error = searchService?.searchError {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else if let results = searchService?.results, !results.isEmpty {
                List(results) { result in
                    Button {
                        selectedResult = result
                    } label: {
                        searchResultRow(result)
                    }
                }
                .listStyle(.plain)
            } else if searchService?.results.isEmpty == true {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("未找到相关书籍")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary.opacity(0.3))
                    Text("输入书名开始搜索")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    private func searchResultRow(_ result: AggregatedSearchResult) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: 45, height: 60)
                .overlay(
                    Text(String(result.title.prefix(1)))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(result.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("\(result.sources.count)个来源")
                .font(.caption)
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }

    private func performSearch() {
        guard !keyword.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task { await searchService?.search(keyword: keyword) }
    }
}
