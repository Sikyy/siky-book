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
                if let service = searchService {
                    searchContent(service)
                } else {
                    placeholder(icon: "text.magnifyingglass", text: "输入书名开始搜索")
                }
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
            .onDisappear {
                searchService?.cancelSearch()
            }
            .sheet(item: $selectedResult) { result in
                SourceSelectView(result: result, onAdded: {
                    selectedResult = nil
                    dismiss()
                })
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

    @ViewBuilder
    private func searchContent(_ service: SearchService) -> some View {
        if service.isSearching && service.results.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                if service.isPreparingSources {
                    Text("正在准备书源…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    progressText(service)
                    Button("暂停") {
                        service.pauseSearch()
                    }
                    .font(.caption)
                }
                Spacer()
            }
        } else if !service.results.isEmpty {
            VStack(spacing: 0) {
                if service.isSearching {
                    progressBar(service)
                } else if service.isSearchPaused {
                    continuationBar(service)
                }
                List(service.results) { result in
                    Button { selectedResult = result } label: {
                        searchResultRow(result)
                    }
                }
                .listStyle(.plain)
            }
        } else if let error = service.searchError {
            placeholder(icon: "exclamationmark.triangle", text: error)
        } else if service.isSearchPaused {
            pausedPlaceholder(service)
        } else if service.isSearchFinished && service.totalCount == 0 {
            placeholder(icon: "books.vertical", text: "没有启用的书源")
        } else if service.isSearchFinished {
            placeholder(icon: "magnifyingglass", text: "未找到相关书籍")
        } else {
            placeholder(icon: "text.magnifyingglass", text: "输入书名开始搜索")
        }
    }

    private func progressBar(_ service: SearchService) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
            progressText(service)
            Spacer()
            Button {
                service.pauseSearch()
            } label: {
                Text("暂停")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGray6).opacity(0.8))
    }

    private func continuationBar(_ service: SearchService) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("已暂停，剩余 \(service.remainingCount) 个书源")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                progressText(service)
            }
            HStack(spacing: 12) {
                Button("继续搜索") {
                    service.continueSearch()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("搜索全部剩余") {
                    service.searchAllRemaining()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemGray6).opacity(0.8))
    }

    private func pausedPlaceholder(_ service: SearchService) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("当前批次暂未发现结果")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("已搜索 \(service.searchedCount)/\(service.totalCount) 个书源，仍有 \(service.remainingCount) 个")
                .font(.caption)
                .foregroundStyle(.tertiary)
            HStack(spacing: 12) {
                Button("继续搜索") {
                    service.continueSearch()
                }
                .buttonStyle(.borderedProminent)

                Button("搜索全部剩余") {
                    service.searchAllRemaining()
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func progressText(_ service: SearchService) -> some View {
        Text("已搜索 \(service.searchedCount)/\(service.totalCount) 个书源")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func placeholder(icon: String, text: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.4))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func searchResultRow(_ result: AggregatedSearchResult) -> some View {
        HStack(spacing: 12) {
            coverView(result)
            VStack(alignment: .leading, spacing: 3) {
                Text(result.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !result.author.isEmpty {
                    Text(result.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let intro = result.intro, !intro.isEmpty {
                    Text(intro)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            Text("\(result.sources.count)源")
                .font(.caption2)
                .foregroundStyle(.blue)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func coverView(_ result: AggregatedSearchResult) -> some View {
        CachedCoverImage(
            urlString: result.coverURL,
            targetSize: CGSize(width: 48, height: 64)
        ) {
            coverPlaceholder(result.title)
        }
        .frame(width: 48, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func coverPlaceholder(_ title: String) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(.systemGray5))
            .frame(width: 48, height: 64)
            .overlay(
                Text(String(title.prefix(1)))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            )
    }

    private func performSearch() {
        guard !keyword.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        searchService?.search(keyword: keyword)
    }
}
