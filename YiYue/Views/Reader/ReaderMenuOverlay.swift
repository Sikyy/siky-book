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

/// 底部五格:目录 / 书签 / 进度 / 亮度 / 排版。
enum ReaderTool: String, CaseIterable, Identifiable {
    case chapters
    case bookmarks
    case progress
    case brightness
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chapters: return "目录"
        case .bookmarks: return "书签"
        case .progress: return "进度"
        case .brightness: return "亮度"
        case .text: return "排版"
        }
    }

    /// 进度格是自绘圆点加横杆,不用 SF Symbol。
    var icon: String {
        switch self {
        case .chapters: return "line.3.horizontal"
        case .bookmarks: return "bookmark"
        case .progress: return "circle"
        case .brightness: return "sun.max"
        case .text: return "textformat.size"
        }
    }
}

enum ReaderToolbarMetrics {
    /// 底部工具条从 y=791 到屏幕底。
    static let height: CGFloat = 83
    static let topBarHeight: CGFloat = 40
    /// 顶栏高 40、返回 / 排版 / 分享 / 更多图标中心 y=78。
    static let topBarTop: CGFloat = 58
    /// 菜单开时的顶栏底色带 0–100:顶栏自己占 58–98,带子上下各留一点余量。
    static let topBarBandHeight: CGFloat = 100

    /// 顶栏图标墨盒约 21.7 宽 × 19 高(原来按 24 点字画,偏大)。
    static let topBarIconWidth: CGFloat = 21.7
    static let topBarIconHeight: CGFloat = 19
    static let topBarGlyphSize: CGFloat = 22
    /// 「排版」的 AA 是 SF Symbol textformat.size:22 点时墨迹约 24.3 宽 × 16 高。
    /// 参考要 25.3 宽 × 19 高,所以字号提到 26(墨高约 19,和另外两颗手感一致),
    /// 再把横向压到 0.88:28.8 × 0.88 ≈ 25.3。只改这一颗,不动分享和更多。
    static let textGlyphSize: CGFloat = 26
    static let textGlyphScaleX: CGFloat = 0.88
    /// 返回的雪佛龙和其他三个同一字号:22 点字、墨高约 19–20。
    static let topBarBackGlyphSize: CGFloat = 22
    /// 雪佛龙字形墨心比字框中心偏左约 2 点,回补后墨心落在 13.8。
    static let backOpticalOffset: CGFloat = 2
    /// 402 点屏上的图标中心 x。右侧三个从屏右缘往回量,换屏宽也不跑位。
    static let backCenterX: CGFloat = 13.8
    /// 参考墨心:排版 294.35、分享 338.3、更多 380.15。
    /// 三颗都是绝对落点,图形墨宽再大也不会把分享挤走。
    static let textCenterFromTrailing: CGFloat = 402 - 294.35  // 107.65
    static let shareCenterFromTrailing: CGFloat = 402 - 338.3  // 63.7
    static let moreCenterFromTrailing: CGFloat = 402 - 380.15  // 21.85
    /// 分享改成「方框 + 右上斜箭头」,20 点字的墨迹约 18 × 18。
    static let shareGlyphSize: CGFloat = 20
    /// 「排版」自绘:两条圆头横线(上短下长)+ 右下角小勾,墨盒 22 × 19。
    static let typesettingGlyphWidth: CGFloat = 22
    static let typesettingGlyphHeight: CGFloat = 19
    /// 「更多」自绘:竖三点,墨盒 3.7 × 16.3。
    static let moreGlyphWidth: CGFloat = 3.7
    static let moreGlyphHeight: CGFloat = 16.3
    /// 图标按钮的点击框:32 宽、40 高,相邻两颗不叠。
    static let buttonBoxWidth: CGFloat = 32

    /// 底部五格:图标墨高 22.3、墨底离屏底 49(原来是 23 / 52)。
    static let iconBoxHeight: CGFloat = 22.3
    static let iconBottomInset: CGFloat = 49
    static let iconGlyphSize: CGFloat = 21.3
    /// 选中格:实心蓝圆 #2493EE;圆直径和图标墨高一致。
    static let selectedFillHex: String = "#2493EE"
    static var selectedFill: Color { Color(hex: selectedFillHex) }
    /// 选中格圆里的小图形要收到圆内(参考图约 10 × 13)。
    static let selectedGlyphSize: CGFloat = 12
    /// 第二格书签:参考墨宽 22、墨高 22.3、描边 1.5。
    /// 描边沿路径居中,所以描边态画 20.5 × 20.8,外沿正好 22 × 22.3。
    static let bookmarkGlyphWidth: CGFloat = 22
    static let bookmarkGlyphHeight: CGFloat = 22.3
    static let bookmarkStrokeWidth: CGFloat = 1.5
    /// 图标墨底离工具条内容顶:83 − 49 − 22.3 = 11.7,再扣 1 点分隔线。
    static let iconTopInset: CGFloat = height - iconBottomInset - iconBoxHeight - 1
    /// 正文可排到的底边离屏底 = 图标墨顶(49 + 22.3 = 71.3)。
    /// 页脚那行删掉后,正文一直排到图标行,这条线接手原来「页脚上沿」的位置。
    static let bodyBottomInset: CGFloat = iconBottomInset + iconBoxHeight
}

/// 第三格:进度。小圆环两侧各一段短线(左 4、右 3),中间留 1 点缝,
/// 不再是「一条长横杆穿过圆」的禁止符。未选中是描边圆,选中格填实(参考图)。
struct ReaderProgressGlyph: View {
    var color: Color
    var isFilled: Bool = false
    /// 圆直径。选中格按参照放大到 15.3,未选中维持 14。
    var circleDiameter: CGFloat = 14
    /// 右侧短线。选中格收成 2.7,和左 4 + 两个 1 点缝凑成 24 宽。
    var trailingBarWidth: CGFloat = 3
    /// 整颗字形的落点宽度。选中格 24,未选中 23。
    var glyphWidth: CGFloat = 23

    var body: some View {
        HStack(spacing: 1) {
            Capsule()
                .fill(color)
                .frame(width: 4, height: 2)
            Group {
                if isFilled {
                    Circle().fill(color)
                } else {
                    Circle().stroke(color, lineWidth: 1.5)
                }
            }
            .frame(width: circleDiameter, height: circleDiameter)
            Capsule()
                .fill(color)
                .frame(width: trailingBarWidth, height: 2)
        }
        .frame(width: glyphWidth, height: 23)
    }
}

/// 「排版」图标:两条圆头横线,上短下长,像标题压正文;右下角一个小勾。
/// 墨盒 22 × 19,全部用 Path 画,不依赖 SF Symbol,也不引图片。
struct ReaderTypesettingGlyph: View {
    var color: Color

    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            let lineHeight = height * 0.135
            let radius = lineHeight / 2

            func line(y: CGFloat, length: CGFloat) {
                let rect = CGRect(x: 0, y: y, width: length, height: lineHeight)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: radius),
                    with: .color(color)
                )
            }

            // 上横线短(标题),下横线长(正文);两线都在墨盒上半部。
            line(y: 0, length: width * 0.55)
            line(y: height * 0.35, length: width * 0.80)

            // 右下角小勾:笔画宽约 2.4,圆头圆角;勾的顶端落在下横线以下。
            var check = Path()
            check.move(to: CGPoint(x: width * 0.55, y: height * 0.72))
            check.addLine(to: CGPoint(x: width * 0.70, y: height * 0.93))
            check.addLine(to: CGPoint(x: width * 0.94, y: height * 0.55))
            context.stroke(
                check,
                with: .color(color),
                style: StrokeStyle(
                    lineWidth: width * 0.11,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
        .frame(
            width: ReaderToolbarMetrics.typesettingGlyphWidth,
            height: ReaderToolbarMetrics.typesettingGlyphHeight
        )

    }
}

/// 「更多」自绘:竖排三个圆点,墨盒 3.7 × 16.3(参照量到的高度)。
struct ReaderMoreGlyph: View {
    var color: Color

    var body: some View {
        Canvas { context, size in
            let diameter = size.width
            let step = (size.height - diameter) / 2
            for index in 0..<3 {
                let y = diameter / 2 + CGFloat(index) * step
                let rect = CGRect(x: 0, y: y - diameter / 2, width: diameter, height: diameter)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
        .frame(
            width: ReaderToolbarMetrics.moreGlyphWidth,
            height: ReaderToolbarMetrics.moreGlyphHeight
        )
    }
}

/// 第二格书签的字形。SF Symbol 的 bookmark 只有约 14 宽,参考要 22 宽;
/// 形状、燕尾深度和 1.5 描边都不变,只把宽度加宽 —— 横向拉伸会把竖笔
/// 撑粗,所以用路径重画,描边保持均匀。
struct ReaderBookmarkGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(2, min(rect.width, rect.height) / 4)
        let notch = min(5, rect.height / 4)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + radius))
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
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - notch))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 滑轨刻度:按档位等分,选中那档是短实线,其余档位一条淡线。
struct ReaderSliderTicks: View {
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

/// 色块 / 缩略图的选中蓝环:描边 2、离块面 2。
/// 用负 padding 把路径推到块外 3 点(2 点留白 + 半个描边),
/// 环就不会压到色块自己的边缘。
struct BrightnessSelectionRing: View {
    let cornerRadius: CGFloat
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(color, lineWidth: 2)
            .padding(-3)
            .allowsHitTesting(false)
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
    /// 阅读进度,和进度格同一个算法。
    var progressPercent: String = ""
    /// 进度格的圆环取 0…1。
    var progressFraction: Double = 0
    /// 本书累计阅读时长(秒):来自 ReaderView 里 ReadingTimeSession 的走表。
    /// 进度面板右栏显示这个真数,左栏的剩余估计也用同一个数,两栏不会对不上。
    var readingSeconds: TimeInterval = 0
    /// 当前页每一条正文线的行顶(屏幕坐标),面板顶边贴它。
    var bodyLineTops: [CGFloat] = []
    /// 顶栏底边的屏幕 y:面板从这条线下面开始,不能盖住顶栏。
    var topBarBottomY: CGFloat = 0
    /// 本书已读完整章数(章序号算真数,不估阅读时长)。
    var readChapterCount: Int = 0
    /// 自动翻页当前开关、间隔(秒);菜单开着时只显示,不驱动计时器。
    var autoPageEnabled: Bool = false
    var autoPageInterval: Int = 20
    var onShowReadingDetails: (() -> Void)? = nil
    var onSetAutoPageEnabled: ((Bool) -> Void)? = nil
    var onSetAutoPageInterval: ((Int) -> Void)? = nil
    /// 从「更多」里删除成功后,阅读页应立即退出,不能继续显示已删掉的书。
    var onBookDeleted: (() -> Void)? = nil

