import SwiftUI
import UniformTypeIdentifiers
import SwiftData

struct BookshelfView: View {
    @Query(sort: \Book.addedDate, order: .reverse) private var books: [Book]
    @Query private var bookSources: [BookSource]
    @Environment(\.modelContext) private var modelContext
    @State private var showingFilePicker = false

#if DEBUG
    /// Debug-only: the Team's simulator is recreated between sessions, so the
    /// book used to check the reader has to be recreatable from the app.
    private func seedSampleBook() {
        let probe = "　　一,二。三“四”五、六;七:八?九!十(甲)乙「丙」丁『戊』己《庚》辛〈壬〉癸【子】丑%寅,卯。一二三四五六七八九十甲乙丙丁戊己庚,辛壬癸子丑寅卯辰巳午未。他说:“你好。”然后走了,没有再回头。Hello, world. This is a long English sentence, with commas; and punctuation? Yes! (Note) \"quoted\" text.\n\n"
        let paragraphs = String(
            repeating: "　　山路上没有灯,只有月光从松枝间漏下来,落在石阶上像一层薄霜。他提着灯笼走了半个时辰,忽然听见前面有人咳嗽。\n\n",
            count: 8
        )
        var text = ""
        for index in 1...7 {
            text += "第\(index)章 夜行\n\n" + String(repeating: probe, count: 4) + paragraphs
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("示例书.txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            _ = try ImportService(modelContext: modelContext).importTXT(from: url)
        } catch {
            importError = error.localizedDescription
            showingError = true
        }
    }
#endif
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Order captured when a book is opened; the shelf keeps it until the reader
    /// is dismissed so the rearrangement happens once, where the user can see it.
    @State private var frozenItemIDs: [String]?
    /// 阅读页刚退出的一小会儿不接收书架上的点击:关闭那一下的抬手不该落到书架上。
    @State private var blocksShelfInput = false
    @State private var readerMenuOpen = false
    @State private var readerIsDark = true
    /// The book being read, remembered across the full-screen cover.
    @State private var openedBookID: UUID?
    /// Bumped to ask the scroll view to go back to the top after a long read.
    @State private var scrollToTopToken = 0
    @State private var popInBookID: UUID?
    @State private var popInProgress: Double = 1
    @State private var lastSortAnimation: (itemID: String, date: Date)?

    private let shelfTopAnchor = "shelf-top"

    /// 三列固定封面宽 108、列间距 19,左右各 20。
    private let columns = Array(repeating: GridItem(.fixed(BookCoverView.coverWidth), spacing: 19), count: 3)

    /// The order the shelf would show right now.
    private var liveItems: [BookshelfItem] {
        let items = BookshelfItem.group(books.filter { !deletingBookIDs.contains($0.id) })
        let sorted = BookshelfItem.sortedByRecentRead(items)
        func pin(_ i: BookshelfItem) -> Date? {
            if case .single(let b) = i { return b.pinnedDate }
            return nil
        }
        let pinned = sorted.filter { pin($0) != nil }.sorted { (pin($0) ?? .distantPast) > (pin($1) ?? .distantPast) }
        return pinned + sorted.filter { pin($0) == nil }
    }

    /// What the grid actually renders: the frozen order while a book is open.
    private var groupedItems: [BookshelfItem] {
        guard let frozenItemIDs else { return liveItems }
        return BookshelfItem.applying(order: frozenItemIDs, to: liveItems)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                shelfHeader
                ScrollViewReader { shelfProxy in
                    ScrollView {
                    if books.isEmpty {
                        emptyState
                    } else {
                        // 行距 33:上一行封面顶到下一行封面顶 = 156 + 14 + 16 + 33 = 219。
                        LazyVGrid(columns: columns, spacing: 33) {
                            ForEach(groupedItems) { item in
                                switch item {
                                case .single(let book):
                                    Button {
                                        openReader(book)
                                    } label: {
                                        BookCoverView(book: book)
                                            .scaleEffect(popInScale(for: book))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                    .fill(Color.white.opacity(popInTint(for: book)))
                                                    .allowsHitTesting(false)
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button {
                                            openReader(book)
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
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .id(shelfTopAnchor)
                    }
                }
                .onChange(of: scrollToTopToken) { _, _ in
                    withAnimation(.easeOut(duration: BookshelfSortTransition.scrollDuration)) {
                        shelfProxy.scrollTo(shelfTopAnchor, anchor: .top)
                    }
                }
                .allowsHitTesting(!blocksShelfInput)
                }
            }
            .background(Color.black)
            // 自绘顶栏:原生工具栏在 iOS 26 会把 20 点标题收进玻璃胶囊,
            // 这里固定为微信读书式的「左标题 + 右三图标」。
            .toolbar(.hidden, for: .navigationBar)
            .statusBarHidden(selectedBook != nil && !readerMenuOpen)
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
            // 阅读页作为一层盖在书架上:退出时不做位移动画,淡出结束的下一帧书架就在那里。
            .overlay {
                if let book = selectedBook {
                    ReaderView(
                        book: book,
                        startChapterIndex: book.lastReadChapterIndex,
                        startPosition: book.lastReadPosition,
                        onClose: { finishReaderClose() },
                        onMenuVisibilityChange: { readerMenuOpen = $0 },
                        onAppearanceChange: { readerIsDark = $0 }
                    )
                    .zIndex(1)
                }
            }
        }
        // 书架本身是深色;阅读页开着时整窗跟随阅读主题,状态栏的时间和电量才看得见。
        .preferredColorScheme(selectedBook == nil ? .dark : (readerIsDark ? .dark : .light))
        .task {
            SampleBookService.seedIfNeeded(modelContext: modelContext)
            #if DEBUG || PERF
            PerfSeed.seedIfNeeded(modelContext: modelContext)
            #endif
        }
        // 用户点书之前就在后台把大书章表读好,开书的那一帧不再扫 SwiftData。
        .task(id: books.count) {
            guard !books.isEmpty else { return }
            let container = modelContext.container
            let requests = books.prefix(8).map {
                ReaderChapterPrefetcher.Request(
                    bookID: $0.id,
                    revision: $0.contentRevision,
                    count: $0.totalChapters
                )
            }
            ReaderChapterPrefetcher.shared.prefetch(requests, container: container)
        }
    }


    private var shelfHeader: some View {
        HStack(spacing: 20) {
            Text("书架")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            Button { showingSearch = true } label: {
                headerIcon("magnifyingglass")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("搜索")

            Menu {
                Button { showingFilePicker = true } label: {
                    Label("导入本地书", systemImage: "doc.badge.plus")
                }
#if DEBUG
                Button { seedSampleBook() } label: {
                    Label("导入示例书", systemImage: "wand.and.stars")
                }
#endif
                Button { showingSources = true } label: {
                    Label("导入书源", systemImage: "link.badge.plus")
                }
                Button { showingSearch = true } label: {
                    Label("去搜索", systemImage: "magnifyingglass")
                }
            } label: {
                headerIcon("plus")
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
                headerIcon("ellipsis")
            }
            .accessibilityLabel("更多")
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
        .background(Color.black)
    }

    private func headerIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 20, weight: .regular))
            .foregroundStyle(.white)
            .frame(width: 28, height: 44)
            .contentShape(Rectangle())
    }

    // MARK: - Returning from the reader

    private func openReader(_ book: Book) {
        PerfProbe.shared.beginOpen()
        frozenItemIDs = groupedItems.map(\.id)
        openedBookID = book.id
        selectedBook = book
    }

    /// Called once the reader has been dismissed: the book that was just read
    /// has already moved to the front in `liveItems`, so the frozen order is
    /// released inside one animation, or the shelf scrolls up and pops it in.
    /// 阅读页淡出结束:一次性换回最终顺序,然后只让排到第一的那本轻微放大一下。
    private func finishReaderClose() {
        selectedBook = nil
        readerMenuOpen = false
        readerIsDark = true
        blocksShelfInput = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            blocksShelfInput = false
        }
        handleReturnFromReader()
    }

    private func handleReturnFromReader() {
        defer { openedBookID = nil }
        guard let frozen = frozenItemIDs else { return }

        let itemID = openedBookID.flatMap { BookshelfItem.itemID(containing: $0, in: liveItems) }
        let previousIndex = itemID.flatMap { frozen.firstIndex(of: $0) }
        let readBookID = openedBookID
        let now = Date()
        let mayAnimate = itemID.map {
            BookshelfSortTransition.shouldAnimate(itemID: $0, lastAnimated: lastSortAnimation, now: now)
        } ?? true
        let mode = BookshelfSortTransition.mode(previousIndex: previousIndex)

        // 顺序一次换到位,网格不播「挪动」动画:分两步换会让同一本书同时出现在两处。
        frozenItemIDs = nil

        guard !reduceMotion, mayAnimate else { return }
        if let itemID { lastSortAnimation = (itemID, now) }

        switch mode {
        case .reorderInPlace:
            // 本来就在第一屏,换完顺序它就在最前面,不需要滚动。
            break
        case .scrollAndPopIn:
            scrollToTopToken += 1
            if let readBookID { startPopIn(bookID: readBookID) }
        }
    }

    private func popInScale(for book: Book) -> CGFloat {
        guard popInBookID == book.id else { return 1 }
        return 1 + (BookshelfSortTransition.popInScale - 1) * (1 - popInProgress)
    }

    private func popInTint(for book: Book) -> Double {
        guard popInBookID == book.id else { return 0 }
        return BookshelfSortTransition.popInTint * (1 - popInProgress)
    }

    private func startPopIn(bookID: UUID) {
        popInBookID = bookID
        popInProgress = 0
        withAnimation(.easeOut(duration: BookshelfSortTransition.popInDuration)) {
            popInProgress = 1
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(BookshelfSortTransition.popInDuration))
            if popInBookID == bookID { popInBookID = nil }
        }
    }

    private func deleteBook(_ book: Book) {
        let bookId = book.id
        guard deletingBookIDs.insert(bookId).inserted else { return }
        let bookTitle = book.title
        let coverURL = book.coverURL
        let wasSample = SampleBookService.isSample(bookID: bookId)
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
            if wasSample {
                SampleBookService.markUserDeleted()
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
                .frame(maxWidth: 300)
                .padding(.bottom, 2)
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
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
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



// MARK: - 临时:造测量用的大书(两百章、五千章)
// 只在 DEBUG / PERF 编译条件下存在,发版包里没有这段代码。
#if DEBUG || PERF
@MainActor
enum PerfSeed {
    private static let doneKey = "perfSeed.v1"

    static func seedIfNeeded(modelContext: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        UserDefaults.standard.set(true, forKey: doneKey)
        make(modelContext: modelContext, title: "测试书·两百章", chapters: 200)
        make(modelContext: modelContext, title: "测试书·五千章", chapters: 5000)
    }

    private static func make(modelContext: ModelContext, title: String, chapters: Int) {
        let book = Book(
            title: title,
            author: "测试",
            sourceType: .localFile,
            totalChapters: chapters
        )
        modelContext.insert(book)
        for index in 0..<chapters {
            let chapter = Chapter(
                index: index,
                title: "第\(index + 1)章 " + body(seed: index, chars: 18),
                content: body(seed: index, chars: 1100)
            )
            chapter.book = book
            modelContext.insert(chapter)
        }
        try? modelContext.save()
        print("PerfSeed: \(title) \(chapters) 章")
    }

    /// 每章内容都不一样,但长度接近,句读整齐,和真书的断行成本相当。
    private static func body(seed: Int, chars: Int) -> String {
        let sentences = [
            "他抬起头,看见窗外的雨还没有停。",
            "桌上的茶早凉了,杯底沉着几片叶子。",
            "远处有人在叫卖,声音穿过巷子传过来。",
            "她翻过一页书,纸边轻轻响了一下。",
            "那年的冬天格外长,屋檐下的冰挂到三月才化。",
            "风从门缝里挤进来,吹得灯芯一晃。",
            "巷口的老槐树下,摆着一张矮凳。",
            "他把信折好,塞进袖子里,没有再看第二眼。",
            "街上的人来人往,没有一个人认得他。",
            "天色暗下来的时候,雨声反而更清楚了。"
        ]
        var out = "（第\(seed + 1)章·测试正文）"
        var i = seed
        while out.count < chars {
            out += sentences[i % sentences.count]
            i += 7
        }
        return out
    }
}
#endif
