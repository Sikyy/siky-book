import SwiftUI

/// Result of asking the book's source for its latest table of contents.
enum TocRefreshOutcome: Sendable {
    case added(Int)
    case upToDate
    case failed
    case unavailable
}

struct ReaderMenuOverlay: View {
    let book: Book
    @Binding var currentChapterIndex: Int
    let totalChapters: Int
    let chapterTitle: String
    let settings: ReaderSettings
    let onDismiss: () -> Void
    let onBack: () -> Void
    let chapters: [Chapter]
    var onCache: ((Int?) -> Void)? = nil
    var onCancelCache: (() -> Void)? = nil
    var onResumeCache: (() -> Void)? = nil
    var cacheState: ReaderCachePresentationState = .unavailable
    var onRefreshToc: (() async -> TocRefreshOutcome)? = nil
    var brightness: Double = 1
    var isFollowingSystemBrightness: Bool = true
    var onBrightnessChange: ((Double) -> Void)? = nil
    var onFollowSystemBrightness: (() -> Void)? = nil

    private var theme: ReaderTheme { settings.theme }

    @State private var showChapterList = false
    @State private var sliderValue: Double = 0
    @State private var showSettings = false
    @State private var draggingFontSize: Double?
    @State private var draggingLineSpacing: Double?
    @State private var chapterSearch = ""
    @State private var isUpdatingToc = false
    @State private var tocToast: String?
    @State private var tocToastRetryable = false
    @State private var tocToastTask: Task<Void, Never>?
    @State private var brightnessValue: Double = 1
    @State private var followSystemFlash = false

