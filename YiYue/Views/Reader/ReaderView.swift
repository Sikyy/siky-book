import SwiftUI
import SwiftData
import Combine
import CoreText
import UIKit

@MainActor
struct ReaderView: View {
    /// Replaced on foreground (see `refreshModelAfterSceneReset`): iOS 27 resets
    /// the SwiftData main context when the scene goes to the background, which
    /// makes every model instance held here unusable.
    @State private var book: Book
    /// Plain copy of the book id, valid even when `book` itself has been reset.
    private let bookID: UUID
    @State private var chapters: [Chapter] = []
    @State private var currentChapterIndex: Int
    @State private var showMenu = false
    /// 正文第一行顶边、菜单顶部面板底边的屏幕位置(菜单开着时用来对齐行边界)。
    @State private var bodyTopY: CGFloat = 0
    @State private var menuTopEdgeY: CGFloat = 0
    @State private var menuBottomTopY: CGFloat = 0
    @State private var currentPageIndex: Int = 0
    /// 跨页选中的锚页与延伸方向:>0 向下、<0 向上,0 表示没有在跨页选。
    @State private var crossSelection: CrossSelection?
    /// 翻页以后要在新页上接着选的那一段。
    @State private var pendingPageSelection: NSRange?
    /// 当前页的系统选区。
    @State private var pageSelection: NSRange = NSRange(location: 0, length: 0)
    /// nil means the reader follows the system brightness.
    @State private var selection: ReaderSelection?
    @State private var readerToast: String?
    /// 提示条上的「撤销」,只在删除书签/笔记时挂上。
    @State private var readerToastUndo: (() -> Void)?
    /// 下拉加书签:已经跟手的距离(阻尼后的),0 表示没在拉。
    @State private var pullOffset: CGFloat = 0
    /// 这次触摸已经认领成下拉,后续不再当翻页/点按处理。
    @State private var pullClaimed = false
    @State private var noteDraft: NoteDraft?
    @State private var pendingParagraphJump: Int?
    @State private var scrollParagraphFrames: [Int: ScrollParagraphFrame] = [:]
    @State private var visibleParagraphIndex = 0
    @State private var manualBrightness: Double?
    @State private var entryBrightness: Double = ReaderScreenBrightness.current
    /// 阅读明细与自动翻页:菜单里的两块,数据都是本书现成的真数。
    @State private var showReadingDetails = false
    @State private var autoPageEnabled = false
    @State private var autoPageInterval = 20
    @State private var autoPageTask: Task<Void, Never>?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var settings = ReaderSettings()
    /// Values the page layout draws with. They are plain copies so a layout pass
    /// never reaches into SwiftData: after a context reset that traps.
    @State private var bookTitle: String
    @State private var bookChapterCount: Int
    @State private var chapterTitles: [String] = []
    @State private var currentChapterID: UUID?
    @Environment(\.scenePhase) private var scenePhase
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
    /// Set when the book cannot be read back after a scene reset. Nothing may
    /// touch the destroyed models then, so the page keeps what it has already
    /// drawn, interactions wait, and a few retries run before the reader offers
    /// a way out instead of trapping.
    @State private var storeUnavailable = false
    /// 滚动模式下正文在动的时候,工具条先收起,滚停再贴回选区上方。
    @State private var isScrollMoving = false
    /// 关闭阅读页:先让正文淡出 0.28 秒,再真正退出,不要一帧硬切到书架。
    @State private var isClosing = false
    @State private var storeRecoveryTask: Task<Void, Never>?
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
    @State private var skipPageReset = false
    @State private var viewSize: CGSize = .zero
    @State private var cachedPages: [[PageFragment]] = [[]]
    /// 调整字号/行距后,用当前页起始段落把读者留在原来的位置。
    @State private var layoutAnchorParagraph: Int?
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
    /// 左侧上一页热区 42 点、右侧下一页 62 点;中间其余部分开/关菜单。
    private let previousPageTapWidth: CGFloat = 42
    private let nextPageTapWidth: CGFloat = 62
    /// 文本视图和父级手势可能同时收到同一次点击,用它去重。
    @State private var lastReaderTapAt: CFAbsoluteTime = -1
    /// 菜单被浮层背景关掉的时刻;用来忽略同一次点击晚到的页面手势。
    @State private var lastMenuDismissAt: CFAbsoluteTime = -1
    @State private var lastReaderTapLocation: CGPoint = .zero

