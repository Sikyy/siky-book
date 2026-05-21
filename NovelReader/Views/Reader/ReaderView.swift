import SwiftUI
import SwiftData
import CoreText

struct ReaderView: View {
    let book: Book
    @State private var chapters: [Chapter] = []
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
    @State private var cacheTask: Task<Void, Never>?
    @State private var skipPageReset = false
    @State private var viewSize: CGSize = .zero
    @State private var cachedPages: [[PageFragment]] = [[]]
    @State private var cachedParagraphs: [String] = []
    @State private var scrolledPage: Int?
    private let pageBottomReserve: CGFloat = 72

    init(book: Book, startChapterIndex: Int = 0) {
        self.book = book
        self._currentChapterIndex = State(initialValue: startChapterIndex)
    }

    /// O(1) access — chapters sorted by index, indices are 0-based contiguous
    private var currentChapter: Chapter? {
        guard currentChapterIndex >= 0, currentChapterIndex < chapters.count else { return nil }
        return chapters[currentChapterIndex]
    }

    /// Load chapters once from SwiftData — no reactive @Query overhead
    private func loadChapters() {
        let bookId = book.id
        let descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate<Chapter> { $0.book?.id == bookId },
            sortBy: [SortDescriptor(\Chapter.index)]
        )
        chapters = (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Reparse paragraphs from current chapter — call on chapter switch / content load
    private func rebuildParagraphs() {
        let text = currentChapter?.content ?? ""
        cachedParagraphs = text
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
                    onCancelCache: { cancelCaching() },
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
            recomputePages()
            if skipPageReset {
                skipPageReset = false
                currentPageIndex = max(cachedPages.count - 1, 0)
            } else {
                currentPageIndex = 0
            }
            scrolledPage = currentPageIndex
        }
        .onAppear { loadChapters() }
        .onDisappear {
            let manager = BookManager(modelContext: modelContext)
            manager.updateProgress(book: book, chapterIndex: currentChapterIndex, position: 0)
        }
        .onChange(of: isLoadingContent) { old, new in
            if old && !new { recomputePages() }
        }
        .onChange(of: settings.fontSize) { _, _ in recomputePages() }
        .onChange(of: settings.lineSpacing) { _, _ in recomputePages() }
        .onChange(of: settings.fontFamily) { _, _ in recomputePages() }
        .onChange(of: settings.horizontalPadding) { _, _ in recomputePages() }
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

                ForEach(Array(cachedParagraphs.enumerated()), id: \.offset) { _, para in
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
            let pages = cachedPages
            let totalPages = pages.count
            let safeIndex = max(0, min(currentPageIndex, totalPages - 1))
            let width = geometry.size.width
            let hasPrev = currentChapterIndex > 0
            let hasNext = currentChapterIndex < chapters.count - 1

            Group {
                if settings.pageMode == .horizontal {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 0) {
                            // Previous chapter sentinel
                            if hasPrev {
                                chapterBoundaryPage(
                                    label: "上一章",
                                    title: prevChapterTitle
                                )
                                .frame(width: width, height: geometry.size.height)
                                .id(-1)
                            }

                            // Content pages
                            ForEach(0..<totalPages, id: \.self) { index in
                                pageView(fragments: pages[index], isFirstPage: index == 0)
                                    .frame(width: width, height: geometry.size.height)
                            }

                            // Next chapter sentinel
                            if hasNext {
                                chapterBoundaryPage(
                                    label: "下一章",
                                    title: nextChapterTitle
                                )
                                .frame(width: width, height: geometry.size.height)
                                .id(totalPages)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $scrolledPage)
                    .onChange(of: scrolledPage) { _, newValue in
                        guard let newValue else { return }
                        if newValue == -1 && hasPrev {
                            skipPageReset = true
                            currentChapterIndex -= 1
                        } else if newValue >= totalPages && hasNext {
                            currentChapterIndex += 1
                        } else if newValue >= 0 && newValue < totalPages {
                            currentPageIndex = newValue
                        }
                    }
                } else {
                    pageView(fragments: pages[safeIndex], isFirstPage: safeIndex == 0)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                handlePageTap(location: location, screenSize: geometry.size, totalPages: totalPages)
            }
            .overlay(alignment: .bottom) {
                if !showMenu {
                    pagedStatusBar(currentPage: safeIndex + 1, totalPages: totalPages)
                }
            }
            .onAppear {
                viewSize = geometry.size
                recomputePages()
                scrolledPage = currentPageIndex
            }
            .onChange(of: geometry.size) { _, newSize in
                viewSize = newSize
                recomputePages()
            }
        }
    }

    /// Sentinel page shown at chapter boundaries — minimal content, quick to render
    private func chapterBoundaryPage(label: String, title: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(settings.theme.textColor.opacity(0.4))
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(settings.theme.textColor.opacity(0.6))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var prevChapterTitle: String {
        let i = currentChapterIndex - 1
        guard i >= 0, i < chapters.count else { return "" }
        return chapters[i].title
    }

    private var nextChapterTitle: String {
        let i = currentChapterIndex + 1
        guard i < chapters.count else { return "" }
        return chapters[i].title
    }

    private func pageView(fragments: [PageFragment], isFirstPage: Bool) -> some View {
        StaticPageView(
            fragments: fragments,
            isFirstPage: isFirstPage,
            chapterTitle: currentChapter?.title ?? "",
            fontSize: settings.fontSize,
            lineSpacing: settings.lineSpacing,
            fontFamily: settings.fontFamily.rawValue,
            textColor: settings.theme.textColor,
            titleColor: settings.theme.chapterTitleColor,
            horizontalPadding: settings.horizontalPadding,
            bottomReserve: pageBottomReserve
        )
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
                currentPageIndex -= 1
                scrolledPage = currentPageIndex
            } else if currentChapterIndex > 0 {
                skipPageReset = true
                currentChapterIndex -= 1
                // onChange(of: currentChapterIndex) handles recomputePages + scroll
            }
        } else if location.x > screenSize.width * 2 / 3 {
            if currentPageIndex < totalPages - 1 {
                currentPageIndex += 1
                scrolledPage = currentPageIndex
            } else if currentChapterIndex < chapters.count - 1 {
                currentChapterIndex += 1
                // onChange(of: currentChapterIndex) handles recomputePages + scroll
            }
        }
    }

