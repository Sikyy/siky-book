import SwiftUI
import SwiftData
import UIKit

/// Result of asking the book's source for its latest table of contents.
enum TocRefreshOutcome: Sendable {
    case added(Int)
    case upToDate
    case failed
    case unavailable
}

/// 菜单顶部面板(标题行 + 亮度条)的底边在屏幕上的位置。
struct ReaderMenuTopEdgePreference: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 菜单底部面板的顶边在屏幕上的位置(按行网格取整用)。
struct ReaderMenuBottomTopPreference: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

/// 底部五格:目录 / 书签 / 文字 / 亮度 / 进度。
enum ReaderTool: String, CaseIterable, Identifiable {
    case chapters
    case bookmarks
    case text
    case brightness
    case progress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chapters: return "目录"
        case .bookmarks: return "书签"
        case .text: return "文字"
        case .brightness: return "亮度"
        case .progress: return "进度"
        }
    }

    /// 第五格是自绘圆环,不用 SF Symbol。
    var icon: String {
        switch self {
        case .chapters: return "line.3.horizontal"
        case .bookmarks: return "bookmark"
        case .text: return "textformat.size"
        case .brightness: return "sun.max"
        case .progress: return "circle"
        }
    }
}

enum ReaderToolbarMetrics {
    /// 底部工具条从 y=791 到屏幕底。
    static let height: CGFloat = 83
    static let topBarHeight: CGFloat = 40
    /// 顶栏高 40、返回图标中心 y=80。
    static let topBarTop: CGFloat = 60
    static let iconSize: CGFloat = 24
    /// 图标中心 y=820,工具条顶 791,图标 24:上沿留 17。
    static let iconTopInset: CGFloat = 16
}

/// 第五格:直径 22、线宽 2、18° 缺口朝上的自绘进度环,
/// 末端一个 2 点实心圆点。缺口收到 20° 以内,不会读成「U」,也不是时钟。
struct ReaderProgressRing: View {
    var color: Color

    /// 圆环画 342°,只留 18° 缺口;旋转 -81° 让缺口中心落在正上方。
    private let arcFraction: CGFloat = 0.95
    private let rotationDegrees: Double = -81
    /// 环中线半径 = (22 - 2) / 2。
    private let ringRadius: CGFloat = 10

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: arcFraction)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(rotationDegrees))

            // 弧末点(参数 0.95 → 342°,再加 -81° = 261°),贴环中线放一颗 2 点圆点。
            Circle()
                .fill(color)
                .frame(width: 2, height: 2)
                .offset(
                    x: ringRadius * cos(261 * .pi / 180),
                    y: ringRadius * sin(261 * .pi / 180)
                )
        }
        .frame(width: 22, height: 22)
    }
}

