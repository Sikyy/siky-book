import SwiftUI
import SwiftData

struct CacheManageView: View {
    @Query(sort: \Book.addedDate, order: .reverse) private var books: [Book]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingClearAll = false

    private var cachedBooks: [Book] {
        books.filter { book in
            book.sourceId != nil && book.chapters.contains { $0.isCached }
        }
    }

    private var totalCachedChapters: Int {
        cachedBooks.reduce(0) { sum, book in
            sum + book.chapters.filter { $0.isCached }.count
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("已缓存章节")
                        Spacer()
                        Text("\(totalCachedChapters) 章")
                            .foregroundStyle(.secondary)
                    }
                }

                if cachedBooks.isEmpty {
                    Section {
                        Text("暂无缓存")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                    }
                } else {
                    Section("按书籍管理") {
                        ForEach(cachedBooks) { book in
                            let cached = book.chapters.filter { $0.isCached }.count
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(book.title)
                                        .font(.body)
                                    Text("\(cached) / \(book.totalChapters) 章已缓存")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("清除") {
                                    clearCache(for: book)
                                }
                                .font(.subheadline)
                                .foregroundStyle(.red)
                            }
                        }
                    }

                    Section {
                        Button("清除全部缓存", role: .destructive) {
                            showingClearAll = true
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("缓存管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("确认清除", isPresented: $showingClearAll) {
                Button("取消", role: .cancel) {}
                Button("清除全部", role: .destructive) { clearAllCache() }
            } message: {
                Text("将清除所有书籍的缓存章节内容，下次阅读需要重新加载")
            }
        }
    }

    private func clearCache(for book: Book) {
        for chapter in book.chapters where chapter.isCached && chapter.sourceURL != nil {
            chapter.content = nil
            chapter.isCached = false
        }
    }

    private func clearAllCache() {
        for book in cachedBooks {
            clearCache(for: book)
        }
    }
}