    var body: some View {
        ZStack {
            Color.clear
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                topBar
                if onBrightnessChange != nil {
                    brightnessBar
                }
                Spacer()
                bottomPanel
            }
        }
        .onAppear {
            sliderValue = Double(currentChapterIndex)
            brightnessValue = brightness
        }
        .onChange(of: brightness) { _, newValue in
            if !isFollowingSystemBrightness {
                brightnessValue = newValue
            }
        }
        .onChange(of: isFollowingSystemBrightness) { _, following in
            if following { brightnessValue = brightness }
        }
        .onChange(of: currentChapterIndex) { _, newValue in
            sliderValue = Double(newValue)
        }
        .sheet(isPresented: $showChapterList) {
            chapterListContent
                .presentationDetents([.medium, .large])
                .presentationBackground(theme.menuBackground)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: { onBack() }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                    Text("返回")
                        .font(.system(size: 16))
                }
                .foregroundStyle(theme.menuPrimary)
            }
            Spacer()
            Text(chapterTitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.menuPrimary)
                .lineLimit(1)
            Spacer()
            cacheTopBarControl
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(theme.menuBackground, ignoresSafeAreaEdges: .top)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.menuSeparator).frame(height: 1)
        }
    }

    @ViewBuilder
    private var cacheTopBarControl: some View {
        if let onCache {
            switch cacheState {
            case .unavailable:
                cacheControlPlaceholder

            case .checking:
                VStack(spacing: 2) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(theme.menuPrimary)
                    Text("检查中")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.menuSecondary)
                }
                .frame(width: 56, height: 36)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("正在检查已有缓存")

            case .empty:
                Menu {
                    Button("缓存接下来 100 章") { onCache(100) }
                    Button("缓存全部") { onCache(nil) }
                } label: {
                    cacheTopLabel(
                        icon: "arrow.down.circle",
                        text: "缓存",
                        color: theme.menuPrimary
                    )
                }
                .accessibilityLabel("缓存小说")

            case let .partial(cached, total):
                Menu {
                    Button("缓存接下来 100 章") { onCache(100) }
                    Button("补全剩余 \(max(0, total - cached)) 章") { onCache(nil) }
                } label: {
                    cacheTopLabel(
                        icon: "arrow.down.circle.fill",
                        text: cacheCountText(cached: cached, total: total),
                        color: theme.menuPrimary
                    )
                }
                .accessibilityLabel("已缓存 \(cached) 章，共 \(total) 章")

            case let .queued(position, cached, total):
                Button {
                    onCancelCache?()
                } label: {
                    cacheTopLabel(
                        icon: "clock.fill",
                        text: position.map { "排队 \($0)" } ?? cacheCountText(cached: cached, total: total),
                        color: theme.menuSecondary
                    )
                }
                .accessibilityLabel(queuedAccessibilityLabel(position: position, cached: cached, total: total))
                .accessibilityHint("轻点暂停缓存任务")

            case let .running(processed, target, cached, total):
                Button {
                    onCancelCache?()
                } label: {
                    VStack(spacing: 2) {
                        ZStack {
                            Circle()
                                .stroke(theme.menuDisabled, lineWidth: 2)
                            Circle()
                                .trim(from: 0, to: taskProgress(processed: processed, target: target))
                                .stroke(theme.menuPrimary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Image(systemName: "pause.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(theme.menuPrimary)
                        }
                        .frame(width: 18, height: 18)
                        Text("\(processed)/\(target)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(theme.menuPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: 56, height: 36)
                }
                .accessibilityLabel(
                    "缓存进度 \(processed)/\(target)，全书已缓存 \(cached)/\(total)"
                )
                .accessibilityHint("轻点暂停")

            case let .pausing(inFlight, cached, total):
                VStack(spacing: 2) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(theme.menuPrimary)
                    Text("暂停中")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.menuSecondary)
                }
                .frame(width: 56, height: 36)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "正在暂停缓存，尚有 \(inFlight) 个请求，全书已缓存 \(cached)/\(total)"
                )

            case let .paused(cached, total):
                Button {
                    onResumeCache?()
                } label: {
                    cacheTopLabel(
                        icon: "arrow.clockwise.circle.fill",
                        text: cacheCountText(cached: cached, total: total),
                        color: .orange
                    )
                }
                .accessibilityLabel("缓存已暂停，已缓存 \(cached)/\(total)")
                .accessibilityHint("轻点继续缓存")

            case let .failed(cached, total, error):
                Button {
                    onResumeCache?()
                } label: {
                    cacheTopLabel(
                        icon: "exclamationmark.triangle.fill",
                        text: "重试",
                        color: .red.opacity(0.9)
                    )
                }
                .accessibilityLabel("缓存失败，已缓存 \(cached)/\(total)")
                .accessibilityHint(error ?? "轻点重试")

            case let .complete(total):
                cacheTopLabel(
                    icon: "checkmark.circle.fill",
                    text: "\(total)/\(total)",
                    color: .green
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("已全部缓存，共 \(total) 章")
            }
        } else {
            cacheControlPlaceholder
        }
    }

    private var cacheControlPlaceholder: some View {
        Color.clear
            .frame(width: 56, height: 36)
            .accessibilityHidden(true)
    }

    private func cacheTopLabel(icon: String, text: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
            Text(text)
                .font(.system(size: 9, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(color)
        .frame(width: 56, height: 36)
    }

    private var cacheStatusMessage: (text: String, color: Color)? {
        switch cacheState {
        case let .pausing(_, cached, total):
            return ("正在暂停 · 已缓存 \(cacheCountText(cached: cached, total: total))", .orange)
        case let .paused(cached, total):
            return ("缓存已暂停 · 已缓存 \(cacheCountText(cached: cached, total: total))", .orange)
        case let .failed(cached, total, error):
            let prefix = "缓存失败 · 已缓存 \(cacheCountText(cached: cached, total: total))"
            guard let error, !error.isEmpty else { return (prefix, .red) }
            return ("\(prefix)\n\(error)", .red)
        default:
            return nil
        }
    }

    private func cacheCountText(cached: Int, total: Int) -> String {
        let safeTotal = max(0, total)
        let safeCached = min(max(0, cached), safeTotal)
        return "\(safeCached)/\(safeTotal)"
    }

    private func taskProgress(processed: Int, target: Int) -> Double {
        guard target > 0 else { return 0 }
        return min(max(Double(processed) / Double(target), 0), 1)
    }

    private func queuedAccessibilityLabel(position: Int?, cached: Int, total: Int) -> String {
        let positionText = position.map { "，当前第 \($0) 位" } ?? ""
        return "缓存任务排队中\(positionText)，全书已缓存 \(cached)/\(total)"
    }

    // MARK: - Bottom Panel

    private var bottomPanel: some View {
        VStack(spacing: 16) {
            if let status = cacheStatusMessage {
                Text(status.text)
                    .font(.system(size: 11))
                    .foregroundStyle(status.color.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            if showSettings {
                settingsControls
            } else {
                chapterSlider
            }
            iconRow
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(theme.menuBackground, ignoresSafeAreaEdges: .bottom)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.menuSeparator).frame(height: 1)
        }
        .animation(.easeInOut(duration: 0.2), value: showSettings)
    }

    // MARK: - Chapter Slider

    private var chapterSlider: some View {
        HStack(spacing: 16) {
            Button {
                if currentChapterIndex > 0 {
                    currentChapterIndex -= 1
                    sliderValue = Double(currentChapterIndex)
                }
            } label: {
                Text("上一章")
                    .font(.system(size: 13))
                    .foregroundStyle(currentChapterIndex > 0 ? theme.menuPrimary : theme.menuDisabled)
            }
            .disabled(currentChapterIndex <= 0)

            Slider(
                value: $sliderValue,
                in: 0...max(Double(totalChapters - 1), 1),
                step: 1
            ) { editing in
                if !editing {
                    currentChapterIndex = Int(sliderValue)
                }
            }
            .tint(theme.menuSecondary)

            Button {
                if currentChapterIndex < totalChapters - 1 {
                    currentChapterIndex += 1
                    sliderValue = Double(currentChapterIndex)
                }
            } label: {
                Text("下一章")
                    .font(.system(size: 13))
                    .foregroundStyle(currentChapterIndex < totalChapters - 1 ? theme.menuPrimary : theme.menuDisabled)
            }
            .disabled(currentChapterIndex >= totalChapters - 1)
        }
    }

    // MARK: - Settings Controls

    private var settingsControls: some View {
        VStack(spacing: 14) {
            // Font size
            HStack(spacing: 12) {
                Button {
                    settings.fontSize = max(settings.fontSize - 1, 12)
                    settings.save()
                } label: {
                    Image(systemName: "textformat.size.smaller")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.menuPrimary)
                        .frame(width: 36, height: 32)
                        .background(theme.menuSelectedFill, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Slider(
                    value: Binding(
                        get: { draggingFontSize ?? Double(settings.fontSize) },
                        set: { draggingFontSize = $0 }
                    ),
                    in: 12...32,
                    step: 1
                ) { editing in
                    guard !editing, let value = draggingFontSize else { return }
                    draggingFontSize = nil
                    guard Int(value) != Int(settings.fontSize) else { return }
                    settings.fontSize = CGFloat(value)
                    settings.save()
                }
                .tint(theme.menuSecondary)

                Button {
                    settings.fontSize = min(settings.fontSize + 1, 32)
                    settings.save()
                } label: {
                    Image(systemName: "textformat.size.larger")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.menuPrimary)
                        .frame(width: 36, height: 32)
                        .background(theme.menuSelectedFill, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Text("\(Int(draggingFontSize ?? Double(settings.fontSize)))")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(theme.menuSecondary)
                    .frame(width: 22)
            }

            // Theme circles
            HStack(spacing: 0) {
                ForEach(ReaderTheme.allCases, id: \.self) { theme in
                    Button {
                        settings.theme = theme
                        settings.save()
                    } label: {
                        VStack(spacing: 5) {
                            ZStack {
                                Circle()
                                    .fill(theme.backgroundColor)
                                    .frame(width: 28, height: 28)
                                Circle()
                                    .strokeBorder(
                                        settings.theme == theme ? theme.menuPrimary : theme.menuDisabled,
                                        lineWidth: settings.theme == theme ? 2.5 : 1
                                    )
                                    .frame(width: 28, height: 28)
                            }
                            Text(theme.displayName)
                                .font(.system(size: 10))
                                .foregroundStyle(settings.theme == theme ? theme.menuPrimary : theme.menuSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Font family
            HStack(spacing: 8) {
                ForEach(FontFamily.allCases, id: \.self) { font in
                    Button {
                        settings.fontFamily = font
                        settings.save()
                    } label: {
                        Text(font.displayName)
                            .font(.system(size: 12))
                            .foregroundStyle(settings.fontFamily == font ? theme.menuPrimary : theme.menuSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(settings.fontFamily == font ? theme.menuSelectedFill : theme.menuUnselectedFill)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Line spacing
            HStack(spacing: 10) {
                Text("行距")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.menuSecondary)
                    .frame(width: 28)
                Slider(
                    value: Binding(
                        get: { draggingLineSpacing ?? settings.lineSpacing },
                        set: { draggingLineSpacing = $0 }
                    ),
                    in: 1.5...2.5,
                    step: 0.1
                ) { editing in
                    guard !editing, let value = draggingLineSpacing else { return }
                    draggingLineSpacing = nil
                    guard abs(value - settings.lineSpacing) > 0.001 else { return }
                    settings.lineSpacing = value
                    settings.save()
                }
                .tint(theme.menuSecondary)
                Text(String(format: "%.1f", draggingLineSpacing ?? settings.lineSpacing))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.menuSecondary)
                    .frame(width: 26)
            }

            // Keep screen awake
            Rectangle()
                .fill(theme.menuSeparator)
                .frame(height: 1)

            HStack {
                Text("保持屏幕常亮")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.menuPrimary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { settings.keepScreenAwake },
                    set: { value in
                        settings.keepScreenAwake = value
                        settings.save()
                    }
                ))
                .labelsHidden()
                .tint(theme.menuPrimary)
                .accessibilityLabel("保持屏幕常亮")
                .accessibilityValue(settings.keepScreenAwake ? "已开启" : "已关闭")
            }
            .frame(height: 44)
        }
    }

    // MARK: - Brightness

    private var brightnessBar: some View {
        HStack(spacing: 12) {
            Button {
                onFollowSystemBrightness?()
                flashFollowSystem()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        isFollowingSystemBrightness || followSystemFlash
                            ? theme.menuPrimary
                            : theme.menuSecondary
                    )
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(followSystemFlash ? theme.menuSelectedFill : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("跟随系统亮度")

            Image(systemName: "sun.min")
                .font(.system(size: 14))
                .foregroundStyle(theme.menuSecondary)

            Slider(
                value: Binding(
                    get: { brightnessValue },
                    set: { newValue in
                        brightnessValue = newValue
                        onBrightnessChange?(newValue)
                    }
                ),
                in: 0...1
            )
            .tint(theme.menuPrimary)
            .accessibilityLabel("屏幕亮度")
            .accessibilityValue("\(Int((brightnessValue * 100).rounded()))%")

            Image(systemName: "sun.max")
                .font(.system(size: 16))
                .foregroundStyle(theme.menuPrimary)
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
        .background(theme.menuBackground, ignoresSafeAreaEdges: .top)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.menuSeparator).frame(height: 1)
        }
    }

    private func flashFollowSystem() {
        withAnimation(.easeInOut(duration: 0.15)) { followSystemFlash = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.15)) { followSystemFlash = false }
            }
        }
    }

    // MARK: - Icon Row

    private var iconRow: some View {
        HStack(spacing: 0) {
            toolButton(icon: "list.bullet", label: "目录") {
                showChapterList = true
            }
            toolButton(
                icon: settings.theme.isDark ? "sun.max" : "moon.fill",
                label: settings.theme.isDark ? "日间" : "夜间"
            ) {
                settings.theme = settings.theme.isDark ? .paper : .dark
                settings.save()
            }
            toolButton(icon: "gearshape", label: "设置") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSettings.toggle()
                }
            }
        }
    }

    private func toolButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(theme.menuPrimary)
                    .frame(height: 24)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.menuSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Chapter List

    private var chapterListContent: some View {
        VStack(spacing: 0) {
            chapterListHeader
            chapterSearchRow
            if let tocToast {
                tocToastBar(tocToast)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
            if !chapterSearchKeyword.isEmpty && !filteredChapters.isEmpty {
                Text("找到 \(filteredChapters.count) 章")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.menuSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
            }
            if filteredChapters.isEmpty && !chapterSearchKeyword.isEmpty {
                emptyChapterSearchResult
            } else {
                chapterList
            }
        }
        .background(theme.menuBackground.ignoresSafeArea())
    }

    /// Plain header row: cache control on the left, title centred, close on the right.
    private var chapterListHeader: some View {
        ZStack {
            Text("目录")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.menuPrimary)

            HStack {
                chapterListCacheControl
                Spacer()
                Button("关闭") { showChapterList = false }
                    .font(.system(size: 15))
                    .foregroundStyle(theme.menuPrimary)
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private var chapterSearchKeyword: String {
        chapterSearch.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredChapters: [Chapter] {
        let keyword = chapterSearchKeyword
        guard !keyword.isEmpty else { return chapters }
        return chapters.filter { $0.title.localizedCaseInsensitiveContains(keyword) }
    }

    private var chapterSearchRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.menuSecondary)
                TextField("", text: $chapterSearch)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.menuPrimary)
                    .tint(theme.menuPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("搜索章节")
                    .overlay(alignment: .leading) {
                        if chapterSearch.isEmpty {
                            Text("搜索章节")
                                .font(.system(size: 14))
                                .foregroundStyle(theme.menuSecondary)
                                .allowsHitTesting(false)
                        }
                    }
                if !chapterSearch.isEmpty {
                    Button {
                        chapterSearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.menuSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.menuPrimary.opacity(0.06))
            )

            if onRefreshToc != nil {
                Button {
                    updateToc()
                } label: {
                    if isUpdatingToc {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16))
                            .foregroundStyle(theme.menuPrimary)
                            .frame(width: 20, height: 20)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isUpdatingToc)
                .accessibilityLabel("更新目录")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var emptyChapterSearchResult: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26))
                .foregroundStyle(theme.menuSecondary)
            Text("没有匹配的章节")
                .font(.system(size: 13))
                .foregroundStyle(theme.menuSecondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tocToastBar(_ text: String) -> some View {
        Button {
            if tocToastRetryable { updateToc() }
        } label: {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(theme.menuPrimary)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.menuPrimary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .disabled(!tocToastRetryable)
        .accessibilityLabel(text)
    }

    private func updateToc() {
        guard let onRefreshToc, !isUpdatingToc else { return }
        isUpdatingToc = true
        Task {
            let outcome = await onRefreshToc()
            await MainActor.run {
                isUpdatingToc = false
                switch outcome {
                case let .added(count):
                    showTocToast("新增 \(count) 章", retryable: false, seconds: 3)
                case .upToDate:
                    showTocToast("已是最新", retryable: false, seconds: 3)
                case .failed:
                    showTocToast("更新失败，点此重试", retryable: true, seconds: 6)
                case .unavailable:
                    showTocToast("这本书没有书源，无法更新目录", retryable: false, seconds: 3)
                }
            }
        }
    }

    private func showTocToast(_ text: String, retryable: Bool, seconds: Double) {
        withAnimation(.easeInOut(duration: 0.15)) {
            tocToast = text
            tocToastRetryable = retryable
        }
        tocToastTask?.cancel()
        tocToastTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.15)) {
                    tocToast = nil
                    tocToastRetryable = false
                }
            }
        }
    }

    private var chapterList: some View {
        ScrollViewReader { proxy in
            List(filteredChapters) { chapter in
                Button {
                    currentChapterIndex = chapter.index
                    showChapterList = false
                } label: {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(theme.menuPrimary)
                            .frame(width: 3)
                            .opacity(chapter.index == currentChapterIndex ? 1 : 0)
                        Text(chapter.title)
                            .font(.body)
                            .foregroundStyle(theme.menuPrimary)
                            .fontWeight(chapter.index == currentChapterIndex ? .semibold : .regular)
                        Spacer()
                        if chapter.index != currentChapterIndex && chapter.isCached {
                            Image(systemName: "checkmark")
                                .foregroundStyle(theme.menuSecondary)
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                }
                .id(chapter.index)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.menuBackground)
            .onAppear {
                scrollToCurrentChapter(with: proxy, animated: false)
            }
            .onChange(of: currentChapterIndex) { _, _ in
                scrollToCurrentChapter(with: proxy, animated: true)
            }
        }
    }

    @ViewBuilder
    private var chapterListCacheControl: some View {
        if let onCache {
            switch cacheState {
            case .unavailable:
                EmptyView()

            case .checking:
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.small)
                    Text("检查缓存")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("正在检查已有缓存")

            case .empty:
                Button("缓存全部") { onCache(nil) }

            case let .partial(cached, total):
                Button {
                    onCache(nil)
                } label: {
                    Label(
                        "补全 \(max(0, total - cached)) 章",
                        systemImage: "arrow.down.circle"
                    )
                }
                .accessibilityLabel("已缓存 \(cached)/\(total)，补全剩余章节")

            case let .queued(position, cached, total):
                Button {
                    onCancelCache?()
                } label: {
                    Label(
                        position.map { "排队第 \($0) 位" } ?? "排队中",
                        systemImage: "clock"
                    )
                }
                .accessibilityLabel(queuedAccessibilityLabel(position: position, cached: cached, total: total))
                .accessibilityHint("轻点暂停缓存任务")

            case let .running(processed, target, cached, total):
                Button {
                    onCancelCache?()
                } label: {
                    Label(
                        "\(processed)/\(target) · 已存 \(cacheCountText(cached: cached, total: total))",
                        systemImage: "pause.fill"
                    )
                    .font(.caption)
                }
                .accessibilityLabel(
                    "缓存进度 \(processed)/\(target)，全书已缓存 \(cached)/\(total)"
                )
                .accessibilityHint("轻点暂停")

            case let .pausing(inFlight, cached, total):
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.small)
                    Text("暂停中")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "正在暂停缓存，尚有 \(inFlight) 个请求，全书已缓存 \(cached)/\(total)"
                )

            case let .paused(cached, total):
                Button {
                    onResumeCache?()
                } label: {
                    Label(
                        "继续 \(cacheCountText(cached: cached, total: total))",
                        systemImage: "arrow.clockwise.circle.fill"
                    )
                    .foregroundStyle(.orange)
                }
                .accessibilityLabel("缓存已暂停，已缓存 \(cached)/\(total)，继续缓存")

            case let .failed(cached, total, error):
                Button {
                    onResumeCache?()
                } label: {
                    Label("重试缓存", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                .accessibilityLabel("缓存失败，已缓存 \(cached)/\(total)")
                .accessibilityHint(error ?? "轻点重试")

            case let .complete(total):
                Label("已缓存 \(total)/\(total)", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("已全部缓存，共 \(total) 章")
            }
        }
    }

    private func scrollToCurrentChapter(with proxy: ScrollViewProxy, animated: Bool) {
        guard chapters.contains(where: { $0.index == currentChapterIndex }) else { return }

        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(currentChapterIndex, anchor: .center)
                }
            } else {
                proxy.scrollTo(currentChapterIndex, anchor: .center)
            }
        }
    }
}