    /// 菜单 / 顶栏 / 面板的配色。照片背景上统一走夜间,
    /// 否则纸色图标压在深色照片上看不见。
    private var theme: ReaderTheme { settings.chromeTheme }

    @Environment(\.modelContext) private var modelContext

    @State private var showChapterList = false
    @State private var sliderValue: Double = 0
    /// 拖滑轨时滑块跟手用的比例;松手后清掉,回到和进度数字同一个值。
    @State private var sliderDragFraction: Double?
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
    @State private var panelSegment: ReaderPanelSegment = .chapters
    @State private var panelDragOffset: CGFloat = 0
    @State private var topBarHeight: CGFloat = 0
    @State private var isPanelSearchOpen = false
    @State private var pendingDeletionID: UUID?
    @State private var undoToast: String?
    @State private var undoToastTask: Task<Void, Never>?
    @State private var showAutoPageSheet = false
    @State private var showSettingsSheet = false
    /// 字号面板三颗按钮的目的地:和设置页对应的三行走同一个详情页。
    @State private var settingsDestination: ReaderSettingsDestination?
    @State private var showMoreMenu = false
    @State private var pendingMoreAction: MoreAction?
    @State private var showDeleteBookConfirmation = false
    @State private var changeSourceBook: Book?
    @State private var coverPickerBook: Book?
    @State private var isDeletingBook = false
    @State private var deleteBookError: String?
    @State private var showDeleteBookError = false

    private enum MoreAction {
        case changeSource
        case editCover
        case settings
        case delete
    }

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
                // 只铺在顶栏底边到菜单块顶边之间:顶栏按钮和底部胶囊不会因为
                // 同一次触摸再命中这层,避免按钮动作和「收菜单」同时触发。
                Color.clear
                    .contentShape(Rectangle())
                    .frame(
                        width: screenWidth,
                        height: max(0, BottomChromeMetrics.panelTop - 98)
                    )
                    .offset(y: 98)
                    .onTapGesture {
                        if selectedTool != nil || showChapterList {
                            closePanel()
                        } else {
                            onDismiss()
                        }
                    }

                // 面板上沿的渐隐先画:面板和它的阴影再压上来,
                // 这样 552–556 的压字带不会把面板阴影的上半截抹掉。
                panelTopFade

                // 底部菜单块:从面板顶(按底往上的间距链算出)到屏底,纸色、分隔线、软阴影。
                // 内容全部画在这块里,正文排版视口一帧不动。
                bottomChrome(width: screenWidth, height: screenHeight)

                // 顶栏底色带:0–100 一条实色,只在图标态(菜单开、没开面板)出现,
                // 面板一开就只剩正文底色,和参考图的两态一致。
                // 照片背景自己已经铺了 0–100 的 20% 黑,这里不再盖一层纸色。
                if selectedTool == nil, !settings.isPhotoBackground {
                    topBarBand(width: screenWidth)
                }

                // 顶栏:高 40,返回 / 排版 / 分享 / 更多。
                topBar