    // MARK: - Page Splitting

    struct PageFragment: Identifiable {
        let id: Int
        let text: String
        let indent: Bool
    }

    private func recomputePages() {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        rebuildParagraphs()
        cachedPages = splitIntoPages(size: viewSize)
        if currentPageIndex >= cachedPages.count {
            currentPageIndex = max(cachedPages.count - 1, 0)
        }
    }

    private func splitIntoPages(size: CGSize) -> [[PageFragment]] {
        guard !cachedParagraphs.isEmpty else { return [[]] }

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

        var queue = cachedParagraphs.reversed().map { QueueItem(text: $0, indent: true) }
        var pages: [[PageFragment]] = []
        var currentPage: [PageFragment] = []
        var currentHeight: CGFloat = titleHeight
        var fragmentId = 0

        while let item = queue.popLast() {
            let h = measureHeight(item.text, indent: item.indent)
            let gap = currentPage.isEmpty ? 0 : lineSpacingValue

            if currentHeight + gap + h <= pageHeight {
                fragmentId += 1
                currentPage.append(PageFragment(id: fragmentId, text: item.text, indent: item.indent))
                currentHeight += gap + h
            } else if currentPage.isEmpty {
                if let (first, second) = splitText(item.text, indent: item.indent, fitting: pageHeight - currentHeight) {
                    fragmentId += 1
                    currentPage.append(PageFragment(id: fragmentId, text: first, indent: item.indent))
                    pages.append(currentPage)
                    currentPage = []
                    currentHeight = 0
                    queue.append(QueueItem(text: second, indent: false))
                } else {
                    fragmentId += 1
                    currentPage.append(PageFragment(id: fragmentId, text: item.text, indent: item.indent))
                    pages.append(currentPage)
                    currentPage = []
                    currentHeight = 0
                }
            } else {
                let remaining = pageHeight - currentHeight - gap
                if remaining > font.lineHeight * 1.5,
                   let (first, second) = splitText(item.text, indent: item.indent, fitting: remaining) {
                    fragmentId += 1
                    currentPage.append(PageFragment(id: fragmentId, text: first, indent: item.indent))
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
        let end = min(currentChapterIndex + 3, chapters.count - 1)
        guard start <= end else { return }

        for index in start...end {
            let chapter = chapters[index]
            guard chapter.content == nil, chapter.sourceURL != nil else { continue }
            Task.detached(priority: .utility) { [modelContext, book] in
                try? await Self.fetchContentDetached(chapter: chapter, book: book, modelContext: modelContext)
            }
        }
    }

    /// Detached prefetch — no capture of ReaderView self
    private static func fetchContentDetached(chapter: Chapter, book: Book, modelContext: ModelContext) async throws {
        guard chapter.content == nil, let sourceURL = chapter.sourceURL else { return }
        guard let bookSourceId = book.sourceId else { return }

        let descriptor = FetchDescriptor<BookSource>(predicate: #Predicate<BookSource> { $0.id == bookSourceId })
        guard let bookSource = try? modelContext.fetch(descriptor).first else { return }
        let legado = try LegadoSourceParser.parse(json: bookSource.ruleJSON, matchingURL: bookSource.sourceURL)
        guard let contentRule = legado.contentRule else { return }

        let html = try await NetworkClient.shared.fetchString(url: sourceURL)
        let content = try SourceEngine().parseContent(response: html, rule: contentRule, baseURL: legado.url)
        await MainActor.run {
            chapter.content = content
            chapter.isCached = true
        }
    }

    private func cacheChapters(count: Int?) {
        guard !isCaching else { return }

        var uncached: [Chapter]
        if let count {
            uncached = chapters
                .filter { $0.content == nil && $0.sourceURL != nil && $0.index > currentChapterIndex }
                .sorted { $0.index < $1.index }
            uncached = Array(uncached.prefix(count))
        } else {
            uncached = chapters
                .filter { $0.content == nil && $0.sourceURL != nil }
                .sorted { $0.index < $1.index }
        }
        guard !uncached.isEmpty else { return }

        isCaching = true
        cachedCount = 0
        totalToCache = uncached.count

        let maxConcurrent = 5
        cacheTask = Task {
            await withTaskGroup(of: Void.self) { group in
                for (i, chapter) in uncached.enumerated() {
                    if Task.isCancelled { break }
                    if i >= maxConcurrent {
                        await group.next()
                    }
                    group.addTask {
                        guard !Task.isCancelled else { return }
                        do {
                            try await fetchContent(for: chapter)
                        } catch {}
                        await MainActor.run { cachedCount += 1 }
                    }
                }
                await group.waitForAll()
            }
            await MainActor.run {
                isCaching = false
                cacheTask = nil
            }
        }
    }

    private func cancelCaching() {
        cacheTask?.cancel()
        cacheTask = nil
        isCaching = false
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

// MARK: - Static Page View (no @Observable dependencies, Equatable for skip)

private struct StaticPageView: View, Equatable {
    let fragments: [ReaderView.PageFragment]
    let isFirstPage: Bool
    let chapterTitle: String
    let fontSize: CGFloat
    let lineSpacing: Double
    let fontFamily: String
    let textColor: Color
    let titleColor: Color
    let horizontalPadding: CGFloat
    let bottomReserve: CGFloat

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.fragments.count == rhs.fragments.count
        && lhs.isFirstPage == rhs.isFirstPage
        && lhs.chapterTitle == rhs.chapterTitle
        && lhs.fontSize == rhs.fontSize
        && lhs.lineSpacing == rhs.lineSpacing
        && lhs.fontFamily == rhs.fontFamily
        && lhs.horizontalPadding == rhs.horizontalPadding
        && lhs.bottomReserve == rhs.bottomReserve
        && lhs.fragments.first?.id == rhs.fragments.first?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: fontSize * (lineSpacing - 1)) {
            if isFirstPage {
                Text(chapterTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(titleColor)
                    .padding(.bottom, 8)
            }

            ForEach(fragments) { frag in
                Text(frag.indent ? "\u{3000}\u{3000}" + frag.text : frag.text)
                    .font(.custom(fontFamily, size: fontSize))
                    .foregroundStyle(textColor)
                    .lineSpacing(fontSize * (lineSpacing - 1))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 20)
        .padding(.bottom, bottomReserve)
    }
}
