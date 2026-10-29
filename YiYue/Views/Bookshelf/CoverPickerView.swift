import SwiftUI
import Nuke
import NukeUI

struct CoverPickerView: View {
    let book: Book
    let onSelected: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [CoverCandidate] = []
    @State private var isLoading = true
    @State private var downloadingId: UUID?
    @State private var searchText: String = ""
    @State private var searchGeneration = UUID()
    @State private var selectionGeneration = UUID()
    @State private var selectionTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                Divider()
                content
            }
            .background(Color(.systemBackground))
            .navigationTitle("选择封面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { cancelSelectionAndDismiss() }
                }
            }
            .task {
                searchText = book.title
                await search(query: book.title)
            }
            .onDisappear {
                selectionTask?.cancel()
                selectionTask = nil
                selectionGeneration = UUID()
                searchGeneration = UUID()
            }
            .interactiveDismissDisabled(downloadingId != nil)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                TextField("搜索书名", text: $searchText)
                    .font(.subheadline)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .onSubmit { Task { await search(query: searchText) } }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }
            }
            .padding(8)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if isSearchFocused {
                Button("搜索") {
                    isSearchFocused = false
                    Task { await search(query: searchText) }
                }
                .font(.subheadline)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("正在搜索封面…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if candidates.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary.opacity(0.5))
                Text("未找到相关封面")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(candidates) { candidate in
                        coverCell(candidate)
                    }
                }
                .padding(16)
            }
        }
    }

    private func coverCell(_ candidate: CoverCandidate) -> some View {
        Button {
            startSelection(candidate)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    CandidateCoverThumbnail(candidate: candidate)
                }
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if downloadingId == candidate.id {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.black.opacity(0.4))
                        ProgressView()
                            .tint(.white)
                    }
                }

                Text(candidate.title)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                HStack(spacing: 2) {
                    Text(candidate.source.rawValue)
                        .font(.system(size: 8))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(candidate.source == .douban ? Color.green.opacity(0.7) : Color.red.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    Text(candidate.author)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(downloadingId != nil)
    }

    private func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let generation = UUID()
        searchGeneration = generation
        isLoading = true
        candidates = []

        // 直接用用户输入的关键词搜豆瓣
        let results = await CoverSearchService.searchCandidates(
            title: trimmed, author: book.author
        )
        guard !Task.isCancelled, searchGeneration == generation else { return }
        candidates = results
        isLoading = false
    }

    private func startSelection(_ candidate: CoverCandidate) {
        selectionTask?.cancel()
        let generation = UUID()
        selectionGeneration = generation
        selectionTask = Task {
            await selectCover(candidate, generation: generation)
        }
    }

    private func cancelSelectionAndDismiss() {
        selectionTask?.cancel()
        selectionTask = nil
        selectionGeneration = UUID()
        dismiss()
    }

    private func selectCover(_ candidate: CoverCandidate, generation: UUID) async {
        downloadingId = candidate.id
        let localPath = await CoverSearchService.downloadCoverToLocal(
            candidate.picURL, bookId: book.id, needsReferer: candidate.needsReferer
        )

        guard !Task.isCancelled, selectionGeneration == generation else {
            if let localPath {
                CoverSearchService.discardDownloadedCover(localPath)
            }
            return
        }
        downloadingId = nil
        selectionTask = nil

        if let localPath {
            onSelected(localPath)
            dismiss()
        }
    }
}

/// 候选封面按网格可见性惰加载，共享全局 Nuke 内存/磁盘缓存。
/// 豆瓣图片需要 Referer，因此使用带请求头的 ImageRequest。
private struct CandidateCoverThumbnail: View {
    let candidate: CoverCandidate

    private let targetSize = CGSize(width: 120, height: 160)

    var body: some View {
        Group {
            if candidate.needsReferer {
                LazyImage(request: refererRequest) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        placeholder
                    }
                }
                .onDisappear(.cancel)
            } else {
                CachedCoverImage(
                    urlString: normalizedURLString,
                    targetSize: targetSize
                ) {
                    placeholder
                }
            }
        }
    }

    private var placeholder: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGray6))
    }

    private var refererRequest: ImageRequest? {
        guard let url = CoverURLResolver.resolve(normalizedURLString) else {
            return nil
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        urlRequest.setValue("https://book.douban.com", forHTTPHeaderField: "Referer")
        urlRequest.timeoutInterval = 10

        var request = ImageRequest(urlRequest: urlRequest)
        request.thumbnail = ImageRequest.ThumbnailOptions(
            size: targetSize,
            unit: .points,
            contentMode: .aspectFill
        )
        return request
    }

    private var normalizedURLString: String {
        candidate.thumbURL.hasPrefix("//")
            ? "https:\(candidate.thumbURL)"
            : candidate.thumbURL
    }
}