/// 滑轨刻度:按档位等分,选中那档是短实线,其余档位一条淡线。
private struct ReaderSliderTicks: View {
    let count: Int
    let selectedIndex: Int
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let thumbInset: CGFloat = 14
            let usableWidth = max(0, proxy.size.width - thumbInset * 2)
            let step = count > 1 ? usableWidth / CGFloat(count - 1) : 0
            ForEach(0..<count, id: \.self) { index in
                let selected = index == selectedIndex
                Capsule()
                    .fill(color.opacity(selected ? 0.85 : 0.26))
                    .frame(width: selected ? 2 : 1, height: selected ? 12 : 7)
                    .position(
                        x: thumbInset + CGFloat(index) * step,
                        y: proxy.size.height / 2 + 12
                    )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
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
    var onJumpToMark: ((ReadingMark) -> Void)? = nil
    var onOpenNote: ((ReadingMark) -> Void)? = nil
    var onAddBookmarkHere: (() -> Void)? = nil
    /// 当前这一页有没有书签:决定那颗按钮是「给这一页加书签」还是「移除书签」。
    var hasPageBookmark: Bool = false
    /// 书签面板顶部「写笔记」:摘录取当前页第一段。
    var onWriteNoteHere: (() -> Void)? = nil
    /// 底部面板往上多长多少,让它的顶边落在正文的行边界上。
    var bottomTopInset: CGFloat = 0
    /// 顶部面板往下多长多少,让它的底边落在正文的行边界上。
    var topBottomInset: CGFloat = 0
    /// 正文第一条线的屏幕 y 和一行的高度:目录/设置面板的顶边要落在行边界上。
    var bodyTopY: CGFloat = 0
    var bodyLineHeight: CGFloat = 0
    /// 阅读进度,和页脚同一个算法。
    var progressPercent: String = ""
    /// 进度格的圆环取 0…1。
    var progressFraction: Double = 0
    /// 当前页每一条正文线的行顶(屏幕坐标),面板顶边贴它。
    var bodyLineTops: [CGFloat] = []
    /// 顶栏底边的屏幕 y:面板从这条线下面开始,不能盖住顶栏。
    var topBarBottomY: CGFloat = 0

    private var theme: ReaderTheme { settings.theme }

    @Environment(\.modelContext) private var modelContext

    @State private var showChapterList = false
    @State private var sliderValue: Double = 0
    /// 当前选中的工具格:目录/书签/文字/亮度/进度。
    @State private var selectedTool: ReaderTool?
    @State private var draggingFontSize: Double?
    @State private var draggingLineSpacing: Double?
    @State private var chapterSearch = ""
    @State private var isUpdatingToc = false
    @State private var tocToast: String?
    @State private var tocToastRetryable = false
    @State private var tocToastTask: Task<Void, Never>?
    @State private var brightnessValue: Double = 1
    @State private var followSystemFlash = false
    @State private var panelSegment: ReaderPanelSegment = .chapters
    @State private var panelDragOffset: CGFloat = 0
    @State private var topBarHeight: CGFloat = 0
    @State private var isPanelSearchOpen = false
    @State private var pendingDeletionID: UUID?
    @State private var undoToast: String?
    @State private var undoToastTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            let screenWidth = geo.size.width
            let screenHeight = geo.size.height
            let barHeight = ReaderToolbarMetrics.height
            let barTop = screenHeight - barHeight
            ZStack(alignment: .topLeading) {
                // 正文自己处理「点一下收菜单」和「长按直接选段」,这一层只负责铺底色,
                // 不能再吃掉手势——否则菜单开着时长按正文没反应。
                Color.clear
                    .allowsHitTesting(false)

                // 菜单开着时,正文区点一下要能收菜单/收面板。
                // 放在顶栏、面板、工具栏下面,不挡它们自己的点击。
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedTool != nil || showChapterList {
                            closePanel()
                        } else {
                            onDismiss()
                        }
                    }

                // 顶栏:高 40、无底色无分隔线,只放返回;章节名不在这里。
                topBar

                if let panelTool = selectedTool {
                    switch panelTool {
                    case .text:
                        textSettingsPanel(barTop: barTop)
                    case .brightness:
                        brightnessFloatingPanel(barTop: barTop)
                    case .progress:
                        progressFloatingPanel(barTop: barTop)
                    case .chapters, .bookmarks:
                        EmptyView()
                    }
                }

                bottomToolbar(width: screenWidth, top: barTop, height: barHeight)

                if showChapterList {
                    panelOverlay
                }
            }
            .frame(width: screenWidth, height: screenHeight, alignment: .topLeading)
        }
        .ignoresSafeArea()
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
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 0) {
            Button(action: { onBack() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(theme.menuPrimary)
                    .frame(width: 30, height: ReaderToolbarMetrics.topBarHeight)
                    // 雪佛龙字形本身偏左,补 1.8 让字墨中心落在 x=15。
                    .offset(x: 1.8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: ReaderToolbarMetrics.topBarHeight)
        // 无底色、无分隔线,直接压在正文上,正文不动。
        .background(Color.clear)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ReaderMenuTopEdgePreference.self,
                    value: proxy.frame(in: .global).maxY
                )
            }
        )
        .offset(y: ReaderToolbarMetrics.topBarTop)
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

    // MARK: - 底部工具栏(五格,只有图标)

    private func bottomToolbar(width: CGFloat, top: CGFloat, height: CGFloat) -> some View {
        let cellWidth = width / CGFloat(ReaderTool.allCases.count)
        return VStack(spacing: 0) {
            Rectangle()
                .fill(theme.menuPrimary.opacity(0.12))
                .frame(height: 1)
            HStack(spacing: 0) {
                ForEach(ReaderTool.allCases) { tool in
                    Button {
                        handleToolTap(tool)
                    } label: {
                        toolIcon(tool)
                            .frame(width: ReaderToolbarMetrics.iconSize,
                                   height: ReaderToolbarMetrics.iconSize)
                            .frame(width: cellWidth, height: height - 1, alignment: .top)
                            .offset(y: ReaderToolbarMetrics.iconTopInset)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tool.title)
                    .accessibilityValue(selectedTool == tool ? "已选中" : "")
                    .accessibilityAddTraits(selectedTool == tool ? [.isSelected] : [])
                }
            }
            .frame(height: height - 1)
        }
        .frame(width: width, height: height)
        .background(theme.menuBackground, ignoresSafeAreaEdges: .bottom)
        .offset(y: top)
    }

    @ViewBuilder
    private func toolIcon(_ tool: ReaderTool) -> some View {
        let selected = selectedTool == tool
        let color = selected ? theme.accentColor : theme.menuPrimary.opacity(0.7)
        switch tool {
        case .progress:
            ReaderProgressRing(color: color)
                .frame(width: 22, height: 22)
        case .bookmarks:
            Image(systemName: hasPageBookmark ? "bookmark.fill" : "bookmark")
                .font(.system(size: ReaderToolbarMetrics.iconSize, weight: .regular))
                .foregroundStyle(color)
                .frame(width: ReaderToolbarMetrics.iconSize,
                       height: ReaderToolbarMetrics.iconSize)
        default:
            Image(systemName: tool.icon)
                .font(.system(size: ReaderToolbarMetrics.iconSize, weight: .regular))
                .foregroundStyle(color)
                .frame(width: ReaderToolbarMetrics.iconSize,
                       height: ReaderToolbarMetrics.iconSize)
        }
    }

    private func handleToolTap(_ tool: ReaderTool) {
        switch tool {
        case .chapters:
            selectedTool = .chapters
            openPanel(.chapters)
        case .bookmarks:
            selectedTool = .bookmarks
            openPanel(.bookmarks)
        case .text, .brightness, .progress:
            if selectedTool == tool {
                selectedTool = nil
            } else {
                selectedTool = tool
                brightnessValue = brightness
            }
        }
    }

    // MARK: - 文字面板(九行)

    /// 面板顶边必须落在正文行边界上(行框顶 + N × 当前行高)。
    private func gridAlignedTop(naturalHeight: CGFloat, barTop: CGFloat) -> CGFloat {
        let raw = barTop - naturalHeight
        let line = currentBodyLineHeight
        // 优先贴当前页真实行框顶:段间距不是行高的整数倍,全局网格会压住半行。
        if let lineTop = measuredBodyLineTops.last(where: { $0 <= raw }) {
            return lineTop
        }
        // 滚动模式量不到真实行框时,从规格的 116 字顶按当前行高铺网格。
        let bodyTop = measuredBodyLineTops.first ?? ReaderTypography.bodyTopInkY
        let steps = floor((raw - bodyTop) / line)
        return bodyTop + max(0, steps) * line
    }

    private func textSettingsPanel(barTop: CGFloat) -> some View {
        let rowHeight: CGFloat = 56
        let gap: CGFloat = 8
        let topPadding: CGFloat = 0
        let naturalHeight = rowHeight * 9 + gap * 8 + topPadding
        let top = gridAlignedTop(naturalHeight: naturalHeight, barTop: barTop)
        return VStack(spacing: gap) {
            fontFamilyRow
            fontSizeRow
            lineSpacingRow
            horizontalPaddingRow
            pageModeRow
            firstLineIndentRow
            backgroundRow
            paragraphSpacingRow
            keepScreenAwakeRow
        }
        .padding(.horizontal, 24)
        .padding(.top, topPadding)
        .frame(maxWidth: .infinity)
        .frame(height: max(0, barTop - top), alignment: .top)
        .background(theme.menuBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.menuPrimary.opacity(0.12)).frame(height: 1)
        }
        .offset(y: top)
    }

    private func settingLabel(_ text: String, width: CGFloat = 64) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(theme.menuSecondary)
            .frame(width: width, alignment: .leading)
    }

    private var fontFamilyRow: some View {
        HStack(spacing: 8) {
            settingLabel("字体", width: 44)
            ForEach(FontFamily.allCases, id: \.self) { font in
                let selected = settings.fontFamily == font
                Button {
                    settings.fontFamily = font
                    settings.save()
                } label: {
                    Text(font.displayName)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? theme.menuBackground : theme.menuSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selected ? theme.accentColor : theme.menuPrimary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(
                                    selected ? Color.clear : theme.menuPrimary.opacity(0.10),
                                    lineWidth: 1
                                )
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(font.displayName)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .frame(height: 56)
    }

    /// 三根档位滑轨统一念「第 N 档,共 M 档」,两端补「已是最小 / 已是最大」。
    private func levelAccessibilityString(index: Int, count: Int) -> String {
        let total = max(count, 1)
        let clamped = min(max(index, 0), total - 1)
        let base = "第 \(clamped + 1) 档，共 \(total) 档"
        if clamped == 0 { return "\(base)，已是最小" }
        if clamped == total - 1 { return "\(base)，已是最大" }
        return base
    }

    private var fontSizeRow: some View {
        HStack(spacing: 8) {
            settingLabel("字号", width: 36)
            Button {
                stepFontSize(-1)
            } label: {
                Text("A")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.menuPrimary)
                    .frame(width: 28, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("缩小字号")

            ReaderLevelSlider(
                normalizedValue: fontSizeIndexBinding,
                tint: theme.menuSecondary,
                label: "字号",
                spokenValue: levelAccessibilityString(
                    index: settings.fontSizeLevelIndex,
                    count: ReaderTypography.fontSizeLevels.count
                ),
                levelCount: ReaderTypography.fontSizeLevels.count
            )
            .frame(height: 44)
            .overlay {
                ReaderSliderTicks(
                    count: ReaderTypography.fontSizeLevels.count,
                    selectedIndex: settings.fontSizeLevelIndex,
                    color: theme.menuSecondary
                )
            }

            Button {
                stepFontSize(1)
            } label: {
                Text("A")
                    .font(.system(size: 20))
                    .foregroundStyle(theme.menuPrimary)
                    .frame(width: 28, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("放大字号")

            Text("\(Int(settings.fontSize))")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(theme.menuSecondary)
                // 不占固定宽度:把省下的 8 点给滑轨,最后一档 40 才能拖到。
                .fixedSize()
        }
        .frame(height: 56)
    }

    private var fontSizeIndexBinding: Binding<Double> {
        Binding(
            get: {
                let count = ReaderTypography.fontSizeLevels.count
                guard count > 1 else { return 0 }
                return Double(settings.fontSizeLevelIndex) / Double(count - 1)
            },
            set: { value in
                let levels = ReaderTypography.fontSizeLevels
                let count = levels.count
                guard count > 1 else { return }
                let index = min(max(Int((value * Double(count - 1)).rounded()), 0), count - 1)
                guard levels[index] != settings.fontSize else { return }
                settings.fontSize = levels[index]
                settings.save()
            }
        )
    }

    private func stepFontSize(_ direction: Int) {
        let levels = ReaderTypography.fontSizeLevels
        let index = min(max(settings.fontSizeLevelIndex + direction, 0), levels.count - 1)
        guard levels[index] != settings.fontSize else { return }
        settings.fontSize = levels[index]
        settings.save()
    }

    private func stepLineSpacing(_ direction: Int) {
        let levels = ReaderTypography.lineSpacingLevels
        let index = min(max(settings.lineSpacingLevelIndex + direction, 0), levels.count - 1)
        guard abs(levels[index] - settings.lineSpacing) > 0.001 else { return }
        settings.lineSpacing = levels[index]
        settings.save()
    }

    private func stepHorizontalPadding(_ direction: Int) {
        let levels = ReaderTypography.horizontalPaddingLevels
        let index = min(max(settings.horizontalPaddingLevelIndex + direction, 0), levels.count - 1)
        guard levels[index] != settings.horizontalPadding else { return }
        settings.horizontalPadding = levels[index]
        settings.save()
    }

    private var lineSpacingRow: some View {
        HStack(spacing: 10) {
            settingLabel("行距", width: 44)
            ReaderLevelSlider(
                normalizedValue: lineSpacingIndexBinding,
                tint: theme.menuSecondary,
                label: "行距",
                spokenValue: levelAccessibilityString(
                    index: settings.lineSpacingLevelIndex,
                    count: ReaderTypography.lineSpacingLevels.count
                ),
                levelCount: ReaderTypography.lineSpacingLevels.count
            )
            .frame(height: 44)
            .overlay {
                ReaderSliderTicks(
                    count: ReaderTypography.lineSpacingLevels.count,
                    selectedIndex: settings.lineSpacingLevelIndex,
                    color: theme.menuSecondary
                )
            }
            Text(String(format: "%.1f", settings.lineSpacing))
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(theme.menuSecondary)
                .frame(width: 30, alignment: .trailing)
        }
        .frame(height: 56)
    }

    private var lineSpacingIndexBinding: Binding<Double> {
        Binding(
            get: {
                let count = ReaderTypography.lineSpacingLevels.count
                guard count > 1 else { return 0 }
                return Double(settings.lineSpacingLevelIndex) / Double(count - 1)
            },
            set: { value in
                let levels = ReaderTypography.lineSpacingLevels
                let count = levels.count
                guard count > 1 else { return }
                let index = min(max(Int((value * Double(count - 1)).rounded()), 0), count - 1)
                guard abs(levels[index] - settings.lineSpacing) > 0.001 else { return }
                settings.lineSpacing = levels[index]
                settings.save()
            }
        )
    }

    private var horizontalPaddingRow: some View {
        HStack(spacing: 10) {
            settingLabel("边距", width: 44)
            ReaderLevelSlider(
                normalizedValue: horizontalPaddingIndexBinding,
                tint: theme.menuSecondary,
                label: "边距",
                spokenValue: levelAccessibilityString(
                    index: settings.horizontalPaddingLevelIndex,
                    count: ReaderTypography.horizontalPaddingLevels.count
                ),
                levelCount: ReaderTypography.horizontalPaddingLevels.count
            )
            .frame(height: 44)
            .overlay {
                ReaderSliderTicks(
                    count: ReaderTypography.horizontalPaddingLevels.count,
                    selectedIndex: settings.horizontalPaddingLevelIndex,
                    color: theme.menuSecondary
                )
            }
            // 边距不显数字。
            Color.clear.frame(width: 30, height: 1)
        }
        .frame(height: 56)
    }

    private var horizontalPaddingIndexBinding: Binding<Double> {
        Binding(
            get: {
                let count = ReaderTypography.horizontalPaddingLevels.count
                guard count > 1 else { return 0 }
                return Double(settings.horizontalPaddingLevelIndex) / Double(count - 1)
            },
            set: { value in
                let levels = ReaderTypography.horizontalPaddingLevels
                let count = levels.count
                guard count > 1 else { return }
                let index = min(max(Int((value * Double(count - 1)).rounded()), 0), count - 1)
                guard levels[index] != settings.horizontalPadding else { return }
                settings.horizontalPadding = levels[index]
                settings.save()
            }
        )
    }

    private var pageModeRow: some View {
        HStack(spacing: 8) {
            settingLabel("翻页方式", width: 72)
            Spacer(minLength: 0)
            ForEach([PageMode.horizontal, PageMode.scroll], id: \.self) { mode in
                let selected = mode == .scroll
                    ? settings.pageMode == .scroll
                    : settings.pageMode != .scroll
                Button {
                    settings.pageMode = mode
                    settings.save(markPageModeExplicit: true)
                } label: {
                    Text(mode.displayName)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? theme.menuBackground : theme.menuSecondary)
                        .frame(width: 62, height: 32)
                        .background(
                            Capsule().fill(selected ? theme.accentColor : theme.menuPrimary.opacity(0.05))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.displayName)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .frame(height: 56)
    }

    private var firstLineIndentRow: some View {
        HStack {
            Text("首行缩进")
                .font(.system(size: 13))
                .foregroundStyle(theme.menuPrimary)
            Spacer()
            Toggle("", isOn: Binding(
                get: { settings.firstLineIndentEnabled },
                set: { value in
                    settings.firstLineIndentEnabled = value
                    settings.save()
                }
            ))
            .labelsHidden()
            .tint(theme.accentColor)
            .accessibilityLabel("首行缩进")
            .accessibilityValue(settings.firstLineIndentEnabled ? "已开启" : "已关闭")
        }
        .frame(height: 56)
    }

    private var backgroundRow: some View {
        HStack(spacing: 12) {
            settingLabel("背景", width: 44)
            ForEach(ReaderTheme.allCases, id: \.self) { item in
                Button {
                    settings.theme = item
                    settings.save()
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(item.backgroundColor)
                                .frame(width: 32, height: 32)
                            Circle()
                                .strokeBorder(
                                    settings.theme == item ? theme.accentColor : theme.menuPrimary.opacity(0.18),
                                    lineWidth: settings.theme == item ? 2 : 1
                                )
                                .frame(width: 32, height: 32)
                        }
                        .frame(width: 36, height: 36)
                        Text(item.displayName)
                            .font(.system(size: 10))
                            .foregroundStyle(settings.theme == item ? theme.menuPrimary : theme.menuSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.displayName)
                .accessibilityAddTraits(settings.theme == item ? [.isSelected] : [])
            }
        }
        .frame(height: 56)
    }

    private var paragraphSpacingRow: some View {
        HStack {
            Text("段间距")
                .font(.system(size: 13))
                .foregroundStyle(theme.menuPrimary)
            Spacer()
            Toggle("", isOn: Binding(
                get: { settings.paragraphSpacingEnabled },
                set: { value in
                    settings.paragraphSpacingEnabled = value
                    settings.save()
                }
            ))
            .labelsHidden()
            .tint(theme.accentColor)
            .accessibilityLabel("段间距")
            .accessibilityValue(settings.paragraphSpacingEnabled ? "已开启" : "已关闭")
        }
        .frame(height: 56)
    }

    private var keepScreenAwakeRow: some View {
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
            .tint(theme.accentColor)
            .accessibilityLabel("保持屏幕常亮")
            .accessibilityValue(settings.keepScreenAwake ? "已开启" : "已关闭")
        }
        .frame(height: 56)
    }

    // MARK: - 亮度 / 进度面板

    private func brightnessFloatingPanel(barTop: CGFloat) -> some View {
        let naturalHeight: CGFloat = 56
        let top = gridAlignedTop(naturalHeight: naturalHeight, barTop: barTop)
        return HStack(spacing: 12) {
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

            Button {
                onFollowSystemBrightness?()
                flashFollowSystem()
            } label: {
                Text("自动")
                    .font(.system(size: 12, weight: isFollowingSystemBrightness ? .semibold : .regular))
                    .foregroundStyle(
                        isFollowingSystemBrightness || followSystemFlash
                            ? theme.accentColor
                            : theme.menuSecondary
                    )
                    .frame(width: 36, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("跟随系统亮度")
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .frame(height: max(0, barTop - top), alignment: .center)
        .background(theme.menuBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.menuPrimary.opacity(0.12)).frame(height: 1)
        }
        .offset(y: top)
    }

    private func progressFloatingPanel(barTop: CGFloat) -> some View {
        let naturalHeight: CGFloat = 92
        let top = gridAlignedTop(naturalHeight: naturalHeight, barTop: barTop)
        return VStack(spacing: 8) {
            Text(progressPercent)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.menuPrimary)
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
            .accessibilityLabel("章节")
            .accessibilityValue("第 \(currentChapterIndex + 1) 章，共 \(totalChapters) 章")
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .frame(height: max(0, barTop - top), alignment: .center)
        .background(theme.menuBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.menuPrimary.opacity(0.12)).frame(height: 1)
        }
        .offset(y: top)
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

    // MARK: - 目录 / 书签面板

    /// 面板顶边:状态栏底(59pt)下面 8pt,再按正文行网格往下取到行边界。
    static let panelTop: CGFloat = 67

    /// 当前排版真正使用的行高:翻页/滚动、字号、行距、边距变化后都重新取。
    private var currentBodyLineHeight: CGFloat {
        bodyLineHeight > 1
            ? bodyLineHeight
            : ReaderTypography.bodyLineHeight(fontSize: settings.fontSize, level: settings.lineSpacing)
    }

    /// 翻页模式量到的当前页行框顶。滚动模式的行框由 SwiftUI Text 自己排,
    /// 和分页缓存的 bodyLineTops 不是同一套坐标,不能拿来贴面板。
    private var measuredBodyLineTops: [CGFloat] {
        guard settings.pageMode != .scroll, bodyTopY > 0 else { return [] }
        return bodyLineTops
    }

    /// 顶栏下面补多少,让面板内容区(目录首行、设置首行)正好从正文行边界开始。
    private var topBarRowInset: CGFloat {
        guard topBarHeight > 1 else { return 0 }
        let line = currentBodyLineHeight
        guard line > 1 else { return 0 }
        let origin = measuredBodyLineTops.first ?? ReaderTypography.bodyTopInkY
        let distance = max(topBarBottomY, Self.panelTop + topBarHeight) - origin
        guard distance > 0 else { return 0 }
        let remainder = distance.truncatingRemainder(dividingBy: line)
        return remainder < 0.5 ? 0 : line - remainder
    }

    /// 面板顶边必须落在正文行边界上:顶栏底边以下的第一条真实行框顶。
    /// 段间距会让行位偏离全局网格,所以用当前页量到的 bodyLineTops。
    private var alignedPanelTop: CGFloat {
        let minimum = max(topBarBottomY, Self.panelTop)
        let line = currentBodyLineHeight
        let lineTops = measuredBodyLineTops
        if let lineTop = lineTops.first(where: { $0 >= minimum - 0.5 }) {
            return lineTop
        }
        if let last = lineTops.last {
            let steps = ceil((minimum - last) / line)
            return last + max(0, steps) * line
        }
        // 滚动模式可能量不到 bodyTopY,退回规格的 116 字顶,按当前行高铺网格。
        let origin = ReaderTypography.bodyTopInkY
        let steps = ceil((minimum - origin) / line)
        return origin + max(0, steps) * line
    }

    /// 目录 / 书签面板:从底部升到状态栏下 8pt,左右贴边、只有上边两个 16pt 圆角,
    /// 界面上没有关闭按钮——出三条:拖动条轻点、往下拖、读屏的自定义动作「关闭」。
    private var panelOverlay: some View {
        // 用屏幕高度而不是 GeometryReader:盖层自己的坐标系从安全区开始,
        // 量出来会比屏幕短,面板顶边就落不到状态栏下 8pt。
        let top = alignedPanelTop
        let height = max(UIScreen.main.bounds.height - top, 320)
        return ZStack(alignment: .top) {
            // 面板以外不压暗:透出来的就是阅读页本身,只负责接住点击收起。
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { closePanel() }

            panelSheet
                .frame(height: height, alignment: .top)
                .background(theme.menuBackground)
                .clipShape(TopRoundedRectangle(radius: 16))
                .overlay(alignment: .top) {
                    TopRoundedRectangle(radius: 16)
                        .stroke(theme.menuPrimary.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 12)
                .offset(y: top + max(0, panelDragOffset))
                .transition(.move(edge: .bottom))
        }
        .ignoresSafeArea()
        .accessibilityAction(named: "关闭") { closePanel() }
        .accessibilityAction(.escape) { closePanel() }
    }

    private var panelSheet: some View {
        VStack(spacing: 0) {
            panelHandle
            panelHeader
            chapterCacheRow
            panelSectionContent
            Spacer(minLength: 0)
        }
    }

    /// 拖动条 36×4,热区 88×44;轻点收起,读屏提示「向下拖动或轻点收起」。
    private var panelHandle: some View {
        Capsule()
            .fill(theme.menuPrimary.opacity(0.25))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .frame(height: 22, alignment: .bottom)
            .padding(.horizontal, 26)
            .contentShape(Rectangle())
            .onTapGesture { closePanel() }
            .gesture(panelDragGesture)
            .accessibilityElement()
            .accessibilityLabel("向下拖动或轻点收起")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { closePanel() }
    }

    private var panelDragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                panelDragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                let flick = value.predictedEndTranslation.height - value.translation.height > 300
                if value.translation.height > 80 || flick {
                    closePanel()
                } else {
                    withAnimation(.easeOut(duration: 0.25)) { panelDragOffset = 0 }
                }
            }
    }

    /// 顶部一行:左「搜索本书」胶囊(高 36、圆角 18、底 字色 6%),右目录/书签 tab;
    /// 下面一条 1pt 分隔线。
    private var panelHeader: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                chapterSearchRow
                panelSegments
            }
            .padding(.leading, 24)
            .padding(.trailing, 24)
            .frame(height: 56)
            .contentShape(Rectangle())
            .gesture(panelDragGesture)

            Rectangle()
                .fill(theme.menuPrimary.opacity(0.12))
                .frame(height: 1)
        }
    }

    private var visibleSegments: [ReaderPanelSegment] {
        ReaderPanelSegment.allCases.filter { $0 != .notes || !notes.isEmpty }
    }

    /// 右端 tab:目录 / 书签(有笔记时再多一个);选中是主色加 2pt 短横线。
    private var panelSegments: some View {
        HStack(spacing: 18) {
            ForEach(visibleSegments) { segment in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { panelSegment = segment }
                } label: {
                    VStack(spacing: 4) {
                        Text(segment.title)
                            .font(.system(size: 15, weight: panelSegment == segment ? .semibold : .regular))
                            .foregroundStyle(panelSegment == segment ? theme.menuPrimary : theme.menuSecondary)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(panelSegment == segment ? theme.accentColor : Color.clear)
                            .frame(width: 18, height: 2)
                    }
                    .frame(height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(segment.title)
                .accessibilityAddTraits(panelSegment == segment ? [.isSelected] : [])
            }
        }
    }

    /// 有书源的书才显示缓存/更新目录这一行;测试书没有书源时整行不出现。
    @ViewBuilder
    private var chapterCacheRow: some View {
        if panelSegment == .chapters,
           onCache != nil,
           cacheState != .unavailable {
            HStack(spacing: 16) {
                Spacer(minLength: 0)
                chapterListCacheControl
                    .font(.system(size: 12))
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
                                .font(.system(size: 15))
                                .foregroundStyle(theme.menuPrimary)
                                .frame(width: 20, height: 20)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isUpdatingToc)
                    .accessibilityLabel("更新目录")
                }
            }
            .padding(.horizontal, 24)
            .frame(height: 32)
        }
    }

    @ViewBuilder
    private var panelSectionContent: some View {
        switch panelSegment {
        case .chapters:
            VStack(spacing: 0) {
                if let tocToast {
                    tocToastBar(tocToast)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .transition(.opacity)
                }
                if chapterSearchKeyword.isEmpty {
                    chapterList
                } else if filteredChapters.isEmpty {
                    emptyChapterSearchResult
                } else {
                    Text("找到 \(filteredChapters.count) 章")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.menuSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 6)
                    chapterList
                }
            }
        case .bookmarks:
            VStack(spacing: 0) {
                addBookmarkRow
                markList(
                    marks: bookmarks,
                    emptyTitle: "还没有书签",
                    emptyBody: "从页面顶部下拉,松手就能加书签"
                )
            }
        case .notes:
            markList(
                marks: notes,
                emptyTitle: "还没有笔记",
                emptyBody: "长按正文选中文字，就能写笔记"
            )
        }
    }

    private func openPanel(_ segment: ReaderPanelSegment) {
        panelSegment = segment
        isPanelSearchOpen = false
        panelDragOffset = 0
        withAnimation(.easeOut(duration: 0.3)) { showChapterList = true }
    }

    private func closePanel() {
        isPanelSearchOpen = false
        chapterSearch = ""
        withAnimation(.easeOut(duration: 0.25)) {
            panelDragOffset = 0
            showChapterList = false
            selectedTool = nil
        }
    }

    /// 书签面板顶部那颗按钮:本页没书签「给这一页加书签」,已有「移除书签」。
    private var addBookmarkRow: some View {
        Button {
            onAddBookmarkHere?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: hasPageBookmark ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 14, weight: .medium))
                Text(hasPageBookmark ? "移除书签" : "给这一页加书签")
                    .font(.system(size: 14))
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.menuPrimary)
            .padding(.horizontal, 24)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasPageBookmark ? "移除书签" : "给这一页加书签")
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.menuPrimary.opacity(0.06))
                .frame(height: 1)
        }
    }

    private var bookMarks: [ReadingMark] {
        book.marks
            .filter { $0.id != pendingDeletionID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var bookmarks: [ReadingMark] { bookMarks.filter { !$0.isNote } }
    private var notes: [ReadingMark] { bookMarks.filter { $0.isNote } }

    /// 有书签的章:目录行右侧那个 6pt 圆点。
    private var bookmarkChapterIndices: Set<Int> {
        Set(bookmarks.map(\.chapterIndex))
    }

    private func markList(
        marks: [ReadingMark],
        emptyTitle: String,
        emptyBody: String
    ) -> some View {
        Group {
            if marks.isEmpty {
                VStack(spacing: 8) {
                    Text(emptyTitle)
                        .font(.system(size: 15))
                        .foregroundStyle(theme.menuPrimary)
                    Text(emptyBody)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.menuSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 120)
            } else {
                List {
                    ForEach(marks) { mark in
                        Button {
                            closePanel()
                            if mark.isNote {
                                onOpenNote?(mark)
                            } else {
                                onJumpToMark?(mark)
                            }
                        } label: {
                            markRow(mark)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteMark(mark)
                            } label: {
                                Text("删除")
                            }
                        }
                        .accessibilityAction(named: "删除") { deleteMark(mark) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    /// 书签行:第一行「第 12 章 夜行 · 33%」加右侧时间,下面两行摘录,行高 84。
    private func markRow(_ mark: ReadingMark) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Text("\(chapterLabel(for: mark)) · \(percentText(for: mark))")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.menuPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(Self.shortDate(mark.createdAt))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.menuSecondary)
            }
            if mark.isNote, let note = mark.note {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.menuSecondary)
                    .lineLimit(2)
            }
            Text(Self.excerptText(mark.excerpt))
                .font(.system(size: 13))
                .foregroundStyle(theme.menuSecondary)
                .lineLimit(2)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// 章节名本身常常已经带「第 N 章」,别在书签行里再叠一遍。
    private func chapterLabel(for mark: ReadingMark) -> String {
        let title = (chapters.first { $0.index == mark.chapterIndex }?.title ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "第 \(mark.chapterIndex + 1) 章" : title
    }

    /// 书签在章内的百分比,按段落在本章里的位置算。
    private func percentText(for mark: ReadingMark) -> String {
        let total = max(chapterParagraphCount(at: mark.chapterIndex), 1)
        let value = min(max(Double(mark.paragraphIndex + 1) / Double(total), 0), 1)
        return "\(Int((value * 100).rounded()))%"
    }

    private func chapterParagraphCount(at index: Int) -> Int {
        guard let chapter = chapters.first(where: { $0.index == index }) else { return 1 }
        return (chapter.content ?? "")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
    }

    static func excerptText(_ text: String) -> String {
        text.count > 200 ? String(text.prefix(200)) + "…" : text
    }

    /// 当天「今天」、今年「8月6日」、往年「2025年8月6日」。
    static func shortDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        if calendar.isDateInToday(date) {
            return "今天"
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            formatter.dateFormat = "M月d日"
        } else {
            formatter.dateFormat = "yyyy年M月d日"
        }
        return formatter.string(from: date)
    }

    /// Deleting waits for the undo window to close, so undo only has to cancel
    /// the pending delete instead of putting a mark back.
    private func deleteMark(_ mark: ReadingMark) {
        pendingDeletionID = mark.id
        showUndoToast("已删除书签")
    }


    private func commitPendingDeletion() {
        guard let id = pendingDeletionID else { return }
        pendingDeletionID = nil
        if let mark = book.marks.first(where: { $0.id == id }) {
            modelContext.delete(mark)
            try? modelContext.save()
        }
    }

    private func undoDelete() {
        pendingDeletionID = nil
        hideUndoToast()
    }

    private func showUndoToast(_ text: String) {
        undoToastTask?.cancel()
        withAnimation(.easeInOut(duration: 0.15)) { undoToast = text }
        undoToastTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                commitPendingDeletion()
                hideUndoToast()
            }
        }
    }

    private func hideUndoToast() {
        undoToastTask?.cancel()
        withAnimation(.easeInOut(duration: 0.15)) { undoToast = nil }
    }

    private func undoBar(_ text: String) -> some View {
        HStack(spacing: 12) {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(theme.menuPrimary)
            Spacer()
            Button(action: undoDelete) {
                Text("撤销")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.menuPrimary)
                    .frame(height: 44)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.menuPrimary.opacity(0.06))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .transition(.opacity)
    }

    private var chapterSearchKeyword: String {
        chapterSearch.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredChapters: [Chapter] {
        let keyword = chapterSearchKeyword
        guard !keyword.isEmpty else { return chapters }
        return chapters.filter { $0.title.localizedCaseInsensitiveContains(keyword) }
    }

    /// 搜索本书:高 36、圆角 18 的胶囊,底色 = 字色 6%;输入即过滤章节。
    private var chapterSearchRow: some View {
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
                .accessibilityLabel("搜索本书")
                .overlay(alignment: .leading) {
                    if chapterSearch.isEmpty {
                        Text("搜索本书")
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
                            .font(.system(size: 15))
                            .foregroundStyle(theme.menuPrimary)
                            .frame(width: 20, height: 20)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isUpdatingToc)
                .accessibilityLabel("更新目录")
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 36)
        .background(
            Capsule(style: .continuous)
                .fill(theme.menuPrimary.opacity(0.06))
        )
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
                    closePanel()
                } label: {
                    chapterRow(chapter)
                }
                .buttonStyle(.plain)
                .id(chapter.index)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
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

    /// 目录行:56pt 高,当前章强调色 + 左侧 3×20 竖条,有书签的章右侧一个 6pt 圆点。
    /// 右侧百分比只给读过的章(章序号在当前章之前);没读过的章不显示数字,
    /// 免得把「这一章在全书的位置」误当成阅读进度。
    private func chapterPercent(for chapter: Chapter) -> Int {
        guard !chapters.isEmpty else { return 0 }
        return Int((Double(chapter.index) / Double(chapters.count) * 100).rounded())
    }

    private func chapterRow(_ chapter: Chapter) -> some View {
        let isCurrent = chapter.index == currentChapterIndex
        let isRead = chapter.index < currentChapterIndex
        let hasBookmark = bookmarkChapterIndices.contains(chapter.index)
        return HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(theme.accentColor)
                .frame(width: 3, height: 20)
                .padding(.leading, 8)
                .opacity(isCurrent ? 1 : 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.title)
                    .font(.system(size: 16, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? theme.accentColor : theme.menuPrimary)
                    .lineLimit(2)
                if isCurrent {
                    Text("当前读到")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.menuSecondary)
                }
            }
            .padding(.leading, 13)
            Spacer(minLength: 8)
            if hasBookmark {
                Circle()
                    .fill(theme.menuSecondary)
                    .frame(width: 6, height: 6)
                    .padding(.trailing, 10)
            }
            if !isCurrent, isRead {
                Text("\(chapterPercent(for: chapter))%")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.menuSecondary)
                    .padding(.trailing, 24)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.menuPrimary.opacity(0.08))
                .frame(height: 1)
                .padding(.leading, 24)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hasBookmark ? "\(chapter.title),有书签" : chapter.title)
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
                        "\(processed)/\(target) · 已缓存 \(cacheCountText(cached: cached, total: total))",
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
                    proxy.scrollTo(currentChapterIndex, anchor: UnitPoint(x: 0, y: 0.34))
                }
            } else {
                proxy.scrollTo(currentChapterIndex, anchor: UnitPoint(x: 0, y: 0.34))
            }
        }
    }
}

