import SwiftUI

struct CoverPickerView: View {
    let book: Book
    let onSelected: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [CoverCandidate] = []
    @State private var thumbImages: [UUID: UIImage] = [:]
    @State private var isLoading = true
    @State private var downloadingId: UUID?
    @State private var searchText: String = ""
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
                    Button("取消") { dismiss() }
                }
            }
            .task {
                searchText = book.title
                await search(query: book.title)
            }
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
                Text("正在搜索封面...")
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
            Task { await selectCover(candidate) }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    if let uiImage = thumbImages[candidate.id] {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemGray6))
                    }
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

                Text(candidate.author)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .disabled(downloadingId != nil)
    }

    private func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isLoading = true
        candidates = []
        thumbImages = [:]

        // 直接用用户输入的关键词搜豆瓣
        let results = await CoverSearchService.searchCandidates(
            title: trimmed, author: book.author
        )
        candidates = results
        isLoading = false

        // 并发加载缩略图
        await loadThumbnails(for: results)
    }

    private func loadThumbnails(for items: [CoverCandidate]) async {
        await withTaskGroup(of: (UUID, UIImage?).self) { group in
            for candidate in items {
                group.addTask {
                    let image = await Self.fetchImage(candidate.thumbURL)
                    return (candidate.id, image)
                }
            }
            for await (id, image) in group {
                if let image {
                    thumbImages[id] = image
                }
            }
        }
    }

    private static func fetchImage(_ urlString: String) async -> UIImage? {
        var raw = urlString
        if raw.hasPrefix("//") { raw = "https:" + raw }
        guard let url = URL(string: raw) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("https://book.douban.com", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let image = UIImage(data: data) else { return nil }
        return image
    }

    private func selectCover(_ candidate: CoverCandidate) async {
        downloadingId = candidate.id
        if let localPath = await CoverSearchService.downloadCoverToLocal(
            candidate.picURL, bookId: book.id
        ) {
            await MainActor.run {
                onSelected(localPath)
                dismiss()
            }
        }
        downloadingId = nil
    }
}
