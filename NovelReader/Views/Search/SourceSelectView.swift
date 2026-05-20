import SwiftUI
import SwiftData

struct SourceSelectView: View {
    let result: AggregatedSearchResult
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddBook = false
    @State private var selectedSource: AggregatedSearchResult.SourceMatch?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.systemGray5))
                            .frame(width: 60, height: 80)
                            .overlay(
                                Text(String(result.title.prefix(1)))
                                    .font(.title)
                                    .foregroundStyle(.secondary)
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.title)
                                .font(.headline)
                            Text(result.author)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("选择来源（\(result.sources.count)个）") {
                    ForEach(result.sources) { source in
                        Button {
                            selectedSource = source
                            showingAddBook = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(source.sourceName)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                }
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
            .sheet(isPresented: $showingAddBook) {
                if let source = selectedSource {
                    AddBookView(
                        title: result.title,
                        author: result.author,
                        coverURL: result.coverURL,
                        sourceName: source.sourceName,
                        sourceId: source.sourceId,
                        bookURL: source.bookURL,
                        legadoSource: source.source
                    )
                }
            }
        }
    }
}
