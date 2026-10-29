import SwiftUI
import UniformTypeIdentifiers
import SwiftData

struct BookshelfView: View {
    @Query(sort: \Book.addedDate, order: .reverse) private var books: [Book]
    @Query private var bookSources: [BookSource]
    @Environment(\.modelContext) private var modelContext
    @State private var showingFilePicker = false
    @State private var showingSearch = false
    @State private var showingSources = false
    @State private var importError: String?
    @State private var showingError = false
    @State private var isRefreshing = false
    @State private var selectedBook: Book?
    @State private var showingCacheManage = false
    @State private var showingAbout = false
    @State private var coverPickerBook: Book?
    @State private var changeSourceBook: Book?
    @State private var deletingBookIDs: Set<UUID> = []
    @State private var deletionError: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    private var groupedItems: [BookshelfItem] {
        let items = BookshelfItem.group(books.filter { !deletingBookIDs.contains($0.id) })
        let sorted = BookshelfItem.sortedByRecentRead(items)
        func pin(_ i: BookshelfItem) -> Date? {
            if case .single(let b) = i { return b.pinnedDate }
            return nil
        }
        let pinned = sorted.filter { pin($0) != nil }.sorted { (pin($0) ?? .distantPast) > (pin($1) ?? .distantPast) }
        return pinned + sorted.filter { pin($0) == nil }
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
                                        selectedBook = book
                                    } label: {
                                        Label("继续阅读", systemImage: "book")
                                    }
                                    Button {
                                        book.pinnedDate = book.pinnedDate == nil ? Date() : nil
                                        try? modelContext.save()
                                    } label: {
                                        Label(book.pinnedDate == nil ? "置顶" : "取消置顶",
                                              systemImage: book.pinnedDate == nil ? "pin" : "pin.slash")
                                    }
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
                        Menu {
                            Button { showingFilePicker = true } label: {
                                Label("导入本地书", systemImage: "doc.badge.plus")
                            }
                            Button { showingSources = true } label: {
                                Label("导入书源", systemImage: "link.badge.plus")
                            }
                            Button { showingSearch = true } label: {
                                Label("去搜索", systemImage: "magnifyingglass")
                            }
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(.white)
                        }
                        .accessibilityLabel("添加")
                        Menu {
                            Button { showingCacheManage = true } label: {
                                Label("缓存管理", systemImage: "arrow.down.circle")
                            }
                            Button { showingSources = true } label: {
                                Label("书源管理", systemImage: "list.bullet.rectangle")
                            }
                            Button { showingAbout = true } label: {
                                Label("关于", systemImage: "info.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundStyle(.white)
                        }
                        .accessibilityLabel("更多")
                    }
                }
            }
            .sheet(isPresented: $showingCacheManage) {
                CacheManageView()
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
            .sheet(isPresented: $showingSources) {
                SourceListView()
            }
            .sheet(isPresented: $showingSearch) {
                SearchView()
            }
            .sheet(isPresented: $showingFilePicker) {
                DocumentPicker(contentTypes: [.plainText, UTType(filenameExtension: "epub") ?? .data]) { url in
                    let service = ImportService(modelContext: modelContext)
                    do {
                        if url.pathExtension.lowercased() == "epub" {
                            _ = try service.importEPUB(from: url)
                        } else {
                            _ = try service.importTXT(from: url)
                        }
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
                ReaderView(book: book, startChapterIndex: book.lastReadChapterIndex, startPosition: book.lastReadPosition)
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
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: "books.vertical")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            Text("书架还是空的")
                .font(.title3.weight(.semibold))
            Text(bookSources.isEmpty
                 ? "导入书源后可以搜书，也可以直接导入本地 txt 或 epub"
                 : "已经有书源了，搜一本书放进书架")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)
            VStack(spacing: 10) {
                if bookSources.isEmpty {
                    Button { showingSources = true } label: {
                        Label("导入书源", systemImage: "link.badge.plus")
                            .font(.body)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button { showingSearch = true } label: {
                        Label("去搜索", systemImage: "magnifyingglass")
                            .font(.body)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button { showingFilePicker = true } label: {
                    Label("导入本地书", systemImage: "doc.badge.plus")
                        .font(.body)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .controlSize(.regular)
            .frame(maxWidth: 260)
            .padding(.horizontal, 32)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 500)
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


