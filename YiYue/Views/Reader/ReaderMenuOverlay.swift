import SwiftUI

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

    @State private var showChapterList = false
    @State private var sliderValue: Double = 0
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Color.clear
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomPanel
            }
        }
        .onAppear { sliderValue = Double(currentChapterIndex) }
        .onChange(of: currentChapterIndex) { _, newValue in
            sliderValue = Double(newValue)
        }
        .sheet(isPresented: $showChapterList) {
            NavigationStack {
                chapterListContent
            }
            .presentationDetents([.medium, .large])
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
                .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            Text(chapterTitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Spacer()
            cacheTopBarControl
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial.opacity(0.98), ignoresSafeAreaEdges: .top)
        .environment(\.colorScheme, .dark)
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
                        .tint(.white.opacity(0.8))
                    Text("检查中")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .frame(width: 56, height: 36)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("正在检查已有缓存")

            case .empty:
                Menu {
                    Button("缓存后100章") { onCache(100) }
                    Button("缓存全部") { onCache(nil) }
                } label: {
                    cacheTopLabel(
                        icon: "arrow.down.circle",
                        text: "缓存",
                        color: .white.opacity(0.85)
                    )
                }
                .accessibilityLabel("缓存小说")

            case let .partial(cached, total):
                Menu {
                    Button("缓存后100章") { onCache(100) }
                    Button("补全剩余 \(max(0, total - cached)) 章") { onCache(nil) }
                } label: {
                    cacheTopLabel(
                        icon: "arrow.down.circle.fill",
                        text: cacheCountText(cached: cached, total: total),
                        color: .white.opacity(0.85)
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
                        color: .white.opacity(0.78)
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
                                .stroke(.white.opacity(0.2), lineWidth: 2)
                            Circle()
                                .trim(from: 0, to: taskProgress(processed: processed, target: target))
                                .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Image(systemName: "pause.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .frame(width: 18, height: 18)
                        Text("\(processed)/\(target)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
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
                        .tint(.white.opacity(0.8))
                    Text("暂停中")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.65))
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
        .background(.ultraThinMaterial.opacity(0.98), ignoresSafeAreaEdges: .bottom)
        .environment(\.colorScheme, .dark)
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
                    .foregroundStyle(.white.opacity(currentChapterIndex > 0 ? 0.7 : 0.3))
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
            .tint(.white.opacity(0.5))

            Button {
                if currentChapterIndex < totalChapters - 1 {
                    currentChapterIndex += 1
                    sliderValue = Double(currentChapterIndex)
                }
            } label: {
                Text("下一章")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(currentChapterIndex < totalChapters - 1 ? 0.7 : 0.3))
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
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 36, height: 32)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Slider(
                    value: Binding(
                        get: { Double(settings.fontSize) },
                        set: {
                            settings.fontSize = CGFloat($0)
                            settings.save()
                        }
                    ),
                    in: 12...32,
                    step: 1
                )
                .tint(.white.opacity(0.5))

                Button {
                    settings.fontSize = min(settings.fontSize + 1, 32)
                    settings.save()
                } label: {
                    Image(systemName: "textformat.size.larger")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 36, height: 32)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Text("\(Int(settings.fontSize))")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
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
                                        settings.theme == theme ? Color.white : Color.white.opacity(0.2),
                                        lineWidth: settings.theme == theme ? 2.5 : 1
                                    )
                                    .frame(width: 28, height: 28)
                            }
                            Text(theme.displayName)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(settings.theme == theme ? 0.8 : 0.4))
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
                            .foregroundStyle(.white.opacity(settings.fontFamily == font ? 0.9 : 0.45))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.white.opacity(settings.fontFamily == font ? 0.15 : 0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Line spacing
            HStack(spacing: 10) {
                Text("行距")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 28)
                Slider(
                    value: Binding(
                        get: { settings.lineSpacing },
                        set: {
                            settings.lineSpacing = $0
                            settings.save()
                        }
                    ),
                    in: 1.5...2.5,
                    step: 0.1
                )
                .tint(.white.opacity(0.5))
                Text(String(format: "%.1f", settings.lineSpacing))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 26)
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
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(height: 24)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Chapter List

    private var chapterListContent: some View {
        ScrollViewReader { proxy in
            List(chapters) { chapter in
                Button {
                    currentChapterIndex = chapter.index
                    showChapterList = false
                } label: {
                    HStack {
                        Text(chapter.title)
                            .font(.body)
                            .foregroundStyle(chapter.index == currentChapterIndex ? .blue : .primary)
                        Spacer()
                        if chapter.index == currentChapterIndex {
                            Image(systemName: "book.fill")
                                .foregroundStyle(.blue)
                                .font(.caption)
                        } else if chapter.isCached {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green.opacity(0.6))
                                .font(.caption2)
                        }
                    }
                }
                .id(chapter.index)
            }
            .onAppear {
                scrollToCurrentChapter(with: proxy, animated: false)
            }
            .onChange(of: currentChapterIndex) { _, _ in
                scrollToCurrentChapter(with: proxy, animated: true)
            }
        }
        .navigationTitle("目录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                chapterListCacheControl
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("关闭") { showChapterList = false }
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
