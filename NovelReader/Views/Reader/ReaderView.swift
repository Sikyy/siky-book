import SwiftUI
import SwiftData
import CoreText

struct ReaderView: View {
    let book: Book
    @Query private var chapters: [Chapter]
    @State private var currentChapterIndex: Int
    @State private var showMenu = false
    @State private var currentPageIndex: Int = 0
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var settings = ReaderSettings()
    @State private var isLoadingContent = false
    @State private var loadError: String?
    @State private var isCaching = false
    @State private var cachedCount = 0
    @State private var totalToCache = 0
    @State private var skipPageReset = false
    @State private var viewSize: CGSize = .zero
    private let pageBottomReserve: CGFloat = 72

    init(book: Book, startChapterIndex: Int = 0) {
        self.book = book
        self._currentChapterIndex = State(initialValue: startChapterIndex)
        let bookId = book.id
        _chapters = Query(
            filter: #Predicate<Chapter> { $0.book?.id == bookId },
            sort: [SortDescriptor(\Chapter.index)]
        )
    }

    private var currentChapter: Chapter? {
        chapters.first { $0.index == currentChapterIndex }
    }

    private var chapterText: String {
        currentChapter?.content ?? ""
    }

    private var paragraphs: [String] {
        chapterText
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        ZStack {
            settings.theme.backgroundColor
                .ignoresSafeArea()

            readingContent

            if showMenu {
                ReaderMenuOverlay(
                    book: book,
                    currentChapterIndex: $currentChapterIndex,
                    totalChapters: book.totalChapters,
                    chapterTitle: currentChapter?.title ?? "",
                    settings: settings,
                    onDismiss: { showMenu = false },
                    onBack: { dismiss() },
                    chapters: chapters,
                    onCache: book.sourceId != nil ? { count in cacheChapters(count: count) } : nil,
                    isCaching: isCaching,
                    cacheProgress: isCaching ? "\(cachedCount)/\(totalToCache)" : nil
                )
            }
        }
        .statusBarHidden(!showMenu)
        .persistentSystemOverlays(showMenu ? .automatic : .hidden)
        .preferredColorScheme(settings.theme.isDark ? .dark : .light)
        .onChange(of: currentChapterIndex) { _, newValue in
            let manager = BookManager(modelContext: modelContext)
            manager.updateProgress(book: book, chapterIndex: newValue, position: 0)
            if skipPageReset {
                skipPageReset = false
            } else {
                currentPageIndex = 0
            }
        }
        .onDisappear {
            let manager = BookManager(modelContext: modelContext)
            manager.updateProgress(book: book, chapterIndex: currentChapterIndex, position: 0)
        }
    }

    // MARK: - Reading Content

