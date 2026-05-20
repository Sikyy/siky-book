import SwiftUI
import SwiftData

struct ReaderView: View {
    let book: Book
    @Query private var chapters: [Chapter]
    @State private var currentChapterIndex: Int
    @State private var showMenu = false
    @State private var scrollPosition: String?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var settings = ReaderSettings()
    @State private var isLoadingContent = false
    @State private var loadError: String?

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

    private var characterCount: Int {
        chapterText.count
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
                    chapters: chapters
                )
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(!showMenu)
        .onChange(of: currentChapterIndex) { _, newValue in
            let manager = BookManager(modelContext: modelContext)
            manager.updateProgress(book: book, chapterIndex: newValue, position: 0)
            settings.save()
        }
        .onDisappear {
            let manager = BookManager(modelContext: modelContext)
            manager.updateProgress(book: book, chapterIndex: currentChapterIndex, position: 0)
        }
        .preferredColorScheme(settings.theme.isDark ? .dark : .light)
    }

    private var paragraphs: [String] {
        chapterText
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

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
                .onTapGesture { location in
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
                .overlay(alignment: .bottom) {
                    if !showMenu {
                        statusBar
                    }
                }
            }
        }
        .onAppear { fetchChapterContentIfNeeded() }
        .onChange(of: currentChapterIndex) { _, _ in fetchChapterContentIfNeeded() }
    }

    private func fetchChapterContentIfNeeded() {
        guard let chapter = currentChapter,
              chapter.content == nil,
              let sourceURL = chapter.sourceURL,
              !isLoadingContent else { return }

        isLoadingContent = true
        loadError = nil

        Task {
            do {
                let html = try await NetworkClient.shared.fetchString(url: sourceURL)
                let bookSourceId = book.sourceId
                if let bookSourceId {
                    let descriptor = FetchDescriptor<BookSource>(predicate: #Predicate<BookSource> { $0.id == bookSourceId })
                    if let bookSource = try? modelContext.fetch(descriptor).first {
                        let legado = try LegadoSourceParser.parse(json: bookSource.ruleJSON)
                        if let contentRule = legado.contentRule {
                            let content = try SourceEngine().parseContent(html: html, rule: contentRule, baseURL: legado.url)
                            await MainActor.run {
                                chapter.content = content
                                chapter.isCached = true
                                isLoadingContent = false
                            }
                            return
                        }
                    }
                }
                await MainActor.run {
                    loadError = "无法解析内容"
                    isLoadingContent = false
                }
            } catch {
                await MainActor.run {
                    loadError = "加载失败"
                    isLoadingContent = false
                }
            }
        }
    }

    private var statusBar: some View {
        HStack {
            Text(book.title)
                .font(.system(size: 11))
                .foregroundStyle(settings.theme.statusBarColor)
            Spacer()
            Text("\(currentChapterIndex + 1) / \(book.totalChapters)")
                .font(.system(size: 11))
                .foregroundStyle(settings.theme.statusBarColor)
        }
        .padding(.horizontal, settings.horizontalPadding)
        .padding(.bottom, 8)
    }
}