                if let panelTool = selectedTool {
                    switch panelTool {
                    case .text:
                        // 字号面板也画在底部 chrome 里:顶边 542,内容从 558 往下排。
                        // 以前那层浮动卡片已撤掉,不再用屏幕绝对坐标定位。
                        EmptyView()
                    case .brightness:
                        // 亮度面板也是底部这块 chrome 自己:滑杆、颜色、背景
                        // 都画在 bottomChrome 里,顶边跟进度面板同一套内容链。
                        EmptyView()
                    case .progress:
                        // 进度面板就是底部这块 chrome 自己:统计行、滑轨、胶囊
                        // 都画在 bottomChrome 里。以前再叠一层旧版浮层面板,
                        // 它的底色会把胶囊盖掉、数字却露在上沿外面,所以这里不画。
                        EmptyView()
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
        .sheet(isPresented: $showAutoPageSheet) {
            ReaderAutoPageSettingsSheet(
                isEnabled: autoPageEnabled,
                interval: autoPageInterval,
                onChangeEnabled: { onSetAutoPageEnabled?($0) },
                onChangeInterval: { onSetAutoPageInterval?($0) }
            )
            .presentationDetents([.height(220)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSettingsSheet) {
            ReaderSettingsSheet(settings: settings)
        }
        .sheet(item: $settingsDestination) { destination in
            // 面板按钮和设置页三行共用一个详情视图,不各写一套。
            ReaderSettingsDetailSheet(destination: destination, settings: settings)
        }
        .sheet(isPresented: $showMoreMenu, onDismiss: performPendingMoreAction) {
            moreSheet
                .presentationDetents([.height(moreSheetHeight)])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(16)
                .presentationBackground(theme.menuBackground)
        }
        .sheet(item: $changeSourceBook) { book in
            ChangeSourceView(book: book)
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
        .alert(
            "删除失败",
            isPresented: Binding(
                get: { showDeleteBookError },
                set: { showDeleteBookError = $0 }
            )
        ) {
            Button("确定") { showDeleteBookError = false }
        } message: {
            Text(deleteBookError ?? "")
        }
        .alert(
            "删除《\(book.title)》?",
            isPresented: $showDeleteBookConfirmation
        ) {
            Button("删除", role: .destructive) { deleteBookFromReader() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这本书和它的阅读进度都会删掉，不能恢复。")
        }
    }

    /// 「更多」的动作表:设置 / 换源(限书源书) / 修改封面 / 删除 / 取消。
    private var moreSheetHeight: CGFloat {
        let actionRowCount = (book.sourceType == .bookSource ? 4 : 3)
        return CGFloat(actionRowCount + 1) * 50 + 8 + 32
    }

    private var moreSheet: some View {
        VStack(spacing: 8) {
            VStack(spacing: 0) {
                if book.sourceType == .bookSource {
                    moreSheetRow("换源") {
                        pendingMoreAction = .changeSource
                        showMoreMenu = false
                    }
                    moreSheetDivider
                }
                moreSheetRow("修改封面") {
                    pendingMoreAction = .editCover
                    showMoreMenu = false
                }
                moreSheetDivider
                // 字号浮层撤掉后,设置页从「更多」进:三颗按钮和设置页仍共用同一套详情页。
                moreSheetRow("设置") {
                    pendingMoreAction = .settings
                    showMoreMenu = false
                }
                moreSheetDivider
                moreSheetRow("删除", destructive: true) {
                    pendingMoreAction = .delete
                    showMoreMenu = false
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.menuPrimary.opacity(0.05))
            )

            moreSheetRow("取消") {
                pendingMoreAction = nil
                showMoreMenu = false
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.menuPrimary.opacity(0.05))
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.menuBackground)
    }

    private func moreSheetRow(
        _ title: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(destructive ? Color.red.opacity(0.9) : theme.menuPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var moreSheetDivider: some View {
        Rectangle()
            .fill(theme.menuPrimary.opacity(0.10))
            .frame(height: 1)
            .padding(.leading, 16)
    }

    /// 动作表收起后再弹下一层,避免系统在 dismissing 期间丢掉新的 sheet。
    private func performPendingMoreAction() {
        guard let action = pendingMoreAction else { return }
        pendingMoreAction = nil
        switch action {
        case .changeSource:
            changeSourceBook = book
        case .editCover:
            coverPickerBook = book
        case .settings:
            showSettingsSheet = true
        case .delete:
            showDeleteBookConfirmation = true
        }
    }

    /// 和书架右键菜单同一条删除路径:清缓存、删模型、示例书标记、清封面,
    /// 成功后立即退出阅读页,不能留在已删除的书上。
    private func deleteBookFromReader() {
        guard !isDeletingBook else { return }
        isDeletingBook = true
        let bookTitle = book.title
        let coverURL = book.coverURL
        let wasSample = SampleBookService.isSample(book)
        Task { @MainActor in
            defer { isDeletingBook = false }
            let manager = BookManager(modelContext: modelContext)
            do {
                try await manager.deleteBook(book)
            } catch {
                deleteBookError = "无法删除《\(bookTitle)》：\(error.localizedDescription)"
                showDeleteBookError = true
                return
            }
            if wasSample {
                SampleBookService.markUserDeleted()
            }
            if let coverURL {
                CoverSearchService.discardDownloadedCover(coverURL)
            }
            if let onBookDeleted {
                onBookDeleted()
            } else {
                onBack()
            }
        }
    }

    // MARK: - Bottom Chrome

    private enum BottomChromeMetrics {
        /// 参考屏高:整块内容按屏幕绝对坐标摆放。
        static let screenBottom: CGFloat = 874

        /// 从 874 的底边往上量:图标 22.3 点、胶囊 36、滑槽 35.7,
        /// 中间夹 35.7 / 35.3,再往上 31.3 到标签、11 到数字,最后 35 到面板顶。
        /// 这些缝就是面板的全部高度,面板不再写死 334。
        static let iconBottomInset = ReaderToolbarMetrics.iconBottomInset       // 49
        static let iconBoxHeight = ReaderToolbarMetrics.iconBoxHeight           // 22.3
        static let iconPillGap: CGFloat = 35.7
        static let pillHeight: CGFloat = 36
        static let pillSliderGap: CGFloat = 35.3
        static let sliderHeight: CGFloat = 35.7
        static let sliderLabelGap: CGFloat = 31.3
        static let labelInkHeight: CGFloat = 9.4
        static let labelNumberGap: CGFloat = 11
        static let numberInkHeight: CGFloat = 17.3
        static let numberPanelGap: CGFloat = 35

        /// 由底往上的间距链算出来的各条边,不再单独硬编码顶边。
        static let iconBottom = screenBottom - iconBottomInset          // 825
        static let iconTop = iconBottom - iconBoxHeight                 // 802.7
        static let pillBottom = iconTop - iconPillGap                   // 767
        static let pillTop = pillBottom - pillHeight                    // 731
        static let sliderBottom = pillTop - pillSliderGap               // 695.7
        static let sliderTop = sliderBottom - sliderHeight              // 660
        static let labelInkBottom = sliderTop - sliderLabelGap          // 628.7
        static let labelInkTop = labelInkBottom - labelInkHeight        // 619.3
        static let numberInkBottom = labelInkTop - labelNumberGap       // 608.3
        static let numberInkTop = numberInkBottom - numberInkHeight     // 591
        static let panelHeight = iconBottomInset + iconBoxHeight + iconPillGap
            + pillHeight + pillSliderGap + sliderHeight + sliderLabelGap
            + labelInkHeight + labelNumberGap + numberInkHeight + numberPanelGap
        /// 面板高 318、贴底:874 − 318 = 556(参考图进度面板顶)。
        static let panelTop = screenBottom - panelHeight                // 556
        /// 夜间进度面板的顶/底色。上沿渐隐的实色端必须是面板顶色,
        /// 否则 552–556 那 4 点压字带会在 556 处露出一条色缝。
        static let panelTopDarkHex = "#141416"
        static let panelBottomDarkHex = "#1C1C1E"
        /// 面板上沿渐隐:只从面板顶 −20 到 −5 走 15 点渐变,
        /// 文字在 536 只剩 30%(遮色 70%),到 551 恢复到全实(遮色 0);
        /// 551 到面板顶是 5 点实色硬裁,正文一个字也不再往下画。
        /// 方向和旧版相反:旧版是上实下虚,参照是上虚下实。
        static let fadeHeight: CGFloat = 15
        /// 渐变顶端遮色 70% = 文字剩 30%。
        static let fadeTopOpacity: Double = 0.70
        /// 渐变底端遮色 42% = 文字剩 58%:裁切线前的最后一点墨不做到全实,
        /// 参照那半截字整行是一个浓度。
        static let fadeBottomOpacity: Double = 0.42
        /// 面板顶 −5 到面板顶的硬裁带。
        static let fadeClipHeight: CGFloat = 5
        /// 整块渐隐 + 硬裁的高度:15 + 5 = 20(从面板顶 −20 起)。
        static let fadeTotalHeight = fadeHeight + fadeClipHeight

        /// 24 点数字的行框顶比墨顶高 6 点。
        static let numberInkTopOffset: CGFloat = 6
        /// 数字行与标签行的间距:让标签墨顶落在 619.3(数字墨底 608.3 + 11)。
        static let numberLabelSpacing: CGFloat = 4
        static let progressFrameTop = numberInkTop - numberInkTopOffset // 585
        /// 面板顶 → 数字墨顶是 35:24 点数字的行框比墨顶高 6 点,
        /// 所以竖直栈的顶距只留 29,数字墨顶正好落在面板顶下 35。
        static let numberFrameTopPadding = numberPanelGap - numberInkTopOffset // 29
        /// 24 点 SF 数字的行框高约 28.6;11 点标签的行框高约 13.1。
        static let numberLineHeight: CGFloat = 28.6
        static let labelLineHeight: CGFloat = 13.1
        /// 数字行框 + 4 点行距 + 标签行框 = 45.7。
        /// 估计句为 nil 时也占住这块高度,下面的滑轨和胶囊不会跟着往上跳。
        static let statsBlockHeight = numberLineHeight + numberLabelSpacing + labelLineHeight // 45.7
        /// 标签行框底到槽顶:104 − 29 − 45.7 = 29.3(链上 31.3 是墨底到槽顶)。
        static let statsSliderGap = sliderTop - panelTop - numberFrameTopPadding - statsBlockHeight
        /// 两栏(Siky 定,第三栏整块不摆):列心落在屏宽四等分 100.5 / 301.5,
        /// 竖线在 x=201,1 点宽。
        /// 参考竖线 583.6–626.2、高 42.6;统计行顶在 585(面板顶 556 + 29),
        /// 所以竖线上移 1.4,数字和标签的落点不动。
        static let dividerHeight: CGFloat = 42.6
        static let dividerWidth: CGFloat = 1
        static let dividerTop: CGFloat = 583.6 - progressFrameTop          // -1.4
        /// 夜间竖线照参考图取 #323233;浅色沿用面板那档 12% 墨。
        static let dividerDarkHex: String = "#323233"
        static let numberFontSize: CGFloat = 24
        static let unitFontSize: CGFloat = 11
        static let grooveLeft: CGFloat = 21
        static let grooveRight: CGFloat = 390
        static let arrowInset: CGFloat = 17
        /// SF 雪佛龙字形在字框里向外偏约 1.2,回补后箭头墨迹中心距槽边 17。
        static let arrowOpticalInset: CGFloat = 1.2
        static let knobSize: CGFloat = 36
        /// 已读段叠在未读槽色上,合成后比未读深约 11 级灰(未读 12% 墨)。
        static let readTrackOpacity: CGFloat = 0.056
        static let pillMargin: CGFloat = 20
        /// 两胶囊 20–190.3 / 211.7–382:中间缝 21.3(参考图量的,不是 21)。
        static let pillGap: CGFloat = 21.3
    }

    /// 亮度面板的竖直链(design-diff-16 §4)。面板顶和进度面板一样是 556,
    /// 高度同样 318:滑杆 32 顶距 + 35.7 + 颜色标题 + 4 块 33 + 背景标题 + 5 图 38。
    /// 每一段都从上一段的底边加间距,不用屏幕绝对 y 偏移。
    private enum BrightnessPanelMetrics {
        static let panelDarkHex = "#171719"
        static let panelTop = BottomChromeMetrics.panelTop                 // 556
        static let panelHeight = BottomChromeMetrics.panelHeight           // 318
        static let ringHex = "#2493EE"

        /// 滑杆轨道整条 x 22–379.7、高 35.7、y 588–623.7;左端一颗小太阳。
        static let sliderLeft: CGFloat = 22
        static let sliderRightInset: CGFloat = 402 - 379.7                 // 22.3
        static let sliderTop = 588 - panelTop                              // 32
        static let sliderHeight: CGFloat = 35.7
        static let sunCenterInset: CGFloat = 20                            // 轨道左端往内 20
        static let sunSize: CGFloat = 13
        /// 参考图的滑块是 36 的实心圆,正好顶满轨道高附近。
        static let knobSize: CGFloat = 36
        static let knobDarkHex = "#8C8C90"
        /// 轨道比面板亮约 10% 墨,和参考图 (39,39,41) 对得上。
        static let trackOpacity: CGFloat = 0.10

        /// 「颜色」墨顶 641.3,墨高 8.7;11 点行框高 13.1,
        /// 行框顶到字墨顶约 2,所以标题上距 = 641.3 − 623.7 − 2 = 15.6。
        static let titleFontSize: CGFloat = 11
        static let titleLineHeight: CGFloat = 13.1
        static let titleInkTopOffset: CGFloat = 2
        static let colorTitleTopGap = 641.3 - (sliderTop + panelTop + sliderHeight) - titleInkTopOffset // 15.6
        /// 标题墨底 650 → 色块顶 663:行框底 652.4 到色块 10.6。
        static let colorTitleBottomGap: CGFloat = 10.6
        /// 色块现在宽 82、缝 10:4 × 82 + 3 × 10 = 358。
        /// 右边缘保持 378.7 不变,所以左边缘从 23 改成 20.7
        /// (20.7 + 358 + 23.3 = 402),四块自然算出来就是 82 宽。
        /// 外圈还是 2 点蓝环 + 2 点留白。
        static let colourLeft: CGFloat = 20.7
        static let colourRightInset: CGFloat = 402 - 378.7                 // 23.3
        static let colourGap: CGFloat = 10
        static let colourHeight: CGFloat = 33
        static let colourCorner: CGFloat = 5
        /// 色块底 696 →「背景」墨顶 713.3,行框顶 711.3,上距 15.3。
        static let backgroundTitleTopGap: CGFloat = 15.3
        /// 「背景」行框底 724.4 → 缩略图顶 731,下距 6.6。
        static let backgroundTitleBottomGap: CGFloat = 6.6
        /// 五张缩略图 22–379.7:高 38、缝 9,宽度由列宽等分(约 64)。
        static let photoLeft: CGFloat = 22
        static let photoRightInset: CGFloat = 402 - 379.7                  // 22.3
        static let photoGap: CGFloat = 9
        static let photoHeight: CGFloat = 38
        static let photoCorner: CGFloat = 8
        /// 蓝环:描边 2、离块面 2;路径内缩 3 = 2 留白 + 半个描边。
        static let ringLineWidth: CGFloat = 2
        static let ringPadding: CGFloat = 3
    }

    /// 字号面板的竖直链(规格 spec-字号面板.md)。面板顶 542,贴底到 874,
    /// 高度 332;里面从上到下四段,段间用实测硬数,全部从上一段底边加间距,
    /// 不写屏幕绝对 y 偏移。
    private enum FontSizePanelMetrics {
        static let panelTop: CGFloat = 542
        static let panelHeight = BottomChromeMetrics.screenBottom - panelTop // 332

        /// 面板顶 → 标题行顶 16。
        static let titleTopGap: CGFloat = 558 - panelTop // 16
        /// 标题行 558.0–575.7,高 17.7。
        static let titleRowHeight: CGFloat = 17.7
        /// 标题墨顶 561.0 = 行框顶 558 + 3;13 点行框在 17.7 行里居中,
        /// 墨高 11.7,正好落在 561.0–572.7。
        static let titleInkTopOffset: CGFloat = 3
        static let titleInkHeight: CGFloat = 11.7
        static let titleLeading: CGFloat = 24.7
        static let titleFontSize: CGFloat = 13

        /// 右侧「仅应用到当前书籍」12 点,墨右 336.3、墨高 10.7。
        static let scopeLabelFontSize: CGFloat = 12
        /// 标签字框右缘到开关左缘:墨右 336.3 + 约 1.2 字框留白 → 337.5,
        /// 开关左缘 344.0,所以缝 6.5。
        static let scopeLabelToggleGap: CGFloat = 6.5
        /// 开关 34 × 17.7,右缘 377.7(离屏边 24.3)。
        static let switchWidth: CGFloat = 34
        static let switchHeight: CGFloat = 17.7
        static let switchTrailingInset: CGFloat = 402 - 377.7 // 24.3
        /// 按参照 34 × 17.7 自绘一颗原生手感的开关:蓝底、白圆钮,
        /// 旋钮保持正圆(15.7),不会被非等比缩放拉成椭圆。
        static let switchKnobDiameter: CGFloat = 15.7
        static let switchKnobInset: CGFloat = 1
        static let switchOffTrackOpacity: Double = 0.22

        /// 标题墨底 572.7 → 滑杆顶 588.0 = 15.3(规格里的这段);
        /// 标题行框底 575.7 → 滑杆顶只有 12.3,两者差一个 3 点的墨顶偏移。
        static let titleInkBottomToSlider: CGFloat = 15.3
        static let titleRowToSlider = titleInkBottomToSlider
            - (titleRowHeight - titleInkTopOffset - titleInkHeight) // 12.3

        /// 滑杆轨道 x 22.0–379.7、高 35.7、全圆角。
        static let sliderLeft: CGFloat = 22
        static let sliderRightInset: CGFloat = 402 - 379.7 // 22.3
        static let sliderHeight: CGFloat = 35.7
        static let sliderKnobSize: CGFloat = 36
        /// 参考 19 号时旋钮中心 126.85。左端圆心 40(= 22 + 18),
        /// 19 是 12 档里的第 4 档(3 / 11),所以行程
        /// (126.85 − 40) ÷ (3 / 11) = 318.5;右端圆心 358.5。
        static let knobTravel: CGFloat = 318.5
        /// 左「A」11 点、字心 41.8;右「A」15 点、字心 359.85。
        static let leftACenter: CGFloat = 41.8
        static let leftAFontSize: CGFloat = 11
        static let rightACenterFromTrailing: CGFloat = 402 - 359.85 // 42.15
        static let rightAFontSize: CGFloat = 15
        /// 旋钮里的字号 13 点。
        static let knobNumberFontSize: CGFloat = 13
        /// 轨道比面板亮约 10% 墨,和亮度面板同一档。
        static let trackOpacity: CGFloat = 0.10
        /// 夜间旋钮参照实测是 #8C8C90;浅色用白。
        static let knobDarkHex = "#8C8C90"

        /// 滑杆底 623.7 → 分段组顶 660.0 = 36.3。
        static let sliderToSegments: CGFloat = 36.3
        /// 两组轨道:左起 22.0,各宽 168.3,缝 21.4,右缘 380.0。
        static let segmentLeading: CGFloat = 22
        static let segmentTrailing: CGFloat = 402 - 380.0 // 22
        static let segmentGap: CGFloat = 21.4
        static let segmentHeight: CGFloat = 35.7
        /// 「小 / 紧」字心距组左 19.8,「大 / 松」字心距组右 19.8。
        static let segmentLabelInset: CGFloat = 19.8
        static let segmentLabelFontSize: CGFloat = 13
        /// 组内旋钮 36,中心在组正中(默认档 3 / 6 = 0.5 → 22 + 84.15 = 106.15)。
        static let segmentKnobSize: CGFloat = 36

        /// 分段组底 695.7 → 按钮顶 730.0 = 34.3。
        static let segmentsToButtons: CGFloat = 34.3
        /// 三颗按钮 112.3 × 37.7,缝 10.4,x 22.0 / 144.7 / 267.3,右缘 379.7。
        static let buttonHeight: CGFloat = 37.7
        static let buttonWidth: CGFloat = 112.3
        static let buttonGap: CGFloat = 10.4
        static let buttonLeading: CGFloat = 22
        static let buttonTrailingInset: CGFloat = 402 - 379.7 // 22.3
        static let buttonFontSize: CGFloat = 13
        /// 文字与「›」之间 4.3,整组在按钮里水平居中。
        static let buttonArrowGap: CGFloat = 4.3
        /// 按钮底色比面板亮一档,沿用设置页那颗 6% 墨。
        static let buttonFillOpacity: CGFloat = 0.06

        /// 按钮底 767.7 → 五格顶 802.3 = 34.6。五格由 bottomToolbar 画,
        /// 这里只留出这段空,不改图标行自己的位置。
        static let buttonsToIconRow: CGFloat = 34.6
    }

    /// 菜单块:进度面板(统计行 / 滑轨 / 胶囊)、亮度面板(滑杆 / 颜色 / 背景)
    /// 或字号面板(标题 / 滑杆 / 两组 / 三颗按钮)。背景从算出的顶边起,
    /// 面板里从顶往下就是一个竖直栈,不再用屏幕绝对 y 偏移。
    /// 进度 / 亮度顶边 556、高 318;字号顶边 542、高 332,都贴屏底。
    /// 上沿渐隐按 20 点收尾,面板顶 −5 以下硬裁。
    private var resolvedPanelTop: CGFloat {
        selectedTool == .text ? FontSizePanelMetrics.panelTop : BottomChromeMetrics.panelTop
    }

    /// 菜单块上沿的渐隐带:让压在边上的那行字淡出去,而不是被切一半。
    /// 实色端要和正文底色一致(纸色 / 夜间 #121212),不能用面板色:
    /// 面板色铺到面板顶上方会把面板顶糊成一条渐变带,分层就量不准了。
    /// 照片背景没有单一底色,才退回面板色。
    private var panelFadeColor: Color {
        if settings.isPhotoBackground {
            if selectedTool == .brightness, theme.isDark {
                return Color(hex: BrightnessPanelMetrics.panelDarkHex)
            }
            return theme.isDark
                ? Color(hex: BottomChromeMetrics.panelTopDarkHex)
                : theme.topBarBand
        }
        return theme.backgroundColor
    }

    /// 面板顶 −20 到 −5 走渐变:顶端文字剩 30%,到底边恢复到 100%;
    /// 再往下的 5 点用实色压死,等于把正文硬裁在面板顶 −5。
    /// 方向和旧版相反:字在靠近面板的一侧最实,往上淡掉。
    private var panelTopFade: some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: panelFadeColor.opacity(BottomChromeMetrics.fadeTopOpacity), location: 0),
                    .init(color: panelFadeColor.opacity(BottomChromeMetrics.fadeBottomOpacity), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: BottomChromeMetrics.fadeHeight)

            panelFadeColor
                .frame(height: BottomChromeMetrics.fadeClipHeight)
        }
        .frame(height: BottomChromeMetrics.fadeTotalHeight)
        .allowsHitTesting(false)
        .offset(y: resolvedPanelTop - BottomChromeMetrics.fadeTotalHeight)
    }

    private func bottomChrome(width: CGFloat, height: CGFloat) -> some View {
        let panelTop = resolvedPanelTop
        let contentHeight = max(0, height - panelTop)
        // 面板高度按内容链算好:进度/亮度 318,字号 332。
        // 图标那一格由 bottomToolbar 画在面板底色上,所以链尾还留 35.7 + 22.3 + 49。
        let showingFont = selectedTool == .text
        let showingBrightness = selectedTool == .brightness
        let basePanelHeight = showingFont
            ? FontSizePanelMetrics.panelHeight
            : BottomChromeMetrics.panelHeight
        let panelHeight = min(basePanelHeight, contentHeight)
        return VStack(spacing: 0) {
            if showingFont {
                // 字号面板:标题行 → 滑杆 → 边距/行距 → 三颗按钮,顶边 542。
                fontPanelContent(width: width)
            } else if showingBrightness {
                // 亮度面板:整块按内容链从上往下排,顶边同样是 556。
                brightnessPanelContent(width: width)
            } else {
                progressStatsRow(width: width)
                    // 固定占住数字行 + 11 点墨距 + 标签行;估计句为空时不留空行但保住高度。
                    .frame(
                        width: width,
                        height: BottomChromeMetrics.statsBlockHeight,
                        alignment: .top
                    )

                chapterSlider(width: width)
                    .frame(width: width, height: BottomChromeMetrics.sliderHeight)
                    .padding(.top, BottomChromeMetrics.statsSliderGap)

                pillRow(width: width)
                    .padding(.top, BottomChromeMetrics.pillSliderGap)
            }
        }
        .padding(.top, showingFont || showingBrightness ? 0 : BottomChromeMetrics.numberFrameTopPadding)
        .frame(width: width, height: panelHeight, alignment: .top)
        .background {
            if showingBrightness, theme.isDark {
                // 亮度面板参考图是 #171719 的实色,不比进度面板的渐变亮。
                Color(hex: BrightnessPanelMetrics.panelDarkHex)
            } else if theme.isDark {
                LinearGradient(
                    colors: [Color(hex: BottomChromeMetrics.panelTopDarkHex),
                             Color(hex: BottomChromeMetrics.panelBottomDarkHex)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                // 浅色面板用顶栏带那一档 (240,232,219),比纸色深一档:
                // 页面 < 顶栏带/面板 < 墨,三层关系才分得开。夜间维持原值。
                theme.topBarBand
            }
        }
        .overlay(alignment: .top) {
            if !theme.isDark {
                Rectangle()
                    .fill(theme.menuPrimary.opacity(0.12))
                    .frame(height: 1)
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 0)
        .offset(y: panelTop)
    }

    // MARK: - 亮度面板

    /// 亮度面板的整条竖直栈:滑杆 → 颜色标题 → 四色块 → 背景标题 → 五张图。
    /// 面板顶 556、高 318,和进度面板同一套顶底;里面不写绝对 y。
    private func brightnessPanelContent(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            brightnessSlider(width: width)
                .frame(width: width, height: BrightnessPanelMetrics.sliderHeight)
                .padding(.top, BrightnessPanelMetrics.sliderTop)

            brightnessGroupTitle("颜色")
                .padding(.top, BrightnessPanelMetrics.colorTitleTopGap)
                .padding(.bottom, BrightnessPanelMetrics.colorTitleBottomGap)

            brightnessColourRow(width: width)

            brightnessGroupTitle("背景")
                .padding(.top, BrightnessPanelMetrics.backgroundTitleTopGap)
                .padding(.bottom, BrightnessPanelMetrics.backgroundTitleBottomGap)

            brightnessPhotoRow(width: width)

            Spacer(minLength: 0)
        }
        .frame(width: width, height: BrightnessPanelMetrics.panelHeight, alignment: .top)
    }

    /// 分组标题墨左 24.3、11 点次要色;行框高 13.1,墨顶在行框顶下约 2 点。
    private func brightnessGroupTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: BrightnessPanelMetrics.titleFontSize))
            .foregroundStyle(theme.menuSecondary)
            .padding(.leading, 24.3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: BrightnessPanelMetrics.titleLineHeight, alignment: .topLeading)
    }

    /// 整条轨 x 22–379.7、高 35.7:左端小太阳,滑块 35 的圆跟着当前亮度走。
    /// 参考图的滑块顶满轨道高,所以轨道两端不给额外内缩。
    private func brightnessSlider(width: CGFloat) -> some View {
        let left = BrightnessPanelMetrics.sliderLeft
        let trackWidth = max(0, width - left - BrightnessPanelMetrics.sliderRightInset)
        let knob = BrightnessPanelMetrics.knobSize
        let travel = max(1, trackWidth - knob)
        let fraction = min(max(brightnessValue, 0), 1)
        let knobX = left + knob / 2 + CGFloat(fraction) * travel
        let centerY = BrightnessPanelMetrics.sliderHeight / 2
        return ZStack(alignment: .topLeading) {
            Capsule(style: .continuous)
                .fill(theme.menuPrimary.opacity(BrightnessPanelMetrics.trackOpacity))
                .frame(width: trackWidth, height: BrightnessPanelMetrics.sliderHeight)
                .position(x: left + trackWidth / 2, y: centerY)

            Image(systemName: "sun.min")
                .font(.system(size: BrightnessPanelMetrics.sunSize, weight: .regular))
                .foregroundStyle(theme.menuPrimary.opacity(0.7))
                .position(x: left + BrightnessPanelMetrics.sunCenterInset, y: centerY)
                .allowsHitTesting(false)

            Circle()
                .fill(theme.isDark
                    ? Color(hex: BrightnessPanelMetrics.knobDarkHex)
                    : Color.white)
                .frame(width: knob, height: knob)
                .shadow(color: .black.opacity(theme.isDark ? 0 : 0.18), radius: 3, x: 0, y: 1)
                .position(x: knobX, y: centerY)
        }
        .frame(width: width, height: BrightnessPanelMetrics.sliderHeight)
        .contentShape(Rectangle())
        .coordinateSpace(name: "brightnessSlider")
        .gesture(brightnessSliderGesture(width: width))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("屏幕亮度")
        .accessibilityValue("\(Int((brightnessValue * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            let step = 0.05
            let delta = direction == .increment ? step : -step
            let next = min(max(brightnessValue + delta, 0), 1)
            brightnessValue = next
            onBrightnessChange?(next)
        }
    }

    private func brightnessSliderGesture(width: CGFloat) -> some Gesture {
        let left = BrightnessPanelMetrics.sliderLeft
        let trackWidth = max(0, width - left - BrightnessPanelMetrics.sliderRightInset)
        let knob = BrightnessPanelMetrics.knobSize
        let travel = max(1, trackWidth - knob)
        return DragGesture(minimumDistance: 0, coordinateSpace: .named("brightnessSlider"))
            .onChanged { value in
                let x = min(max(value.location.x - left - knob / 2, 0), travel)
                let next = Double(x / travel)
                guard abs(next - brightnessValue) > 0.0005 else { return }
                brightnessValue = next
                onBrightnessChange?(next)
            }
    }

    /// 颜色四块:白 / 米黄 / 护眼绿 / 夜间,宽 79.7、缝 12.3、高 33。
    /// 选中加 2 点蓝环,环离块面留 2 点。夜间块里放一个月亮,和参考图一致。
    private func brightnessColourRow(width: CGFloat) -> some View {
        HStack(spacing: BrightnessPanelMetrics.colourGap) {
            ForEach(Array(ReaderTheme.palette.enumerated()), id: \.element) { index, item in
                let selected = !settings.isPhotoBackground && settings.theme == item
                Button {
                    settings.selectColour(item)
                } label: {
                    RoundedRectangle(cornerRadius: BrightnessPanelMetrics.colourCorner, style: .continuous)
                        .fill(item.backgroundColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: BrightnessPanelMetrics.colourHeight)
                        .overlay {
                            if item == .dark {
                                Image(systemName: "moon.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(selected
                                        ? Color(hex: BrightnessPanelMetrics.ringHex)
                                        : Color.white.opacity(0.8))
                            }
                        }
                        .overlay {
                            if selected {
                                BrightnessSelectionRing(
                                    cornerRadius: BrightnessPanelMetrics.colourCorner + 3,
                                    color: Color(hex: BrightnessPanelMetrics.ringHex)
                                )
                            }
                        }
                        .contentShape(RoundedRectangle(
                            cornerRadius: BrightnessPanelMetrics.colourCorner,
                            style: .continuous
                        ))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.displayName)，四个里第 \(index + 1) 个")
                .accessibilityValue(selected ? "已选中" : "")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(.leading, BrightnessPanelMetrics.colourLeft)
        .padding(.trailing, BrightnessPanelMetrics.colourRightInset)
        .frame(width: width, height: BrightnessPanelMetrics.colourHeight, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("颜色")
    }

    /// 背景五张实景图:高 38、缝 9、圆角 8,宽度按 22–379.7 等分(约 64)。
    /// 图上不写字;名称只给读屏。
    private func brightnessPhotoRow(width: CGFloat) -> some View {
        HStack(spacing: BrightnessPanelMetrics.photoGap) {
            ForEach(Array(ReaderBackgroundPhoto.allCases.enumerated()), id: \.element) { index, photo in
                let selected = settings.backgroundPhoto == photo
                Button {
                    settings.selectPhoto(photo)
                } label: {
                    Image(photo.assetName)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: BrightnessPanelMetrics.photoHeight)
                        .clipped()
                        .clipShape(RoundedRectangle(
                            cornerRadius: BrightnessPanelMetrics.photoCorner,
                            style: .continuous
                        ))
                        .overlay {
                            if selected {
                                BrightnessSelectionRing(
                                    cornerRadius: BrightnessPanelMetrics.photoCorner + 3,
                                    color: Color(hex: BrightnessPanelMetrics.ringHex)
                                )
                            }
                        }
                        .contentShape(RoundedRectangle(
                            cornerRadius: BrightnessPanelMetrics.photoCorner,
                            style: .continuous
                        ))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(photo.displayName)，五个里第 \(index + 1) 个")
                .accessibilityValue(selected ? "已选中" : "")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(.leading, BrightnessPanelMetrics.photoLeft)
        .padding(.trailing, BrightnessPanelMetrics.photoRightInset)
        .frame(width: width, height: BrightnessPanelMetrics.photoHeight, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("背景")
    }

    // MARK: - 字号面板

    /// 字号面板的整条竖直栈:标题行 → 字号滑杆 → 边距/行距 → 三颗按钮。
    /// 面板顶 542、高 332;段间硬数从上一段底边加,不写屏幕绝对 y。
    private func fontPanelContent(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            fontSizeTitleRow(width: width)
                .frame(width: width, height: FontSizePanelMetrics.titleRowHeight)
                .padding(.top, FontSizePanelMetrics.titleTopGap)

            fontSizeSlider(width: width)
                .frame(width: width, height: FontSizePanelMetrics.sliderHeight)
                .padding(.top, FontSizePanelMetrics.titleRowToSlider)

            fontSizeSegmentRow(width: width)
                .frame(width: width, height: FontSizePanelMetrics.segmentHeight)
                .padding(.top, FontSizePanelMetrics.sliderToSegments)

            fontSizeButtonRow(width: width)
                .frame(width: width, height: FontSizePanelMetrics.buttonHeight)
                .padding(.top, FontSizePanelMetrics.segmentsToButtons)

            Spacer(minLength: 0)
        }
        .frame(width: width, height: FontSizePanelMetrics.panelHeight, alignment: .top)
    }

    /// 标题行 558.0–575.7:左「字体大小」13 点半粗,右「仅应用到当前书籍」12 点 + 34 × 17.7 开关。
    /// 开关不是摆设:它真的切换字号写全局还是只写当前这本书。
    private func fontSizeTitleRow(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("字体大小")
                .font(.system(size: FontSizePanelMetrics.titleFontSize, weight: .semibold))
                .foregroundStyle(theme.menuPrimary)
                .padding(.leading, FontSizePanelMetrics.titleLeading)

            Spacer(minLength: 8)

            HStack(spacing: FontSizePanelMetrics.scopeLabelToggleGap) {
                Text("仅应用到当前书籍")
                    .font(.system(size: FontSizePanelMetrics.scopeLabelFontSize))
                    .foregroundStyle(theme.menuSecondary)
                    .fixedSize()

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        settings.setOnlyCurrentBookFontSize(!settings.onlyCurrentBookFontSize)
                    }
                } label: {
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(settings.onlyCurrentBookFontSize
                                ? ReaderToolbarMetrics.selectedFill
                                : theme.menuPrimary.opacity(FontSizePanelMetrics.switchOffTrackOpacity))
                        Circle()
                            .fill(Color.white)
                            .frame(
                                width: FontSizePanelMetrics.switchKnobDiameter,
                                height: FontSizePanelMetrics.switchKnobDiameter
                            )
                            .shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 1)
                            .padding(.leading, FontSizePanelMetrics.switchKnobInset)
                            .offset(x: settings.onlyCurrentBookFontSize
                                ? FontSizePanelMetrics.switchWidth
                                    - FontSizePanelMetrics.switchKnobDiameter
                                    - FontSizePanelMetrics.switchKnobInset * 2
                                : 0)
                    }
                    .frame(width: FontSizePanelMetrics.switchWidth,
                           height: FontSizePanelMetrics.switchHeight)
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("仅应用到当前书籍")
                .accessibilityValue(settings.onlyCurrentBookFontSize ? "已开启" : "已关闭")
                .accessibilityAddTraits(settings.onlyCurrentBookFontSize ? [.isSelected] : [])
            }
            .padding(.trailing, FontSizePanelMetrics.switchTrailingInset)
        }
        .frame(width: width, height: FontSizePanelMetrics.titleRowHeight)
    }

    /// 字号滑杆 588.0–623.7:整条 22.0–379.7、高 35.7、全圆角;
    /// 左 A 11 点(字心 41.8)、右 A 15 点(字心 359.85),36 点旋钮里写当前字号。
    private func fontSizeSlider(width: CGFloat) -> some View {
        let left = FontSizePanelMetrics.sliderLeft
        let trackWidth = max(0, width - left - FontSizePanelMetrics.sliderRightInset)
        let knob = FontSizePanelMetrics.sliderKnobSize
        let levels = ReaderTypography.fontSizeLevels
        let count = levels.count
        let index = settings.fontSizeLevelIndex
        let fraction = count > 1 ? CGFloat(index) / CGFloat(count - 1) : 0
        let knobX = left + knob / 2 + fraction * FontSizePanelMetrics.knobTravel
        let centerY = FontSizePanelMetrics.sliderHeight / 2
        return ZStack(alignment: .topLeading) {
            Capsule(style: .continuous)
                .fill(theme.menuPrimary.opacity(FontSizePanelMetrics.trackOpacity))
                .frame(width: trackWidth, height: FontSizePanelMetrics.sliderHeight)
                .position(x: left + trackWidth / 2, y: centerY)

            Text("A")
                .font(.system(size: FontSizePanelMetrics.leftAFontSize))
                .foregroundStyle(theme.menuPrimary)
                .position(x: FontSizePanelMetrics.leftACenter, y: centerY)
                .allowsHitTesting(false)

            Text("A")
                .font(.system(size: FontSizePanelMetrics.rightAFontSize))
                .foregroundStyle(theme.menuPrimary)
                .position(x: width - FontSizePanelMetrics.rightACenterFromTrailing, y: centerY)
                .allowsHitTesting(false)

            fontSizeKnob(
                label: "\(Int(settings.fontSize))",
                diameter: knob,
                fontSize: FontSizePanelMetrics.knobNumberFontSize
            )
            .position(x: knobX, y: centerY)
        }
        .frame(width: width, height: FontSizePanelMetrics.sliderHeight)
        .contentShape(Rectangle())
        .coordinateSpace(name: "fontSizeSlider")
        .gesture(fontSizeSliderGesture(width: width))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("字体大小")
        .accessibilityValue("\(Int(settings.fontSize))")
        .accessibilityAdjustableAction { direction in
            let levels = ReaderTypography.fontSizeLevels
            let index = min(max(settings.fontSizeLevelIndex
                + (direction == .increment ? 1 : -1), 0), levels.count - 1)
            guard levels[index] != settings.fontSize else { return }
            settings.fontSize = levels[index]
            settings.save()
        }
    }

    private func fontSizeSliderGesture(width: CGFloat) -> some Gesture {
        let left = FontSizePanelMetrics.sliderLeft
        let knob = FontSizePanelMetrics.sliderKnobSize
        let travel = FontSizePanelMetrics.knobTravel
        return DragGesture(minimumDistance: 0, coordinateSpace: .named("fontSizeSlider"))
            .onChanged { value in
                let x = min(max(value.location.x - left - knob / 2, 0), travel)
                let fraction = x / travel
                let levels = ReaderTypography.fontSizeLevels
                let count = levels.count
                guard count > 1 else { return }
                let index = min(max(Int((fraction * CGFloat(count - 1)).rounded()), 0), count - 1)
                guard levels[index] != settings.fontSize else { return }
                // 拖动时实时改字号,阅读页照旧跟着重新分页。
                settings.fontSize = levels[index]
                settings.save()
            }
    }

    /// 36 点圆旋钮,里面写当前值。夜间参照实测是 #8C8C90,浅色用白。
    private func fontSizeKnob(label: String, diameter: CGFloat, fontSize: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(theme.isDark
                    ? Color(hex: FontSizePanelMetrics.knobDarkHex)
                    : Color.white)
                .shadow(color: .black.opacity(theme.isDark ? 0 : 0.18), radius: 3, x: 0, y: 1)
            Text(label)
                .font(.system(size: fontSize))
                .foregroundStyle(theme.isDark ? Color.white : theme.menuPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: diameter, height: diameter)
    }

    /// 边距 / 行距两组:各 168.3 宽、35.7 高、全圆角;左起 22.0,第二组 211.7。
    private func fontSizeSegmentRow(width: CGFloat) -> some View {
        let leading = FontSizePanelMetrics.segmentLeading
        let trailing = FontSizePanelMetrics.segmentTrailing
        let gap = FontSizePanelMetrics.segmentGap
        let segmentWidth = max(0, (width - leading - trailing - gap) / 2)
        return HStack(spacing: gap) {
            fontSizeSegment(
                width: segmentWidth,
                knobLabel: "边距",
                leadingLabel: "小",
                trailingLabel: "大",
                levels: ReaderTypography.horizontalPaddingLevels,
                current: settings.horizontalPadding,
                coordinateName: "fontSizeMarginSegment",
                commit: { value in
                    settings.horizontalPadding = value
                    settings.save()
                }
            )

            fontSizeSegment(
                width: segmentWidth,
                knobLabel: "行距",
                leadingLabel: "紧",
                trailingLabel: "松",
                levels: ReaderTypography.lineSpacingLevels,
                current: settings.lineSpacing,
                coordinateName: "fontSizeLineSpacingSegment",
                commit: { value in
                    settings.lineSpacing = value
                    settings.save()
                }
            )
        }
        .padding(.leading, leading)
        .padding(.trailing, trailing)
        .frame(width: width, height: FontSizePanelMetrics.segmentHeight)
    }

    /// 单组轨道:小/紧在左 19.8,大/松在右 19.8,旋钮中心按档位在组内走。
    private func fontSizeSegment<T: BinaryFloatingPoint>(
        width: CGFloat,
        knobLabel: String,
        leadingLabel: String,
        trailingLabel: String,
        levels: [T],
        current: T,
        coordinateName: String,
        commit: @escaping (T) -> Void
    ) -> some View {
        let knob = FontSizePanelMetrics.segmentKnobSize
        let count = levels.count
        let index = levels.enumerated().min {
            abs(Double($0.element) - Double(current)) < abs(Double($1.element) - Double(current))
        }?.offset ?? 0
        let fraction = count > 1 ? CGFloat(index) / CGFloat(count - 1) : 0
        let knobX = knob / 2 + fraction * max(0, width - knob)
        let centerY = FontSizePanelMetrics.segmentHeight / 2
        return ZStack(alignment: .topLeading) {
            Capsule(style: .continuous)
                .fill(theme.menuPrimary.opacity(FontSizePanelMetrics.trackOpacity))
                .frame(width: width, height: FontSizePanelMetrics.segmentHeight)

            Text(leadingLabel)
                .font(.system(size: FontSizePanelMetrics.segmentLabelFontSize))
                .foregroundStyle(theme.menuPrimary)
                .position(x: FontSizePanelMetrics.segmentLabelInset, y: centerY)
                .allowsHitTesting(false)

            Text(trailingLabel)
                .font(.system(size: FontSizePanelMetrics.segmentLabelFontSize))
                .foregroundStyle(theme.menuPrimary)
                .position(x: width - FontSizePanelMetrics.segmentLabelInset, y: centerY)
                .allowsHitTesting(false)

            fontSizeKnob(
                label: knobLabel,
                diameter: knob,
                fontSize: FontSizePanelMetrics.segmentLabelFontSize
            )
            .position(x: knobX, y: centerY)
        }
        .frame(width: width, height: FontSizePanelMetrics.segmentHeight)
        .contentShape(Rectangle())
        .coordinateSpace(name: coordinateName)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateName))
                .onChanged { value in
                    let travel = max(1, width - knob)
                    let x = min(max(value.location.x - knob / 2, 0), travel)
                    let fraction = x / travel
                    guard count > 1 else { return }
                    let index = min(max(Int((fraction * CGFloat(count - 1)).rounded()), 0), count - 1)
                    let level = levels[index]
                    guard abs(Double(level) - Double(current)) > 0.0001 else { return }
                    commit(level)
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(knobLabel)
        .accessibilityValue(levelValueDescription(index: index, count: count))
        .accessibilityAdjustableAction { direction in
            let next = min(max(index + (direction == .increment ? 1 : -1), 0), count - 1)
            guard next != index else { return }
            commit(levels[next])
        }
    }

    private func levelValueDescription(index: Int, count: Int) -> String {
        let total = max(count, 1)
        let clamped = min(max(index, 0), total - 1)
        return "第 \(clamped + 1) 档，共 \(total) 档"
    }

    /// 三颗按钮 730.0–767.7:112.3 × 37.7、缝 10.4,整组 22.0–379.7。
    /// 每颗都开到和设置页对应行同一个详情页。
    private func fontSizeButtonRow(width: CGFloat) -> some View {
        let buttonWidth = FontSizePanelMetrics.buttonWidth
        let gap = FontSizePanelMetrics.buttonGap
        let leading = FontSizePanelMetrics.buttonLeading
        let trailing = max(0, width - leading - buttonWidth * 3 - gap * 2)
        return HStack(spacing: gap) {
            fontSizeActionButton("字体样式", width: buttonWidth) {
                settingsDestination = .fontStyle
            }
            fontSizeActionButton("首行缩进", width: buttonWidth) {
                settingsDestination = .firstLineIndent
            }
            fontSizeActionButton("翻页方式", width: buttonWidth) {
                settingsDestination = .pageMode
            }
        }
        .padding(.leading, leading)
        .padding(.trailing, trailing)
        .frame(width: width, height: FontSizePanelMetrics.buttonHeight)
    }

    private func fontSizeActionButton(
        _ title: String,
        width: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: FontSizePanelMetrics.buttonArrowGap) {
                Text(title)
                    .font(.system(size: FontSizePanelMetrics.buttonFontSize))
                Text("›")
                    .font(.system(size: FontSizePanelMetrics.buttonFontSize))
            }
            .foregroundStyle(theme.menuPrimary)
            .frame(width: width, height: FontSizePanelMetrics.buttonHeight)
            .background(
                Capsule(style: .continuous)
                    .fill(theme.menuPrimary.opacity(FontSizePanelMetrics.buttonFillOpacity))
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func progressStatsRow(width: CGFloat) -> some View {
        // 百分号照参考图单独排 11 点;右栏的时长直接吃 ReadingTimeFormat 的拆段。
        let percentPieces = progressValuePieces(progressPercent)
        let durationPieces = ReadingTimeFormat.pieces(readingSeconds)
        // 左栏标签用百分比同一份进度比例和右栏同一份秒数反推,两栏永远不打架。
        // 文案只按进度比例分三档:不到 5% 写「刚开始读」;过了 5% 有估计句就用
        // 估计句,估不出来写「阅读进度」。三档都占同一行,数字的纵向位置不动。
        let estimate = ReadingTimeFormat.remainingEstimate(
            progress: progressFraction,
            seconds: readingSeconds
        )
        let progressLabel: String
        if progressFraction < 0.05 {
            progressLabel = "刚开始读"
        } else if let estimate {
            progressLabel = estimate
        } else {
            progressLabel = "阅读进度"
        }
        let columnWidth = width / 2
        return HStack(alignment: .top, spacing: 0) {
            progressStatColumn(
                pieces: percentPieces,
                label: progressLabel,
                accessibilityLabel: "\(progressPercent)，\(progressLabel)"
            )
            .frame(width: columnWidth)

            progressStatColumn(
                pieces: durationPieces,
                label: "阅读时长",
                accessibilityLabel: ReadingTimeFormat.spoken(readingSeconds)
            )
            .frame(width: columnWidth)
        }
        .frame(width: width)
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(
                    theme.isDark
                        ? Color(hex: BottomChromeMetrics.dividerDarkHex)
                        : theme.menuPrimary.opacity(0.12)
                )
                .frame(width: BottomChromeMetrics.dividerWidth,
                       height: BottomChromeMetrics.dividerHeight)
                .offset(
                    x: width / 2 - BottomChromeMetrics.dividerWidth / 2,
                    y: BottomChromeMetrics.dividerTop
                )
                .accessibilityHidden(true)
        }
    }

    /// 进度数字拆成「数」和「%」两段:数字 24 点,百分号 11 点,共用基线。
    private func progressValuePieces(_ percent: String) -> [ReadingTimeFormat.Piece] {
        guard percent.hasSuffix("%") else {
            return [ReadingTimeFormat.Piece(text: percent, isNumber: true)]
        }
        return [
            ReadingTimeFormat.Piece(text: String(percent.dropLast()), isNumber: true),
            ReadingTimeFormat.Piece(text: "%", isNumber: false)
        ]
    }

    /// 主数字 24 点;单位 / 百分号 / 「不到」这类文字 11 点,和主数字共用同一条基线。
    /// 两栏内容都在各自列宽里居中(列心 100.5 / 301.5),不是左对齐。
    /// 整块(数字 + 标签)是一个读屏元素,念屏上真有的「百分比 + 标签」。
    private func progressStatColumn(
        pieces: [ReadingTimeFormat.Piece],
        label: String,
        accessibilityLabel: String
    ) -> some View {
        VStack(spacing: BottomChromeMetrics.numberLabelSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                ForEach(pieces.indices, id: \.self) { index in
                    let piece = pieces[index]
                    Text(piece.text)
                        .font(.system(
                            size: piece.isNumber
                                ? BottomChromeMetrics.numberFontSize
                                : BottomChromeMetrics.unitFontSize,
                            weight: .medium
                        ))
                        .monospacedDigit()
                        .foregroundStyle(theme.textColor.opacity(0.9))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            // 三档标签都恒有一行,数字从同一个行框顶起排,行不跳。
            Text(label)
                .font(.system(size: BottomChromeMetrics.unitFontSize))
                .foregroundStyle(theme.textColor.opacity(0.45))
                .lineLimit(1)
                .fixedSize()
        }
        .frame(minWidth: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func chapterSlider(width: CGFloat) -> some View {
        let grooveLeft = BottomChromeMetrics.grooveLeft
        let grooveRight = min(BottomChromeMetrics.grooveRight, width)
        let grooveWidth = max(0, grooveRight - grooveLeft)
        let knobInset = BottomChromeMetrics.knobSize / 2
        let travelLeft = grooveLeft + knobInset
        let travelWidth = max(1, grooveWidth - knobInset * 2)
        // 滑块落点和上方进度数字用同一个值:显示 40% 就让圆心落在可走段的 40%,
        // 不再用「章序号 /(总章数-1)」——那会把 8/20 画到约 44% 的位置。
        // 拖动时临时跟手,松手后回到进度数字的值。
        let fraction = min(max(sliderDragFraction ?? progressFraction, 0), 1)
        let knobX = travelLeft + CGFloat(fraction) * travelWidth
        let centerY = BottomChromeMetrics.sliderHeight / 2
        return ZStack {
            Capsule()
                .fill(theme.menuPrimary.opacity(0.12))
                .frame(width: grooveWidth, height: BottomChromeMetrics.sliderHeight)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(theme.menuPrimary.opacity(BottomChromeMetrics.readTrackOpacity))
                        .frame(width: max(0, knobX - grooveLeft))
                }
                .clipShape(Capsule())
                .position(x: grooveLeft + grooveWidth / 2, y: centerY)
                .contentShape(Rectangle().inset(by: -16))
                .gesture(chapterSliderGesture(width: width))

            Circle()
                // 浅色面板改成顶栏带后,滑块用纸色才能从面板上浮出来;
                // 夜间仍用菜单底色。
                .fill(theme.isDark ? theme.menuBackground : theme.backgroundColor)
                .frame(width: BottomChromeMetrics.knobSize,
                       height: BottomChromeMetrics.knobSize)
                .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
                .position(x: knobX, y: centerY)
                .gesture(chapterSliderGesture(width: width))
                .accessibilityElement()
                .accessibilityLabel("章节滑轨")
                .accessibilityValue("第 \(currentChapterIndex + 1) 章，共 \(totalChapters) 章")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: jumpChapter(to: currentChapterIndex + 1)
                    case .decrement: jumpChapter(to: currentChapterIndex - 1)
                    @unknown default: break
                    }
                }

            Button {
                jumpChapter(to: currentChapterIndex - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(theme.menuPrimary.opacity(0.6))
                    .frame(width: 44, height: BottomChromeMetrics.sliderHeight)
                    .offset(x: BottomChromeMetrics.arrowOpticalInset)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .position(x: grooveLeft + BottomChromeMetrics.arrowInset, y: centerY)
            .disabled(currentChapterIndex <= 0)
            .accessibilityLabel("上一章")

            Button {
                jumpChapter(to: currentChapterIndex + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(theme.menuPrimary.opacity(0.6))
                    .frame(width: 44, height: BottomChromeMetrics.sliderHeight)
                    .offset(x: -BottomChromeMetrics.arrowOpticalInset)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .position(x: grooveRight - BottomChromeMetrics.arrowInset, y: centerY)
            .disabled(currentChapterIndex >= totalChapters - 1)
            .accessibilityLabel("下一章")
        }
        .coordinateSpace(name: "chapterSlider")
    }

    private func chapterSliderGesture(width: CGFloat) -> some Gesture {
        let grooveLeft = BottomChromeMetrics.grooveLeft
        let grooveRight = min(BottomChromeMetrics.grooveRight, width)
        let knobInset = BottomChromeMetrics.knobSize / 2
        let travelLeft = grooveLeft + knobInset
        let travelWidth = max(1, grooveRight - grooveLeft - knobInset * 2)
        let maxIndex = max(totalChapters - 1, 1)
        return DragGesture(minimumDistance: 0, coordinateSpace: .named("chapterSlider"))
            .onChanged { value in
                let x = min(max(value.location.x - travelLeft, 0), travelWidth)
                let fraction = Double(x / travelWidth)
                sliderDragFraction = fraction
                sliderValue = fraction * Double(maxIndex)
            }
            .onEnded { _ in
                // 进度数字是全书进度(章序号/总章数),按同一比例反推落在哪一章。
                let fraction = min(max(sliderDragFraction ?? 0, 0), 1)
                let index = Int(floor(fraction * Double(max(totalChapters, 1))))
                jumpChapter(to: index)
                sliderDragFraction = nil
            }
    }

    private func jumpChapter(to index: Int) {
        let clamped = min(max(index, 0), max(totalChapters - 1, 0))
        sliderValue = Double(clamped)
        if clamped != currentChapterIndex {
            currentChapterIndex = clamped
        }
    }

    private func pillRow(width: CGFloat) -> some View {
        let height = BottomChromeMetrics.pillHeight
        let margin = BottomChromeMetrics.pillMargin
        let gap = BottomChromeMetrics.pillGap
        let pillWidth = max(0, (width - margin * 2 - gap) / 2)
        let rightX = margin + pillWidth + gap
        return ZStack {
            pillButton(
                title: "阅读明细",
                highlighted: false,
                action: { onShowReadingDetails?() }
            )
            .frame(width: pillWidth, height: height)
            .contentShape(Rectangle())
            .position(
                x: margin + pillWidth / 2,
                y: height / 2
            )

            pillButton(
                // Camo 定:胶囊写的是「点下去会做什么」,不是当前状态。
                title: autoPageEnabled ? "关闭自动翻页" : "开启自动翻页",
                accessibilityValue: autoPageEnabled ? "已开启" : "已关闭",
                highlighted: autoPageEnabled,
                action: {
                    if autoPageEnabled {
                        onSetAutoPageEnabled?(false)
                    } else {
                        onSetAutoPageEnabled?(true)
                        showAutoPageSheet = true
                    }
                }
            )
            .frame(width: pillWidth, height: height)
            .contentShape(Rectangle())
            .position(
                x: rightX + pillWidth / 2,
                y: height / 2
            )
        }
        .frame(width: width, height: height)
    }

    private func pillButton(title: String, accessibilityValue: String? = nil, highlighted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(highlighted ? theme.menuBackground : theme.menuPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    Capsule(style: .continuous)
                        .fill(highlighted ? theme.accentColor : theme.menuPrimary.opacity(0.06))
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(accessibilityValue ?? ""))
        .accessibilityAddTraits(highlighted ? [.isSelected] : [])
    }

    // MARK: - Top Bar

    /// 菜单开、没开面板时的顶栏底色带:0–100 一条实色,夜间 #131314。
    /// 只铺在图标态;面板开时这份带上就只剩正文底色。
    private func topBarBand(width: CGFloat) -> some View {
        theme.topBarBand
            .frame(width: width, height: ReaderToolbarMetrics.topBarBandHeight)
            .allowsHitTesting(false)
    }

    /// 顶栏图标:墨盒 21.7 × 19,外面留 32 × 40 的点击框。
    /// horizontalScale 只给「排版」的 AA 用:把 26 点字形横向压回 25.3 墨宽,
    /// 纵向不动,墨高仍是约 19。
    private func topBarIconLabel(
        systemName: String,
        glyphSize: CGFloat,
        opticalOffset: CGFloat = 0,
        glyphHorizontalScale: CGFloat = 1
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: glyphSize, weight: .regular))
            .scaleEffect(x: glyphHorizontalScale, y: 1)
            .foregroundStyle(theme.menuPrimary)
            .frame(width: ReaderToolbarMetrics.topBarIconWidth,
                   height: ReaderToolbarMetrics.topBarIconHeight)
            .offset(x: opticalOffset)
            .frame(width: ReaderToolbarMetrics.buttonBoxWidth,
                   height: ReaderToolbarMetrics.topBarHeight)
            .contentShape(Rectangle())
    }

    private func topBarIconButton(
        systemName: String,
        label: String,
        glyphSize: CGFloat,
        centerX: CGFloat,
        opticalOffset: CGFloat = 0,
        glyphHorizontalScale: CGFloat = 1,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            topBarIconLabel(
                systemName: systemName,
                glyphSize: glyphSize,
                opticalOffset: opticalOffset,
                glyphHorizontalScale: glyphHorizontalScale
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .position(x: centerX, y: ReaderToolbarMetrics.topBarHeight / 2)
    }

    private var topBar: some View {
        ZStack(alignment: .topLeading) {
            if selectedTool != nil {
                // 面板开着:左侧只留章节名,字墨从 x=31 起,比正文(28)稍内收;
                // 墨迹 y 76–86,比居中位置下移 3 点。
                Text(chapterTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textColor.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 30)
                    .frame(height: ReaderToolbarMetrics.topBarHeight)
                    .offset(y: 3)
                    .accessibilityLabel(chapterTitle.isEmpty ? "" : "当前章节 \(chapterTitle)")
            } else {
                // 两态只换内容:图标态四颗按参考图的墨心落点排,
                // 返回 13.8、排版 294.35、分享 338.3、更多 380.15(402 点宽)。
                GeometryReader { proxy in
                    let width = proxy.size.width
                    topBarIconButton(
                        systemName: "chevron.left",
                        label: "返回",
                        glyphSize: ReaderToolbarMetrics.topBarBackGlyphSize,
                        centerX: ReaderToolbarMetrics.backCenterX,
                        opticalOffset: ReaderToolbarMetrics.backOpticalOffset,
                        action: { onBack() }
                    )

                    // 「排版」自绘:两条圆头横线 + 右下小勾,墨盒 22 × 19。
                    Button { handleToolTap(.text) } label: {
                        ReaderTypesettingGlyph(color: theme.menuPrimary)
                            .frame(
                                width: ReaderToolbarMetrics.buttonBoxWidth,
                                height: ReaderToolbarMetrics.topBarHeight
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("排版")
                    .position(
                        x: width - ReaderToolbarMetrics.textCenterFromTrailing,
                        y: ReaderToolbarMetrics.topBarHeight / 2
                    )

                    // 分享只发一句字,不放链接;系统分享面板由 ShareLink 拉起。
                    // 图形用「方框 + 右上斜箭头」,墨迹约 18 × 18,不再顶出行高。
                    ShareLink(item: "我在『今日已阅』读《\(book.title)》。") {
                        topBarIconLabel(
                            systemName: "arrow.up.right.square",
                            glyphSize: ReaderToolbarMetrics.shareGlyphSize
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("分享")
                    .position(
                        x: width - ReaderToolbarMetrics.shareCenterFromTrailing,
                        y: ReaderToolbarMetrics.topBarHeight / 2
                    )

                    // 「更多」自绘:竖三点,墨盒 3.7 × 16.3;系统里没有等价的竖向省略号。
                    Button { showMoreMenu = true } label: {
                        ReaderMoreGlyph(color: theme.menuPrimary)
                            .frame(
                                width: ReaderToolbarMetrics.buttonBoxWidth,
                                height: ReaderToolbarMetrics.topBarHeight
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("更多")
                    .position(
                        x: width - ReaderToolbarMetrics.moreCenterFromTrailing,
                        y: ReaderToolbarMetrics.topBarHeight / 2
                    )
                }
                .frame(height: ReaderToolbarMetrics.topBarHeight)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: ReaderToolbarMetrics.topBarHeight)
        // 图标态下面铺实色带;带子本身在 topBarBand 里画,这层只让顶栏不挡正文。
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
                            .frame(width: ReaderToolbarMetrics.iconBoxHeight,
                                   height: ReaderToolbarMetrics.iconBoxHeight)
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
        // 五格和上面的面板是同一块 chrome:浅色用顶栏带的色,否则图标行会在
        // 791 处又掉回纸色,面板看起来被截成两段。夜间维持菜单底。
        .background(theme.isDark ? theme.menuBackground : theme.topBarBand,
                    ignoresSafeAreaEdges: .bottom)
        .offset(y: top)
    }

    @ViewBuilder
    private func toolIcon(_ tool: ReaderTool) -> some View {
        let selected = selectedTool == tool
        let tint = theme.menuPrimary.opacity(0.7)
        let iconSide = ReaderToolbarMetrics.iconBoxHeight
        switch tool {
        case .progress:
            // 选中格:参照实测蓝块 24 × 15.3、中心 x 201.2、y 813.8。
            // 形状仍是「圆 + 两侧短线」,只把圆和右侧短线放大,不改形状。
            ReaderProgressGlyph(
                color: selected ? ReaderToolbarMetrics.selectedFill : tint,
                isFilled: selected,
                circleDiameter: selected ? 15.3 : 14,
                trailingBarWidth: selected ? 2.7 : 3,
                glyphWidth: selected ? 24 : 23
            )
            .frame(width: iconSide, height: iconSide)
            // 五格列心在 201.0,参照蓝块中心 201.2,选中态右移 0.2。
            .offset(x: selected ? 0.2 : 0)
        case .text:
            Text("A")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(selected ? ReaderToolbarMetrics.selectedFill : tint)
                .frame(width: iconSide, height: iconSide)
        case .brightness:
            // 选中格太阳中心填实,和参考图一致。
            Image(systemName: selected ? "sun.max.fill" : tool.icon)
                .font(.system(size: ReaderToolbarMetrics.iconGlyphSize, weight: .regular))
                .foregroundStyle(selected ? ReaderToolbarMetrics.selectedFill : tint)
                .frame(width: iconSide, height: iconSide)
        case .chapters:
            // 选中态照参照:图形整个转蓝,不铺底、不加圆。
            Image(systemName: bookmarkSymbol(for: tool))
                .font(.system(size: ReaderToolbarMetrics.iconGlyphSize, weight: .regular))
                .foregroundStyle(selected ? ReaderToolbarMetrics.selectedFill : tint)
                .frame(width: iconSide, height: iconSide)
        case .bookmarks:
            // 第二格:墨宽按参考加到 22(原来是 13.7),形状和描边不变。
            // 选中态照参照:图形整个转蓝,不铺底、不加圆。
            let markTint = selected ? ReaderToolbarMetrics.selectedFill : tint
            Group {
                if hasPageBookmark {
                    ReaderBookmarkGlyph()
                        .fill(markTint)
                        .frame(
                            width: ReaderToolbarMetrics.bookmarkGlyphWidth,
                            height: ReaderToolbarMetrics.bookmarkGlyphHeight
                        )
                } else {
                    ReaderBookmarkGlyph()
                        .stroke(
                            markTint,
                            style: StrokeStyle(
                                lineWidth: ReaderToolbarMetrics.bookmarkStrokeWidth,
                                lineJoin: .round
                            )
                        )
                        .frame(
                            width: ReaderToolbarMetrics.bookmarkGlyphWidth
                                - ReaderToolbarMetrics.bookmarkStrokeWidth,
                            height: ReaderToolbarMetrics.bookmarkGlyphHeight
                                - ReaderToolbarMetrics.bookmarkStrokeWidth
                        )
                }
            }
            .frame(width: iconSide, height: iconSide)
        }
    }

    /// 第二格是书签(有意和微信读书的「笔记」不同):有书签时用填实图形。
    private func bookmarkSymbol(for tool: ReaderTool) -> String {
        guard tool == .bookmarks, hasPageBookmark else { return tool.icon }
        return "bookmark.fill"
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
        // 滚动模式量不到真实行框时,从规格的 125.3 字顶按当前行高铺网格。
        let bodyTop = measuredBodyLineTops.first ?? ReaderBodyMetrics.firstLineInkTop
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
        let origin = measuredBodyLineTops.first ?? ReaderBodyMetrics.firstLineInkTop
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
        // 滚动模式可能量不到 bodyTopY,退回规格的 125.3 字顶,按当前行高铺网格。
        let origin = ReaderBodyMetrics.firstLineInkTop
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
                    emptyBody: "从页面顶部下拉，松手即可添加书签"
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

/// 自动翻页设置:行名「自动翻页」+ 开关,下面「间隔」三档,默认 20 秒。
/// 关着时不驱动计时器;菜单打开时 ReaderView 会暂停,菜单关掉自动接着走。
struct ReaderAutoPageSettingsSheet: View {
    let isEnabled: Bool
    let interval: Int
    let onChangeEnabled: (Bool) -> Void
    let onChangeInterval: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    private let intervals = [10, 20, 30]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("自动翻页")
                    .font(.system(size: 16))
                Spacer(minLength: 16)
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { onChangeEnabled($0) }
                ))
                .labelsHidden()
                .tint(.accentColor)
                .accessibilityLabel("自动翻页")
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("间隔")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(intervals, id: \.self) { seconds in
                        Button {
                            onChangeInterval(seconds)
                        } label: {
                            Text("\(seconds) 秒")
                                .font(.system(size: 13, weight: interval == seconds ? .semibold : .regular))
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(interval == seconds
                                              ? Color.accentColor
                                              : Color.primary.opacity(0.06))
                                )
                                .foregroundStyle(interval == seconds ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(interval == seconds ? [.isSelected] : [])
                    }
                }
            }

            Spacer(minLength: 0)

            Button("完成") { dismiss() }
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
        }
        .padding(20)
    }
}
