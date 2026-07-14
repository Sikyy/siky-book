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
    @State private var changeSourceBook: Book?
    @State private var deletingBookIDs: Set<UUID> = []
    @State private var deletionError: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    private var groupedItems: [BookshelfItem] {
        BookshelfItem.group(books.filter { !deletingBookIDs.contains($0.id) })
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
                                    if book.sourceType == .bookSource {
                                        Button {
                                            changeSourceBook = book
                                        } label: {
                                            Label("换源", systemImage: "arrow.triangle.2.circlepath")
                                        }
                                    }
                                    Button {
                                        coverPickerBook = book
                                    } label: {
                                        Label("修改封面", systemImage: "photo.on.rectangle")
                                    }
                                    Button(role: .destructive) {
                                        deleteBook(book)
                                    } label: {
                                        Label("删除", systemImage: "trash")
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
            .alert(
                "删除失败",
                isPresented: Binding(
                    get: { deletionError != nil },
                    set: { if !$0 { deletionError = nil } }
                )
            ) {
                Button("确定") { deletionError = nil }
            } message: {
                Text(deletionError ?? "")
            }
            .sheet(item: $coverPickerBook) { book in
                CoverPickerView(book: book) { localPath in
                    let previousCover = book.coverURL
                    book.coverURL = localPath
                    try? modelContext.save()
                    if let previousCover, previousCover != localPath {
                        CoverSearchService.discardDownloadedCover(previousCover)
                    }
                }
            }
            .sheet(item: $changeSourceBook) { book in
                ChangeSourceView(book: book)
            }
            .fullScreenCover(item: $selectedBook) { book in
                ReaderView(book: book, startChapterIndex: book.lastReadChapterIndex)
            }
        }
        .preferredColorScheme(.dark)
    }


    private func deleteBook(_ book: Book) {
        let bookId = book.id
        guard deletingBookIDs.insert(bookId).inserted else { return }
        let bookTitle = book.title
        let coverURL = book.coverURL
        // Cache lifetime follows an explicit book deletion. Do not infer
        // orphans from the launch-time @Query snapshot: SwiftData can publish
        // a transient partial result while the persistent store is loading.
        Task { @MainActor in
            defer { deletingBookIDs.remove(bookId) }
            let manager = BookManager(modelContext: modelContext)
            do {
                try await manager.deleteBook(book)
            } catch {
                deletionError = "无法删除《\(bookTitle)》：\(error.localizedDescription)"
                return
            }
            if let coverURL {
                CoverSearchService.discardDownloadedCover(coverURL)
            }
        }
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
