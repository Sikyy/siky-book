import SwiftUI
import SwiftData

struct SourceSelectView: View {
    let result: AggregatedSearchResult
    var onAdded: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        bookCover
                        VStack(alignment: .leading, spacing: 6) {
                            Text(result.title)
                                .font(.headline)
                            if !result.author.isEmpty {
                                Text(result.author)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if let intro = result.intro, !intro.isEmpty {
                                Text(intro)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(3)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("选择来源（\(result.sources.count)个）") {
                    ForEach(result.sources) { source in
                        NavigationLink {
                            AddBookView(
                                title: result.title,
                                author: result.author,
                                coverURL: result.coverURL,
                                intro: result.intro,
                                sourceName: source.sourceName,
                                sourceId: source.sourceId,
                                bookURL: source.bookURL,
                                legadoSource: source.source,
                                onAdded: onAdded
                            )
                        } label: {
                            HStack {
                                Text(source.sourceName)
                                    .font(.body)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择来源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var bookCover: some View {
        if let urlString = result.coverURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    coverPlaceholder
                }
            }
            .frame(width: 60, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            coverPlaceholder
        }
    }

    private var coverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(.systemGray5))
            .frame(width: 60, height: 80)
            .overlay(
                Text(String(result.title.prefix(1)))
                    .font(.title)
                    .foregroundStyle(.secondary)
            )
    }
}