    private enum TapSentinel { case prev, next }
    private enum ReaderTapAction { case previousPage, nextPage, toggleMenu, none }
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
            case page(fragments: [PageFragment], chapterTitle: String, pageIndex: Int)
            case boundary(label: String, chapterTitle: String)
        }

        let id: HorizontalPageID
        let content: Content
    }

    /// 退出用:由书架传入,让它自己决定怎么把阅读页换下去(这里不做位移)。
    private let onClose: (() -> Void)?
    /// 菜单开合会影响系统状态栏是否显示,书架(现在是最外层)需要知道。
    private let onMenuVisibilityChange: ((Bool) -> Void)?
    /// 阅读主题的深浅要交给最外层(状态栏文字的深浅跟着主题走)。
    private let onAppearanceChange: ((Bool) -> Void)?

    init(
        book: Book,
        startChapterIndex: Int = 0,
        startPosition: Double = 0,
        onClose: (() -> Void)? = nil,
        onMenuVisibilityChange: ((Bool) -> Void)? = nil,
        onAppearanceChange: ((Bool) -> Void)? = nil
    ) {
        self.onClose = onClose
        self.onMenuVisibilityChange = onMenuVisibilityChange
        self.onAppearanceChange = onAppearanceChange
        self.bookID = book.id
        self._book = State(initialValue: book)
        self._bookTitle = State(initialValue: book.title)
        self._bookChapterCount = State(initialValue: book.totalChapters)
        self._currentChapterIndex = State(initialValue: startChapterIndex)
        self._restorePositionFraction = State(initialValue: startPosition > 0 ? startPosition : nil)
    }

    /// Whether the reader is allowed to draw and read its models. Panels that
    /// touch SwiftData stay hidden outside the active phase.
    private var sceneIsActive: Bool {
        scenePhase == .active
    }

    /// iOS 27 resets the SwiftData main context when the scene goes to the
    /// background: the book and chapters this reader was handed are then
    /// destroyed and any property access traps in SwiftData. Re-fetch them by
    /// their plain ids the moment the scene is active again.
    /// 关闭阅读页:正文淡出后再退出,交给书架接上去。
    private func closeReader() {
        guard !isClosing else { return }
        withAnimation(.easeOut(duration: 0.28)) { isClosing = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            if let onClose {
                onClose()
            } else {
                dismiss()
            }
        }
    }

    private func refreshModelAfterSceneReset() {
        storeRecoveryTask?.cancel()
        storeRecoveryTask = nil
        if let fresh = SwiftDataRefetch.book(id: bookID, in: modelContext) {
            storeUnavailable = false
            if fresh !== book {
                book = fresh
                chapters = []
                loadChapters()
            }
        } else {
            // 取不到:不对已销毁的实例做任何读取,页面停在原处,先等着重试。
            storeUnavailable = true
            scheduleStoreRecovery(attempt: 0)
        }
        if let markID = noteDraft?.markID {
            noteDraft?.mark = SwiftDataRefetch.readingMark(id: markID, in: modelContext)
        }
    }

    /// The store did not answer right away. Give it a few patient tries; if it
    /// keeps failing the reader says so and lets the reader go back to the
    /// shelf, where a fresh query reloads everything anyway.
    private func scheduleStoreRecovery(attempt: Int) {
        storeRecoveryTask?.cancel()
        storeRecoveryTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(attempt == 0 ? 250 : 500))
            guard !Task.isCancelled, scenePhase == .active else { return }
            if let fresh = SwiftDataRefetch.book(id: bookID, in: modelContext) {
                book = fresh
                chapters = []
                loadChapters()
                storeUnavailable = false
            } else if attempt < 3 {
                scheduleStoreRecovery(attempt: attempt + 1)
            }
        }
    }

    /// Quiet notice over the untouched page when its data did not come back.
    private var storeUnavailableNotice: some View {
        VStack(spacing: 12) {
            Text("数据暂时没读回来")
                .font(.subheadline.weight(.medium))
            Text("回书架重进这本书就能接着读,阅读位置不会丢。")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .opacity(0.7)
            Button("返回书架") { dismiss() }
                .font(.subheadline.weight(.semibold))
                .padding(.top, 2)
        }
        .foregroundStyle(settings.theme.textColor)
        .padding(22)
        .background(settings.theme.backgroundColor.opacity(0.96), in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(settings.theme.textColor.opacity(0.12))
        )
        .padding(32)
    }

    /// Copies everything the page layout needs out of SwiftData. Called whenever
    /// the book or its chapters change, never during a layout pass.
    private func refreshLayoutSnapshots() {
        bookTitle = book.title
        bookChapterCount = max(book.totalChapters, chapters.count)
        chapterTitles = chapters.map(\.title)
        let index = currentChapterIndex
        currentChapterID = (index >= 0 && index < chapters.count) ? chapters[index].id : nil
    }

    /// Chapter title by index from the snapshot, never from a live model.
    private func chapterTitle(at index: Int) -> String {
        guard index >= 0, index < chapterTitles.count else { return "" }
        return chapterTitles[index]
    }

    private var currentChapterTitle: String {
        chapterTitle(at: currentChapterIndex)
    }

    /// O(1) access — chapters sorted by index, indices are 0-based contiguous
    private var currentChapter: Chapter? {
        guard currentChapterIndex >= 0, currentChapterIndex < chapters.count else { return nil }
        return chapters[currentChapterIndex]
    }

    /// Load the already-related chapters once, avoiding a second predicate fetch.
    private func loadChapters() {
        chapters = book.chapters.sorted { $0.index < $1.index }
        refreshLayoutSnapshots()
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
                .allowsHitTesting(!storeUnavailable)

            if storeUnavailable {
                storeUnavailableNotice
            }

            if sceneIsActive, let selection, !isScrollMoving {
                selectionToolbar(for: selection)
            }

            if sceneIsActive, showMenu {
                ReaderMenuOverlay(
                    book: book,
                    currentChapterIndex: $currentChapterIndex,
                    totalChapters: book.totalChapters,
                    chapterTitle: currentChapter?.title ?? "",
                    settings: settings,
                    onDismiss: {
                        // 记下浮层背景关菜单的时刻:同一次点击的另一份投递可能稍后
                        // 才到页面手势,短暂忽略,避免菜单刚关又被开回来。
                        lastMenuDismissAt = CFAbsoluteTimeGetCurrent()
                        showMenu = false
                    },
                    onBack: { closeReader() },
                    chapters: chapters,
                    onCache: book.sourceId != nil ? { count in cacheChapters(count: count) } : nil,
                    onCancelCache: { cancelCaching() },
                    onResumeCache: { resumeCaching() },
                    cacheState: cachePresentationState,
                    onRefreshToc: book.sourceId == nil ? nil : { await refreshTableOfContents() },
                    brightness: manualBrightness ?? ReaderScreenBrightness.current,
                    isFollowingSystemBrightness: manualBrightness == nil,
                    onBrightnessChange: { value in
                        manualBrightness = value
                        ReaderScreenBrightness.set(value)
                    },
                    onFollowSystemBrightness: {
                        manualBrightness = nil
                        ReaderScreenBrightness.set(entryBrightness)
                    },
                    onJumpToMark: { mark in jump(to: mark) },
                    onOpenNote: { mark in
                        noteDraft = NoteDraft(
                            chapterIndex: mark.chapterIndex,
                            paragraphIndex: mark.paragraphIndex,
                            excerpt: mark.excerpt,
                            mark: mark,
                            markID: mark.id
                        )
                    },
                    onAddBookmarkHere: { togglePageBookmark() },
                    hasPageBookmark: pageBookmarkMark != nil,
                    onWriteNoteHere: { writeNoteAtCurrentPage() },
                    bottomTopInset: bottomMenuInset,
                    topBottomInset: menuTopInset,
                    bodyTopY: bodyTopY,
                    bodyLineHeight: bodyLineHeight,
                    progressPercent: menuProgressText,
                    progressFraction: overallProgressFraction,
                    bodyLineTops: currentPageLineTops,
                    topBarBottomY: menuTopEdgeY,
                    readChapterCount: readChapterCount,
                    autoPageEnabled: autoPageEnabled,
                    autoPageInterval: autoPageInterval,
                    onShowReadingDetails: { showReadingDetails = true },
                    onSetAutoPageEnabled: { enabled in
                        autoPageEnabled = enabled
                        restartAutoPage()
                    },
                    onSetAutoPageInterval: { seconds in
                        autoPageInterval = seconds
                        restartAutoPage()
                    }
                )
            }

            if let readerToast {
                VStack {
                    HStack(spacing: 12) {
                        Text(readerToast)
                            .font(.system(size: 13))
                            .foregroundStyle(settings.theme.menuPrimary)
                        if let undo = readerToastUndo {
                            Button {
                                readerToastUndo = nil
                                withAnimation(.easeInOut(duration: 0.15)) { self.readerToast = nil }
                                undo()
                            } label: {
                                Text("撤销")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(settings.theme.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(settings.theme.menuBackground)
                        )
                        .padding(.top, showMenu ? 132 : 60)
                    Spacer()
                }
                .allowsHitTesting(readerToastUndo != nil)
                .transition(.opacity)
            }

            // 关闭阅读页:整页在 0.28 秒里淡到书架的底色,退出就没有硬切的一帧。
            Color.black
                .opacity(isClosing ? 1 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .sheet(item: $noteDraft) { draft in
            NoteEditorView(
                excerpt: draft.excerpt,
                initialNote: draft.mark?.note ?? "",
                onCancel: { noteDraft = nil },
                onSave: { note in
                    saveNote(note, for: draft)
                    noteDraft = nil
                },
                onDelete: draft.mark == nil ? nil : {
                    if let mark = draft.mark { deleteMark(mark) }
                    noteDraft = nil
                }
            )
        }
        .sheet(isPresented: $showReadingDetails) {
            ReaderReadingDetailsView(stats: readingStats)
        }
        .onPreferenceChange(ReaderBodyTopPreference.self) { y in bodyTopY = y }
        .onPreferenceChange(ReaderMenuTopEdgePreference.self) { y in
            // 面板自己会长,量到的底边会被上一次的补齐量带着跑;只在没有补齐时记录。
            if menuTopInset == 0 { menuTopEdgeY = y }
        }
        .onPreferenceChange(ReaderMenuBottomTopPreference.self) { y in
            if bottomMenuInset == 0 { menuBottomTopY = y }
        }
        .statusBarHidden(!showMenu)
        .persistentSystemOverlays(showMenu ? .automatic : .hidden)
        .preferredColorScheme(settings.theme.isDark ? .dark : .light)
        .onAppear { onAppearanceChange?(settings.theme.isDark) }
        .onChange(of: settings.theme) { _, theme in onAppearanceChange?(theme.isDark) }
        .onChange(of: showMenu) { _, open in
            // 菜单开着就不该同时有选中段,toolbar 和菜单会叠在一起。
            if open { selection = nil }
            onMenuVisibilityChange?(open)
            // 自动翻页在菜单打开时停,菜单关掉后接着走。
            restartAutoPage()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Re-fetch before the first draw, so the reader never renders
                // with a model the background reset has already destroyed.
                refreshModelAfterSceneReset()
                if sceneIsActive {
                    ReaderActivityStore.recordReadingDay(bookID: bookID)
                }
                restartAutoPage()
            case .inactive, .background:
                autoPageTask?.cancel()
                autoPageTask = nil
            @unknown default:
                break
            }
        }
        .onChange(of: currentChapterIndex) { _, newValue in
            currentChapterID = chapters.indices.contains(newValue) ? chapters[newValue].id : nil
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
            entryBrightness = ReaderScreenBrightness.current
            applyKeepScreenAwake()
            ReaderActivityStore.recordReadingDay(bookID: bookID)
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
            autoPageTask?.cancel()
            autoPageTask = nil
            persistReadingPosition()
            try? modelContext.save()
            ReaderScreenBrightness.set(entryBrightness)
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: currentPageIndex) { _, _ in
            persistReadingPosition()
        }
        .onChange(of: settings.keepScreenAwake) { _, _ in applyKeepScreenAwake() }
        .onChange(of: settings.fontSize) { _, _ in readerLayoutDidChange(delayNanoseconds: 0) }
        .onChange(of: settings.lineSpacing) { _, _ in readerLayoutDidChange(delayNanoseconds: 0) }
        .onChange(of: settings.fontFamily) { _, _ in readerLayoutDidChange(delayNanoseconds: 150_000_000) }
        .onChange(of: settings.horizontalPadding) { _, _ in readerLayoutDidChange(delayNanoseconds: 150_000_000) }
        .onChange(of: settings.firstLineIndentEnabled) { _, _ in readerLayoutDidChange(delayNanoseconds: 0) }
        .onChange(of: settings.paragraphSpacingEnabled) { _, _ in readerLayoutDidChange(delayNanoseconds: 0) }
        .onChange(of: settings.pageMode) { _, _ in
            tapSentinel = nil
            cancelPendingHorizontalChapterTransition(returningToCurrentPage: true)
            recomputePages()
            restartAutoPage()
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
                    // 正文按屏幕绝对坐标排版:首行 116、页脚 55 都是相对屏幕底的。
                    pullablePage.ignoresSafeArea()
                }
            }
        }
    }

    /// 顶部面板往下多长多少:让面板底边落在正文的行边界上,被它压住的那一行
    /// 整行藏起来。正文一动不动,动的只是面板。
    private var menuTopInset: CGFloat {
        guard showMenu, bodyTopY > 0, menuTopEdgeY > 0 else { return 0 }
        let line = bodyLineHeight
        guard line > 1 else { return 0 }
        let distance = menuTopEdgeY - bodyTopY
        guard distance > 0 else { return 0 }
        let remainder = distance.truncatingRemainder(dividingBy: line)
        return remainder < 0.5 ? 0 : line - remainder
    }

    /// 底部面板顶边同样按行网格取整:被它压住的那一行整行藏在面板后面,不露字头。
    private var bottomMenuInset: CGFloat {
        guard showMenu, bodyTopY > 0, menuBottomTopY > 0 else { return 0 }
        let line = bodyLineHeight
        guard line > 1 else { return 0 }
        let distance = menuBottomTopY - bodyTopY
        guard distance > 0 else { return 0 }
        let remainder = distance.truncatingRemainder(dividingBy: line)
        return remainder < 0.5 ? 0 : remainder
    }

    /// 全书进度(0…1),和页脚、进度格同一个算法。
    private var overallProgressFraction: Double {
        let pageCount = max(cachedPages.count, 1)
        let currentPage = min(max(currentPageIndex + 1, 1), pageCount)
        let chapterFraction = pageCount > 1
            ? Double(currentPage - 1) / Double(pageCount - 1)
            : 0
        return (Double(currentChapterIndex) + chapterFraction) / Double(max(bookChapterCount, 1))
    }

    /// 菜单进度,和页脚同一个算法。
    private var menuProgressText: String {
        "\(Int((overallProgressFraction * 100).rounded()))%"
    }

    /// 已读章节:读完的整章数用章序号算真数,不估阅读时长。
    /// 读完整本时按总章数计;否则当前章之前的章节都算读完。
    private var readChapterCount: Int {
        let total = max(bookChapterCount, chapters.count)
        if book.readingStatus == .finished {
            return max(total, 0)
        }
        return min(max(currentChapterIndex, 0), max(total, 0))
    }

    /// 阅读明细:只读本机真有的记录,不补 0、不编时长/笔记。
    private var readingStats: ReaderReadingStats {
        ReaderReadingStats(
            readingDays: ReaderActivityStore.readingDays(bookID: bookID),
            pagesRead: ReaderActivityStore.pagesRead(bookID: bookID),
            bookmarkCount: book.marks.filter { !$0.isNote }.count,
            finishedChapters: readChapterCount
        )
    }

    /// 自动翻页:关着或菜单开着时没有计时器;菜单关掉/回到前台自动接着走。
    private func restartAutoPage() {
        autoPageTask?.cancel()
        autoPageTask = nil
        guard autoPageEnabled,
              !showMenu,
              sceneIsActive,
              settings.pageMode != .scroll,
              !storeUnavailable,
              !isClosing else { return }

        let seconds = max(autoPageInterval, 1)
        autoPageTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                guard autoPageEnabled,
                      !showMenu,
                      scenePhase == .active,
                      settings.pageMode != .scroll,
                      !storeUnavailable,
                      !isClosing,
                      selection == nil,
                      !isLoadingContent,
                      !isPaginating else { continue }
                advanceAutoPage()
            }
        }
    }

    private func advanceAutoPage() {
        let totalPages = max(cachedPages.count, 1)
        guard chapters.indices.contains(currentChapterIndex) else { return }
        if settings.pageMode == .tap {
            if currentPageIndex < totalPages - 1 {
                currentPageIndex += 1
            } else if currentChapterIndex < chapters.count - 1 {
                currentChapterIndex += 1
                currentPageIndex = 0
            }
        } else {
            performPageTurn(direction: .next, totalPages: totalPages)
        }
    }

    /// 正文一行的高度 = 字号 × (行距档位 × 字体基准),和排版用的是同一个算法。
    private var bodyLineHeight: CGFloat {
        settings.bodyLineHeight
    }

    /// SwiftUI Text 的 lineSpacing 只补自然行高之外的差额。
    private var bodyLineGap: CGFloat {
        let size = CGFloat(settings.fontSize)
        let font = settings.fontFamily.uiFont(size: size)
        return max(0, bodyLineHeight - font.lineHeight)
    }

    /// 正文容器顶(屏幕坐标):首行字顶 116 减去行内字墨偏移。
    private var bodyContainerTopY: CGFloat {
        let size = CGFloat(settings.fontSize)
        let font = settings.fontFamily.uiFont(size: size)
        let inkOffset = ReaderTypography.inkTopOffset(
            fontSize: size,
            lineHeight: settings.bodyLineHeight,
            font: font
        )
        return max(0, ReaderTypography.bodyTopInkY - inkOffset + ReaderTypography.bodyInkCalibration)
    }

    /// 当前页每一条正文线的行顶(屏幕坐标)。段间距 28 会让行位偏离
    /// 34.2 的全局网格,面板顶边必须贴真实行顶,否则会压住半行字。
    private var currentPageLineTops: [CGFloat] {
        guard viewSize.width > 0,
              cachedPages.indices.contains(currentPageIndex) else { return [] }
        let fragments = cachedPages[currentPageIndex]
        guard !fragments.isEmpty else { return [] }

        let size = CGFloat(settings.fontSize)
        let font = settings.fontFamily.uiFont(size: size)
        let lineHeight = settings.bodyLineHeight
        let textWidth = max(1, viewSize.width - settings.horizontalPadding * 2)
        let spacing = ReaderTypography.characterSpacing(
            fontSize: size,
            textWidth: textWidth,
            font: font
        )
        let indent = ReaderTypography.firstLineIndent(fontSize: size, textWidth: textWidth)

        var tops: [CGFloat] = []
        var y = bodyContainerTopY
        for fragment in fragments {
            // 分页时已经把禁则断行结果用硬换行存进 fragment,这里只数行数,
            // 不再让 boundingRect 重新按自己的断点算高度。
            let lineCount = max(1, ReaderLineBreaker.lines(
                in: fragment.text,
                width: textWidth,
                firstLineIndent: fragment.indent && settings.firstLineIndentEnabled ? indent : 0,
                attributes: [.font: font, .kern: spacing]
            ).count)
            for line in 0..<lineCount {
                tops.append(y + CGFloat(line) * lineHeight)
            }
            y += CGFloat(lineCount) * lineHeight + settings.paragraphSpacing
        }
        return tops
    }

    // MARK: - Scroll Mode

    private var bodyRepeatsChapterTitle: Bool {
        guard let first = cachedParagraphs.first else { return false }
        let body = first.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }
        return body == (currentChapter?.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 滚动模式正文首行字顶 116:SwiftUI Text 的行框顶到字墨顶实测约 2.8 点。
    private var scrollBodyTopInset: CGFloat {
        116 - 2.8
    }

    /// 滚动模式章节名字顶 76:12 号字的行框顶到字墨顶实测约 2 点。
    private var scrollChapterTitleTopInset: CGFloat {
        76 - 2
    }

    /// 滚动模式也按默认 19 号的 18 字行宽补字距,和翻页模式同一套排版。
    private var scrollCharacterSpacing: CGFloat {
        let size = settings.fontSize
        let font = settings.fontFamily.uiFont(size: size)
        let width = viewSize.width > 0 ? viewSize.width : UIScreen.main.bounds.width
        let textWidth = max(1, width - settings.horizontalPadding * 2)
        return ReaderTypography.characterSpacing(
            fontSize: size,
            textWidth: textWidth,
            font: font
        )
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !bodyRepeatsChapterTitle {
                    Text(currentChapter?.title ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(settings.theme.chapterTitleColor)
                        .padding(.top, scrollChapterTitleTopInset)
                        // 章节名行高 14.3 + 25 让正文行框顶落在 116 的字墨线上。
                        .padding(.bottom, 25)
                        // 菜单开着时左上角只有返回箭头,章节名不能和它挤在一起。
                        // 只藏不删,滚动内容的高度和位置保持不变。
                        .opacity(showMenu ? 0 : 1)
                        .allowsHitTesting(!showMenu)
                }

                VStack(alignment: .leading, spacing: settings.paragraphSpacing) {
                ForEach(Array(cachedParagraphs.enumerated()), id: \.offset) { index, para in
                    Text("\u{3000}\u{3000}" + para)
                        .font(settings.fontFamily.isSystem
                            ? .system(size: settings.fontSize)
                            : .custom(settings.fontFamily.postScriptName, size: settings.fontSize))
                        .foregroundStyle(settings.theme.textColor)
                        .lineSpacing(bodyLineGap)
                        .kerning(scrollCharacterSpacing)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(alignment: .topLeading) {
                            if selection?.paragraphIndex == index,
                               selection?.chapterIndex == currentChapterIndex {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(settings.theme.textColor.opacity(0.12))
                                    .padding(.horizontal, -4)
                                    .padding(.vertical, -2)
                            }
                        }
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: ScrollParagraphFramesKey.self,
                                    value: [
                                        index: ScrollParagraphFrame(
                                            global: proxy.frame(in: .global),
                                            inScroll: proxy.frame(in: .named("readerScroll")).minY
                                        )
                                    ]
                                )
                            }
                        )
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.35) {
                            // 菜单开着时长按正文:先收菜单,直接开始选段。
                            if showMenu {
                                showMenu = false
                            }
                            selection = ReaderSelection(
                                paragraphIndex: index,
                                text: para,
                                frame: scrollParagraphFrames[index]?.global ?? .zero,
                                chapterIndex: currentChapterIndex
                            )
                            announceSelection(para)
                        }
                }
                }
                .padding(.top, bodyRepeatsChapterTitle ? scrollBodyTopInset : 0)
            }
            .padding(.horizontal, settings.horizontalPadding)
            .padding(.bottom, 80)
        }
        .coordinateSpace(name: "readerScroll")
        .modifier(ScrollPhaseObserver { moving in
            if isScrollMoving != moving {
                isScrollMoving = moving
            }
        })
        .onPreferenceChange(ScrollParagraphFramesKey.self) { frames in
            scrollParagraphFrames = frames
            // 选区跟着文字走:滚完把工具条要用的框换成新的位置。
            if let selection, selection.chapterIndex == currentChapterIndex,
               let frame = frames[selection.paragraphIndex]?.global {
                self.selection?.frame = frame
            }
            if let first = frames.values
                .filter({ $0.inScroll >= -24 })
                .min(by: { $0.inScroll < $1.inScroll }),
               let index = frames.first(where: { $0.value.inScroll == first.inScroll })?.key {
                visibleParagraphIndex = index
            }
        }
        .id(currentChapterID)
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .global) { location in
            handleTap(location: location)
        }
        .overlay(alignment: .bottom) {
            readerFooter(currentPage: currentPageIndex + 1, totalPages: max(cachedPages.count, 1))
                .opacity(showMenu ? 0 : 1)
                .animation(.linear(duration: 0.12), value: showMenu)
        }
        // 滚动模式也按屏幕绝对坐标排版:首行 116、页脚字底 55 和翻页模式一致。
        .ignoresSafeArea()
    }

    // MARK: - 下拉加书签

    /// 一页外面套一层:下拉时整页(正文 + 页脚)跟手下移,页顶露出提示带和丝带。
    private var pullablePage: some View {
        ZStack(alignment: .top) {
            if pullOffset > 0 {
                pullHintBand
            }
            pagedContent
                .overlay(alignment: .topTrailing) { pullRibbon }
                .offset(y: pullOffset)
        }
        .simultaneousGesture(pullGesture)
    }

    /// 下拉只在翻页模式下、菜单关着、没在选字时认领。
    private var pullGestureEnabled: Bool {
        settings.pageMode != .scroll && !showMenu && selection == nil && !isClosing
    }

    private var pullGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard pullGestureEnabled else { return }
                if !pullClaimed {
                    let dy = value.translation.height
                    let dx = value.translation.width
                    // 只认屏幕上方 260pt 起手、向下且竖着的那一笔。
                    guard value.startLocation.y <= 260, dy >= 18, abs(dy) > abs(dx) else { return }
                    pullClaimed = true
                }
                let dy = value.translation.height
                pullOffset = dy <= 120 ? max(0, dy) : 120 + (dy - 120) * 0.35
            }
            .onEnded { _ in
                guard pullClaimed else { return }
                let triggered = pullOffset >= 100
                pullClaimed = false
                withAnimation(.timingCurve(0.33, 0, 0.2, 1, duration: 0.25)) {
                    pullOffset = 0
                }
                if triggered { togglePageBookmark() }
            }
    }

    /// 当前页第一段上挂着的书签(笔记不算)。
    private var pageBookmarkMark: ReadingMark? {
        guard let anchor = currentPageAnchorParagraph() else { return nil }
        return book.marks.first {
            !$0.isNote
                && $0.chapterIndex == currentChapterIndex
                && $0.paragraphIndex == anchor.index
        }
    }

    /// 松手会发生什么,决定提示文字和丝带的明暗。
    private var pullWillDelete: Bool { pageBookmarkMark != nil }

    private var pullHintBand: some View {
        ZStack(alignment: .top) {
            settings.theme.backgroundColor
            Text(pullWillDelete ? "松手删除书签" : "松手添加书签")
                .font(.system(size: 13))
                .foregroundStyle(settings.theme.textColor.opacity(0.55))
                .padding(.top, 30)
        }
        .frame(height: 88)
        .frame(maxWidth: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    /// 书签丝带:拉动时 26×62 在右上角预示松手结果,已有书签时 24×36 停在页角。
    @ViewBuilder
    private var pullRibbon: some View {
        if pullOffset > 0 {
            BookmarkRibbonShape(notch: 10)
                .fill(settings.theme.accentColor)
                .opacity(pullWillDelete ? 1 : 0.35)
                .frame(width: 26, height: 62)
                .padding(.trailing, 38)
        } else if pageBookmarkMark != nil {
            BookmarkRibbonShape(notch: 8)
                .fill(settings.theme.accentColor)
                .frame(width: 24, height: 36)
                .padding(.trailing, 14)
                .padding(.top, 51)
        }
    }

    private func togglePageBookmark() {
        guard let anchor = currentPageAnchorParagraph() else { return }
        if let mark = pageBookmarkMark {
            deleteMark(mark)
            return
        }
        let mark = ReadingMark(
            chapterIndex: currentChapterIndex,
            paragraphIndex: anchor.index,
            excerpt: anchor.text
        )
        mark.book = book
        modelContext.insert(mark)
        try? modelContext.save()
        showReaderToast("已添加书签", seconds: 1.5)
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
                        pageView(fragments: pages[safeIndex], pageIndex: safeIndex)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .global) { location in
                handlePageTap(location: location, screenSize: geometry.size, totalPages: totalPages)
            }
            .overlay(alignment: .bottom) {
                readerFooter(currentPage: safeIndex + 1, totalPages: totalPages)
                    .opacity(showMenu ? 0 : 1)
                    .animation(.linear(duration: 0.12), value: showMenu)
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
                        case let .page(fragments, chapterTitle, pageIndex):
                            pageView(
                                fragments: fragments,
                                chapterTitle: chapterTitle,
                                pageIndex: pageIndex
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
                        pageView(fragments: pages[index], pageIndex: index)
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
                        chapterTitle: previousChapter.title,
                        pageIndex: max(prepared.pages.count - 1, 0)
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
                    chapterTitle: chapter.title,
                    pageIndex: index
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
                        chapterTitle: nextChapter.title,
                        pageIndex: 0
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
        chapterTitle(at: currentChapterIndex - 1)
    }

    private var nextChapterTitle: String {
        chapterTitle(at: currentChapterIndex + 1)
    }

    private func pageView(
        fragments: [PageFragment],
        chapterTitle: String? = nil,
        pageIndex: Int? = nil
    ) -> some View {
        let extendingHighlight: Bool = {
            guard let pageIndex, let cross = crossSelection, cross.anchorPage != pageIndex else { return false }
            return cross.direction > 0 ? pageIndex > cross.anchorPage : pageIndex < cross.anchorPage
        }()
        return StaticPageView(
            fragments: fragments,
            chapterTitle: chapterTitle ?? currentChapterTitle,
            showsChapterTitle: (pageIndex ?? currentPageIndex) != 0 && !showMenu,
            fontSize: settings.fontSize,
            lineSpacing: settings.lineSpacing,
            fontFamily: settings.fontFamily.rawValue,
            textColor: settings.theme.textColor,
            titleColor: settings.theme.chapterTitleColor,
            horizontalPadding: settings.horizontalPadding,
            bottomReserve: pageBottomReserve,
            paragraphSpacing: settings.paragraphSpacing,
            firstLineIndentEnabled: settings.firstLineIndentEnabled,
            bodyLineHeight: settings.bodyLineHeight,
            selectedParagraphIndex: selection?.paragraphIndex,
            onSelectParagraph: { index, text, frame in
                if showMenu {
                    showMenu = false
                }
                selection = ReaderSelection(
                    paragraphIndex: index,
                    text: text,
                    frame: frame,
                    chapterIndex: currentChapterIndex
                )
            },
            accentColor: settings.theme.accentColor,
            highlightAll: extendingHighlight,
            desiredSelection: pageIndex == currentPageIndex ? pendingPageSelection : nil,
            onSelectionChange: { range in
                pageSelection = range
                if pendingPageSelection != nil, range.length > 0 {
                    pendingPageSelection = nil
                }
            },
            onEdgeHold: { isTop in handleSelectionEdgeHold(isTop: isTop) },
            onScreenTap: { point in handleTap(location: point) }
        )
    }

    // MARK: - Tap Handling

    private func handleTap(location: CGPoint) {
        guard beginReaderTap(at: location) else { return }
        // 页面手势只负责开菜单;关闭交给菜单浮层的全屏背景层,
        // 避免同一次点击的第二份投递把刚打开的菜单又按回去。
        guard !showMenu else { return }
        // 浮层刚关菜单时,同一次点击的页面手势可能晚到;短暂忽略,防止又开回来。
        guard CFAbsoluteTimeGetCurrent() - lastMenuDismissAt > 0.5 else { return }
        if selection != nil {
            selection = nil
            return
        }

        // 滚动模式没有左右翻页,保持原来的中间三分之一开菜单。
        if settings.pageMode == .scroll {
            let screenSize = currentWindowSize
            let screenWidth = screenSize.width
            let screenHeight = screenSize.height
            let centerXRange = (screenWidth / 3)...(screenWidth * 2 / 3)
            let centerYRange = (screenHeight / 3)...(screenHeight * 2 / 3)
            if centerXRange.contains(location.x) && centerYRange.contains(location.y) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showMenu.toggle()
                }
            }
            return
        }

        performReaderTap(
            location: location,
            screenSize: currentWindowSize,
            totalPages: max(cachedPages.count, 1)
        )
    }

    private func handlePageTap(location: CGPoint, screenSize: CGSize, totalPages: Int) {
        guard beginReaderTap(at: location) else { return }
        // 同上:页面手势只开菜单,关闭交给浮层背景层。
        guard !showMenu else { return }
        guard CFAbsoluteTimeGetCurrent() - lastMenuDismissAt > 0.5 else { return }
        if selection != nil {
            selection = nil
            return
        }
        performReaderTap(location: location, screenSize: screenSize, totalPages: totalPages)
    }

    /// 手势统一成窗口坐标后,分区判断也用同一套窗口尺寸。
    private var currentWindowSize: CGSize {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
        return window?.bounds.size ?? UIScreen.main.bounds.size
    }

    /// 同一次点击可能被 PageTextView 的手势和父级 onTapGesture 各收到一次,
    /// 80 毫秒内同一点只处理一次,避免翻两页或菜单开了又关。
    ///
    /// 两个手势现在都投递窗口坐标(.global / convert to nil),同一次点击的
    /// 两点只差亚像素;80 点容差只是兜底,人手不可能在 80 毫秒内点两处相距
    /// 80 点的位置。
    private func beginReaderTap(at location: CGPoint) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        let dx = location.x - lastReaderTapLocation.x
        let dy = location.y - lastReaderTapLocation.y
        let tolerance: CGFloat = 80
        if now - lastReaderTapAt < 0.08, dx * dx + dy * dy < tolerance * tolerance {
            return false
        }
        lastReaderTapAt = now
        lastReaderTapLocation = location
        return true
    }

    /// 竖直方向只认正文区;页脚那一行不响应,横向按 42 / 62 点分流。
    private func readerTapAction(location: CGPoint, screenSize: CGSize) -> ReaderTapAction {
        guard screenSize.width > 0, screenSize.height > 0 else { return .none }
        let footerTop = screenSize.height - ReaderTypography.footerBottomInset - 16
        let contentTop = min(bodyContainerTopY, footerTop)
        let contentBottom = min(
            bodyContainerTopY + bodyLineHeight * ReaderTypography.bodyLineCount,
            footerTop
        )
        guard location.y >= contentTop - 0.5, location.y <= contentBottom + 0.5 else {
            return .none
        }
        if location.x < previousPageTapWidth {
            return .previousPage
        }
        if location.x > screenSize.width - nextPageTapWidth {
            return .nextPage
        }
        return .toggleMenu
    }

    private func performReaderTap(location: CGPoint, screenSize: CGSize, totalPages: Int) {
        switch readerTapAction(location: location, screenSize: screenSize) {
        case .previousPage:
            performPageTurn(direction: .previous, totalPages: totalPages)
        case .nextPage:
            performPageTurn(direction: .next, totalPages: totalPages)
        case .toggleMenu:
            withAnimation(.easeInOut(duration: 0.2)) {
                showMenu.toggle()
            }
        case .none:
            break
        }
    }

    private func performPageTurn(direction: HorizontalDirection, totalPages: Int) {
        let chapterBefore = currentChapterIndex
        let pageBefore = currentPageIndex
        defer {
            if currentChapterIndex != chapterBefore || currentPageIndex != pageBefore {
                ReaderActivityStore.recordPageFlip(bookID: bookID)
            }
        }
        let hasPrev = currentChapterIndex > 0
        let hasNext = currentChapterIndex < chapters.count - 1

        if settings.pageMode == .tap {
            if direction == .previous {
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
            }
        } else {
            handleHorizontalPageTap(
                direction: direction,
                totalPages: totalPages,
                hasPrev: hasPrev,
                hasNext: hasNext
            )
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

    struct CrossSelection: Equatable {
        var anchorPage: Int
        var direction: Int
    }

    /// 手指拖到页面上下边缘停住 0.45 秒:翻到相邻页/相邻章,并把选中延伸过去。
    private func handleSelectionEdgeHold(isTop: Bool) {
        guard settings.pageMode != .scroll, !showMenu else { return }
        let lastPage = max(cachedPages.count - 1, 0)
        let fromPage = currentPageIndex
        if isTop {
            if currentPageIndex > 0 {
                currentPageIndex -= 1
            } else if currentChapterIndex > 0 {
                currentChapterIndex -= 1
                currentPageIndex = max(cachedPages.count - 1, 0)
            } else {
                return
            }
            // 新页整页算进选区:锚点留在刚才那页,方向向上。
            crossSelection = CrossSelection(anchorPage: fromPage, direction: -1)
        } else {
            if currentPageIndex < lastPage {
                currentPageIndex += 1
            } else if currentChapterIndex < chapters.count - 1 {
                currentChapterIndex += 1
                currentPageIndex = 0
            } else {
                return
            }
            crossSelection = CrossSelection(anchorPage: fromPage, direction: 1)
        }
        pendingPageSelection = nil
    }

    struct PageFragment: Identifiable, Sendable {
        let id: Int
        let text: String
        let indent: Bool
        /// Paragraph inside the chapter; a paragraph split across pages keeps the same index.
        var paragraphIndex: Int = 0
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
            bottomReserve: Double(pageBottomReserve),
            paragraphSpacing: Double(settings.paragraphSpacing),
            firstLineIndent: settings.firstLineIndentEnabled
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
            bottomReserve: Double(pageBottomReserve),
            paragraphSpacing: Double(settings.paragraphSpacing),
            firstLineIndent: settings.firstLineIndentEnabled
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
        let anchorParagraph = currentPageAnchorParagraph()?.index
        layoutAnchorParagraph = anchorParagraph
        cancelPendingHorizontalChapterTransition(returningToCurrentPage: true)
        adjacentPreparationTask?.cancel()
        adjacentPreparationTask = nil
        adjacentPreparationGeneration = nil
        adjacentPreparationActiveChapterID = nil
        preparedChapterWindow.invalidateLayouts()
        recomputePages(delayNanoseconds: delayNanoseconds)

        guard let anchorParagraph else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            // 只有这次重排设下的锚点才生效,不抢正常的翻页。
            guard layoutAnchorParagraph == anchorParagraph else { return }
            layoutAnchorParagraph = nil
            guard !cachedPages.isEmpty else { return }
            let targetPage: Int?
            if let exactPage = cachedPages.firstIndex(where: {
                $0.first?.paragraphIndex == anchorParagraph
            }) {
                targetPage = exactPage
            } else {
                targetPage = cachedPages.lastIndex(where: {
                    ($0.first?.paragraphIndex ?? Int.max) <= anchorParagraph
                })
            }
            guard let targetPage else { return }
            currentPageIndex = min(max(targetPage, 0), max(cachedPages.count - 1, 0))
            scrolledPage = currentHorizontalPageID(pageIndex: currentPageIndex)
        }
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
            applyPendingParagraphJump()
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
        let fontSize = CGFloat(input.fontSize)
        // 一页正文固定 18 行的容量:行高 = 字号 × 倍率。
        let lineHeight = ReaderTypography.bodyLineHeight(fontSize: fontSize, level: input.lineSpacing)
        let pageHeight = lineHeight * ReaderTypography.bodyLineCount
        let paragraphGap = CGFloat(input.paragraphSpacing)

        let font = FontFamily.uiFont(
            family: input.fontFamily,
            size: fontSize,
            usesSystemFont: input.usesSystemFont
        )
        let characterSpacing = ReaderTypography.characterSpacing(
            fontSize: fontSize,
            textWidth: textWidth,
            font: font
        )
        let indentWidth = ReaderTypography.firstLineIndent(fontSize: fontSize, textWidth: textWidth)

        func style(indent: Bool) -> NSParagraphStyle {
            let paraStyle = NSMutableParagraphStyle()
            paraStyle.lineSpacing = 0
            paraStyle.minimumLineHeight = lineHeight
            paraStyle.maximumLineHeight = lineHeight
            paraStyle.paragraphSpacing = 0
            paraStyle.firstLineHeadIndent = indent && input.firstLineIndent ? indentWidth : 0
            return paraStyle
        }

        func attributes(indent: Bool) -> [NSAttributedString.Key: Any] {
            [
                .font: font,
                .paragraphStyle: style(indent: indent),
                .kern: characterSpacing
            ]
        }

        func lineStrings(_ text: String, indent: Bool) -> [String] {
            // 标点禁则和分页共用同一套断行:这里算好的行会以硬换行拼回去,
            // TextKit 渲染时不会再自行改断点。
            let firstIndent = indent && input.firstLineIndent ? indentWidth : 0
            return ReaderLineBreaker.lines(
                in: text,
                width: textWidth,
                firstLineIndent: firstIndent,
                attributes: attributes(indent: false)
            )
        }

        func measureHeight(_ text: String, indent: Bool) -> CGFloat {
            // 行数 × 行高,不再用 boundingRect 的四舍五入结果。
            CGFloat(lineStrings(text, indent: indent).count) * lineHeight
        }

        func splitText(_ text: String, indent: Bool, fitting height: CGFloat) -> (String, String)? {
            // 剩下的高度能放下一整行就切一行,不要把整段推到下一页。
            let safeHeight = height
            guard safeHeight >= lineHeight - 0.5 else { return nil }

            let lines = lineStrings(text, indent: indent)
            let maxLines = Int(floor((safeHeight + 0.5) / lineHeight))
            guard maxLines > 0, lines.count > maxLines else { return nil }

            let first = lines.prefix(maxLines).joined(separator: "\n")
            let second = lines.dropFirst(maxLines).joined(separator: "\n")
            guard !second.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return (first, second)
        }

        struct QueueItem {
            let text: String
            let indent: Bool
            let paragraphIndex: Int
        }

        var queue = paragraphs.enumerated().reversed().map {
            QueueItem(text: $1, indent: true, paragraphIndex: $0)
        }
        var pages: [[PageFragment]] = []
        var currentPage: [PageFragment] = []
        var currentHeight: CGFloat = 0
        var fragmentId = 0

        while let item = queue.popLast() {
            guard !Task.isCancelled else { return nil }
            let brokenText = lineStrings(item.text, indent: item.indent).joined(separator: "\n")
            let h = measureHeight(item.text, indent: item.indent)
            let gap = currentPage.isEmpty ? 0 : paragraphGap

            if currentHeight + gap + h <= pageHeight {
                fragmentId += 1
                currentPage.append(PageFragment(id: fragmentId, text: brokenText, indent: item.indent, paragraphIndex: item.paragraphIndex))
                currentHeight += gap + h
            } else if currentPage.isEmpty {
                if let (first, second) = splitText(item.text, indent: item.indent, fitting: pageHeight - currentHeight) {
                    fragmentId += 1
                    currentPage.append(PageFragment(id: fragmentId, text: first, indent: item.indent, paragraphIndex: item.paragraphIndex))
                    pages.append(currentPage)
                    currentPage = []
                    currentHeight = 0
                    queue.append(QueueItem(text: second, indent: false, paragraphIndex: item.paragraphIndex))
                } else {
                    fragmentId += 1
                    currentPage.append(PageFragment(id: fragmentId, text: brokenText, indent: item.indent, paragraphIndex: item.paragraphIndex))
                    pages.append(currentPage)
                    currentPage = []
                    currentHeight = 0
                }
            } else {
                let remaining = pageHeight - currentHeight - gap
                if remaining >= lineHeight - 0.5,
                   let (first, second) = splitText(item.text, indent: item.indent, fitting: remaining) {
                    fragmentId += 1
                    currentPage.append(PageFragment(id: fragmentId, text: first, indent: item.indent, paragraphIndex: item.paragraphIndex))
                    pages.append(currentPage)
                    currentPage = []
                    currentHeight = 0
                    queue.append(QueueItem(text: second, indent: false, paragraphIndex: item.paragraphIndex))
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

    // MARK: - Bookmarks and Notes

    private func selectionToolbar(for selection: ReaderSelection) -> some View {
        GeometryReader { geometry in
            let size = geometry.size
            let toolbarHeight: CGFloat = 44
            let gap: CGFloat = 8
            let width: CGFloat = 186
            let frame = selection.frame
            let fitsAbove = frame.minY - gap - toolbarHeight > 40
            let y = fitsAbove
                ? frame.minY - gap - toolbarHeight
                : min(frame.maxY + gap, size.height - toolbarHeight - 20)
            let origin = geometry.frame(in: .global).origin
            let x = min(max(frame.midX - width / 2, 8), max(size.width - width - 8, 8)) - origin.x

            let summary = selectionSummary(selection.text)

            HStack(spacing: 0) {
                selectionAction(icon: "bookmark", title: "书签", accessibility: "添加书签", hint: summary) {
                    addBookmark(from: selection)
                }
                selectionAction(icon: "note.text", title: "笔记", accessibility: "写笔记", hint: summary) {
                    openNote(from: selection)
                }
                selectionAction(icon: "doc.on.doc", title: "复制", accessibility: "复制", hint: summary) {
                    copySelection(selection)
                }
            }
            .frame(width: width, height: toolbarHeight)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(settings.theme.textColor)
            )
            .offset(x: x, y: y - origin.y)
        }
    }

    /// VoiceOver hears what was selected and how long it is as soon as the
    /// toolbar appears; the toolbar's three buttons stay ordinary elements.
    private func selectionSummary(_ text: String) -> String {
        let count = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        return "已选中一段，共 \(count) 字"
    }

    private func announceSelection(_ text: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: selectionSummary(text))
    }

    private func selectionAction(
        icon: String,
        title: String,
        accessibility: String,
        hint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(title)
                    .font(.system(size: 10))
            }
            .foregroundStyle(settings.theme.backgroundColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
        .accessibilityHint(hint)
    }

    private func showReaderToast(_ text: String, seconds: Double = 2, undo: (() -> Void)? = nil) {
        readerToastUndo = undo
        withAnimation(.easeInOut(duration: 0.15)) { readerToast = text }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.15)) { readerToast = nil }
                readerToastUndo = nil
            }
        }
    }

    private func copySelection(_ selection: ReaderSelection) {
        UIPasteboard.general.string = selection.text
        self.selection = nil
        showReaderToast("已复制")
    }

    private func addBookmark(from selection: ReaderSelection) {
        let alreadySaved = book.marks.contains {
            $0.chapterIndex == selection.chapterIndex
                && $0.paragraphIndex == selection.paragraphIndex
        }
        if alreadySaved {
            self.selection = nil
            showReaderToast("已添加书签")
            return
        }
        let mark = ReadingMark(
            chapterIndex: selection.chapterIndex,
            paragraphIndex: selection.paragraphIndex,
            excerpt: selection.text
        )
        mark.book = book
        modelContext.insert(mark)
        try? modelContext.save()
        self.selection = nil
        showReaderToast("已添加书签")
    }

    private func openNote(from selection: ReaderSelection) {
        noteDraft = NoteDraft(
            chapterIndex: selection.chapterIndex,
            paragraphIndex: selection.paragraphIndex,
            excerpt: selection.text
        )
        self.selection = nil
    }

    private func saveNote(_ note: String, for draft: NoteDraft) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let mark = draft.mark {
            mark.note = trimmed.isEmpty ? nil : trimmed
            try? modelContext.save()
        } else {
            let mark = ReadingMark(
                chapterIndex: draft.chapterIndex,
                paragraphIndex: draft.paragraphIndex,
                excerpt: draft.excerpt,
                note: trimmed.isEmpty ? nil : trimmed
            )
            mark.book = book
            modelContext.insert(mark)
            try? modelContext.save()
        }
        showReaderToast("笔记已保存")
    }

    private func deleteMark(_ mark: ReadingMark) {
        let chapterIndex = mark.chapterIndex
        let paragraphIndex = mark.paragraphIndex
        let excerpt = mark.excerpt
        let note = mark.note
        let wasNote = mark.isNote
        modelContext.delete(mark)
        try? modelContext.save()
        showReaderToast(wasNote ? "已删除笔记" : "已删除书签", undo: {
            let restored = ReadingMark(
                chapterIndex: chapterIndex,
                paragraphIndex: paragraphIndex,
                excerpt: excerpt,
                note: note
            )
            restored.book = book
            modelContext.insert(restored)
            try? modelContext.save()
        })
    }

    /// Bookmarks the first paragraph visible on the current page.
    /// The paragraph the current page starts at, skipping a heading repeated in
    /// the body. Used by the bookmark and the note entry points in the menu.
    private func currentPageAnchorParagraph() -> (index: Int, text: String)? {
        let paragraphIndex: Int
        if settings.pageMode == .scroll {
            paragraphIndex = visibleParagraphIndex
        } else if let page = cachedPages.indices.contains(currentPageIndex) ? cachedPages[currentPageIndex] : nil,
                  let first = page.first?.paragraphIndex {
            paragraphIndex = first
        } else {
            return nil
        }
        guard cachedParagraphs.indices.contains(paragraphIndex) else { return nil }
        var chosen = paragraphIndex
        var text = cachedParagraphs[chosen]
        // The first paragraph of a chapter is often the chapter title itself;
        // a bookmark on it would read as the heading, not as text.
        if isChapterTitleParagraph(text, at: chosen),
           cachedParagraphs.indices.contains(chosen + 1) {
            chosen += 1
            text = cachedParagraphs[chosen]
        }
        return (chosen, text)
    }

    private func addBookmarkAtCurrentPage() {
        guard let anchor = currentPageAnchorParagraph() else { return }
        addBookmark(from: ReaderSelection(
            paragraphIndex: anchor.index,
            text: anchor.text,
            frame: .zero,
            chapterIndex: currentChapterIndex
        ))
    }

    /// 书签面板顶部的「写笔记」:摘录取当前页第一段,直接进笔记编辑。
    private func writeNoteAtCurrentPage() {
        guard let anchor = currentPageAnchorParagraph() else { return }
        showMenu = false
        noteDraft = NoteDraft(
            chapterIndex: currentChapterIndex,
            paragraphIndex: anchor.index,
            excerpt: anchor.text
        )
    }

    /// True when the paragraph is the chapter heading repeated in the body.
    private func isChapterTitleParagraph(_ text: String, at index: Int) -> Bool {
        guard index == 0 else { return false }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }
        let title = (currentChapter?.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !title.isEmpty && body == title
    }

    private func jump(to mark: ReadingMark) {
        selection = nil
        pendingParagraphJump = mark.paragraphIndex
        if mark.chapterIndex != currentChapterIndex {
            currentChapterIndex = mark.chapterIndex
        } else {
            applyPendingParagraphJump()
        }
    }

    private func applyPendingParagraphJump() {
        guard let paragraphIndex = pendingParagraphJump else { return }
        pendingParagraphJump = nil
        guard let pageIndex = cachedPages.firstIndex(where: { page in
            page.contains { $0.paragraphIndex == paragraphIndex }
        }) else { return }
        currentPageIndex = pageIndex
    }

    private func persistReadingPosition() {
        let manager = BookManager(modelContext: modelContext)
        manager.updateProgress(book: book, chapterIndex: currentChapterIndex, position: chapterPositionFraction)
    }

    private func applyKeepScreenAwake() {
        UIApplication.shared.isIdleTimerDisabled = settings.keepScreenAwake
    }

    /// 本章已读字符数(当前页起点,1 起算)与本篇总字符数;空白和分页硬换行都不算。
    private var chapterPositionText: String {
        let total = cachedParagraphs.reduce(0) { $0 + ReaderCharacterCount.count($1) }
        guard total > 0 else { return "0 / 0" }

        let consumed: Int
        if settings.pageMode == .scroll {
            let end = min(max(visibleParagraphIndex, 0), cachedParagraphs.count)
            consumed = cachedParagraphs.prefix(end).reduce(0) { $0 + ReaderCharacterCount.count($1) }
        } else {
            let end = min(max(currentPageIndex, 0), cachedPages.count)
            consumed = cachedPages.prefix(end).reduce(0) { partial, page in
                partial + page.reduce(0) { $0 + ReaderCharacterCount.count($1.text) }
            }
        }
        let position = min(max(consumed + 1, 1), total)
        return "\(position) / \(total)"
    }

    /// 页脚:左书名(一行省略,不加书名号)、右本章已读/总字数。
    /// 11 点、次要色,左右和正文对齐,字底离屏幕底 55。
    private func readerFooter(currentPage: Int, totalPages: Int) -> some View {
        let color = settings.theme.statusBarColor
        let positionText = chapterPositionText
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(bookTitle)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(positionText)
                .monospacedDigit()
                .fixedSize()
                .frame(alignment: .trailing)
        }
        .font(.system(size: 11))
        .foregroundStyle(color)
        .padding(.horizontal, settings.horizontalPadding)
        // 字底 55:字身底边到屏幕底的距离,行框底还留着 descender 的一点空。
        // 实测再往下 0.3 点正好让字墨底落进 55 点(3x 下 1 像素)。
        .padding(.bottom, ReaderTypography.footerBottomInset - 2.7)
        .frame(maxWidth: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
        // 读屏整行一句。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("《\(bookTitle)》,本章读到 \(positionText)")
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
    let paragraphSpacing: Double
    let firstLineIndent: Bool
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
    let paragraphSpacing: Double
    let firstLineIndent: Bool
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
    /// 章节名只在「本章不是第一页」且菜单关着时出现。
    let showsChapterTitle: Bool
    let fontSize: CGFloat
    let lineSpacing: Double
    let fontFamily: String
    let textColor: Color
    let titleColor: Color
    let horizontalPadding: CGFloat
    let bottomReserve: CGFloat
    let paragraphSpacing: CGFloat
    let firstLineIndentEnabled: Bool
    let bodyLineHeight: CGFloat
    /// Paragraph currently selected for a bookmark or note.
    var selectedParagraphIndex: Int?
    /// Long press on a paragraph: index, full text and its screen frame.
    var onSelectParagraph: ((Int, String, CGRect) -> Void)?
    /// 系统选字:强调色、跨页高亮、选区回调、边缘停留回调。
    var accentColor: Color = .accentColor
    var highlightAll: Bool = false
    var extraHighlight: NSRange?
    var desiredSelection: NSRange?
    var onSelectionChange: ((NSRange) -> Void)?
    var onEdgeHold: ((Bool) -> Void)?
    /// 文本视图吃掉单击,把它截下来交回 SwiftUI 的点击分流。
    var onScreenTap: ((CGPoint) -> Void)?

    private var uiFont: UIFont {
        FontFamily.uiFont(
            family: fontFamily,
            size: fontSize,
            usesSystemFont: fontFamily == FontFamily.system.rawValue
        )
    }

    /// 章节名 12 号字在 76 的位置:行框顶到字面顶约 3 点。
    private var chapterTitleLayoutY: CGFloat {
        ReaderTypography.chapterTitleTopInkY - 2
    }

    var body: some View {
        GeometryReader { proxy in
            let pageWidth = proxy.size.width
            let textWidth = max(0, pageWidth - horizontalPadding * 2)
            let inkOffset = ReaderTypography.inkTopOffset(
                fontSize: fontSize,
                lineHeight: bodyLineHeight,
                font: uiFont
            )
            // 首行字顶 116:文本容器顶 = 116 - 行内字顶偏移。
            let bodyLayoutY = max(0, ReaderTypography.bodyTopInkY - inkOffset + ReaderTypography.bodyInkCalibration)
            ZStack(alignment: .topLeading) {
                if showsChapterTitle {
                    Text(chapterTitle)
                        .font(.system(size: ReaderPageHeaderMetrics.fontSize))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: textWidth, alignment: .leading)
                        .offset(x: horizontalPadding, y: chapterTitleLayoutY)
                }

                PageTextView(
                    fragments: fragments,
                    fontSize: fontSize,
                    lineSpacing: lineSpacing,
                    fontFamily: fontFamily,
                    textColor: textColor,
                    textWidth: textWidth,
                    paragraphSpacing: paragraphSpacing,
                    firstLineIndentEnabled: firstLineIndentEnabled,
                    highlightedParagraph: selectedParagraphIndex,
                    accentColor: accentColor,
                    highlightAll: highlightAll,
                    extraHighlight: extraHighlight,
                    desiredSelection: desiredSelection,
                    onSelectionChanged: onSelectionChange,
                    onEdgeHold: onEdgeHold,
                    onScreenTap: onScreenTap
                )
                .frame(
                    width: textWidth,
                    height: max(0, proxy.size.height - bodyLayoutY),
                    alignment: .topLeading
                )
                .offset(x: horizontalPadding, y: bodyLayoutY)

                Color.clear
                    .frame(width: 1, height: 1)
                    .preference(key: ReaderBodyTopPreference.self, value: ReaderTypography.bodyTopInkY)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }
}

/// 正文第一行的顶边在屏幕上的位置;菜单打开时用它把正文让到整行边界上。
struct ReaderBodyTopPreference: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        guard next > 0 else { return }
        value = value == 0 ? next : min(value, next)
    }
}