private enum ReaderPanelSegment: String, CaseIterable, Identifiable {
    case chapters
    case bookmarks
    case notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chapters: return "目录"
        case .bookmarks: return "书签"
        case .notes: return "笔记"
        }
    }
}

/// Full-screen note editor: the passage on top, the reader's own words below.
struct NoteEditorView: View {
    let excerpt: String
    let initialNote: String
    let onCancel: () -> Void
    let onSave: (String) -> Void
    var onDelete: (() -> Void)? = nil

    @State private var text: String
    @State private var isConfirmingDelete = false
    @FocusState private var isFocused: Bool

    init(
        excerpt: String,
        initialNote: String,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.excerpt = excerpt
        self.initialNote = initialNote
        self.onCancel = onCancel
        self.onSave = onSave
        self.onDelete = onDelete
        _text = State(initialValue: initialNote)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView {
                    Text(excerpt)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.primary.opacity(0.06))
                        )
                }
                .frame(maxHeight: 132)

                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("写下你的想法…")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(.system(size: 15))
                        .focused($isFocused)
                        .scrollContentBackground(.hidden)
                }

                if let onDelete {
                    Button(role: .destructive) {
                        // The dialog must not come up under the keyboard, or its
                        // cancel button is unreachable.
                        isFocused = false
                        Task {
                            try? await Task.sleep(nanoseconds: 250_000_000)
                            isConfirmingDelete = true
                        }
                    } label: {
                        Text("删除这条笔记")
                            .font(.system(size: 15))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .navigationTitle("写笔记")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("删除这条笔记？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) { onDelete?() }
                Button("取消", role: .cancel) {}
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { onSave(text) }
                }
            }
        }
        .onAppear { isFocused = true }
    }
}