    private var readingContent: some View {
        ZStack {
            if isLoadingContent {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("加载中...")
                        .font(.subheadline)
                        .foregroundStyle(settings.theme.textColor.opacity(0.6))
                }
            } else if let error = loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(settings.theme.textColor.opacity(0.5))
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(settings.theme.textColor.opacity(0.6))
                    Button("重试") { fetchChapterContentIfNeeded() }
                        .foregroundStyle(.blue)
                }
            } else {
                switch settings.pageMode {
                case .scroll:
                    scrollContent
                case .horizontal, .tap:
                    pagedContent
                }
            }
        }
        .onAppear { fetchChapterContentIfNeeded() }
        .onChange(of: currentChapterIndex) { _, _ in fetchChapterContentIfNeeded() }
    }

    // MARK: - Scroll Mode

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: settings.fontSize * (settings.lineSpacing - 1)) {
                Text(currentChapter?.title ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(settings.theme.chapterTitleColor)
                    .padding(.bottom, 8)

                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, para in
                    Text("\u{3000}\u{3000}" + para)
                        .font(.custom(settings.fontFamily.rawValue, size: settings.fontSize))
                        .foregroundStyle(settings.theme.textColor)
                        .lineSpacing(settings.fontSize * (settings.lineSpacing - 1))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, settings.horizontalPadding)
            .padding(.top, 20)
            .padding(.bottom, 60)
        }
        .contentShape(Rectangle())
        .onTapGesture { location in
            handleTap(location: location)
        }
        .overlay(alignment: .bottom) {
            if !showMenu { statusBar }
        }
    }

    // MARK: - Paged Mode

    private var pagedContent: some View {
        GeometryReader { geometry in
            let pages = splitIntoPages(size: geometry.size)
            let totalPages = pages.count
            let safeIndex = max(0, min(currentPageIndex, totalPages - 1))
            let hasNext = currentChapterIndex < book.totalChapters - 1
            let hasPrev = currentChapterIndex > 0

            let allPageTags: [Int] = {
                var tags: [Int] = []
                if hasPrev { tags.append(-1) }
                for i in 0..<totalPages { tags.append(i) }
                if hasNext { tags.append(totalPages) }
                return tags
            }()

            ZStack {
                if settings.pageMode == .horizontal {
                    TabView(selection: $currentPageIndex) {
                        ForEach(allPageTags, id: \.self) { tag in
                            Group {
                                if tag == -1 || tag >= totalPages {
                                    settings.theme.backgroundColor
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                } else {
                                    pageView(fragments: pages[tag], isFirstPage: tag == 0)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                handlePageTap(location: location, screenSize: geometry.size, totalPages: totalPages)
                            }
                            .tag(tag)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .id(currentChapterIndex)
                    .onChange(of: currentPageIndex) { _, newValue in
                        if hasNext && newValue >= totalPages {
                            currentChapterIndex += 1
                            currentPageIndex = 0
                        } else if hasPrev && newValue < 0 {
                            skipPageReset = true
                            currentChapterIndex -= 1
                            let newPages = splitIntoPages(size: geometry.size)
                            currentPageIndex = max(newPages.count - 1, 0)
                        }
                    }
                } else {
                    pageView(fragments: pages[safeIndex], isFirstPage: safeIndex == 0)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            handlePageTap(location: location, screenSize: geometry.size, totalPages: totalPages)
                        }
                }
            }
            .overlay(alignment: .bottom) {
                if !showMenu {
                    pagedStatusBar(currentPage: safeIndex + 1, totalPages: totalPages)
                }
            }
            .onAppear {
                viewSize = geometry.size
                if currentPageIndex >= pages.count {
                    currentPageIndex = max(pages.count - 1, 0)
                }
            }
            .onChange(of: geometry.size) { _, newSize in
                viewSize = newSize
            }
        }
    }

    private func pageView(fragments: [PageFragment], isFirstPage: Bool) -> some View {
        VStack(alignment: .leading, spacing: settings.fontSize * (settings.lineSpacing - 1)) {
            if isFirstPage {
                Text(currentChapter?.title ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(settings.theme.chapterTitleColor)
                    .padding(.bottom, 8)
            }

            ForEach(fragments) { frag in
                Text(frag.indent ? "\u{3000}\u{3000}" + frag.text : frag.text)
                    .font(.custom(settings.fontFamily.rawValue, size: settings.fontSize))
                    .foregroundStyle(settings.theme.textColor)
                    .lineSpacing(settings.fontSize * (settings.lineSpacing - 1))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(.horizontal, settings.horizontalPadding)
        .padding(.top, 20)
        .padding(.bottom, pageBottomReserve)
    }

    // MARK: - Tap Handling

    private func handleTap(location: CGPoint) {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        let centerXRange = (screenWidth / 3)...(screenWidth * 2 / 3)
        let centerYRange = (screenHeight / 3)...(screenHeight * 2 / 3)
        if centerXRange.contains(location.x) && centerYRange.contains(location.y) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showMenu.toggle()
            }
        }
    }

    private func handlePageTap(location: CGPoint, screenSize: CGSize, totalPages: Int) {
        let centerXRange = (screenSize.width / 3)...(screenSize.width * 2 / 3)
        let centerYRange = (screenSize.height / 3)...(screenSize.height * 2 / 3)

        if centerXRange.contains(location.x) && centerYRange.contains(location.y) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showMenu.toggle()
            }
            return
        }

        if location.x < screenSize.width / 3 {
            if currentPageIndex > 0 {
                withAnimation { currentPageIndex -= 1 }
            } else if currentChapterIndex > 0 {
                skipPageReset = true
                currentChapterIndex -= 1
                let newPages = splitIntoPages(size: viewSize)
                currentPageIndex = max(newPages.count - 1, 0)
            }
        } else if location.x > screenSize.width * 2 / 3 {
            if currentPageIndex < totalPages - 1 {
                withAnimation { currentPageIndex += 1 }
            } else if currentChapterIndex < book.totalChapters - 1 {
                currentChapterIndex += 1
                currentPageIndex = 0
            }
        }
    }

    // MARK: - Page Splitting

    struct PageFragment: Identifiable {
        let id = UUID()
        let text: String
        let indent: Bool
    }

    private func splitIntoPages(size: CGSize) -> [[PageFragment]] {
        guard !paragraphs.isEmpty else { return [[]] }

        let textWidth = size.width - settings.horizontalPadding * 2
        let pageHeight = max(120, size.height - 20 - pageBottomReserve)
        let titleHeight: CGFloat = 30
        let lineSpacingValue = settings.fontSize * (settings.lineSpacing - 1)

        let font = UIFont(name: settings.fontFamily.rawValue, size: settings.fontSize)
            ?? UIFont.systemFont(ofSize: settings.fontSize)
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineSpacing = lineSpacingValue
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paraStyle
        ]

        func measureHeight(_ text: String, indent: Bool) -> CGFloat {
            let display = indent ? "\u{3000}\u{3000}" + text : text
            let attrStr = NSAttributedString(string: display, attributes: attributes)
            let rect = attrStr.boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            return ceil(rect.height)
        }

        func splitText(_ text: String, indent: Bool, fitting height: CGFloat) -> (String, String)? {
            let safeHeight = height - font.lineHeight
            guard safeHeight > font.lineHeight else { return nil }

            let display = indent ? "\u{3000}\u{3000}" + text : text
            let prefixLen = indent ? 2 : 0
            let attrStr = NSAttributedString(string: display, attributes: attributes)
            let setter = CTFramesetterCreateWithAttributedString(attrStr)
            let path = CGPath(rect: CGRect(x: 0, y: 0, width: textWidth, height: safeHeight), transform: nil)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            let endIndex = visibleRange.location + visibleRange.length

            let nsDisplay = display as NSString
            guard endIndex > prefixLen, endIndex < nsDisplay.length else { return nil }

            let originalEnd = endIndex - prefixLen
            let nsText = text as NSString
            guard originalEnd > 0, originalEnd < nsText.length else { return nil }

            let first = nsText.substring(to: originalEnd)
            let second = nsText.substring(from: originalEnd)
            guard !second.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return (first, second)
        }

        struct QueueItem {
            let text: String
            let indent: Bool
        }

        var queue = paragraphs.reversed().map { QueueItem(text: $0, indent: true) }
        var pages: [[PageFragment]] = []
        var currentPage: [PageFragment] = []
        var currentHeight: CGFloat = titleHeight

        while let item = queue.popLast() {
            let h = measureHeight(item.text, indent: item.indent)
            let gap = currentPage.isEmpty ? 0 : lineSpacingValue

            if currentHeight + gap + h <= pageHeight {
                currentPage.append(PageFragment(text: item.text, indent: item.indent))
                currentHeight += gap + h
            } else if currentPage.isEmpty {
                if let (first, second) = splitText(item.text, indent: item.indent, fitting: pageHeight - currentHeight) {
                    currentPage.append(PageFragment(text: first, indent: item.indent))
                    pages.append(currentPage)
                    currentPage = []
                    currentHeight = 0
                    queue.append(QueueItem(text: second, indent: false))
                } else {
                    currentPage.append(PageFragment(text: item.text, indent: item.indent))
                    pages.append(currentPage)
                    currentPage = []
                    currentHeight = 0
                }
            } else {
                let remaining = pageHeight - currentHeight - gap
                if remaining > font.lineHeight * 1.5,
                   let (first, second) = splitText(item.text, indent: item.indent, fitting: remaining) {
                    currentPage.append(PageFragment(text: first, indent: item.indent))
                    pages.append(currentPage)
                    currentPage = []
                    currentHeight = 0
                    queue.append(QueueItem(text: second, indent: false))
                } else {
                    pages.append(currentPage)
                    currentPage = []
                    currentHeight = 0
                    queue.append(item)
                }
            }
        }

        if !currentPage.isEmpty {
            pages.append(currentPage)
        }

        return pages.isEmpty ? [[]] : pages
    }

    // MARK: - Content Fetching

    private func fetchChapterContentIfNeeded() {
        guard let chapter = currentChapter,
              chapter.content == nil,
              chapter.sourceURL != nil,
              !isLoadingContent else { return }

        isLoadingContent = true
        loadError = nil

        Task {
            do {
                try await fetchContent(for: chapter)
                await MainActor.run { isLoadingContent = false }
                prefetchNextChapters()
            } catch {
                await MainActor.run {
                    loadError = "加载失败"
                    isLoadingContent = false
                }
            }
        }
    }

    private func fetchContent(for chapter: Chapter) async throws {
        guard chapter.content == nil, let sourceURL = chapter.sourceURL else { return }
        guard let bookSourceId = book.sourceId else { throw NetworkError.requestFailed }

        let descriptor = FetchDescriptor<BookSource>(predicate: #Predicate<BookSource> { $0.id == bookSourceId })
        guard let bookSource = try modelContext.fetch(descriptor).first else { throw NetworkError.requestFailed }
        let legado = try LegadoSourceParser.parse(json: bookSource.ruleJSON, matchingURL: bookSource.sourceURL)
        guard let contentRule = legado.contentRule else { throw NetworkError.requestFailed }

        let html = try await NetworkClient.shared.fetchString(url: sourceURL)
        let content = try SourceEngine().parseContent(response: html, rule: contentRule, baseURL: legado.url)
        await MainActor.run {
            chapter.content = content
            chapter.isCached = true
        }
    }

    private func prefetchNextChapters() {
        let start = currentChapterIndex + 1
        let end = min(currentChapterIndex + 3, book.totalChapters - 1)
        guard start <= end else { return }

        for index in start...end {
            guard let chapter = chapters.first(where: { $0.index == index }),
                  chapter.content == nil, chapter.sourceURL != nil else { continue }
            Task { try? await fetchContent(for: chapter) }
        }
    }

    private func cacheChapters(count: Int?) {
        guard !isCaching else { return }

        var uncached: [Chapter]
        if let count {
            // 缓存后 N 章：从当前章节之后开始
            uncached = chapters
                .filter { $0.content == nil && $0.sourceURL != nil && $0.index > currentChapterIndex }
                .sorted { $0.index < $1.index }
            uncached = Array(uncached.prefix(count))
        } else {
            // 缓存全部：所有未缓存章节
            uncached = chapters
                .filter { $0.content == nil && $0.sourceURL != nil }
                .sorted { $0.index < $1.index }
        }
        guard !uncached.isEmpty else { return }

        isCaching = true
        cachedCount = 0
        totalToCache = uncached.count

        Task {
            for chapter in uncached {
                do {
                    try await fetchContent(for: chapter)
                } catch {}
                await MainActor.run { cachedCount += 1 }
            }
            await MainActor.run { isCaching = false }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            Text(book.title)
                .font(.system(size: 11))
                .foregroundStyle(settings.theme.statusBarColor)
            Spacer()
            if isCaching {
                Text("缓存中 \(cachedCount)/\(totalToCache)")
                    .font(.system(size: 11))
                    .foregroundStyle(settings.theme.statusBarColor)
            } else {
                Text("\(currentChapterIndex + 1) / \(book.totalChapters)")
                    .font(.system(size: 11))
                    .foregroundStyle(settings.theme.statusBarColor)
            }
        }
        .padding(.horizontal, settings.horizontalPadding)
        .padding(.bottom, 8)
    }

    private func pagedStatusBar(currentPage: Int, totalPages: Int) -> some View {
        HStack {
            Text(book.title)
                .font(.system(size: 11))
                .foregroundStyle(settings.theme.statusBarColor)
            Spacer()
            Text("\(currentPage)/\(totalPages)")
                .font(.system(size: 11))
                .foregroundStyle(settings.theme.statusBarColor)
        }
        .padding(.horizontal, settings.horizontalPadding)
        .padding(.bottom, 8)
    }
}