/// Where a paragraph sits on screen, in global space and inside the scroll view.
struct ScrollParagraphFrame: Equatable {
    let global: CGRect
    let inScroll: CGFloat
}

struct ScrollParagraphFramesKey: PreferenceKey {
    static var defaultValue: [Int: ScrollParagraphFrame] = [:]
    static func reduce(value: inout [Int: ScrollParagraphFrame], nextValue: () -> [Int: ScrollParagraphFrame]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// 报告滚动是否还在进行(iOS 18 才有 true 的滚动阶段;旧系统当作一直静止)。
private struct ScrollPhaseObserver: ViewModifier {
    let onChange: (Bool) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, phase in
                onChange(phase != .idle)
            }
        } else {
            content
        }
    }
}

/// A paragraph the reader picked for a bookmark or a note.
struct ReaderSelection: Equatable {
    let paragraphIndex: Int
    let text: String
    /// Screen frame of the paragraph, used to place the action toolbar.
    var frame: CGRect
    let chapterIndex: Int
}

/// What the note editor is editing.
struct NoteDraft: Identifiable {
    let id = UUID()
    let chapterIndex: Int
    let paragraphIndex: Int
    let excerpt: String
    var mark: ReadingMark?
    /// Plain id of `mark`: the sheet is normally presented from `.sheet(item:)`
    /// and can outlive a context reset, which destroys the model itself.
    var markID: UUID?
}

/// Screen brightness of the reader's window. Kept in one place so the reader can
/// restore the system value when it closes.
enum ReaderScreenBrightness {
    static var current: Double {
        Double(windowScene?.screen.brightness ?? 1)
    }

    static func set(_ value: Double) {
        windowScene?.screen.brightness = CGFloat(min(max(value, 0), 1))
    }

    private static var windowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }
}

/// 书签丝带:下端一个燕尾。拉动时是松手结果的预告,落定后是留在页角的那一枚。
struct BookmarkRibbonShape: Shape {
    var notch: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - notch))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
