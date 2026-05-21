import SwiftUI
import SwiftData

struct BookshelfView: View {
    @Query(sort: \Book.addedDate, order: .reverse) private var books: [Book]
    @Environment(\.modelContext) private var modelContext
    @State private var showingFilePicker = false
    @State private var showingSearch = false
    @State private var showingSources = false
    @State private var importError: String?
    @State private var showingError = false
    @State private var isRefreshing = false
    @State private var selectedBook: Book?
    @State private var showingCacheManage = false
    @State private var coverPickerBook: Book?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    private var groupedItems: [BookshelfItem] {
        BookshelfItem.group(books)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if books.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(groupedItems) { item in
                            switch item {
                            case .single(let book):
                                Button {
                                    selectedBook = book
                                } label: {
                                    BookCoverView(book: book)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        coverPickerBook = book
                                    } label: {
                                        Label("修改封面", systemImage: "photo.on.rectangle")
                                    }
                                }
                            case .series(let name, let seriesBooks):
                                SeriesBookView(seriesName: name, books: seriesBooks)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .background(Color.black)
            .task { await refreshBookCovers() }
            .refreshable { await refreshBookCovers() }
            .navigationTitle("书架")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showingSearch = true }) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.white)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button(action: { showingCacheManage = true }) {
                            Image(systemName: "arrow.down.circle")
                                .foregroundStyle(.white)
                        }
                        Button(action: { showingSources = true }) {
                            Image(systemName: "list.bullet.rectangle")
                                .foregroundStyle(.white)
                        }
                        Button(action: { showingFilePicker = true }) {
                            Image(systemName: "plus")
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingCacheManage) {
                CacheManageView()
            }
            .sheet(isPresented: $showingSources) {
                SourceListView()
            }
            .sheet(isPresented: $showingSearch) {
                SearchView()
            }
            .sheet(isPresented: $showingFilePicker) {
                DocumentPicker { url in
                    let service = ImportService(modelContext: modelContext)
                    do {
                        _ = try service.importTXT(from: url)
                    } catch {
                        importError = error.localizedDescription
                        showingError = true
                    }
                }
            }
            .alert("导入失败", isPresented: $showingError) {
                Button("确定") {}
            } message: {
                Text(importError ?? "")
            }
            .sheet(item: $coverPickerBook) { book in
                CoverPickerView(book: book) { localPath in
                    book.coverURL = localPath
                    try? modelContext.save()
                }
            }
            .fullScreenCover(item: $selectedBook) { book in
                ReaderView(book: book, startChapterIndex: book.lastReadChapterIndex)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func refreshBookCovers() async {
        let booksNeedCover = books.filter {
            guard let url = $0.coverURL?.trimmingCharacters(in: .whitespaces), !url.isEmpty else { return true }
            // 过滤掉豆瓣默认占位图等无效封面
            if url.contains("book-default") || url.contains("default-book") || url.contains("/nophoto/") { return true }
            return false
        }
        print("[Cover] Need cover for \(booksNeedCover.count) books")
        guard !booksNeedCover.isEmpty else { return }

        let engine = SourceEngine()
        let ruleExecutor = RuleExecutor()

        for book in booksNeedCover {
            print("[Cover] Processing: \(book.title), author: \(book.author), current coverURL: \(book.coverURL ?? "nil")")

            // 1. 优先从书源获取封面
            if let sourceId = book.sourceId, let sourceBookURL = book.sourceBookURL {
                do {
                    let descriptor = FetchDescriptor<BookSource>(predicate: #Predicate<BookSource> { $0.id == sourceId })
                    if let bookSource = try modelContext.fetch(descriptor).first {
                        let legado = try LegadoSourceParser.parse(json: bookSource.ruleJSON, matchingURL: bookSource.sourceURL)
                        if let infoRule = legado.bookInfoRule, let coverRule = infoRule.coverUrl {
                            let resolvedURL = engine.resolveURL(sourceBookURL, base: legado.url)
                            let html = try await NetworkClient.shared.fetchString(url: resolvedURL)
                            if let coverURL = try? ruleExecutor.getString(html: html, rule: coverRule, baseURL: legado.url),
                               !coverURL.isEmpty {
                                let resolved = engine.resolveURL(coverURL, base: legado.url)
                                print("[Cover] Source provided cover: \(resolved)")
                                book.coverURL = resolved
                                continue
                            }
                        }
                    }
                } catch {
                    print("[Cover] Source cover fetch error: \(error)")
                }
            }

            // 2. 兜底：通过书名+作者名搜索封面
            print("[Cover] Falling back to Douban search for: \(book.title)")
            if let coverURL = await CoverSearchService.searchCover(title: book.title, author: book.author, bookId: book.id) {
                print("[Cover] Douban found cover: \(coverURL)")
                book.coverURL = coverURL
            } else {
                print("[Cover] Douban search returned nil")
            }
        }
        try? modelContext.save()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "book.closed")
                .font(.system(size: 48))
                .foregroundStyle(.gray.opacity(0.3))
            Text("书架空空如也")
                .foregroundStyle(.gray.opacity(0.5))
                .font(.subheadline)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }
}

#Preview("Bookshelf with series") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Book.self, Chapter.self, BookSource.self,
        configurations: config
    )
    let context = container.mainContext

    let b1 = Book(title: "斗破苍穹", author: "天蚕土豆", sourceType: .localFile, totalChapters: 1647)
    b1.lastReadChapterIndex = 741
    b1.readingStatus = .reading
    context.insert(b1)

    let b2 = Book(title: "三体", author: "刘慈欣", sourceType: .localFile, totalChapters: 100)
    b2.readingStatus = .unread
    context.insert(b2)

    for i in 1...8 {
        let b = Book(title: "盗墓笔记\(i)", author: "南派三叔", sourceType: .localFile, totalChapters: 200)
        b.seriesName = "盗墓笔记"
        b.seriesIndex = i
        if i < 3 {
            b.readingStatus = .finished
            b.lastReadChapterIndex = 200
        } else if i == 3 {
            b.readingStatus = .reading
            b.lastReadChapterIndex = 66
        }
        context.insert(b)
    }

    let b3 = Book(title: "活着", author: "余华", sourceType: .localFile, totalChapters: 12)
    b3.lastReadChapterIndex = 12
    b3.readingStatus = .finished
    context.insert(b3)

    return BookshelfView()
        .modelContainer(container)
}

#Preview("Empty bookshelf") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Book.self, Chapter.self, BookSource.self,
        configurations: config
    )
    return BookshelfView()
        .modelContainer(container)
}
