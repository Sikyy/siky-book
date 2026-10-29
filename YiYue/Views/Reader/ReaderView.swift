import SwiftUI
import SwiftData
import Combine
import CoreText

@MainActor
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
    @State private var isPaginating = false
    @State private var loadError: String?
    @State private var isSwitchingChapterSource = false
    @State private var chapterSourceSwitchTask: Task<Void, Never>?
    @State private var chapterSourceSwitchGeneration: UUID?
    @State private var isCaching = false
    @State private var cachedCount = 0
    @State private var completedCacheCount = 0
    @State private var totalToCache = 0
    @State private var cacheTask: Task<Void, Never>?
    @State private var downloadSnapshot: ChapterDownloadSnapshot?
    @State private var cacheSummary: BookCacheSummary?
    @State private var isCheckingCacheSummary = false
    @State private var reconciledDownloadMarker: String?
    @State private var cacheReconciliationMarkerInFlight: String?
    @State private var pendingCacheReconciliationMarker: String?
    @State private var chapterLoadTask: Task<Void, Never>?
    @State private var prefetchTask: Task<Void, Never>?
    @State private var adjacentPreparationTask: Task<Void, Never>?
    @State private var loadingIndicatorTask: Task<Void, Never>?
    @State private var paginationIndicatorTask: Task<Void, Never>?
    @State private var readerMetadataSaveTask: Task<Void, Never>?
    @State private var terminalCacheReconciliationTask: Task<Void, Never>?
    @State private var cacheGeneration: UUID?
    @State private var prefetchGeneration: UUID?
    @State private var adjacentPreparationGeneration: UUID?
    @State private var adjacentPreparationActiveChapterID: UUID?
    @State private var paginationTask: Task<Void, Never>?
    @State private var contentLoadGeneration: UUID?
    @State private var paginationGeneration: UUID?
    @State private var pendingPagePosition: PaginationPosition?
    /// Fraction (0…1) of the way into the chapter to jump to once pagination finishes; cleared after use.
    @State private var restorePositionFraction: Double?
    @State private var footerClock = ""
    @State private var skipPageReset = false
    @State private var viewSize: CGSize = .zero
    @State private var cachedPages: [[PageFragment]] = [[]]
    @State private var cachedParagraphs: [String] = []
    @State private var currentChapterContent: String?
    @State private var preparedChapterWindow = ReaderPreparedChapterWindow()
    @State private var scrolledPage: HorizontalPageID?
    @State private var tapSentinel: TapSentinel? = nil
    @State private var pendingHorizontalChapterTransition: PendingHorizontalChapterTransition?
    @State private var isHorizontalScrollIdle = true
    @State private var isCommittingHorizontalChapterTransition = false
    @State private var horizontalTransitionCommitTask: Task<Void, Never>?
    @State private var horizontalProgrammaticScrollFallbackTask: Task<Void, Never>?
    @State private var horizontalIdleFinalizationTask: Task<Void, Never>?
    @State private var horizontalPageDescriptorSnapshot: [HorizontalPageDescriptor]?
    /// One-line footer (11 pt + 8 pt inset) plus a small separation from text.
    private let pageBottomReserve: CGFloat = 32

    private enum TapSentinel { case prev, next }
    private enum PaginationPosition { case preserve, first, last }
    private enum PreparedChapterActivation { case rendered, contentOnly, unavailable }

    private enum HorizontalDirection: Hashable {
        case previous
        case next
    }

    private enum HorizontalPageID: Hashable {
        case page(chapterID: UUID, pageIndex: Int)
        case boundary(ownerChapterID: UUID, targetChapterID: UUID, direction: HorizontalDirection)
        case legacyTrigger(ownerChapterID: UUID, direction: HorizontalDirection)
    }

    private struct PendingHorizontalChapterTransition: Equatable {
        let direction: HorizontalDirection
        let targetChapterID: UUID
        let previewPageID: HorizontalPageID
    }

    private struct HorizontalPageDescriptor: Identifiable {
        enum Content {
            case page(fragments: [PageFragment], chapterTitle: String)
            case boundary(label: String, chapterTitle: String)
        }

        let id: HorizontalPageID
        let content: Content
    }

    init(book: Book, startChapterIndex: Int = 0, startPosition: Double = 0) {
        self.book = book
        self._currentChapterIndex = State(initialValue: startChapterIndex)
        self._restorePositionFraction = State(initialValue: startPosition > 0 ? startPosition : nil)
    }

    /// O(1) access — chapters sorted by index, indices are 0-based contiguous
    private var currentChapter: Chapter? {
        guard currentChapterIndex >= 0, currentChapterIndex < chapters.count else { return nil }
        return chapters[currentChapterIndex]
    }

    /// Load the already-related chapters once, avoiding a second predicate fetch.
    private func loadChapters() {
        chapters = book.chapters.sorted { $0.index < $1.index }
        guard book.sourceId != nil else {
            cacheSummary = nil
            isCheckingCacheSummary = false
            return
        }

        // Give the menu an immediate approximation from persisted metadata.
        // The authoritative user-managed directory is checked only after the
        // first visible page and its hot adjacent preparation are ready.
        cacheSummary = metadataCacheSummary()
        isCheckingCacheSummary = cacheSummary.map { $0.cached + $0.uncached > 0 } ?? false
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
                    onResumeCache: { resumeCaching() },
                    cacheState: cachePresentationState,
                    onRefreshToc: book.sourceId == nil ? nil : { await refreshTableOfContents() }
                )
            }
        }
        .statusBarHidden(!showMenu)
        .persistentSystemOverlays(showMenu ? .automatic : .hidden)
        .preferredColorScheme(settings.theme.isDark ? .dark : .light)
        .onChange(of: currentChapterIndex) { _, newValue in
            tapSentinel = nil
            pendingHorizontalChapterTransition = nil
            horizontalTransitionCommitTask?.cancel()
            horizontalTransitionCommitTask = nil
            horizontalProgrammaticScrollFallbackTask?.cancel()
            horizontalProgrammaticScrollFallbackTask = nil
            horizontalIdleFinalizationTask?.cancel()
            horizontalIdleFinalizationTask = nil
            horizontalPageDescriptorSnapshot = nil
            isHorizontalScrollIdle = true
            isCommittingHorizontalChapterTransition = false
            chapterSourceSwitchTask?.cancel()
            chapterSourceSwitchGeneration = nil
            chapterSourceSwitchTask = nil
            isSwitchingChapterSource = false
            let position: PaginationPosition = skipPageReset ? .last : .first
            skipPageReset = false
            let manager = BookManager(modelContext: modelContext)
            manager.updateProgress(book: book, chapterIndex: newValue, position: 0)

            let retainedAdjacentPreparation = cancelCurrentChapterRendering(
                preservingAdjacentFor: currentChapter?.id
            )
            trimPreparedChapterWindow()
            switch activatePreparedChapter(position: position) {
            case .rendered:
                prepareAdjacentChapters()
                prefetchNextChapters()
            case .contentOnly:
                if let retainedAdjacentPreparation,
                   let chapter = currentChapter {
                    activatePreparedChapterWhenReady(
                        retainedAdjacentPreparation,
                        chapterID: chapter.id,
                        capturedSourceIdentity: sourceIdentity(for: chapter),
                        position: position
                    )
                } else {
                    recomputePages(position: position)
                    prefetchNextChapters()
                }
            case .unavailable:
                currentChapterContent = nil
                if let retainedAdjacentPreparation,
                   let chapter = currentChapter {
                    withTransaction(Transaction(animation: nil)) {
                        cachedParagraphs = []
                        cachedPages = [[]]
                        currentPageIndex = 0
                        scrolledPage = horizontalPageID(
                            chapterID: chapter.id,
                            pageIndex: 0
                        )
                        pendingPagePosition = position
                    }
                    activatePreparedChapterWhenReady(
                        retainedAdjacentPreparation,
                        chapterID: chapter.id,
                        capturedSourceIdentity: sourceIdentity(for: chapter),
                        position: position
                    )
                } else {
                    recomputePages(position: position)
                    fetchChapterContentIfNeeded()
                }
            }
            scheduleReaderMetadataSave()
        }
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            footerClock = Self.footerTimeFormatter.string(from: Date())
            loadChapters()
            recomputePages(position: .first)
            fetchChapterContentIfNeeded()
        }
        .task {
            await observeChapterDownloads()
        }
        .onDisappear {
            chapterLoadTask?.cancel()
            prefetchTask?.cancel()
            adjacentPreparationTask?.cancel()
            loadingIndicatorTask?.cancel()
            paginationIndicatorTask?.cancel()
            readerMetadataSaveTask?.cancel()
            terminalCacheReconciliationTask?.cancel()
            paginationTask?.cancel()
            chapterSourceSwitchTask?.cancel()
            horizontalTransitionCommitTask?.cancel()
            horizontalProgrammaticScrollFallbackTask?.cancel()
            horizontalIdleFinalizationTask?.cancel()
            chapterSourceSwitchGeneration = nil
            // Only queue preparation belongs to this Reader presentation. An
            // enqueued explicit cache operation is app-owned and keeps running.
            cacheTask?.cancel()
            persistReadingPosition()
            try? modelContext.save()
        }
        .onChange(of: currentPageIndex) { _, _ in
            persistReadingPosition()
        }
        .onChange(of: settings.fontSize) { _, _ in readerLayoutDidChange(delayNanoseconds: 150_000_000) }
        .onChange(of: settings.lineSpacing) { _, _ in readerLayoutDidChange(delayNanoseconds: 150_000_000) }
        .onChange(of: settings.fontFamily) { _, _ in readerLayoutDidChange(delayNanoseconds: 150_000_000) }
        .onChange(of: settings.horizontalPadding) { _, _ in readerLayoutDidChange(delayNanoseconds: 150_000_000) }
        .onChange(of: settings.pageMode) { _, _ in
            tapSentinel = nil
            cancelPendingHorizontalChapterTransition(returningToCurrentPage: true)
            recomputePages()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            cancelPendingHorizontalChapterTransition(returningToCurrentPage: true)
            adjacentPreparationTask?.cancel()
            adjacentPreparationTask = nil
            adjacentPreparationGeneration = nil
            adjacentPreparationActiveChapterID = nil
            if let chapterID = currentChapter?.id {
                preparedChapterWindow.retain(chapterIDs: [chapterID])
            } else {
                preparedChapterWindow.removeAll()
            }
        }
    }

    // MARK: - Reading Content

    private var readingContent: some View {
        ZStack {
            if isLoadingContent || isPaginating {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(isLoadingContent ? "加载中…" : "排版中…")
                        .font(.subheadline)
                        .foregroundStyle(settings.theme.textColor.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { showMenu.toggle() }
                }
            } else if let error = loadError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(settings.theme.textColor.opacity(0.5))
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(settings.theme.textColor.opacity(0.6))
                        .multilineTextAlignment(.center)
                    HStack(spacing: 18) {
                        Button("重试") { fetchChapterContentIfNeeded() }
                            .foregroundStyle(.blue)
                        if book.sourceId != nil {
                            Button {
                                startCurrentChapterSourceSwitch()
                            } label: {
                                if isSwitchingChapterSource {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .scaleEffect(0.75)
                                        Text("换源中")
                                    }
                                } else {
                                    Label("单章换源", systemImage: "arrow.triangle.2.circlepath")
                                }
                            }
                            .foregroundStyle(.blue)
                            .disabled(isSwitchingChapterSource)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { showMenu.toggle() }
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
                        .font(settings.fontFamily.isSystem
                            ? .system(size: settings.fontSize)
                            : .custom(settings.fontFamily.rawValue, size: settings.fontSize))
                        .foregroundStyle(settings.theme.textColor)
                        .lineSpacing(settings.fontSize * (settings.lineSpacing - 1))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, settings.horizontalPadding)
            .padding(.top, 20)
            .padding(.bottom, 60)
        }
        .id(currentChapter?.id)
        .contentShape(Rectangle())
        .onTapGesture { location in
            handleTap(location: location)
        }
        .overlay(alignment: .bottom) {
            if !showMenu {
                readerFooter(currentPage: currentPageIndex + 1, totalPages: max(cachedPages.count, 1))
            }
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
                    horizontalPagedContent(
                        pages: pages,
                        width: width,
                        height: geometry.size.height,
                        hasPrev: hasPrev,
                        hasNext: hasNext
                    )
                } else {
                    if tapSentinel == .next, currentChapterIndex < chapters.count - 1 {
                        chapterBoundaryPage(label: "下一章", title: nextChapterTitle)
                    } else if tapSentinel == .prev, currentChapterIndex > 0 {
                        chapterBoundaryPage(label: "上一章", title: prevChapterTitle)
                    } else {
                        pageView(fragments: pages[safeIndex])
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                handlePageTap(location: location, screenSize: geometry.size, totalPages: totalPages)
            }
            .overlay(alignment: .bottom) {
                if !showMenu {
                    readerFooter(currentPage: safeIndex + 1, totalPages: totalPages)
                }
            }
            .onAppear {
                updateReaderGeometry(geometry.size)
                scrolledPage = currentHorizontalPageID(pageIndex: currentPageIndex)
            }
            .onChange(of: geometry.size) { _, newSize in
                updateReaderGeometry(newSize)
            }
        }
    }

    @ViewBuilder
    private func horizontalPagedContent(
        pages: [[PageFragment]],
        width: CGFloat,
        height: CGFloat,
        hasPrev: Bool,
        hasNext: Bool
    ) -> some View {
        if #available(iOS 18.0, *) {
            continuousHorizontalPagedContent(
                pages: pages,
                width: width,
                height: height
            )
        } else {
            legacyHorizontalPagedContent(
                pages: pages,
                width: width,
                height: height,
                hasPrev: hasPrev,
                hasNext: hasNext
            )
        }
    }

    /// iOS 18 exposes the real scroll phase, so an adjacent chapter can be part
    /// of the same paging strip and only become current after deceleration ends.
    @available(iOS 18.0, *)
    private func continuousHorizontalPagedContent(
        pages: [[PageFragment]],
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let liveDescriptors = continuousHorizontalPageDescriptors(currentPages: pages)
        let descriptors = horizontalPageDescriptorSnapshot ?? liveDescriptors

        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(descriptors) { descriptor in
                    Group {
                        switch descriptor.content {
                        case let .page(fragments, chapterTitle):
                            pageView(
                                fragments: fragments,
                                chapterTitle: chapterTitle
                            )
                        case let .boundary(label, chapterTitle):
                            chapterBoundaryPage(label: label, title: chapterTitle)
                        }
                    }
                    .frame(width: width, height: height)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrolledPage)
        .onScrollPhaseChange { _, newPhase in
            if newPhase == .idle {
                isHorizontalScrollIdle = true
                horizontalProgrammaticScrollFallbackTask?.cancel()
                horizontalProgrammaticScrollFallbackTask = nil
                scheduleHorizontalScrollIdleFinalization()
            } else {
                if isHorizontalScrollIdle {
                    horizontalPageDescriptorSnapshot = liveDescriptors
                }
                isHorizontalScrollIdle = false
                horizontalTransitionCommitTask?.cancel()
                horizontalTransitionCommitTask = nil
                horizontalProgrammaticScrollFallbackTask?.cancel()
                horizontalProgrammaticScrollFallbackTask = nil
                horizontalIdleFinalizationTask?.cancel()
                horizontalIdleFinalizationTask = nil
            }
        }
        .onChange(of: scrolledPage) { _, newValue in
            handleContinuousHorizontalScrollPosition(newValue)
        }
    }

    /// iOS 17 has no deceleration-complete callback in SwiftUI. Keep the old
    /// two-step boundary/trigger interaction there instead of guessing with a
    /// timer and potentially replacing the pager while it is still moving.
    @ViewBuilder
    private func legacyHorizontalPagedContent(
        pages: [[PageFragment]],
        width: CGFloat,
        height: CGFloat,
        hasPrev: Bool,
        hasNext: Bool
    ) -> some View {
        if let chapter = currentChapter {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    if hasPrev {
                        settings.theme.backgroundColor
                            .frame(width: width, height: height)
                            .id(HorizontalPageID.legacyTrigger(
                                ownerChapterID: chapter.id,
                                direction: .previous
                            ))

                        chapterBoundaryPage(label: "上一章", title: prevChapterTitle)
                            .frame(width: width, height: height)
                            .id(boundaryPageID(
                                ownerChapterID: chapter.id,
                                targetChapterID: chapters[currentChapterIndex - 1].id,
                                direction: .previous
                            ))
                    }

                    ForEach(0..<pages.count, id: \.self) { index in
                        pageView(fragments: pages[index])
                            .frame(width: width, height: height)
                            .id(horizontalPageID(chapterID: chapter.id, pageIndex: index))
                    }

                    if hasNext {
                        chapterBoundaryPage(label: "下一章", title: nextChapterTitle)
                            .frame(width: width, height: height)
                            .id(boundaryPageID(
                                ownerChapterID: chapter.id,
                                targetChapterID: chapters[currentChapterIndex + 1].id,
                                direction: .next
                            ))

                        settings.theme.backgroundColor
                            .frame(width: width, height: height)
                            .id(HorizontalPageID.legacyTrigger(
                                ownerChapterID: chapter.id,
                                direction: .next
                            ))
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $scrolledPage)
            .onChange(of: scrolledPage) { _, newValue in
                handleLegacyHorizontalScrollPosition(newValue)
            }
        } else {
            settings.theme.backgroundColor
        }
    }

    private func continuousHorizontalPageDescriptors(
        currentPages: [[PageFragment]]
    ) -> [HorizontalPageDescriptor] {
        guard let chapter = currentChapter else { return [] }
        var descriptors: [HorizontalPageDescriptor] = []

        if currentChapterIndex > 0 {
            let previousIndex = currentChapterIndex - 1
            let previousChapter = chapters[previousIndex]
            let keepsBoundary = shouldKeepPendingBoundaryPreview(
                targetChapterID: previousChapter.id,
                direction: .previous
            )
            if !keepsBoundary,
               let prepared = preparedEntry(at: previousIndex),
               let fragments = prepared.pages.last {
                descriptors.append(HorizontalPageDescriptor(
                    id: horizontalPageID(
                        chapterID: previousChapter.id,
                        pageIndex: max(prepared.pages.count - 1, 0)
                    ),
                    content: .page(
                        fragments: fragments,
                        chapterTitle: previousChapter.title
                    )
                ))
            } else {
                descriptors.append(HorizontalPageDescriptor(
                    id: HorizontalPageID.boundary(
                        ownerChapterID: chapter.id,
                        targetChapterID: previousChapter.id,
                        direction: .previous
                    ),
                    content: .boundary(
                        label: "上一章",
                        chapterTitle: previousChapter.title
                    )
                ))
            }
        }

        descriptors.append(contentsOf: currentPages.indices.map { index in
            HorizontalPageDescriptor(
                id: horizontalPageID(chapterID: chapter.id, pageIndex: index),
                content: .page(
                    fragments: currentPages[index],
                    chapterTitle: chapter.title
                )
            )
        })

        if currentChapterIndex + 1 < chapters.count {
            let nextIndex = currentChapterIndex + 1
            let nextChapter = chapters[nextIndex]
            let keepsBoundary = shouldKeepPendingBoundaryPreview(
                targetChapterID: nextChapter.id,
                direction: .next
            )
            if !keepsBoundary,
               let prepared = preparedEntry(at: nextIndex),
               let fragments = prepared.pages.first {
                descriptors.append(HorizontalPageDescriptor(
                    id: horizontalPageID(chapterID: nextChapter.id, pageIndex: 0),
                    content: .page(
                        fragments: fragments,
                        chapterTitle: nextChapter.title
                    )
                ))
            } else {
                descriptors.append(HorizontalPageDescriptor(
                    id: HorizontalPageID.boundary(
                        ownerChapterID: chapter.id,
                        targetChapterID: nextChapter.id,
                        direction: .next
                    ),
                    content: .boundary(
                        label: "下一章",
                        chapterTitle: nextChapter.title
                    )
                ))
            }
        }

        return descriptors
    }

    private func shouldKeepPendingBoundaryPreview(
        targetChapterID: UUID,
        direction: HorizontalDirection
    ) -> Bool {
        guard let pending = pendingHorizontalChapterTransition,
              pending.targetChapterID == targetChapterID,
              pending.direction == direction,
              case .boundary = pending.previewPageID else { return false }
        return true
    }

    private func preparedEntry(at chapterIndex: Int) -> ReaderPreparedChapterWindow.Entry? {
        guard chapters.indices.contains(chapterIndex),
              let layoutKey = currentLayoutKey else { return nil }
        let chapter = chapters[chapterIndex]
        guard let entry = preparedChapterWindow.preparedEntry(
            chapterID: chapter.id,
            sourceIdentity: sourceIdentity(for: chapter),
            layoutKey: layoutKey
        ), entry.pages.contains(where: { !$0.isEmpty }) else { return nil }
        return entry
    }

    private func horizontalPageID(chapterID: UUID, pageIndex: Int) -> HorizontalPageID {
        .page(chapterID: chapterID, pageIndex: pageIndex)
    }

    private func currentHorizontalPageID(pageIndex: Int) -> HorizontalPageID? {
        guard let chapter = currentChapter else { return nil }
        return horizontalPageID(chapterID: chapter.id, pageIndex: pageIndex)
    }

    private func boundaryPageID(
        ownerChapterID: UUID,
        targetChapterID: UUID,
        direction: HorizontalDirection
    ) -> HorizontalPageID {
        .boundary(
            ownerChapterID: ownerChapterID,
            targetChapterID: targetChapterID,
            direction: direction
        )
    }

    private func legacyBoundaryPageID(
        ownerChapterID: UUID,
        direction: HorizontalDirection
    ) -> HorizontalPageID? {
        let targetIndex = direction == .previous
            ? currentChapterIndex - 1
            : currentChapterIndex + 1
        guard chapters.indices.contains(targetIndex) else { return nil }
        return boundaryPageID(
            ownerChapterID: ownerChapterID,
            targetChapterID: chapters[targetIndex].id,
            direction: direction
        )
    }

    private func continuousPreviewPageID(
        direction: HorizontalDirection
    ) -> HorizontalPageID? {
        guard let chapter = currentChapter else { return nil }
        let targetIndex = direction == .previous
            ? currentChapterIndex - 1
            : currentChapterIndex + 1
        guard chapters.indices.contains(targetIndex) else { return nil }
        let targetChapter = chapters[targetIndex]
        if let prepared = preparedEntry(at: targetIndex) {
            let pageIndex = direction == .previous
                ? max(prepared.pages.count - 1, 0)
                : 0
            return horizontalPageID(chapterID: targetChapter.id, pageIndex: pageIndex)
        }
        return .boundary(
            ownerChapterID: chapter.id,
            targetChapterID: targetChapter.id,
            direction: direction
        )
    }

    @available(iOS 18.0, *)
    private func handleContinuousHorizontalScrollPosition(_ newValue: HorizontalPageID?) {
        guard let newValue, let chapter = currentChapter else {
            if !isCommittingHorizontalChapterTransition {
                pendingHorizontalChapterTransition = nil
                horizontalTransitionCommitTask?.cancel()
                horizontalTransitionCommitTask = nil
            }
            return
        }
        if case let .page(chapterID, pageIndex) = newValue,
           chapterID == chapter.id {
            pendingHorizontalChapterTransition = nil
            horizontalTransitionCommitTask?.cancel()
            horizontalTransitionCommitTask = nil
            currentPageIndex = min(max(pageIndex, 0), max(cachedPages.count - 1, 0))
            return
        }

        for direction in [HorizontalDirection.previous, .next] {
            let targetIndex = direction == .previous
                ? currentChapterIndex - 1
                : currentChapterIndex + 1
            guard chapters.indices.contains(targetIndex) else { continue }
            let targetChapter = chapters[targetIndex]

            let isMatchingPreview: Bool
            switch newValue {
            case let .page(chapterID, pageIndex):
                guard let prepared = preparedEntry(at: targetIndex) else {
                    isMatchingPreview = false
                    break
                }
                let expectedPageIndex = direction == .previous
                    ? max(prepared.pages.count - 1, 0)
                    : 0
                isMatchingPreview = chapterID == targetChapter.id
                    && pageIndex == expectedPageIndex
            case let .boundary(ownerChapterID, targetChapterID, boundaryDirection):
                isMatchingPreview = ownerChapterID == chapter.id
                    && targetChapterID == targetChapter.id
                    && boundaryDirection == direction
            case .legacyTrigger:
                isMatchingPreview = false
            }

            guard isMatchingPreview else { continue }
            pendingHorizontalChapterTransition = PendingHorizontalChapterTransition(
                direction: direction,
                targetChapterID: targetChapter.id,
                previewPageID: newValue
            )
            if isHorizontalScrollIdle {
                schedulePendingHorizontalChapterCommit()
            }
            return
        }

        pendingHorizontalChapterTransition = nil
        horizontalTransitionCommitTask?.cancel()
        horizontalTransitionCommitTask = nil
    }

    @available(iOS 18.0, *)
    private func schedulePendingHorizontalChapterCommit() {
        horizontalTransitionCommitTask?.cancel()
        horizontalTransitionCommitTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            horizontalTransitionCommitTask = nil
            attemptPendingHorizontalChapterCommit()
        }
    }

    @available(iOS 18.0, *)
    private func scheduleHorizontalScrollIdleFinalization() {
        horizontalIdleFinalizationTask?.cancel()
        horizontalIdleFinalizationTask = Task { @MainActor in
            // scrollPosition's final binding update can be delivered just after
            // the phase becomes idle. Keep the frozen strip for that turn.
            await Task.yield()
            await Task.yield()
            guard !Task.isCancelled,
                  isHorizontalScrollIdle,
                  settings.pageMode == .horizontal else { return }

            handleContinuousHorizontalScrollPosition(scrolledPage)
            attemptPendingHorizontalChapterCommit()
            if pendingHorizontalChapterTransition == nil,
               !isCommittingHorizontalChapterTransition {
                horizontalPageDescriptorSnapshot = nil
            }
            horizontalIdleFinalizationTask = nil
        }
    }

    @available(iOS 18.0, *)
    private func animateContinuousHorizontalScroll(to pageID: HorizontalPageID) {
        if isHorizontalScrollIdle {
            horizontalPageDescriptorSnapshot = continuousHorizontalPageDescriptors(
                currentPages: cachedPages
            )
        }
        isHorizontalScrollIdle = false

        // A programmatic scroll normally reports `.animating` and then `.idle`.
        // Keep a fallback for accessibility/reduced-motion cases where SwiftUI
        // changes the binding without emitting a phase cycle.
        horizontalProgrammaticScrollFallbackTask?.cancel()
        horizontalProgrammaticScrollFallbackTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 400_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled, scrolledPage == pageID else { return }
            horizontalProgrammaticScrollFallbackTask = nil
            isHorizontalScrollIdle = true
            handleContinuousHorizontalScrollPosition(scrolledPage)
            attemptPendingHorizontalChapterCommit()
            if pendingHorizontalChapterTransition == nil,
               !isCommittingHorizontalChapterTransition {
                horizontalPageDescriptorSnapshot = nil
            }
        }

        withAnimation(.easeOut(duration: 0.28)) {
            scrolledPage = pageID
        }
    }

    @available(iOS 18.0, *)
    private func attemptPendingHorizontalChapterCommit() {
        guard settings.pageMode == .horizontal,
              isHorizontalScrollIdle,
              !isCommittingHorizontalChapterTransition,
              let pending = pendingHorizontalChapterTransition,
              scrolledPage == pending.previewPageID else { return }

        let targetIndex = pending.direction == .previous
            ? currentChapterIndex - 1
            : currentChapterIndex + 1
        guard chapters.indices.contains(targetIndex),
              chapters[targetIndex].id == pending.targetChapterID else { return }

        let prepared = preparedEntry(at: targetIndex)
        let targetPageIndex: Int
        switch pending.previewPageID {
        case let .page(chapterID, pageIndex):
            guard chapterID == pending.targetChapterID,
                  let prepared,
                  !prepared.pages.isEmpty else { return }
            let expectedPageIndex = pending.direction == .previous
                ? max(prepared.pages.count - 1, 0)
                : 0
            guard pageIndex == expectedPageIndex else { return }
            targetPageIndex = expectedPageIndex
        case .boundary:
            // A cold or failed preparation must not trap the reader on the
            // boundary forever. Commit at rest and let the normal chapter load
            // path take over; a ready entry still preserves the exact anchor.
            if let prepared, !prepared.pages.isEmpty {
                targetPageIndex = pending.direction == .previous
                    ? max(prepared.pages.count - 1, 0)
                    : 0
            } else {
                targetPageIndex = 0
            }
        case .legacyTrigger:
            return
        }
        let activatedPageID = horizontalPageID(
            chapterID: pending.targetChapterID,
            pageIndex: targetPageIndex
        )

        isCommittingHorizontalChapterTransition = true
        horizontalTransitionCommitTask?.cancel()
        horizontalTransitionCommitTask = nil
        withTransaction(Transaction(animation: nil)) {
            if let prepared {
                currentChapterContent = prepared.content
                cachedParagraphs = prepared.paragraphs
                cachedPages = prepared.pages
                currentPageIndex = targetPageIndex
                pendingPagePosition = nil
                isLoadingContent = false
                isPaginating = false
                loadError = nil
            } else {
                // Never re-label the old chapter's pages with the target
                // chapter ID while the cold fallback starts loading.
                currentChapterContent = nil
                cachedParagraphs = []
                cachedPages = [[]]
                currentPageIndex = 0
                pendingPagePosition = pending.direction == .previous ? .last : .first
            }
            scrolledPage = activatedPageID
            pendingHorizontalChapterTransition = nil
            horizontalPageDescriptorSnapshot = nil
            skipPageReset = pending.direction == .previous
            currentChapterIndex = targetIndex
        }
    }

    private func handleLegacyHorizontalScrollPosition(_ newValue: HorizontalPageID?) {
        guard let newValue, let chapter = currentChapter else { return }
        switch newValue {
        case let .legacyTrigger(ownerChapterID, direction)
            where ownerChapterID == chapter.id:
            if direction == .previous, currentChapterIndex > 0 {
                skipPageReset = true
                currentChapterIndex -= 1
            } else if direction == .next, currentChapterIndex + 1 < chapters.count {
                currentChapterIndex += 1
            }
        case let .page(chapterID, pageIndex) where chapterID == chapter.id:
            currentPageIndex = min(max(pageIndex, 0), max(cachedPages.count - 1, 0))
        default:
            break
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

    private func pageView(
        fragments: [PageFragment],
        chapterTitle: String? = nil
    ) -> some View {
        StaticPageView(
            fragments: fragments,
            chapterTitle: chapterTitle ?? currentChapter?.title ?? "",
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

        let hasPrev = currentChapterIndex > 0
        let hasNext = currentChapterIndex < chapters.count - 1

        if location.x < screenSize.width / 3 {
            // Tap left — go back
            if settings.pageMode == .tap {
                if tapSentinel == .prev {
                    tapSentinel = nil
                    skipPageReset = true
                    currentChapterIndex -= 1
                } else if tapSentinel == .next {
                    tapSentinel = nil
                } else if currentPageIndex > 0 {
                    currentPageIndex -= 1
                } else if hasPrev {
                    tapSentinel = .prev
                }
            } else {
                handleHorizontalPageTap(
                    direction: .previous,
                    totalPages: totalPages,
                    hasPrev: hasPrev,
                    hasNext: hasNext
                )
            }
        } else if location.x > screenSize.width * 2 / 3 {
            // Tap right — go forward
            if settings.pageMode == .tap {
                if tapSentinel == .next {
                    tapSentinel = nil
                    currentChapterIndex += 1
                } else if tapSentinel == .prev {
                    tapSentinel = nil
                } else if currentPageIndex < totalPages - 1 {
                    currentPageIndex += 1
                } else if hasNext {
                    tapSentinel = .next
                }
            } else {
                handleHorizontalPageTap(
                    direction: .next,
                    totalPages: totalPages,
                    hasPrev: hasPrev,
                    hasNext: hasNext
                )
            }
        }
    }

    private func handleHorizontalPageTap(
        direction: HorizontalDirection,
        totalPages: Int,
        hasPrev: Bool,
        hasNext: Bool
    ) {
        guard let chapter = currentChapter else { return }

        if #available(iOS 18.0, *) {
            if let pending = pendingHorizontalChapterTransition {
                // A repeated tap in the transition direction must not enqueue a
                // second chapter change. The opposite direction returns to the
                // edge page of the still-current chapter.
                guard pending.direction != direction else { return }
                pendingHorizontalChapterTransition = nil
                horizontalTransitionCommitTask?.cancel()
                horizontalTransitionCommitTask = nil
                let edgePageIndex = pending.direction == .previous
                    ? 0
                    : max(totalPages - 1, 0)
                currentPageIndex = edgePageIndex
                animateContinuousHorizontalScroll(to: horizontalPageID(
                    chapterID: chapter.id,
                    pageIndex: edgePageIndex
                ))
                return
            }

            if direction == .previous {
                if currentPageIndex > 0 {
                    currentPageIndex -= 1
                    animateContinuousHorizontalScroll(to: horizontalPageID(
                        chapterID: chapter.id,
                        pageIndex: currentPageIndex
                    ))
                } else if hasPrev,
                          let previewPageID = continuousPreviewPageID(direction: .previous) {
                    animateContinuousHorizontalScroll(to: previewPageID)
                }
            } else if currentPageIndex < totalPages - 1 {
                currentPageIndex += 1
                animateContinuousHorizontalScroll(to: horizontalPageID(
                    chapterID: chapter.id,
                    pageIndex: currentPageIndex
                ))
            } else if hasNext,
                      let previewPageID = continuousPreviewPageID(direction: .next) {
                animateContinuousHorizontalScroll(to: previewPageID)
            }
            return
        }

        let previousBoundary = legacyBoundaryPageID(
            ownerChapterID: chapter.id,
            direction: .previous
        )
        let nextBoundary = legacyBoundaryPageID(
            ownerChapterID: chapter.id,
            direction: .next
        )
        if direction == .previous {
            if scrolledPage == previousBoundary, hasPrev {
                scrolledPage = .legacyTrigger(
                    ownerChapterID: chapter.id,
                    direction: .previous
                )
            } else if scrolledPage == nextBoundary {
                currentPageIndex = max(totalPages - 1, 0)
                scrolledPage = currentHorizontalPageID(pageIndex: currentPageIndex)
            } else if currentPageIndex > 0 {
                currentPageIndex -= 1
                scrolledPage = currentHorizontalPageID(pageIndex: currentPageIndex)
            } else if hasPrev {
                scrolledPage = previousBoundary
            }
        } else if scrolledPage == nextBoundary, hasNext {
            scrolledPage = .legacyTrigger(
                ownerChapterID: chapter.id,
                direction: .next
            )
        } else if scrolledPage == previousBoundary {
            currentPageIndex = 0
            scrolledPage = currentHorizontalPageID(pageIndex: 0)
        } else if currentPageIndex < totalPages - 1 {
            currentPageIndex += 1
            scrolledPage = currentHorizontalPageID(pageIndex: currentPageIndex)
        } else if hasNext {
            scrolledPage = nextBoundary
        }
    }

    // MARK: - Page Splitting

    struct PageFragment: Identifiable, Sendable {
        let id: Int
        let text: String
        let indent: Bool
    }

    private var hasRenderableCurrentChapter: Bool {
        switch settings.pageMode {
        case .scroll:
            return !cachedParagraphs.isEmpty
        case .horizontal, .tap:
            return cachedPages.contains { !$0.isEmpty }
        }
    }

    private func quantizedLayoutDimension(_ value: CGFloat) -> Double {
        let scale = max(UIScreen.main.scale, 1)
        return Double((value * scale).rounded() / scale)
    }

    private var currentLayoutKey: ReaderChapterLayoutKey? {
        guard viewSize.width > 0, viewSize.height > 0 else { return nil }
        return ReaderChapterLayoutKey(
            width: quantizedLayoutDimension(viewSize.width),
            height: quantizedLayoutDimension(viewSize.height),
            fontSize: Double(settings.fontSize),
            lineSpacing: settings.lineSpacing,
            fontFamily: settings.fontFamily.rawValue,
            usesSystemFont: settings.fontFamily.isSystem,
            horizontalPadding: Double(settings.horizontalPadding),
            bottomReserve: Double(pageBottomReserve)
        )
    }

    private func makePaginationInput(content: String) -> PaginationInput {
        PaginationInput(
            content: content,
            width: quantizedLayoutDimension(viewSize.width),
            height: quantizedLayoutDimension(viewSize.height),
            fontSize: Double(settings.fontSize),
            lineSpacing: settings.lineSpacing,
            fontFamily: settings.fontFamily.rawValue,
            usesSystemFont: settings.fontFamily.isSystem,
            horizontalPadding: Double(settings.horizontalPadding),
            bottomReserve: Double(pageBottomReserve)
        )
    }

    private func updateReaderGeometry(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let hasSamePixelSize = quantizedLayoutDimension(viewSize.width)
                == quantizedLayoutDimension(size.width)
            && quantizedLayoutDimension(viewSize.height)
                == quantizedLayoutDimension(size.height)
        guard !hasSamePixelSize else {
            viewSize = size
            if currentChapterContent != nil, !hasRenderableCurrentChapter {
                recomputePages()
            }
            return
        }
        viewSize = size
        readerLayoutDidChange()
    }

    private func readerLayoutDidChange(delayNanoseconds: UInt64 = 0) {
        cancelPendingHorizontalChapterTransition(returningToCurrentPage: true)
        adjacentPreparationTask?.cancel()
        adjacentPreparationTask = nil
        adjacentPreparationGeneration = nil
        adjacentPreparationActiveChapterID = nil
        preparedChapterWindow.invalidateLayouts()
        recomputePages(delayNanoseconds: delayNanoseconds)
    }

    private func cancelPendingHorizontalChapterTransition(
        returningToCurrentPage: Bool
    ) {
        let hadPendingTransition = pendingHorizontalChapterTransition != nil
        pendingHorizontalChapterTransition = nil
        horizontalTransitionCommitTask?.cancel()
        horizontalTransitionCommitTask = nil
        horizontalProgrammaticScrollFallbackTask?.cancel()
        horizontalProgrammaticScrollFallbackTask = nil
        horizontalIdleFinalizationTask?.cancel()
        horizontalIdleFinalizationTask = nil
        horizontalPageDescriptorSnapshot = nil
        isHorizontalScrollIdle = true
        isCommittingHorizontalChapterTransition = false
        if hadPendingTransition, returningToCurrentPage {
            scrolledPage = currentHorizontalPageID(pageIndex: currentPageIndex)
        }
    }

    @discardableResult
    private func cancelCurrentChapterRendering(
        preservingAdjacentFor chapterID: UUID?
    ) -> Task<Void, Never>? {
        let shouldRetainAdjacent = chapterID == adjacentPreparationActiveChapterID
        let retainedAdjacentPreparation = shouldRetainAdjacent
            ? adjacentPreparationTask
            : nil
        chapterLoadTask?.cancel()
        chapterLoadTask = nil
        loadingIndicatorTask?.cancel()
        loadingIndicatorTask = nil
        paginationIndicatorTask?.cancel()
        paginationIndicatorTask = nil
        paginationTask?.cancel()
        paginationTask = nil
        if retainedAdjacentPreparation == nil {
            adjacentPreparationTask?.cancel()
            adjacentPreparationTask = nil
            adjacentPreparationGeneration = nil
            adjacentPreparationActiveChapterID = nil
        }
        prefetchTask?.cancel()
        prefetchTask = nil
        contentLoadGeneration = UUID()
        paginationGeneration = UUID()
        isLoadingContent = false
        isPaginating = false
        loadError = nil
        return retainedAdjacentPreparation
    }

    private func scheduleReaderMetadataSave() {
        readerMetadataSaveTask?.cancel()
        readerMetadataSaveTask = Task {
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            try? modelContext.save()
            readerMetadataSaveTask = nil
        }
    }

    private func scheduleTerminalCacheReconciliation() {
        guard terminalCacheReconciliationTask == nil,
              currentChapterContent != nil,
              !cachedParagraphs.isEmpty else { return }
        terminalCacheReconciliationTask = Task(priority: .utility) {
            do {
                // Let the hot next-chapter disk lookup and pagination win the
                // actor/CPU race before any cold whole-book validation scan.
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return
            }
            await synchronizeChapterDownloadSnapshot()
            if !Task.isCancelled, isCheckingCacheSummary {
                await refreshUserManagedCacheSummary()
            }
            terminalCacheReconciliationTask = nil
        }
    }

    private func trimPreparedChapterWindow() {
        let chapterIDs = ReaderPreparedChapterWindow.adjacentIndices(
            currentIndex: currentChapterIndex,
            chapterCount: chapters.count,
            includingCurrent: true
        ).map { chapters[$0].id }
        preparedChapterWindow.retain(chapterIDs: Set(chapterIDs))
    }

    private func sourceIdentity(for chapter: Chapter) -> ReaderChapterSourceIdentity {
        ReaderChapterSourceIdentity(
            bookSourceID: book.sourceId,
            chapterSourceURL: chapter.sourceURL
        )
    }

    private func activatePreparedChapter(
        position: PaginationPosition
    ) -> PreparedChapterActivation {
        guard let chapter = currentChapter else { return .unavailable }
        let sourceIdentity = sourceIdentity(for: chapter)

        let prepared: ReaderPreparedChapterWindow.Entry?
        if settings.pageMode == .scroll {
            prepared = preparedChapterWindow.parsedEntry(
                chapterID: chapter.id,
                sourceIdentity: sourceIdentity
            )
        } else if let layoutKey = currentLayoutKey {
            prepared = preparedChapterWindow.preparedEntry(
                chapterID: chapter.id,
                sourceIdentity: sourceIdentity,
                layoutKey: layoutKey
            )
        } else {
            prepared = nil
        }
        guard let prepared else {
            guard let contentOnly = preparedChapterWindow.entry(
                chapterID: chapter.id,
                sourceIdentity: sourceIdentity
            ) else { return .unavailable }
            withTransaction(Transaction(animation: nil)) {
                currentChapterContent = contentOnly.content
                cachedParagraphs = contentOnly.paragraphs
                cachedPages = [[]]
                currentPageIndex = 0
                scrolledPage = horizontalPageID(chapterID: chapter.id, pageIndex: 0)
                pendingPagePosition = position
                isLoadingContent = false
                isPaginating = false
                loadError = nil
            }
            return .contentOnly
        }

        withTransaction(Transaction(animation: nil)) {
            currentChapterContent = prepared.content
            cachedParagraphs = prepared.paragraphs
            cachedPages = prepared.pages
            switch position {
            case .first:
                currentPageIndex = 0
            case .last:
                currentPageIndex = max(prepared.pages.count - 1, 0)
            case .preserve:
                currentPageIndex = min(currentPageIndex, max(prepared.pages.count - 1, 0))
            }
            scrolledPage = horizontalPageID(
                chapterID: chapter.id,
                pageIndex: currentPageIndex
            )
            pendingPagePosition = nil
            isLoadingContent = false
            isPaginating = false
            loadError = nil
        }
        return .rendered
    }

    private func activatePreparedChapterWhenReady(
        _ preparationTask: Task<Void, Never>,
        chapterID: UUID,
        capturedSourceIdentity: ReaderChapterSourceIdentity,
        position: PaginationPosition
    ) {
        chapterLoadTask?.cancel()
        loadingIndicatorTask?.cancel()
        let generation = UUID()
        contentLoadGeneration = generation
        isLoadingContent = false
        scheduleLoadingIndicator(
            generation: generation,
            chapterID: chapterID,
            capturedSourceIdentity: capturedSourceIdentity
        )

        chapterLoadTask = Task {
            await preparationTask.value
            guard !Task.isCancelled,
                  contentLoadGeneration == generation else {
                finishChapterLoadIfCurrent(generation: generation)
                return
            }
            guard currentChapter?.id == chapterID,
                  currentChapter.map(sourceIdentity(for:)) == capturedSourceIdentity else {
                finishChapterLoadIfCurrent(generation: generation)
                return
            }

            finishChapterLoadIfCurrent(generation: generation)
            switch activatePreparedChapter(position: position) {
            case .rendered:
                prepareAdjacentChapters()
                prefetchNextChapters()
            case .contentOnly:
                recomputePages(position: position)
                prefetchNextChapters()
            case .unavailable:
                fetchChapterContentIfNeeded()
            }
        }
    }

    private func prepareAdjacentChapters() {
        adjacentPreparationTask?.cancel()
        adjacentPreparationTask = nil
        adjacentPreparationGeneration = nil
        adjacentPreparationActiveChapterID = nil

        guard currentChapterContent != nil, !chapters.isEmpty else { return }
        let indices = ReaderPreparedChapterWindow.adjacentIndices(
            currentIndex: currentChapterIndex,
            chapterCount: chapters.count
        )
        guard !indices.isEmpty else { return }

        trimPreparedChapterWindow()
        let generation = UUID()
        adjacentPreparationGeneration = generation
        adjacentPreparationTask = Task(priority: .utility) {
            var didUpdateMetadata = false
            defer {
                if adjacentPreparationGeneration == generation {
                    adjacentPreparationTask = nil
                    adjacentPreparationGeneration = nil
                    adjacentPreparationActiveChapterID = nil
                    if didUpdateMetadata {
                        scheduleReaderMetadataSave()
                    }
                }
            }
            for index in indices {
                guard !Task.isCancelled,
                      adjacentPreparationGeneration == generation else { return }
                let relevantIndices = ReaderPreparedChapterWindow.adjacentIndices(
                    currentIndex: currentChapterIndex,
                    chapterCount: chapters.count,
                    includingCurrent: true
                )
                guard relevantIndices.contains(index) else { continue }
                let chapter = chapters[index]
                let chapterID = chapter.id
                adjacentPreparationActiveChapterID = chapterID
                let capturedSourceIdentity = sourceIdentity(for: chapter)

                if settings.pageMode == .scroll,
                   preparedChapterWindow.parsedEntry(
                    chapterID: chapterID,
                    sourceIdentity: capturedSourceIdentity
                   ) != nil {
                    continue
                }
                if let layoutKey = currentLayoutKey,
                   preparedChapterWindow.preparedEntry(
                    chapterID: chapterID,
                    sourceIdentity: capturedSourceIdentity,
                    layoutKey: layoutKey
                   ) != nil {
                    continue
                }

                let content: String
                if let storedContent = preparedChapterWindow.content(
                    chapterID: chapterID,
                    sourceIdentity: capturedSourceIdentity
                ) {
                    content = storedContent
                } else {
                    do {
                        content = try await loadContent(for: chapter)
                        try Task.checkCancellation()
                    } catch is CancellationError {
                        return
                    } catch {
                        continue
                    }
                    guard adjacentPreparationGeneration == generation,
                          sourceIdentity(for: chapter) == capturedSourceIdentity else { return }
                    preparedChapterWindow.storeContent(
                        content,
                        chapterID: chapterID,
                        sourceIdentity: capturedSourceIdentity
                    )
                    didUpdateMetadata = true
                }

                let input = makePaginationInput(content: content)
                let layoutKey = currentLayoutKey
                let worker = Task.detached(priority: .utility) {
                    Self.paginate(input)
                }
                let output = await withTaskCancellationHandler {
                    await worker.value
                } onCancel: {
                    worker.cancel()
                }

                guard !Task.isCancelled,
                      let output,
                      adjacentPreparationGeneration == generation,
                      sourceIdentity(for: chapter) == capturedSourceIdentity else { return }
                if output.didPaginate, currentLayoutKey != layoutKey {
                    continue
                }
                let stillRelevant = ReaderPreparedChapterWindow.adjacentIndices(
                    currentIndex: currentChapterIndex,
                    chapterCount: chapters.count,
                    includingCurrent: true
                ).contains(index)
                guard stillRelevant else { continue }
                preparedChapterWindow.store(
                    chapterID: chapterID,
                    sourceIdentity: capturedSourceIdentity,
                    content: content,
                    paragraphs: output.paragraphs,
                    pages: output.pages,
                    layoutKey: output.didPaginate ? layoutKey : nil
                )
                if #available(iOS 18.0, *) {
                    // The user may already be resting on the fallback boundary.
                    // Readiness changes do not move scrollPosition, so retry here.
                    attemptPendingHorizontalChapterCommit()
                    if isCommittingHorizontalChapterTransition { return }
                }
            }

        }
    }

    private func finishPaginationIfCurrent(generation: UUID) {
        guard paginationGeneration == generation else { return }
        paginationIndicatorTask?.cancel()
        paginationIndicatorTask = nil
        isPaginating = false
        paginationTask = nil
    }

    private func schedulePaginationIndicator(
        generation: UUID,
        chapterID: UUID,
        capturedSourceIdentity: ReaderChapterSourceIdentity
    ) {
        paginationIndicatorTask?.cancel()
        paginationIndicatorTask = Task {
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled,
                  paginationGeneration == generation,
                  currentChapter?.id == chapterID,
                  currentChapter.map(sourceIdentity(for:)) == capturedSourceIdentity,
                  currentChapterContent != nil,
                  !hasRenderableCurrentChapter else { return }
            isPaginating = true
        }
    }

    private func recomputePages(
        position: PaginationPosition = .preserve,
        delayNanoseconds: UInt64 = 0
    ) {
        paginationTask?.cancel()
        paginationIndicatorTask?.cancel()
        paginationIndicatorTask = nil
        isPaginating = false

        if position != .preserve {
            pendingPagePosition = position
            cachedParagraphs = []
            cachedPages = [[]]
            currentPageIndex = 0
            scrolledPage = currentHorizontalPageID(pageIndex: 0)
        }

        let generation = UUID()
        paginationGeneration = generation
        let chapterID = currentChapter?.id
        let chapterSourceIdentity = currentChapter.map(sourceIdentity(for:))
        let effectivePosition = pendingPagePosition ?? position
        let content = currentChapterContent ?? ""
        let input = makePaginationInput(content: content)
        let layoutKey = currentLayoutKey
        if !hasRenderableCurrentChapter,
           !input.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let chapterID,
           let chapterSourceIdentity {
            schedulePaginationIndicator(
                generation: generation,
                chapterID: chapterID,
                capturedSourceIdentity: chapterSourceIdentity
            )
        }

        paginationTask = Task {
            if delayNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                } catch {
                    finishPaginationIfCurrent(generation: generation)
                    return
                }
            }
            let worker = Task.detached(priority: .userInitiated) {
                let signposter = PerformanceSignposts.reader
                let signpostID = signposter.makeSignpostID()
                var result = "cancelled"
                var pageCount = 0
                let state = signposter.beginInterval(
                    "Pagination",
                    id: signpostID,
                    "characters=\(input.content.count)"
                )
                defer {
                    signposter.endInterval(
                        "Pagination",
                        state,
                        "result=\(result, privacy: .public) pages=\(pageCount)"
                    )
                }
                let output = Self.paginate(input)
                if let output {
                    result = "success"
                    pageCount = output.pages.count
                }
                return output
            }
            let output = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }

            guard !Task.isCancelled, let output else {
                finishPaginationIfCurrent(generation: generation)
                return
            }
            guard paginationGeneration == generation,
                  currentChapter?.id == chapterID,
                  currentChapter.map(sourceIdentity(for:)) == chapterSourceIdentity else {
                finishPaginationIfCurrent(generation: generation)
                return
            }

            cachedParagraphs = output.paragraphs
            cachedPages = output.pages
            if let chapterID, let chapterSourceIdentity, !content.isEmpty {
                preparedChapterWindow.store(
                    chapterID: chapterID,
                    sourceIdentity: chapterSourceIdentity,
                    content: content,
                    paragraphs: output.paragraphs,
                    pages: output.pages,
                    layoutKey: output.didPaginate ? layoutKey : nil
                )
                trimPreparedChapterWindow()
            }
            switch effectivePosition {
            case .first:
                currentPageIndex = 0
            case .last:
                currentPageIndex = max(output.pages.count - 1, 0)
            case .preserve:
                currentPageIndex = min(currentPageIndex, max(output.pages.count - 1, 0))
            }
            // A placeholder pass (empty content, single page) must not consume the
            // saved fraction, or reopening a book lands on page 1 again.
            if let fraction = restorePositionFraction, output.pages.count > 1 {
                restorePositionFraction = nil
                let lastPage = output.pages.count - 1
                currentPageIndex = min(max(Int((fraction * Double(lastPage)).rounded()), 0), lastPage)
            }
            scrolledPage = chapterID.map {
                horizontalPageID(chapterID: $0, pageIndex: currentPageIndex)
            }
            if output.didPaginate {
                pendingPagePosition = nil
            }
            finishPaginationIfCurrent(generation: generation)
            if adjacentPreparationTask == nil {
                prepareAdjacentChapters()
            }
            scheduleTerminalCacheReconciliation()
        }
    }

    nonisolated private static func paginate(_ input: PaginationInput) -> PaginationOutput? {
        guard !Task.isCancelled else { return nil }
        let text = SourceEngine.removeAdLines(input.content)
        let paragraphs = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard input.width > 0, input.height > 0 else {
            return PaginationOutput(paragraphs: paragraphs, pages: [[]], didPaginate: false)
        }
        guard !paragraphs.isEmpty else {
            return PaginationOutput(paragraphs: [], pages: [[]], didPaginate: false)
        }

        let textWidth = CGFloat(input.width - input.horizontalPadding * 2)
        let pageHeight = max(120, CGFloat(input.height - 20 - input.bottomReserve))
        let fontSize = CGFloat(input.fontSize)
        let lineSpacingValue = fontSize * CGFloat(input.lineSpacing - 1)
        let pageHeaderHeight = ceil(UIFont.systemFont(
            ofSize: ReaderPageHeaderMetrics.fontSize
        ).lineHeight) + ReaderPageHeaderMetrics.bottomPadding + lineSpacingValue

        let font: UIFont = input.usesSystemFont
            ? UIFont.systemFont(ofSize: fontSize)
            : UIFont(name: input.fontFamily, size: fontSize)
                ?? UIFont.systemFont(ofSize: fontSize)
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
        var currentHeight: CGFloat = pageHeaderHeight
        var fragmentId = 0

        while let item = queue.popLast() {
            guard !Task.isCancelled else { return nil }
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
                    currentHeight = pageHeaderHeight
                    queue.append(QueueItem(text: second, indent: false))
                } else {
                    fragmentId += 1
                    currentPage.append(PageFragment(id: fragmentId, text: item.text, indent: item.indent))
                    pages.append(currentPage)
                    currentPage = []
                    currentHeight = pageHeaderHeight
                }
            } else {
                let remaining = pageHeight - currentHeight - gap
                if remaining > font.lineHeight * 1.5,
                   let (first, second) = splitText(item.text, indent: item.indent, fitting: remaining) {
                    fragmentId += 1
                    currentPage.append(PageFragment(id: fragmentId, text: first, indent: item.indent))
                    pages.append(currentPage)
                    currentPage = []
                    currentHeight = pageHeaderHeight
                    queue.append(QueueItem(text: second, indent: false))
                } else {
                    pages.append(currentPage)
                    currentPage = []
                    currentHeight = pageHeaderHeight
                    queue.append(item)
                }
            }
        }

        if !currentPage.isEmpty {
            pages.append(currentPage)
        }

        return PaginationOutput(
            paragraphs: paragraphs,
            pages: pages.isEmpty ? [[]] : pages,
            didPaginate: true
        )
    }

    // MARK: - Content Fetching

    private func finishChapterLoadIfCurrent(generation: UUID) {
        guard contentLoadGeneration == generation else { return }
        loadingIndicatorTask?.cancel()
        loadingIndicatorTask = nil
        isLoadingContent = false
        isPaginating = false
        chapterLoadTask = nil
    }

    private func scheduleLoadingIndicator(
        generation: UUID,
        chapterID: UUID,
        capturedSourceIdentity: ReaderChapterSourceIdentity
    ) {
        loadingIndicatorTask?.cancel()
        loadingIndicatorTask = Task {
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled,
                  contentLoadGeneration == generation,
                  currentChapter?.id == chapterID,
                  currentChapter.map(sourceIdentity(for:)) == capturedSourceIdentity else { return }
            if currentChapterContent == nil {
                isLoadingContent = true
            } else if !hasRenderableCurrentChapter {
                isPaginating = true
            }
        }
    }

    private func fetchChapterContentIfNeeded() {
        chapterLoadTask?.cancel()
        prefetchTask?.cancel()
        loadingIndicatorTask?.cancel()

        guard let chapter = currentChapter else {
            chapterLoadTask = nil
            loadingIndicatorTask = nil
            isLoadingContent = false
            return
        }
        guard currentChapterContent == nil else {
            chapterLoadTask = nil
            loadingIndicatorTask = nil
            isLoadingContent = false
            return
        }

        let chapterID = chapter.id
        let capturedSourceIdentity = sourceIdentity(for: chapter)
        let generation = UUID()
        contentLoadGeneration = generation
        isLoadingContent = false
        loadError = nil
        scheduleLoadingIndicator(
            generation: generation,
            chapterID: chapterID,
            capturedSourceIdentity: capturedSourceIdentity
        )

        chapterLoadTask = Task {
            let signposter = PerformanceSignposts.reader
            let signpostID = signposter.makeSignpostID()
            var intervalResult = "cancelled"
            var characterCount = 0
            let intervalState = signposter.beginInterval("ReaderContentLoad", id: signpostID)
            defer {
                signposter.endInterval(
                    "ReaderContentLoad",
                    intervalState,
                    "result=\(intervalResult, privacy: .public) characters=\(characterCount)"
                )
            }
            do {
                let content = try await loadContent(for: chapter)
                try Task.checkCancellation()
                guard contentLoadGeneration == generation else { return }
                guard currentChapter?.id == chapterID,
                      sourceIdentity(for: chapter) == capturedSourceIdentity else {
                    finishChapterLoadIfCurrent(generation: generation)
                    return
                }
                currentChapterContent = content
                preparedChapterWindow.storeContent(
                    content,
                    chapterID: chapterID,
                    sourceIdentity: capturedSourceIdentity
                )
                intervalResult = "success"
                characterCount = content.count
                // Begin the lower-priority next/previous preparation as soon as
                // the current body is available. Current pagination remains
                // user-initiated and wins CPU scheduling.
                prepareAdjacentChapters()
                recomputePages()
                finishChapterLoadIfCurrent(generation: generation)
                prefetchNextChapters()
                scheduleReaderMetadataSave()
            } catch is CancellationError {
                intervalResult = "cancelled"
                finishChapterLoadIfCurrent(generation: generation)
            } catch {
                intervalResult = "error"
                guard contentLoadGeneration == generation else { return }
                guard currentChapter?.id == chapterID,
                      sourceIdentity(for: chapter) == capturedSourceIdentity else {
                    finishChapterLoadIfCurrent(generation: generation)
                    return
                }
                let detail: String
                switch error {
                case NetworkError.invalidURL:
                    detail = "无效的章节链接\n可尝试单章换源或返回书架「换源」"
                case NetworkError.httpError(let code):
                    detail = "服务器返回错误（\(code)）\n可尝试单章换源或返回书架「换源」"
                case NetworkError.requestFailed:
                    detail = "服务器无响应\n可尝试单章换源或返回书架「换源」"
                case let urlError as URLError where urlError.code == .timedOut:
                    detail = "请求超时，可点击重试"
                case is URLError:
                    detail = "网络连接异常，请检查网络"
                case ContentLoadError.noSourceId, ContentLoadError.sourceNotFound:
                    detail = "书源丢失\n请返回书架「换源」"
                case ContentLoadError.noContentRule:
                    detail = "该书源无内容解析规则\n请返回书架「换源」"
                case ContentLoadError.emptyContent:
                    detail = "章节内容为空\n可尝试单章换源或返回书架「换源」"
                case ContentLoadError.invalidContent(let reason):
                    detail = "\(reason)\n可尝试单章换源或返回书架「换源」"
                default:
                    detail = "加载失败\n\(error.localizedDescription)"
                }
                print("[ReaderView] fetchContent error: \(error)")
                loadError = detail
                finishChapterLoadIfCurrent(generation: generation)
            }
        }
    }

    private static let maxRetries = 3

    private func loadContent(for chapter: Chapter) async throws -> String {
        if chapter.sourceURL == nil {
            guard let content = chapter.content,
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ContentLoadError.emptyContent
            }
            return content
        }

        // Capture the book generation before the first cache suspension in
        // this logical load. Reusing it through disk lookup and networking
        // prevents a clear/source switch that lands between those stages from
        // granting the old request a fresh write generation.
        let operationToken = await ChapterContentStore.shared.makeWriteToken(bookID: book.id)

        if let legacy = chapter.content, SourceEngine.isValidContent(legacy) {
            let retention: ChapterCacheRetention = chapter.isCached ? .userManaged : .automatic
            do {
                let outcome = try await ChapterContentStore.shared.store(
                    legacy,
                    bookID: book.id,
                    chapterID: chapter.id,
                    retention: retention,
                    writeToken: operationToken
                )
                guard !Task.isCancelled,
                      await ChapterContentStore.shared.isWriteTokenCurrent(
                        operationToken,
                        bookID: book.id,
                        chapterID: chapter.id
                      ) else { throw CancellationError() }
                if outcome.isStored {
                    chapter.content = nil
                }
                chapter.isCached = outcome.effectiveRetention == .userManaged
            } catch is CancellationError {
                throw CancellationError()
            } catch ChapterContentStoreError.staleWrite {
                throw CancellationError()
            } catch {
                // Keep legacy SwiftData content as a safe fallback when disk persistence fails.
                try Task.checkCancellation()
                guard await ChapterContentStore.shared.isWriteTokenCurrent(
                    operationToken,
                    bookID: book.id,
                    chapterID: chapter.id
                ) else { throw CancellationError() }
            }
            return legacy
        }

        if let stored = await ChapterContentStore.shared.load(bookID: book.id, chapterID: chapter.id) {
            try Task.checkCancellation()
            guard await ChapterContentStore.shared.isWriteTokenCurrent(
                operationToken,
                bookID: book.id,
                chapterID: chapter.id
            ) else { throw CancellationError() }
            chapter.isCached = stored.retention == .userManaged
            return stored.content
        }

        try Task.checkCancellation()
        guard await ChapterContentStore.shared.isWriteTokenCurrent(
            operationToken,
            bookID: book.id,
            chapterID: chapter.id
        ) else { throw CancellationError() }
        chapter.isCached = false
        let content = try await fetchRemoteContent(for: chapter)
        try Task.checkCancellation()
        guard await persistRemoteContent(
            content,
            for: chapter,
            retention: .automatic,
            writeToken: operationToken
        ) else { throw CancellationError() }
        return content
    }

    private func fetchRemoteContent(for chapter: Chapter) async throws -> String {
        guard let sourceURL = chapter.sourceURL else { throw ContentLoadError.emptyContent }
        guard let bookSourceId = book.sourceId else { throw ContentLoadError.noSourceId }

        let descriptor = FetchDescriptor<BookSource>(predicate: #Predicate<BookSource> { $0.id == bookSourceId })
        guard let bookSource = try modelContext.fetch(descriptor).first else { throw ContentLoadError.sourceNotFound }
        let legado = try LegadoSourceParser.parse(json: bookSource.ruleJSON, matchingURL: bookSource.sourceURL)
        guard let contentRule = legado.contentRule else { throw ContentLoadError.noContentRule }
        let nextChapterURL = chapters.first(where: { $0.index == chapter.index + 1 })?.sourceURL

        // Retry up to 3 times with increasing delay
        var lastError: Error = NetworkError.requestFailed
        for attempt in 1...Self.maxRetries {
            do {
                guard let content = try await ChapterContentLoader.shared.fetch(
                    ChapterContentRequest(
                        url: sourceURL,
                        rule: contentRule,
                        baseURL: legado.url,
                        nextChapterURL: nextChapterURL
                    )
                ) else {
                    throw ContentLoadError.emptyContent
                }
                try Task.checkCancellation()
                if let reason = SourceEngine.contentValidationError(content) {
                    throw ContentLoadError.invalidContent(reason)
                }
                return content
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as ContentLoadError {
                throw error
            } catch {
                lastError = error
                if attempt < Self.maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                }
            }
        }
        throw lastError
    }

    private func persistRemoteContent(
        _ content: String,
        for chapter: Chapter,
        retention: ChapterCacheRetention,
        writeToken: ChapterContentWriteToken
    ) async -> Bool {
        do {
            let outcome = try await ChapterContentStore.shared.store(
                content,
                bookID: book.id,
                chapterID: chapter.id,
                retention: retention,
                writeToken: writeToken
            )
            guard !Task.isCancelled,
                  await ChapterContentStore.shared.isWriteTokenCurrent(
                    writeToken,
                    bookID: book.id,
                    chapterID: chapter.id
                  ) else { return false }
            // Oversized automatic entries deliberately stay in SwiftData so a
            // later launch cannot fall back to an older disk copy.
            chapter.content = outcome.isStored ? nil : content
            chapter.isCached = outcome.effectiveRetention == .userManaged
            return true
        } catch is CancellationError {
            return false
        } catch ChapterContentStoreError.staleWrite {
            // A clear, source switch, or deletion superseded this fetch.
            // Do not resurrect either disk or SwiftData cache state.
            return false
        } catch {
            guard !Task.isCancelled,
                  await ChapterContentStore.shared.isWriteTokenCurrent(
                    writeToken,
                    bookID: book.id,
                    chapterID: chapter.id
                  ) else { return false }
            // Preserve the previous SwiftData behavior if the cache directory is unavailable.
            chapter.content = content
            chapter.isCached = retention == .userManaged
            return true
        }
    }

    private func persistReplacementContent(
        _ content: String,
        for chapter: Chapter,
        retention: ChapterCacheRetention,
        writeToken: ChapterContentWriteToken
    ) async throws {
        let replacement: ChapterContentReplacement
        do {
            replacement = try await ChapterContentStore.shared.replace(
                content,
                bookID: book.id,
                chapterID: chapter.id,
                retention: retention,
                writeToken: writeToken
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch ChapterContentStoreError.staleWrite {
            throw CancellationError()
        }

        guard !Task.isCancelled,
              await ChapterContentStore.shared.isWriteTokenCurrent(
                replacement.writeToken,
                bookID: book.id,
                chapterID: chapter.id
              ) else { throw CancellationError() }

        let previousContent = chapter.content
        let previousCachedState = chapter.isCached
        chapter.content = replacement.outcome?.isStored == true ? nil : content
        chapter.isCached = replacement.retention == .userManaged

        if replacement.outcome?.isStored != true {
            do {
                try modelContext.save()
            } catch {
                chapter.content = previousContent
                chapter.isCached = previousCachedState
                throw ChapterSourceSwitchError.persistenceFailed
            }
        }
    }

    private func startCurrentChapterSourceSwitch() {
        chapterSourceSwitchTask?.cancel()
        chapterLoadTask?.cancel()
        chapterLoadTask = nil
        loadingIndicatorTask?.cancel()
        loadingIndicatorTask = nil
        contentLoadGeneration = UUID()
        isLoadingContent = false
        adjacentPreparationTask?.cancel()
        adjacentPreparationTask = nil
        adjacentPreparationGeneration = nil
        adjacentPreparationActiveChapterID = nil
        let generation = UUID()
        chapterSourceSwitchGeneration = generation
        chapterSourceSwitchTask = Task { await switchCurrentChapterSource(generation: generation) }
    }

    private func switchCurrentChapterSource(generation: UUID) async {
        guard let chapter = currentChapter, !isSwitchingChapterSource else { return }
        let chapterID = chapter.id
        let originalError = loadError

        isSwitchingChapterSource = true
        do {
            let writeToken = await ChapterContentStore.shared.makeWriteToken(bookID: book.id)
            let cachedBeforeReplacement = await ChapterContentStore.shared.load(
                bookID: book.id,
                chapterID: chapter.id
            )
            guard await ChapterContentStore.shared.isWriteTokenCurrent(
                writeToken,
                bookID: book.id,
                chapterID: chapter.id
            ) else { throw CancellationError() }
            let replacementRetention: ChapterCacheRetention = chapter.isCached
                || cachedBeforeReplacement?.retention == .userManaged
                ? .userManaged
                : .automatic
            let content = try await fetchContentFromAlternativeSource(for: chapter)
            try Task.checkCancellation()
            guard chapterSourceSwitchGeneration == generation,
                  currentChapter?.id == chapterID else { throw CancellationError() }
            try await persistReplacementContent(
                content,
                for: chapter,
                retention: replacementRetention,
                writeToken: writeToken
            )
            try Task.checkCancellation()
            guard chapterSourceSwitchGeneration == generation else { return }
            isSwitchingChapterSource = false
            chapterSourceSwitchGeneration = nil
            chapterSourceSwitchTask = nil
            if currentChapter?.id == chapter.id {
                preparedChapterWindow.remove(chapterID: chapter.id)
                preparedChapterWindow.storeContent(
                    content,
                    chapterID: chapter.id,
                    sourceIdentity: sourceIdentity(for: chapter)
                )
                currentChapterContent = content
                loadError = nil
                recomputePages()
            }
            try? modelContext.save()
        } catch is CancellationError {
            if chapterSourceSwitchGeneration == generation {
                isSwitchingChapterSource = false
                chapterSourceSwitchGeneration = nil
                chapterSourceSwitchTask = nil
            }
        } catch {
            guard chapterSourceSwitchGeneration == generation else { return }
            let message = describeChapterSourceSwitchError(error)
            loadError = [originalError, "单章换源失败：\(message)"]
                .compactMap { $0 }
                .joined(separator: "\n")
            isSwitchingChapterSource = false
            chapterSourceSwitchGeneration = nil
            chapterSourceSwitchTask = nil
        }
    }

    private func fetchContentFromAlternativeSource(for chapter: Chapter) async throws -> String {
        let candidates = try alternativeSourceCandidates()
        guard !candidates.isEmpty else { throw ChapterSourceSwitchError.noAlternativeSource }

        for candidate in candidates {
            guard !Task.isCancelled else { throw CancellationError() }
            do {
                if let content = try await fetchContent(candidate: candidate, matching: chapter) {
                    return content
                }
            } catch {
                continue
            }
        }

        throw ChapterSourceSwitchError.noUsableChapter
    }

    private func alternativeSourceCandidates() throws -> [AlternativeChapterSource] {
        let currentSourceId = book.sourceId
        let blockedIds = book.blockedSourceIds
        var seen: Set<UUID> = []
        var candidates: [AlternativeChapterSource] = []

        for pinned in book.pinnedSources {
            guard let sourceId = UUID(uuidString: pinned.sourceId),
                  sourceId != currentSourceId,
                  !blockedIds.contains(pinned.sourceId),
                  seen.insert(sourceId).inserted else { continue }

            let descriptor = FetchDescriptor<BookSource>(
                predicate: #Predicate<BookSource> { $0.id == sourceId }
            )
            guard let source = try modelContext.fetch(descriptor).first else { continue }
            candidates.append(AlternativeChapterSource(
                id: source.id,
                name: source.name,
                sourceURL: source.sourceURL,
                ruleJSON: source.ruleJSON,
                bookURL: pinned.bookURL
            ))
        }

        var descriptor = FetchDescriptor<BookSource>()
        descriptor.predicate = #Predicate<BookSource> { $0.enabled == true }
        let sources = try modelContext.fetch(descriptor)
        for source in sources {
            let sourceIdString = source.id.uuidString
            guard source.id != currentSourceId,
                  !blockedIds.contains(sourceIdString),
                  seen.insert(source.id).inserted else { continue }
            candidates.append(AlternativeChapterSource(
                id: source.id,
                name: source.name,
                sourceURL: source.sourceURL,
                ruleJSON: source.ruleJSON,
                bookURL: nil
            ))
        }

        return candidates
    }

    private func fetchContent(candidate: AlternativeChapterSource, matching chapter: Chapter) async throws -> String? {
        let engine = SourceEngine()
        let legado = try LegadoSourceParser.parse(json: candidate.ruleJSON, matchingURL: candidate.sourceURL)
        guard let contentRule = legado.contentRule else { return nil }

        let bookURL: String
        if let pinnedBookURL = candidate.bookURL, !pinnedBookURL.isEmpty {
            bookURL = pinnedBookURL
        } else {
            guard let matchedBookURL = try await searchBookURL(in: legado, title: book.title, author: book.author) else {
                return nil
            }
            bookURL = matchedBookURL
        }

        let chapterInfos = try await fetchChapters(source: legado, bookURL: bookURL)
        guard let match = matchChapter(chapter, in: chapterInfos) else { return nil }
        let nextChapterURL = chapterInfos.indices.contains(match.index + 1) ? chapterInfos[match.index + 1].url : nil

        guard let content = try await engine.fetchFullContent(
            url: match.info.url,
            rule: contentRule,
            baseURL: legado.url,
            nextChapterURL: nextChapterURL
        ),
        SourceEngine.isValidContent(content) else {
            return nil
        }

        return content
    }

    private func searchBookURL(in source: LegadoSource, title: String, author: String) async throws -> String? {
        let engine = SourceEngine()
        guard let searchRequest = engine.buildSearchRequest(source: source, keyword: title, page: 1),
              let searchRule = source.searchRule else {
            return nil
        }

        let response = try await NetworkClient.shared.fetchString(
            url: searchRequest.url,
            method: searchRequest.method,
            body: searchRequest.body,
            headers: searchRequest.headers.isEmpty ? nil : searchRequest.headers
        )
        let results = try engine.parseSearchResults(response: response, rule: searchRule, baseURL: source.url)
        let titleLower = title.lowercased()
        let authorLower = author.lowercased()

        return results.first { result in
            let resultTitle = result.title.lowercased()
            if resultTitle == titleLower { return true }
            guard resultTitle.contains(titleLower) || titleLower.contains(resultTitle) else { return false }
            guard !authorLower.isEmpty, !result.author.isEmpty else { return true }
            let resultAuthor = result.author.lowercased()
            return resultAuthor.contains(authorLower) || authorLower.contains(resultAuthor)
        }?.bookURL
    }

    private func fetchChapters(source: LegadoSource, bookURL: String) async throws -> [ChapterInfo] {
        let engine = SourceEngine()
        let resolvedURL = engine.resolveURL(bookURL, base: source.url)
        let response = try await NetworkClient.shared.fetchString(url: resolvedURL)
        guard let tocRule = source.tocRule else { throw ChapterSourceSwitchError.noTocRule }

        var tocResponse = response
        var tocBaseURL = resolvedURL
        if let tocUrlRule = source.bookInfoRule?.tocUrl, !tocUrlRule.isEmpty {
            let ruleExecutor = RuleExecutor()
            if let parsedTocURL = try? ruleExecutor.getString(html: response, rule: tocUrlRule, baseURL: resolvedURL),
               !parsedTocURL.isEmpty {
                tocBaseURL = engine.resolveURL(parsedTocURL, base: resolvedURL)
                tocResponse = try await NetworkClient.shared.fetchString(url: tocBaseURL)
            }
        }

        var chapters = try engine.parseChapterList(response: tocResponse, rule: tocRule, baseURL: tocBaseURL)
            .map { ChapterInfo(title: $0.title, url: engine.resolveURL($0.url, base: tocBaseURL)) }

        if let nextRule = tocRule.nextTocUrl, !nextRule.isEmpty {
            var visitedURLs: Set<String> = []
            var currentResponse = tocResponse
            var currentBaseURL = tocBaseURL

            for _ in 0..<200 {
                guard let nextURL = engine.parseNextTocUrl(response: currentResponse, rule: nextRule, baseURL: currentBaseURL) else { break }
                let resolvedNext = engine.resolveURL(nextURL, base: currentBaseURL)
                guard !visitedURLs.contains(resolvedNext) else { break }
                visitedURLs.insert(resolvedNext)

                let nextResponse = try await NetworkClient.shared.fetchString(url: resolvedNext)
                let pageChapters = try engine.parseChapterList(response: nextResponse, rule: tocRule, baseURL: resolvedNext)
                    .map { ChapterInfo(title: $0.title, url: engine.resolveURL($0.url, base: resolvedNext)) }
                guard !pageChapters.isEmpty else { break }

                chapters.append(contentsOf: pageChapters)
                currentResponse = nextResponse
                currentBaseURL = resolvedNext
            }
        }

        var seen = Set<String>()
        let deduplicated = chapters.filter { seen.insert("\($0.title)|\($0.url)").inserted }
        guard !deduplicated.isEmpty else { throw ChapterSourceSwitchError.noChapters }
        return deduplicated
    }

    /// Fetches the book's current table of contents from its source and appends
    /// chapters the shelf does not have yet. Existing chapters keep their index so
    /// reading positions and caches stay valid.
    private func refreshTableOfContents() async -> TocRefreshOutcome {
        guard let sourceId = book.sourceId,
              let bookURL = book.sourceBookURL, !bookURL.isEmpty else { return .unavailable }

        let descriptor = FetchDescriptor<BookSource>(predicate: #Predicate<BookSource> { $0.id == sourceId })
        guard let source = try? modelContext.fetch(descriptor).first,
              let legado = try? LegadoSourceParser.parse(json: source.ruleJSON, matchingURL: source.sourceURL) else {
            return .failed
        }

        do {
            let infos = try await fetchChapters(source: legado, bookURL: bookURL)
            guard !Task.isCancelled else { return .upToDate }

            let fresh = TocMerger.newChapters(
                existingTitles: chapters.map(\.title),
                existingURLs: Set(chapters.compactMap { $0.sourceURL }),
                incoming: infos
            )
            guard !fresh.isEmpty else { return .upToDate }

            var nextIndex = (chapters.map(\.index).max() ?? -1) + 1
            for info in fresh {
                let chapter = Chapter(index: nextIndex, title: info.title)
                chapter.sourceURL = info.url
                chapter.book = book
                modelContext.insert(chapter)
                nextIndex += 1
            }
            let added = fresh.count
            book.totalChapters = max(book.totalChapters, nextIndex)
            try? modelContext.save()
            loadChapters()
            return .added(added)
        } catch {
            return .failed
        }
    }

    private func matchChapter(_ chapter: Chapter, in chapters: [ChapterInfo]) -> (info: ChapterInfo, index: Int)? {
        let targetTitle = normalizedChapterTitle(chapter.title)
        if let exact = chapters.enumerated().first(where: { normalizedChapterTitle($0.element.title) == targetTitle }) {
            return (exact.element, exact.offset)
        }

        if targetTitle.count >= 4,
           let partial = chapters.enumerated().first(where: {
               let candidate = normalizedChapterTitle($0.element.title)
               return candidate.count >= 4 && (candidate.contains(targetTitle) || targetTitle.contains(candidate))
           }) {
            return (partial.element, partial.offset)
        }

        guard chapters.indices.contains(chapter.index) else { return nil }
        return (chapters[chapter.index], chapter.index)
    }

    private func normalizedChapterTitle(_ title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\u{3000}", with: "")
    }

    private func describeChapterSourceSwitchError(_ error: Error) -> String {
        switch error {
        case ChapterSourceSwitchError.noAlternativeSource:
            return "没有可用的其他书源"
        case ChapterSourceSwitchError.noTocRule:
            return "候选书源没有目录规则"
        case ChapterSourceSwitchError.noChapters:
            return "候选书源无法获取章节目录"
        case ChapterSourceSwitchError.noUsableChapter:
            return "其他书源也没有抓到有效正文"
        case ChapterSourceSwitchError.persistenceFailed:
            return "新正文无法保存，请检查设备存储空间后重试"
        default:
            return error.localizedDescription
        }
    }

    private enum ContentLoadError: Error {
        case noSourceId
        case sourceNotFound
        case noContentRule
        case emptyContent
        case invalidContent(String)
    }

    private func prefetchNextChapters() {
        prefetchTask?.cancel()
        // The immediate next chapter belongs to the render window above. Keep
        // farther raw-content prefetch separate, matching the reader hot path.
        let start = currentChapterIndex + 2
        let end = min(currentChapterIndex + 3, chapters.count - 1)
        guard start <= end,
              let configuration = chapterContentConfiguration() else { return }

        let selected = Array(chapters[start...end]).filter {
            !hasCachedContent($0) && $0.sourceURL != nil
        }
        let jobs = makeChapterFetchJobs(from: selected)
        guard !jobs.isEmpty else { return }

        let generation = UUID()
        prefetchGeneration = generation
        prefetchTask = Task(priority: .utility) {
            await withTaskGroup(of: ReaderChapterFetchResult.self) { group in
                var iterator = jobs.makeIterator()
                let maxConcurrent = min(2, jobs.count)

                for _ in 0..<maxConcurrent {
                    guard let job = iterator.next() else { break }
                    group.addTask {
                        await Self.downloadChapter(job, configuration: configuration, retention: .automatic)
                    }
                }

                while let result = await group.next() {
                    guard !Task.isCancelled else {
                        group.cancelAll()
                        break
                    }
                    if result.succeeded,
                       let chapter = chapters.first(where: { $0.id == result.chapterID }),
                       !chapter.isCached {
                        chapter.content = result.fallbackContent
                        chapter.isCached = result.isUserManaged
                    }
                    if let nextJob = iterator.next() {
                        group.addTask {
                            await Self.downloadChapter(nextJob, configuration: configuration, retention: .automatic)
                        }
                    }
                }
            }
            if !Task.isCancelled { try? modelContext.save() }
            if prefetchGeneration == generation {
                prefetchTask = nil
            }
        }
    }

    private func cacheChapters(count: Int?) {
        guard !isCaching, cacheTask == nil else { return }
        guard let configuration = chapterContentConfiguration() else { return }

        isCaching = true
        cachedCount = 0
        completedCacheCount = 0
        totalToCache = 0

        let startingChapterIndex = currentChapterIndex
        let generation = UUID()
        cacheGeneration = generation
        let bookID = book.id
        let bookTitle = book.title
        cacheTask = Task {
            var didEnqueue = false
            defer {
                if cacheGeneration == generation {
                    cacheGeneration = nil
                    cacheTask = nil
                    if !didEnqueue {
                        isCaching = false
                    }
                }
            }

            let preparationToken = await ChapterDownloadManager.shared
                .makePreparationToken(bookID: bookID)
            guard !Task.isCancelled, cacheGeneration == generation else { return }

            let storedChapterIDs: Set<UUID>
            do {
                storedChapterIDs = try await ChapterContentStore.shared.storedChapterIDs(
                    bookID: bookID,
                    retention: .userManaged
                )
            } catch {
                return
            }
            guard !Task.isCancelled, cacheGeneration == generation else { return }
            await updateUserManagedCacheSummary(storedChapterIDs: storedChapterIDs)
            guard !Task.isCancelled, cacheGeneration == generation else { return }

            var selected = chapters.filter { chapter in
                guard chapter.sourceURL != nil,
                      !storedChapterIDs.contains(chapter.id) else { return false }
                let hasValidLegacyCache = chapter.isCached
                    && SourceEngine.isValidContent(chapter.content)
                guard !hasValidLegacyCache else { return false }
                return count == nil || chapter.index > startingChapterIndex
            }
            if let count {
                selected = Array(selected.prefix(max(0, count)))
            }
            let jobs = makeChapterFetchJobs(from: selected)
            totalToCache = jobs.count

            guard !jobs.isEmpty else {
                _ = await applyUserManagedCacheMetadata(
                    storedChapterIDs: storedChapterIDs,
                    fallbackContents: [:]
                )
                return
            }

            let request = ChapterDownloadRequest(
                bookID: bookID,
                bookTitle: bookTitle,
                jobs: jobs.map {
                    ChapterDownloadJob(
                        bookID: $0.bookID,
                        chapterID: $0.chapterID,
                        sourceURL: $0.sourceURL,
                        nextChapterURL: $0.nextChapterURL
                    )
                },
                configuration: ChapterDownloadConfiguration(
                    rule: configuration.rule,
                    baseURL: configuration.baseURL
                )
            )

            do {
                try Task.checkCancellation()
                let snapshot = try await ChapterDownloadManager.shared.enqueue(
                    request,
                    preparationToken: preparationToken
                )
                didEnqueue = true
                applyDownloadSnapshot(snapshot)
                ChapterDownloadSystemTask.shared.submitUserInitiated(
                    bookID: bookID,
                    bookTitle: bookTitle
                )
            } catch {
                return
            }
        }
    }

    private func observeChapterDownloads() async {
        // Coalesced invalidations cannot lose a terminal state: every signal is
        // resolved through the manager's authoritative snapshot for this book.
        let stream = await ChapterDownloadManager.shared.updates(replayCurrent: false)
        // Initial reader bootstrap only needs progress metadata. A terminal
        // cache validation is scheduled after the first page and hot neighbor
        // are ready, so a cold directory scan cannot delay reader startup.
        await synchronizeChapterDownloadSnapshot(allowTerminalReconciliation: false)
        for await _ in stream {
            guard !Task.isCancelled else { return }
            await synchronizeChapterDownloadSnapshot()
        }
    }

    private func synchronizeChapterDownloadSnapshot(
        allowTerminalReconciliation: Bool = true
    ) async {
        guard let snapshot = await ChapterDownloadManager.shared.snapshot(bookID: book.id) else {
            downloadSnapshot = nil
            isCaching = false
            return
        }
        applyDownloadSnapshot(snapshot)

        guard snapshot.phase == .paused
                || snapshot.phase == .completed
                || snapshot.phase == .failed
                || snapshot.phase == .cancelled else { return }
        let marker = "\(snapshot.id.uuidString)-\(snapshot.phase.rawValue)-\(snapshot.updatedAt.timeIntervalSince1970)"
        guard reconciledDownloadMarker != marker else { return }
        guard allowTerminalReconciliation else { return }
        if let inFlightMarker = cacheReconciliationMarkerInFlight {
            if inFlightMarker != marker {
                pendingCacheReconciliationMarker = marker
            }
            return
        }
        // A cold cache index may need to validate thousands of files. Never
        // let that actor work get ahead of the first visible page and the hot
        // adjacent-chapter preparation path.
        guard currentChapterContent != nil, hasRenderableCurrentChapter else { return }
        cacheReconciliationMarkerInFlight = marker
        let didReconcile = await reconcileUserManagedCache(fallbackContents: [:])
        if cacheReconciliationMarkerInFlight == marker {
            cacheReconciliationMarkerInFlight = nil
        }
        if didReconcile, !Task.isCancelled {
            reconciledDownloadMarker = marker
        }

        guard !Task.isCancelled,
              pendingCacheReconciliationMarker != nil else { return }
        pendingCacheReconciliationMarker = nil
        await synchronizeChapterDownloadSnapshot()
    }

    private func applyDownloadSnapshot(_ snapshot: ChapterDownloadSnapshot) {
        downloadSnapshot = snapshot
        isCaching = snapshot.phase.isActive
        completedCacheCount = min(
            snapshot.targetCount,
            snapshot.durableStoredCount + snapshot.processedCount
        )
        cachedCount = min(
            snapshot.targetCount,
            snapshot.durableStoredCount + snapshot.succeededCount
        )
        totalToCache = snapshot.targetCount
    }

    private func cancelCaching() {
        cacheTask?.cancel()
        let bookID = book.id
        Task {
            if let snapshot = await ChapterDownloadManager.shared.pause(bookID: bookID) {
                applyDownloadSnapshot(snapshot)
            } else {
                isCaching = false
            }
        }
    }

    private func resumeCaching() {
        guard let snapshot = downloadSnapshot,
              snapshot.phase == .paused || snapshot.phase == .failed else { return }
        let bookID = book.id
        Task {
            do {
                if let resumed = try await ChapterDownloadManager.shared.resume(bookID: bookID) {
                    applyDownloadSnapshot(resumed)
                    ChapterDownloadSystemTask.shared.submitUserInitiated(
                        bookID: bookID,
                        bookTitle: resumed.bookTitle
                    )
                }
            } catch {
                loadError = "无法继续缓存：\(error.localizedDescription)"
            }
        }
    }

    private var cachePresentationState: ReaderCachePresentationState {
        let hasEligibleRemoteChapter: Bool
        if let cacheSummary {
            hasEligibleRemoteChapter = cacheSummary.cached + cacheSummary.uncached > 0
        } else {
            hasEligibleRemoteChapter = chapters.contains { $0.sourceURL != nil }
        }
        // Cache preparation validates the durable store and builds the missing
        // job list before the manager can publish a queued snapshot. Keep that
        // work visible instead of briefly showing the previous idle state.
        let isPreparingCache = isCaching && downloadSnapshot?.phase.isActive != true
        return ReaderCachePresentationState.derive(
            isAvailable: book.sourceId != nil && hasEligibleRemoteChapter,
            isChecking: isCheckingCacheSummary || isPreparingCache,
            summary: cacheSummary,
            snapshot: downloadSnapshot
        )
    }

    /// Fast startup approximation. `isCached` represents explicit/user-managed
    /// cache metadata; automatic reader prefetches never set it.
    private func metadataCacheSummary() -> BookCacheSummary {
        var cached = 0
        var uncached = 0
        for chapter in chapters where chapter.sourceURL != nil {
            if chapter.isCached {
                cached += 1
            } else {
                uncached += 1
            }
        }
        return BookCacheSummary(cached: cached, uncached: uncached)
    }

    private func refreshUserManagedCacheSummary() async {
        guard book.sourceId != nil else {
            cacheSummary = nil
            isCheckingCacheSummary = false
            return
        }

        let storedChapterIDs: Set<UUID>
        do {
            storedChapterIDs = try await ChapterContentStore.shared.storedChapterIDs(
                bookID: book.id,
                retention: .userManaged
            )
        } catch {
            // Preserve the last known metadata approximation on an unreadable
            // directory; an I/O error must never turn a cached book into zero.
            isCheckingCacheSummary = false
            return
        }
        guard !Task.isCancelled else { return }
        await updateUserManagedCacheSummary(storedChapterIDs: storedChapterIDs)
    }

    private func updateUserManagedCacheSummary(
        storedChapterIDs: Set<UUID>
    ) async {
        var cached = 0
        var eligible = 0
        for chapter in chapters where chapter.sourceURL != nil {
            eligible += 1
            if storedChapterIDs.contains(chapter.id)
                || (chapter.isCached && SourceEngine.isValidContent(chapter.content)) {
                cached += 1
            }
            if eligible.isMultiple(of: 50) {
                guard !Task.isCancelled else { return }
                await Task.yield()
            }
        }
        guard !Task.isCancelled else { return }
        cacheSummary = BookCacheSummary(
            cached: cached,
            uncached: max(0, eligible - cached)
        )
        isCheckingCacheSummary = false
    }

    private var chapterDownloadProgressText: String? {
        guard let snapshot = downloadSnapshot else {
            return isCaching ? "检查已有缓存…" : nil
        }
        if snapshot.phase == .paused || snapshot.phase == .failed {
            return "已缓存 \(snapshot.durableStoredCount) 章"
        }
        guard snapshot.phase.isActive else { return nil }
        return "\(completedCacheCount)/\(totalToCache)，已缓存 \(cachedCount) 章"
    }

    private func reconcileUserManagedCache(fallbackContents: [UUID: String]) async -> Bool {
        let storedChapterIDs: Set<UUID>
        do {
            storedChapterIDs = try await ChapterContentStore.shared.storedChapterIDs(
                bookID: book.id,
                retention: .userManaged
            )
        } catch {
            // A directory read failure must not clear otherwise-valid cache
            // metadata. Preserve existing flags and only commit in-memory
            // fallbacks produced by this run.
            var mutationCount = 0
            for chapter in chapters {
                guard let fallbackContent = fallbackContents[chapter.id] else { continue }
                chapter.content = fallbackContent
                chapter.isCached = true
                mutationCount += 1
                if mutationCount.isMultiple(of: 50) {
                    guard !Task.isCancelled else { return false }
                    await Task.yield()
                }
            }
            try? modelContext.save()
            return false
        }

        return await applyUserManagedCacheMetadata(
            storedChapterIDs: storedChapterIDs,
            fallbackContents: fallbackContents
        )
    }

    private func applyUserManagedCacheMetadata(
        storedChapterIDs: Set<UUID>,
        fallbackContents: [UUID: String]
    ) async -> Bool {
        var visitedCount = 0
        var cachedChapterCount = 0
        for chapter in chapters where chapter.sourceURL != nil {
            if let fallbackContent = fallbackContents[chapter.id] {
                chapter.content = fallbackContent
            }

            let shouldBeCached = storedChapterIDs.contains(chapter.id)
                || fallbackContents[chapter.id] != nil
                || (chapter.isCached && SourceEngine.isValidContent(chapter.content))
            if chapter.isCached != shouldBeCached {
                chapter.isCached = shouldBeCached
            }
            if shouldBeCached {
                cachedChapterCount += 1
            }

            visitedCount += 1
            if visitedCount.isMultiple(of: 50) {
                // Keep the reader responsive while reconciling very large books.
                guard !Task.isCancelled else { return false }
                await Task.yield()
            }
        }
        cacheSummary = BookCacheSummary(
            cached: cachedChapterCount,
            uncached: max(0, visitedCount - cachedChapterCount)
        )
        isCheckingCacheSummary = false
        do {
            try modelContext.save()
            return true
        } catch {
            return false
        }
    }

    private func chapterContentConfiguration() -> ReaderChapterFetchConfiguration? {
        guard let sourceID = book.sourceId else { return nil }
        let descriptor = FetchDescriptor<BookSource>(predicate: #Predicate<BookSource> { $0.id == sourceID })
        guard let source = try? modelContext.fetch(descriptor).first,
              let legado = try? LegadoSourceParser.parse(json: source.ruleJSON, matchingURL: source.sourceURL),
              let contentRule = legado.contentRule else { return nil }
        return ReaderChapterFetchConfiguration(rule: contentRule, baseURL: legado.url)
    }

    private func makeChapterFetchJobs(from selected: [Chapter]) -> [ReaderChapterFetchJob] {
        let sourceURLByIndex = Dictionary(uniqueKeysWithValues: chapters.compactMap { chapter in
            chapter.sourceURL.map { (chapter.index, $0) }
        })
        return selected.compactMap { chapter in
            guard let sourceURL = chapter.sourceURL else { return nil }
            return ReaderChapterFetchJob(
                bookID: book.id,
                chapterID: chapter.id,
                sourceURL: sourceURL,
                nextChapterURL: sourceURLByIndex[chapter.index + 1]
            )
        }
    }

    private func hasCachedContent(_ chapter: Chapter) -> Bool {
        chapter.isCached
    }

    nonisolated private static func downloadChapter(
        _ job: ReaderChapterFetchJob,
        configuration: ReaderChapterFetchConfiguration,
        retention: ChapterCacheRetention
    ) async -> ReaderChapterFetchResult {
        guard !Task.isCancelled else {
            return ReaderChapterFetchResult(
                chapterID: job.chapterID,
                succeeded: false,
                fallbackContent: nil,
                isUserManaged: false
            )
        }
        do {
            let writeToken = await ChapterContentStore.shared.makeWriteToken(bookID: job.bookID)
            try Task.checkCancellation()
            if retention == .userManaged,
               (try? await ChapterContentStore.shared.promote(
                    bookID: job.bookID,
                    chapterID: job.chapterID,
                    writeToken: writeToken
               )) == true {
                return ReaderChapterFetchResult(
                    chapterID: job.chapterID,
                    succeeded: true,
                    fallbackContent: nil,
                    isUserManaged: true
                )
            }
            try Task.checkCancellation()
            if let cached = await ChapterContentStore.shared.load(
                bookID: job.bookID,
                chapterID: job.chapterID
            ), retention == .automatic {
                try Task.checkCancellation()
                return ReaderChapterFetchResult(
                    chapterID: job.chapterID,
                    succeeded: true,
                    fallbackContent: nil,
                    isUserManaged: cached.retention == .userManaged
                )
            }

            let content = try await ChapterContentLoader.shared.fetch(
                ChapterContentRequest(
                    url: job.sourceURL,
                    rule: configuration.rule,
                    baseURL: configuration.baseURL,
                    nextChapterURL: job.nextChapterURL
                )
            )
            guard let content, SourceEngine.isValidContent(content) else {
                return ReaderChapterFetchResult(
                    chapterID: job.chapterID,
                    succeeded: false,
                    fallbackContent: nil,
                    isUserManaged: false
                )
            }
            try Task.checkCancellation()
            do {
                let outcome = try await ChapterContentStore.shared.store(
                    content,
                    bookID: job.bookID,
                    chapterID: job.chapterID,
                    retention: retention,
                    writeToken: writeToken
                )
                return ReaderChapterFetchResult(
                    chapterID: job.chapterID,
                    succeeded: outcome.isStored,
                    fallbackContent: nil,
                    isUserManaged: outcome.effectiveRetention == .userManaged
                )
            } catch ChapterContentStoreError.staleWrite {
                return ReaderChapterFetchResult(
                    chapterID: job.chapterID,
                    succeeded: false,
                    fallbackContent: nil,
                    isUserManaged: false
                )
            } catch is CancellationError {
                return ReaderChapterFetchResult(
                    chapterID: job.chapterID,
                    succeeded: false,
                    fallbackContent: nil,
                    isUserManaged: false
                )
            } catch {
                guard !Task.isCancelled,
                      await ChapterContentStore.shared.isWriteTokenCurrent(
                        writeToken,
                        bookID: job.bookID,
                        chapterID: job.chapterID
                      ) else {
                    return ReaderChapterFetchResult(
                        chapterID: job.chapterID,
                        succeeded: false,
                        fallbackContent: nil,
                        isUserManaged: false
                    )
                }
                return ReaderChapterFetchResult(
                    chapterID: job.chapterID,
                    succeeded: true,
                    fallbackContent: content,
                    isUserManaged: retention == .userManaged
                )
            }
        } catch {
            return ReaderChapterFetchResult(
                chapterID: job.chapterID,
                succeeded: false,
                fallbackContent: nil,
                isUserManaged: false
            )
        }
    }

    // MARK: - Status Bar

    /// Page index inside the chapter as a 0…1 fraction, so reopening lands on the same line.
    private var chapterPositionFraction: Double {
        let pageCount = cachedPages.count
        guard pageCount > 1 else { return 0 }
        return Double(min(max(currentPageIndex, 0), pageCount - 1)) / Double(pageCount - 1)
    }

    private func persistReadingPosition() {
        let manager = BookManager(modelContext: modelContext)
        manager.updateProgress(book: book, chapterIndex: currentChapterIndex, position: chapterPositionFraction)
    }

    private static let footerTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var footerTimer: Publishers.Autoconnect<Timer.TimerPublisher> {
        Self.footerTimerPublisher
    }

    private static let footerTimerPublisher = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    /// Left: book title, centre: overall progress, right: time — or the battery when it runs low.
    private func readerFooter(currentPage: Int, totalPages: Int) -> some View {
        let pageCount = max(totalPages, 1)
        let chapterFraction = pageCount > 1
            ? Double(min(max(currentPage - 1, 0), pageCount - 1)) / Double(pageCount - 1)
            : 0
        let overall = (Double(currentChapterIndex) + chapterFraction) / Double(max(book.totalChapters, 1))
        let percentText = "\(Int((overall * 100).rounded()))%"
        let color = settings.theme.statusBarColor
        return GeometryReader { geo in
            ZStack {
                Text(percentText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(color)
                HStack(spacing: 8) {
                    Text(book.title)
                        .font(.system(size: 11))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: geo.size.width * 0.4, alignment: .leading)
                    Spacer(minLength: 0)
                    if showsBatteryInFooter {
                        HStack(spacing: 3) {
                            Image(systemName: "battery.25")
                                .font(.system(size: 10))
                            Text("\(Int((UIDevice.current.batteryLevel * 100).rounded()))%")
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .foregroundStyle(footerWarningColor)
                    } else {
                        Text(footerClock.isEmpty ? Self.footerTimeFormatter.string(from: Date()) : footerClock)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(color)
                    }
                }
            }
        }
        .frame(height: 28)
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
        .onReceive(footerTimer) { date in
            footerClock = Self.footerTimeFormatter.string(from: date)
        }
    }

    private var showsBatteryInFooter: Bool {
        let level = UIDevice.current.batteryLevel
        return level >= 0 && level < 0.2
    }

    private var footerWarningColor: Color {
        settings.theme.isDark ? Color(hex: "#ff6b6b") : Color(hex: "#c0392b")
    }
}

private struct ReaderChapterFetchConfiguration: Sendable {
    let rule: LegadoSource.ContentRule
    let baseURL: String
}

private struct ReaderChapterFetchJob: Sendable {
    let bookID: UUID
    let chapterID: UUID
    let sourceURL: String
    let nextChapterURL: String?
}

private struct ReaderChapterFetchResult: Sendable {
    let chapterID: UUID
    let succeeded: Bool
    let fallbackContent: String?
    let isUserManaged: Bool
}

struct ReaderChapterSourceIdentity: Hashable, Sendable {
    let bookSourceID: UUID?
    let chapterSourceURL: String?
}

struct ReaderChapterLayoutKey: Hashable, Sendable {
    let width: Double
    let height: Double
    let fontSize: Double
    let lineSpacing: Double
    let fontFamily: String
    let usesSystemFont: Bool
    let horizontalPadding: Double
    let bottomReserve: Double
}

struct ReaderPreparedChapterWindow: Sendable {
    struct Entry: Sendable {
        let chapterID: UUID
        let sourceIdentity: ReaderChapterSourceIdentity
        let content: String
        let paragraphs: [String]
        let pages: [[ReaderView.PageFragment]]
        let layoutKey: ReaderChapterLayoutKey?
    }

    private var entries: [UUID: Entry] = [:]

    var count: Int { entries.count }

    static func adjacentIndices(
        currentIndex: Int,
        chapterCount: Int,
        includingCurrent: Bool = false
    ) -> [Int] {
        guard currentIndex >= 0,
              currentIndex < chapterCount,
              chapterCount > 0 else { return [] }
        var result: [Int] = []
        if includingCurrent {
            result.append(currentIndex)
        }
        if currentIndex + 1 < chapterCount {
            result.append(currentIndex + 1)
        }
        if currentIndex > 0 {
            result.append(currentIndex - 1)
        }
        return result
    }

    func entry(
        chapterID: UUID,
        sourceIdentity: ReaderChapterSourceIdentity
    ) -> Entry? {
        guard let entry = entries[chapterID],
              entry.sourceIdentity == sourceIdentity else { return nil }
        return entry
    }

    func content(
        chapterID: UUID,
        sourceIdentity: ReaderChapterSourceIdentity
    ) -> String? {
        entry(chapterID: chapterID, sourceIdentity: sourceIdentity)?.content
    }

    func parsedEntry(
        chapterID: UUID,
        sourceIdentity: ReaderChapterSourceIdentity
    ) -> Entry? {
        guard let entry = entry(chapterID: chapterID, sourceIdentity: sourceIdentity),
              !entry.paragraphs.isEmpty else { return nil }
        return entry
    }

    func preparedEntry(
        chapterID: UUID,
        sourceIdentity: ReaderChapterSourceIdentity,
        layoutKey: ReaderChapterLayoutKey
    ) -> Entry? {
        guard let entry = entry(chapterID: chapterID, sourceIdentity: sourceIdentity),
              entry.layoutKey == layoutKey else { return nil }
        return entry
    }

    mutating func storeContent(
        _ content: String,
        chapterID: UUID,
        sourceIdentity: ReaderChapterSourceIdentity
    ) {
        if let entry = entries[chapterID],
           entry.content == content,
           entry.sourceIdentity == sourceIdentity { return }
        entries[chapterID] = Entry(
            chapterID: chapterID,
            sourceIdentity: sourceIdentity,
            content: content,
            paragraphs: [],
            pages: [[]],
            layoutKey: nil
        )
    }

    mutating func store(
        chapterID: UUID,
        sourceIdentity: ReaderChapterSourceIdentity,
        content: String,
        paragraphs: [String],
        pages: [[ReaderView.PageFragment]],
        layoutKey: ReaderChapterLayoutKey?
    ) {
        entries[chapterID] = Entry(
            chapterID: chapterID,
            sourceIdentity: sourceIdentity,
            content: content,
            paragraphs: paragraphs,
            pages: pages.isEmpty ? [[]] : pages,
            layoutKey: layoutKey
        )
    }

    mutating func invalidateLayouts() {
        entries = entries.mapValues { entry in
            Entry(
                chapterID: entry.chapterID,
                sourceIdentity: entry.sourceIdentity,
                content: entry.content,
                paragraphs: entry.paragraphs,
                pages: [[]],
                layoutKey: nil
            )
        }
    }

    mutating func retain(chapterIDs: Set<UUID>) {
        entries = entries.filter { chapterIDs.contains($0.key) }
    }

    mutating func remove(chapterID: UUID) {
        entries.removeValue(forKey: chapterID)
    }

    mutating func removeAll() {
        entries.removeAll(keepingCapacity: false)
    }
}

private struct PaginationInput: Sendable {
    let content: String
    let width: Double
    let height: Double
    let fontSize: Double
    let lineSpacing: Double
    let fontFamily: String
    let usesSystemFont: Bool
    let horizontalPadding: Double
    let bottomReserve: Double
}

private struct PaginationOutput: Sendable {
    let paragraphs: [String]
    let pages: [[ReaderView.PageFragment]]
    let didPaginate: Bool
}

private struct AlternativeChapterSource {
    let id: UUID
    let name: String
    let sourceURL: String
    let ruleJSON: String
    let bookURL: String?
}

private enum ChapterSourceSwitchError: Error {
    case noAlternativeSource
    case noTocRule
    case noChapters
    case noUsableChapter
    case persistenceFailed
}

private enum ReaderPageHeaderMetrics {
    static let fontSize: CGFloat = 12
    static let bottomPadding: CGFloat = 8
}

// MARK: - Static Page View (no @Observable dependencies)

private struct StaticPageView: View {
    let fragments: [ReaderView.PageFragment]
    let chapterTitle: String
    let fontSize: CGFloat
    let lineSpacing: Double
    let fontFamily: String
    let textColor: Color
    let titleColor: Color
    let horizontalPadding: CGFloat
    let bottomReserve: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: fontSize * (lineSpacing - 1)) {
            Text(chapterTitle)
                .font(.system(size: ReaderPageHeaderMetrics.fontSize))
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.bottom, ReaderPageHeaderMetrics.bottomPadding)

            ForEach(fragments) { frag in
                Text(frag.indent ? "\u{3000}\u{3000}" + frag.text : frag.text)
                    .font(fontFamily == FontFamily.system.rawValue
                        ? .system(size: fontSize)
                        : .custom(fontFamily, size: fontSize))
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