/// 面板只有上边两个圆角,下边是直角。
struct TopRoundedRectangle: Shape {
    var radius: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 滑轨本体用 UISlider;读屏交给自定义 UIAccessibilityElement,
/// 才能把「第 N 档,共 M 档」作为值念出来,而不是小数百分比。
struct ReaderLevelSlider: View {
    @Binding var normalizedValue: Double
    let tint: Color
    let label: String
    let spokenValue: String
    let levelCount: Int

    var body: some View {
        ReaderLevelSliderControl(
            normalizedValue: $normalizedValue,
            tint: tint,
            label: label,
            spokenValue: spokenValue,
            levelCount: levelCount
        )
    }
}

private struct ReaderLevelSliderControl: UIViewRepresentable {
    @Binding var normalizedValue: Double
    let tint: Color
    let label: String
    let spokenValue: String
    let levelCount: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> ReaderLevelUISlider {
        let slider = ReaderLevelUISlider()
        slider.isAccessibilityElement = false
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.isContinuous = true
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.valueChanged(_:)),
            for: .valueChanged
        )
        return slider
    }

    func updateUIView(_ slider: ReaderLevelUISlider, context: Context) {
        context.coordinator.parent = self
        slider.value = Float(min(max(normalizedValue, 0), 1))
        slider.minimumTrackTintColor = UIColor(tint)
        slider.maximumTrackTintColor = UIColor(tint).withAlphaComponent(0.22)
        slider.levelCount = max(levelCount, 2)
        slider.spokenLabel = label
        slider.spokenValue = spokenValue
        slider.refreshAccessibilityElement()
    }

    final class Coordinator: NSObject {
        var parent: ReaderLevelSliderControl

        init(_ parent: ReaderLevelSliderControl) {
            self.parent = parent
        }

        @objc func valueChanged(_ sender: UISlider) {
            parent.normalizedValue = Double(sender.value)
        }
    }
}

final class ReaderLevelUISlider: UISlider {
    var spokenLabel: String = ""
    var spokenValue: String = ""
    var levelCount: Int = 2

    private lazy var levelElement: ReaderSliderAccessibilityElement = {
        let element = ReaderSliderAccessibilityElement(accessibilityContainer: self)
        element.slider = self
        return element
    }()

    private lazy var levelElements: [Any] = [levelElement]

    override var accessibilityElements: [Any]? {
        get { levelElements }
        set { }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        levelElement.accessibilityFrameInContainerSpace = bounds
    }

    func refreshAccessibilityElement() {
        levelElement.spokenLabel = spokenLabel
        levelElement.spokenValue = spokenValue
        levelElement.accessibilityFrameInContainerSpace = bounds
    }

    func adjustLevel(by direction: Int) {
        let steps = max(levelCount - 1, 1)
        let next = min(max(value + Float(direction) / Float(steps), 0), 1)
        guard next != value else { return }
        value = next
        sendActions(for: .valueChanged)
    }
}

final class ReaderSliderAccessibilityElement: UIAccessibilityElement {
    weak var slider: ReaderLevelUISlider?
    var spokenLabel = ""
    var spokenValue = ""

    override var accessibilityLabel: String? {
        get { spokenLabel }
        set { spokenLabel = newValue ?? "" }
    }

    override var accessibilityValue: String? {
        get { spokenValue }
        set { spokenValue = newValue ?? "" }
    }

    override var accessibilityTraits: UIAccessibilityTraits {
        get { .adjustable }
        set { }
    }

    override func accessibilityIncrement() {
        slider?.adjustLevel(by: 1)
    }

    override func accessibilityDecrement() {
        slider?.adjustLevel(by: -1)
    }
}
