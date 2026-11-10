import SwiftUI
import UIKit
import SwiftData

// MARK: - 两页共用配色

/// 目录页(`05-目录.png`)和书签页(`06-笔记.png`)共用的配色与尺寸。
/// 数值来自 `.airbuild/weread-ref-2/` 的两张 402×874 截图实测,
/// 规格见 `.airbuild/spec/spec-目录与笔记.md`,文案见 Camo 的 `bookmark-page-copy.md`。
struct ReaderPageStyle {
    let theme: ReaderTheme

    var panel: Color { theme.menuBackground }
    var primary: Color { theme.menuPrimary }
    var secondary: Color { theme.menuSecondary }
    /// 搜索占位字:夜间单独提到 #969698(150,150,152),不跟次要色那一档。
    var searchPlaceholder: Color { theme.isDark ? Color(hex: "#969698") : theme.secondaryColor }
    /// 参照图里的蓝:和底栏选中格同一个值 #2493EE,不用主题的砖红强调色。
    var blue: Color { ReaderToolbarMetrics.selectedFill }
    /// 卡片底:比面板深一档(浅色)/亮一档(夜间),一条公式两边都对。
    var card: Color { theme.menuPrimary.opacity(0.06) }
    var divider: Color { theme.menuPrimary.opacity(0.12) }
    var faint: Color { theme.menuPrimary.opacity(0.07) }
    var fieldFill: Color { theme.menuPrimary.opacity(0.07) }
    var disabled: Color { theme.menuPrimary.opacity(0.3) }
    /// 「全部删除」:只换颜色,不用实心红块。
    var destructive: Color { theme.isDark ? Color(hex: "#D98276") : Color(hex: "#B4483B") }
    /// 目录顶部胶囊里选中的那半截:比容器亮一档。
    var segmentFill: Color { theme.isDark ? Color.white.opacity(0.14) : Color.white.opacity(0.9) }
    /// 「最后一章」浮钮:实心深底亮字,和页面至少差 40 级,底下的章名不许透上来。
    var pillFill: Color { theme.isDark ? Color(hex: "#4A4238") : Color(hex: "#3A322A") }
    var pillForeground: Color { Color(hex: "#F7F0DE") }
}

// MARK: - 目录页

/// 目录页的一行。用值类型而不是 Chapter 模型:动画期间不碰 SwiftData。
struct ReaderTocEntry: Identifiable, Equatable, Sendable {
    let index: Int
    let title: String
    /// 这一章在全书的位置百分比,和进度面板同一个算法(章序号 / 总章数)。
    let percent: Int
    /// 这一章起点之前的累计字数。目录右侧显示的是这个(万字以上写成「12.3万」),
    /// 百分比在长书里会连着好几章一模一样,没有信息量。远端书没字数表时是 0。
    var words: Int = 0

    var id: Int { index }
}

private struct TocLastRowBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

struct ReaderTocPage: View {
    let style: ReaderPageStyle
    let entries: [ReaderTocEntry]
    let currentIndex: Int
    /// 当前读到的位置,和进度面板同一个数。
    let currentPercentText: String
    let hasPageBookmark: Bool
    let onSelect: (Int) -> Void
    let onAddBookmark: () -> Void
    /// 有书源的书才出现的「缓存 / 更新目录」那一行。
    var headerAccessory: AnyView? = nil
    /// 搜索态时告诉外面一声:底栏那五格被键盘盖住,不该再进读屏。
    var onSearchingChanged: ((Bool) -> Void)? = nil

    @State private var searchText = ""
    @State private var isSearching = false
    /// 最后一行的底边在屏幕上的位置(全局坐标);量不到时是极大值,
    /// 表示还没建出来或已经滚出列表,也就是不在视野里。
    @State private var lastRowBottom: CGFloat = .greatestFiniteMagnitude
    /// 点「最后一章」时递增,由 ScrollViewReader 接住去滚。
    @State private var jumpToLastTick = 0
    @FocusState private var searchFocused: Bool

    private var filteredEntries: [ReaderTocEntry] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return entries }
        return entries.filter { $0.title.localizedCaseInsensitiveContains(keyword) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchCapsule
                .padding(.horizontal, 16)
                .padding(.top, 95)

            if let headerAccessory {
                headerAccessory
            }

            list
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) {
            if showLastChapterPill {
                lastChapterPill { jumpToLastTick += 1 }
                    .padding(.bottom, 101.3)
            }
        }
    }

    /// 最后一章不在视野里(或者列表还没建到最后一行)时才浮出来;章数不足一屏不浮。
    private var showLastChapterPill: Bool {
        guard !filteredEntries.isEmpty, filteredEntries.count > 6 else { return false }
        return lastRowBottom > 800
    }

    // MARK: 顶部胶囊

    private var searchCapsule: some View {
        HStack(spacing: 0) {
            if isSearching {
                HStack(spacing: 13.4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(style.secondary)
                    TextField(
                        "",
                        text: $searchText,
                        prompt: Text("搜索章节").foregroundStyle(style.searchPlaceholder)
                    )
                        .font(.system(size: 15))
                        .foregroundStyle(style.primary)
                        .tint(style.blue)
                        .focused($searchFocused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(style.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清空搜索")
                    }
                }
                .padding(.horizontal, 12.7)
                .frame(width: 185, height: 27)
                .contentShape(Rectangle())
                .onTapGesture { searchFocused = true }
            } else {
                Button {
                    beginSearch()
                } label: {
                    HStack(spacing: 13.4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15))
                        Text("搜索章节")
                            .font(.system(size: 15))
                            .foregroundStyle(style.searchPlaceholder)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(style.secondary)
                    .padding(.leading, 12.7)
                    .frame(width: 185, height: 27)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("搜索章节")
                .accessibilityAddTraits(.isSearchField)
            }

            Spacer(minLength: 0)

            // 不用 .disabled:禁用会把标签整体压暗,「目录」就比下面的章名还浅。
            // 它和左边的搜索框是一枚开关的两半:目录态是选中的那一半(读屏念已选中),
            // 搜索态是「取消」,点了回到目录列表。
            Button {
                if isSearching { endSearch() }
            } label: {
                Text(isSearching ? "取消" : "目录")
                    .font(.system(size: 15, weight: .medium))
                    // 搜索态的「取消」是要按的按钮:夜间走占位字那档 (150,150,152),
                    // 原来那次要色只有 4.26:1,不够。
                    .foregroundStyle(isSearching ? style.searchPlaceholder : style.primary)
                    .frame(width: 181.7, height: 27)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isSearching ? Color.clear : style.segmentFill)
                    )
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSearching ? "取消搜索" : "目录")
            // 目录态它是这枚开关选中的那一半:读屏念「已选中」,
            // 不是念成一个按得动、按了不响应的按钮;搜索态才是「取消」。
            .accessibilityAddTraits(isSearching ? [] : [.isSelected])
            .padding(.trailing, 3.3)
        }
        .frame(height: 27)
        .background(Capsule(style: .continuous).fill(style.faint))
    }

    private func beginSearch() {
        isSearching = true
        searchFocused = true
        onSearchingChanged?(true)
    }

    private func endSearch() {
        searchText = ""
        isSearching = false
        searchFocused = false
        onSearchingChanged?(false)
    }

    // MARK: 列表

    /// 临时 A/B 开关:启动参数 `-UseLegacyTocList YES` 时走旧实现(List 一次建全行),
    /// 用来量「框一弹把一百多章全建出来」这一条的改前/改后。量完删掉。
    private var usesLegacyList: Bool {
        UserDefaults.standard.bool(forKey: "UseLegacyTocList")
    }

    @ViewBuilder
    private var list: some View {
        if usesLegacyList {
            List(filteredEntries) { entry in
                row(entry)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        } else {
            modernList
        }
    }

    private var modernList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredEntries) { entry in
                        VStack(spacing: 0) {
                            row(entry)
                            if entry.index == currentIndex {
                                currentBlock
                            }
                        }
                        .id(entry.index)
                        .background {
                            if entry.index == entries.last?.index {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: TocLastRowBottomKey.self,
                                        value: proxy.frame(in: .global).maxY
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.top, 13)
                .padding(.bottom, 120)
                .overlay {
                    if filteredEntries.isEmpty, isSearching {
                        Text("没有找到章节")
                            .font(.system(size: 13))
                            .foregroundStyle(style.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .padding(.top, 60)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onAppear {
                guard !isSearching else { return }
                proxy.scrollTo(currentIndex, anchor: .center)
            }
            .onPreferenceChange(TocLastRowBottomKey.self) { value in
                lastRowBottom = value
            }
            .onChange(of: jumpToLastTick) { _, _ in
                guard let last = entries.last else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(last.index, anchor: .bottom)
                }
            }
        }
    }

    /// 目录右侧:这一章起点在全书的位置。万字以上写成「12.3万」,读着比裸数字快。
    static func positionText(_ words: Int) -> String {
        words >= 10000
            ? String(format: "%.1f万", Double(words) / 10000)
            : "\(words)"
    }

    private func row(_ entry: ReaderTocEntry) -> some View {
        let isCurrent = entry.index == currentIndex
        return Button {
            onSelect(entry.index)
        } label: {
            HStack(spacing: 0) {
                Text(entry.title)
                    .font(.system(size: 16.5, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(style.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(entry.words > 0 ? Self.positionText(entry.words) : "\(entry.percent)%")
                    .font(.system(size: 10))
                    .foregroundStyle(style.secondary)
                    .monospacedDigit()
            }
            .padding(.leading, 59.7)
            .padding(.trailing, 27.3)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(style.divider)
                .frame(height: 1)
                .padding(.horizontal, 26)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(isCurrent ? "当前章，" : "")\(entry.title)，全书 \(entry.percent)%"
        )
        .accessibilityAddTraits(.isButton)
    }

    /// 当前章下面那一块:书签图标 + 「当前读到」+ 「添加书签」,占 70.3。
    /// 命中区只给「图标 + 两行字」这半边(约 x 73–140、高 44 起),
    /// 右侧百分比那段不接点击——那行看起来是位置指示,点哪儿都删书签会误删。
    private var currentBlock: some View {
        HStack(alignment: .top, spacing: 0) {
            Button {
                onAddBookmark()
            } label: {
                HStack(alignment: .top, spacing: 9.7) {
                    Image(systemName: hasPageBookmark ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(style.blue)
                        .frame(width: 14.7, height: 16)
                        .padding(.top, 17.5)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("当前读到")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(style.blue)
                        Text(hasPageBookmark ? "删除书签" : "添加书签")
                            .font(.system(size: 12))
                            .foregroundStyle(style.secondary)
                    }
                    .padding(.top, 15.5)
                }
                .frame(minHeight: 44, alignment: .top)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // padding 加在 Button 外面:左内缩不算命中区,点左侧空白不会删书签。
            .padding(.leading, 73.3)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(hasPageBookmark ? "删除书签" : "添加书签")，第 \(currentIndex + 1) 章，全书 \(currentPercentText)"
            )
            .accessibilityAddTraits(.isButton)

            Spacer(minLength: 8)

            Text(currentPercentText)
                .font(.system(size: 10))
                .foregroundStyle(style.secondary)
                .monospacedDigit()
                .padding(.trailing, 27.3)
                .padding(.top, 17.5)
        }
        .frame(height: 70.3, alignment: .top)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(style.divider)
                .frame(height: 1)
                .padding(.horizontal, 26)
        }
    }

    private func lastChapterPill(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 12, weight: .medium))
                Text("最后一章")
                    .font(.system(size: 12))
            }
            .foregroundStyle(style.pillForeground)
            .frame(width: 126.3, height: 33.7)
            .background(
                Capsule(style: .continuous)
                    .fill(style.pillFill)
                    .shadow(color: .black.opacity(0.16), radius: 2, x: 0, y: 1)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("跳到最后一章")
    }
}

// MARK: - 书签页

struct ReaderBookmarkEntry: Identifiable, Equatable {
    let id: UUID
    let chapterIndex: Int
    let chapterTitle: String
    let paragraphIndex: Int
    let excerpt: String
    let createdAt: Date
}

struct ReaderBookmarkPage: View {
    let style: ReaderPageStyle
    let bookTitle: String
    let coverURL: String?
    let readingSeconds: TimeInterval
    let entries: [ReaderBookmarkEntry]
    let onOpenReadingDetails: () -> Void
    let onJump: (UUID) -> Void
    let onDeleteAll: () -> Void
    var onDeleteOne: ((UUID) -> Void)? = nil

    @State private var searchText = ""
    @State private var isSearching = false
    @State private var grouped = false
    @State private var showDeleteConfirm = false
    @State private var shareFile: ExportFile?
    @FocusState private var searchFocused: Bool

    private struct ExportFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    private var filteredEntries: [ReaderBookmarkEntry] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return entries }
        return entries.filter {
            $0.excerpt.localizedCaseInsensitiveContains(keyword)
                || $0.chapterTitle.localizedCaseInsensitiveContains(keyword)
                || bookTitle.localizedCaseInsensitiveContains(keyword)
        }
    }

    private struct ChapterGroup: Identifiable {
        let id: Int
        let title: String
        let entries: [ReaderBookmarkEntry]
    }

    private var chapterGroups: [ChapterGroup] {
        var order: [Int] = []
        var titles: [Int: String] = [:]
        var grouped: [Int: [ReaderBookmarkEntry]] = [:]
        for entry in filteredEntries {
            if titles[entry.chapterIndex] == nil {
                order.append(entry.chapterIndex)
                titles[entry.chapterIndex] = entry.chapterTitle
            }
            grouped[entry.chapterIndex, default: []].append(entry)
        }
        return order.map { index in
            ChapterGroup(
                id: index,
                title: titles[index] ?? "",
                entries: grouped[index] ?? []
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                bookCard

                if isSearching {
                    searchField
                }

                if !isSearching && entries.isEmpty {
                    emptyCard
                } else if filteredEntries.isEmpty {
                    Text("没有找到书签")
                        .font(.system(size: 13))
                        .foregroundStyle(style.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else {
                    markList
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 99)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .alert("删除全部书签？", isPresented: $showDeleteConfirm) {
            Button("删除全部", role: .destructive) { onDeleteAll() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这本书里的 \(entries.count) 条书签会一起删掉，不能撤销。")
        }
        .sheet(item: $shareFile) { file in
            BookmarkShareSheet(url: file.url)
        }
    }

    // MARK: 本书卡片

    private var bookCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 11) {
                    Text(bookTitle)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(style.primary)
                        .lineLimit(1)
                    readingTimeRow
                }
                .padding(.top, 36)

                Spacer(minLength: 0)

                cover
                    .padding(.top, 16)
            }
            .frame(height: 100.7, alignment: .top)

            Spacer(minLength: 0)

            // 空态不画那排按钮:四个按不动的东西摆在那儿,人第一眼就是「坏了」。
            if !entries.isEmpty {
                actionRow
                    .padding(.bottom, 17)
            }
        }
        .padding(.horizontal, 16)
        // 空态那排按钮撤了,卡也要跟着收到 98.7,否则下面空出一大片像没加载出来。
        .frame(width: 366, height: entries.isEmpty ? 98.7 : 188)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(style.card))
    }

    @ViewBuilder
    private var readingTimeRow: some View {
        HStack(spacing: 3) {
            if readingSeconds >= 60 {
                Text("阅读时长 \(ReadingTimeFormat.spoken(readingSeconds))")
                    .foregroundStyle(style.secondary)
                Text("·")
                    .foregroundStyle(style.secondary)
            }
            Button {
                onOpenReadingDetails()
            } label: {
                Text("阅读明细")
                    .foregroundStyle(style.blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("阅读明细")
        }
        .font(.system(size: 13))
    }

    private var cover: some View {
        CachedCoverImage(
            urlString: coverURL,
            targetSize: CGSize(width: 59.7, height: 84.7)
        ) {
            coverPlaceholder
        }
        .frame(width: 59.7, height: 84.7)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .accessibilityHidden(true)
    }

    /// 没有封面图时的兜底:纸色底 + 书名首字 + 右下一条书脊。不留空框、不挂外图。
    private var coverPlaceholder: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(style.theme.menuPrimary.opacity(0.10))
            Text(String(bookTitle.prefix(1)))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(style.secondary)
                .padding(.leading, 6)
                .padding(.top, 5)
            VStack {
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(style.secondary.opacity(0.45))
                        .frame(width: 2, height: 22)
                }
            }
            .padding(.trailing, 7)
            .padding(.bottom, 7)
        }
    }

    private var actionRow: some View {
        let enabled = !entries.isEmpty
        return HStack(spacing: 0) {
            actionButton(
                icon: "magnifyingglass",
                title: "搜索",
                isLabel: "搜索书签",
                tint: style.primary,
                enabled: enabled
            ) {
                isSearching = true
                searchFocused = true
            }
            actionButton(
                icon: "square.and.arrow.up",
                title: "导出",
                isLabel: "导出书签",
                tint: style.primary,
                enabled: enabled
            ) {
                export()
            }
            actionButton(
                icon: "list.bullet.rectangle",
                title: "按章节",
                tint: style.primary,
                enabled: enabled
            ) {
                grouped.toggle()
            }
            .accessibilityValue(grouped ? "已开启" : "")
            actionButton(
                icon: "trash",
                title: "全部删除",
                tint: style.destructive,
                enabled: enabled
            ) {
                showDeleteConfirm = true
            }
            .accessibilityLabel("全部删除，删除这本书的全部书签")
        }
        .frame(maxWidth: .infinity)
    }

    /// 屏幕上是短名(搜索/导出/按章节/全部删除),读屏念全名。
    private func actionButton(
        icon: String,
        title: String,
        isLabel: String? = nil,
        tint: Color,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 18, height: 18)
                Text(title)
                    .font(.system(size: 11))
            }
            .foregroundStyle(enabled ? tint : style.disabled)
            .frame(width: 83.7, height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(isLabel ?? title)
    }

    // MARK: 搜索

    private var searchField: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(style.secondary)
                TextField("搜索书签", text: $searchText)
                    .font(.system(size: 14))
                    .foregroundStyle(style.primary)
                    .tint(style.blue)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(style.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空搜索")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(style.fieldFill)
            )

            Button {
                searchText = ""
                isSearching = false
                searchFocused = false
            } label: {
                Text("取消")
                    .font(.system(size: 14))
                    .foregroundStyle(style.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消搜索")
        }
    }

    // MARK: 列表与空态

    private var emptyCard: some View {
        VStack(spacing: 5) {
            Text("还没有书签")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(style.primary)
            Text("翻到想留住的地方，从页面顶部往下拉，松手就加上了。")
                .font(.system(size: 13))
                .foregroundStyle(style.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 366, height: 158)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(style.card))
    }

    @ViewBuilder
    private var markList: some View {
        if grouped {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(chapterGroups) { group in
                    VStack(alignment: .leading, spacing: 16) {
                        Text(group.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(style.primary)
                            .lineLimit(1)
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(group.entries) { entry in
                                markRow(entry)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(style.card))
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(filteredEntries) { entry in
                    markRow(entry)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(style.card))
        }
    }

    private func markRow(_ entry: ReaderBookmarkEntry) -> some View {
        Button {
            onJump(entry.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.excerpt)
                    .font(.system(size: 13))
                    .foregroundStyle(style.primary)
                    .lineSpacing(5)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("\(entry.chapterTitle) · 第 \(entry.paragraphIndex + 1) 段")
                    .font(.system(size: 12))
                    .foregroundStyle(style.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                onDeleteOne?(entry.id)
            } label: {
                Text("删除书签")
            }
        }
    }

    // MARK: 导出

    private func export() {
        let name = "《\(bookTitle)》书签.txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try Self.exportText(bookTitle: bookTitle, entries: entries)
                .write(to: url, atomically: true, encoding: .utf8)
            shareFile = ExportFile(url: url)
        } catch {
            shareFile = nil
        }
    }

    /// 每条一段,段与段之间空一行:书名 / 章名 · 第几段 / 时间 / 摘句。
    static func exportText(bookTitle: String, entries: [ReaderBookmarkEntry]) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月 d 日 HH:mm"
        return entries
            .map { entry in
                """
                《\(bookTitle)》
                \(entry.chapterTitle) · 第 \(entry.paragraphIndex + 1) 段
                \(formatter.string(from: entry.createdAt))
                「\(entry.excerpt)」
                """
            }
            .joined(separator: "\n\n")
    }
}

/// 系统分享面板。导出的是真文件(.txt),不是一段文字。
struct BookmarkShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - 全书百分比表

/// 全书位置只跟每章字数有关:第 N 章起点 = 第 N 章之前的累计字数 ÷ 全书字数。
/// 它是固定值,和读到哪无关,所以一本书只算一次、存成表;
/// 目录页、进度面板、滑轨都读同一张表 —— 大目录下不能每次开面板都把整本算一遍,
/// 也不能让目录行和进度数字各算一套。
@MainActor
final class TocPercentTable {
    static let shared = TocPercentTable()

    private struct Cached {
        /// 章数 + 首尾章名 + 正文版本:目录或任何一章正文变了就重算,没变就直接用。
        let signature: String
        /// 按章序排好的章号。
        let indices: [Int]
        /// 每章字数;整本都有正文才有,远端书没下载完是 nil,退回按章序号算。
        let lengths: [Int]?
        /// 各章起点之前的累计字数,只算一次。
        let cumulative: [Int]
        let totalWords: Int
        let entries: [ReaderTocEntry]
    }

    private var cache: [UUID: Cached] = [:]
    /// 正在后台算的小时。同一本不重复起。
    private var building: Set<UUID> = []
    /// 这个章数以内主线程直接算(两百章三毫秒);再大就挪后台,开书不等它。
    private let inlineChapterLimit = 500

    private func signature(of chapters: [Chapter]) -> String {
        // 章节数、首尾章名判不出「中间换了一章」或者「正文从 SwiftData 搬到磁盘」,
        // 再把书的正文版本带上:这几种改动都会把它加一。
        let revision = chapters.first?.book?.contentRevision ?? 0
        return Self.signature(
            count: chapters.count,
            revision: revision,
            firstTitle: chapters.first?.title ?? "",
            lastTitle: chapters.last?.title ?? ""
        )
    }

    nonisolated static func signature(count: Int, revision: Int, firstTitle: String, lastTitle: String) -> String {
        "\(count)|\(revision)|\(firstTitle)|\(lastTitle)"
    }

    /// 书打开、目录刷新之后调一次。小书当场算好;
    /// 大书先不算,后台算完落盘,下次开这本书直接从盘上读。
    func refresh(bookID: UUID, chapters: [Chapter], container: ModelContainer?) {
        _ = table(bookID: bookID, chapters: chapters)
        guard cache[bookID]?.lengths == nil, let container else { return }
        scheduleBackgroundBuild(
            bookID: bookID,
            container: container,
            signature: signature(of: chapters)
        )
    }

    /// 目录行:章名 + 这一章起点在全书的位置。
    func entries(bookID: UUID, chapters: [Chapter]) -> [ReaderTocEntry] {
        table(bookID: bookID, chapters: chapters).entries
    }

    /// 大书的目录:章表在后台已经算好,这里只把轻表套进去。
    /// 盘上有字数表就按字数,没有就按章序,和原来的两条路一致。
    func entries(bookID: UUID, infos: [ReaderChapterInfo], revision: Int) -> [ReaderTocEntry] {
        guard !infos.isEmpty else { return [] }
        let signature = Self.signature(
            count: infos.count,
            revision: revision,
            firstTitle: infos.first?.title ?? "",
            lastTitle: infos.last?.title ?? ""
        )
        if let cached = cache[bookID], cached.signature == signature {
            return cached.entries
        }
        let indices = infos.map(\.index)
        let lengths = TocLengthStore.load(bookID: bookID, signature: signature, indices: indices)
            ?? cache[bookID].flatMap { $0.indices.count == indices.count ? $0.lengths : nil }
        let totalWords = lengths?.reduce(0, +) ?? 0
        var cumulative: [Int] = []
        cumulative.reserveCapacity(indices.count)
        var walked = 0
        for offset in indices.indices {
            cumulative.append(walked)
            if let lengths, totalWords > 0 { walked += lengths[offset] }
        }
        let entries: [ReaderTocEntry]
        if let lengths, totalWords > 0 {
            entries = infos.enumerated().map { offset, info in
                ReaderTocEntry(
                    index: info.index,
                    title: info.title,
                    percent: Int((Double(cumulative[offset]) / Double(totalWords) * 100).rounded()),
                    words: cumulative[offset]
                )
            }
        } else {
            let total = max(infos.count, 1)
            entries = infos.enumerated().map { offset, info in
                ReaderTocEntry(
                    index: info.index,
                    title: info.title,
                    percent: Int((Double(offset) / Double(total) * 100).rounded())
                )
            }
        }
        cache[bookID] = Cached(
            signature: signature,
            indices: indices,
            lengths: (lengths != nil && totalWords > 0) ? lengths : nil,
            cumulative: cumulative,
            totalWords: totalWords,
            entries: entries
        )
        return entries
    }

    /// 后台章表扫完之后直接装表,主线程不再建 5000 条目录。
    func install(
        bookID: UUID,
        signature: String,
        indices: [Int],
        lengths: [Int],
        entries: [ReaderTocEntry]
    ) {
        var cumulative: [Int] = []
        cumulative.reserveCapacity(indices.count)
        var walked = 0
        for offset in indices.indices {
            cumulative.append(walked)
            if lengths.count == indices.count { walked += lengths[offset] }
        }
        let totalWords = (lengths.count == indices.count) ? lengths.reduce(0, +) : 0
        cache[bookID] = Cached(
            signature: signature,
            indices: indices,
            lengths: totalWords > 0 ? lengths : nil,
            cumulative: cumulative,
            totalWords: totalWords,
            entries: entries
        )
    }

    /// 读到某一章某一页时的全书位置(0…1):这一章起点 + 章内进度 × 本章占比。
    func fraction(bookID: UUID, chapters: [Chapter], chapterIndex: Int, pageFraction: Double) -> Double {
        let table = table(bookID: bookID, chapters: chapters)
        return fraction(
            table: table,
            chapterIndex: chapterIndex,
            pageFraction: pageFraction
        )
    }

    /// 大书用章数直接查已经装好的表;表还没到时按章序退,不阻塞开书。
    func fraction(bookID: UUID, chapterCount: Int, chapterIndex: Int, pageFraction: Double) -> Double {
        guard chapterCount > 0 else { return 0 }
        if let table = cache[bookID], table.indices.count == chapterCount {
            return fraction(table: table, chapterIndex: chapterIndex, pageFraction: pageFraction)
        }
        let inChapter = min(max(pageFraction, 0), 1)
        let position = min(max(chapterIndex, 0), chapterCount - 1)
        return (Double(position) + inChapter) / Double(chapterCount)
    }

    private func fraction(table: Cached, chapterIndex: Int, pageFraction: Double) -> Double {
        guard !table.indices.isEmpty else { return 0 }
        let position = table.indices.firstIndex(of: chapterIndex)
            ?? min(max(chapterIndex, 0), table.indices.count - 1)
        let inChapter = min(max(pageFraction, 0), 1)
        if let lengths = table.lengths,
           table.totalWords > 0,
           lengths.indices.contains(position) {
            let walked = Double(table.cumulative[position]) + inChapter * Double(lengths[position])
            return walked / Double(table.totalWords)
        }
        return (Double(position) + inChapter) / Double(table.indices.count)
    }

    /// 反推:全书位置 0…1 落在哪一章(滑轨松手时用,和上面的算法是同一张表)。
    func chapterIndex(bookID: UUID, chapters: [Chapter], forFraction fraction: Double) -> Int {
        chapterIndex(table: table(bookID: bookID, chapters: chapters), forFraction: fraction)
    }

    func chapterIndex(bookID: UUID, chapterCount: Int, forFraction fraction: Double) -> Int {
        guard chapterCount > 0 else { return 0 }
        if let table = cache[bookID], table.indices.count == chapterCount {
            return chapterIndex(table: table, forFraction: fraction)
        }
        let clamped = min(max(fraction, 0), 1)
        return min(max(Int(floor(clamped * Double(chapterCount))), 0), chapterCount - 1)
    }

    private func chapterIndex(table: Cached, forFraction fraction: Double) -> Int {
        guard !table.indices.isEmpty else { return 0 }
        let clamped = min(max(fraction, 0), 1)
        guard let lengths = table.lengths, table.totalWords > 0 else {
            let position = Int(floor(clamped * Double(table.indices.count)))
            return table.indices[min(max(position, 0), table.indices.count - 1)]
        }
        let target = Int((clamped * Double(table.totalWords)).rounded())
        // cumulative 是升序的,二分找最后一个起点不超过目标的章。
        var low = 0
        var high = table.cumulative.count - 1
        var found = 0
        while low <= high {
            let mid = (low + high) / 2
            if table.cumulative[mid] <= target {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        _ = lengths
        return table.indices[found]
    }

    private func table(bookID: UUID, chapters: [Chapter]) -> Cached {
        let signature = signature(of: chapters)
        if let cached = cache[bookID], cached.signature == signature {
            return cached
        }
        let sorted = chapters.sorted { $0.index < $1.index }
        let indices = sorted.map(\.index)

        // 1. 盘上有这张表,直接读 —— 不碰任何一章正文。
        if let disk = TocLengthStore.load(bookID: bookID, signature: signature, indices: indices) {
            let built = build(sorted: sorted, signature: signature, lengths: disk)
            cache[bookID] = built
            return built
        }

        // 2. 小书当场算;大书先用章序号,后台算完落盘。
        let lengths = sorted.count <= inlineChapterLimit ? inlineLengths(sorted) : nil
        let built = build(sorted: sorted, signature: signature, lengths: lengths)
        cache[bookID] = built
        return built
    }

    /// 每章字数:缺一章就整本退回按章序号算。
    private func inlineLengths(_ sorted: [Chapter]) -> [Int]? {
        var lengths: [Int] = []
        lengths.reserveCapacity(sorted.count)
        for chapter in sorted {
            guard let content = chapter.content, !content.isEmpty else { return nil }
            lengths.append(content.count)
        }
        return lengths
    }

    private func build(sorted: [Chapter], signature: String, lengths source: [Int]?) -> Cached {
        let indices = sorted.map(\.index)
        let lengths = (source?.count == indices.count) ? source : nil
        let totalWords = lengths?.reduce(0, +) ?? 0
        var cumulative: [Int] = []
        cumulative.reserveCapacity(indices.count)
        var walked = 0
        for offset in indices.indices {
            cumulative.append(walked)
            if let lengths, totalWords > 0 { walked += lengths[offset] }
        }

        let entries: [ReaderTocEntry]
        if let lengths, totalWords > 0 {
            entries = sorted.enumerated().map { offset, chapter in
                ReaderTocEntry(
                    index: chapter.index,
                    title: chapter.title,
                    percent: Int((Double(cumulative[offset]) / Double(totalWords) * 100).rounded()),
                    words: cumulative[offset]
                )
            }
        } else {
            let total = max(sorted.count, 1)
            entries = sorted.enumerated().map { offset, chapter in
                ReaderTocEntry(
                    index: chapter.index,
                    title: chapter.title,
                    percent: Int((Double(offset) / Double(total) * 100).rounded())
                )
            }
        }

        return Cached(
            signature: signature,
            indices: indices,
            lengths: (lengths != nil && totalWords > 0) ? lengths : nil,
            cumulative: cumulative,
            totalWords: totalWords,
            entries: entries
        )
    }

    private func scheduleBackgroundBuild(bookID: UUID, container: ModelContainer, signature: String) {
        guard !building.contains(bookID) else { return }
        building.insert(bookID)
        Task.detached(priority: .utility) { [weak self] in
            let lengths = Self.computeLengths(bookID: bookID, container: container)
            await MainActor.run {
                guard let self else { return }
                self.building.remove(bookID)
                guard let lengths else { return }
                TocLengthStore.save(
                    bookID: bookID,
                    signature: signature,
                    indices: Array(0..<lengths.count),
                    lengths: lengths
                )
                // 这一本当前记着的表作废:下次查表从盘上读新的。
                if self.cache[bookID]?.signature == signature, self.cache[bookID]?.lengths == nil {
                    self.cache.removeValue(forKey: bookID)
                }
            }
        }
    }

    /// 后台读整本每章字数。自己开一个 ModelContext,不碰主线程那个。
    nonisolated private static func computeLengths(bookID: UUID, container: ModelContainer) -> [Int]? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate<Chapter> { $0.book?.id == bookID },
            sortBy: [SortDescriptor(\.index)]
        )
        guard let chapters = try? context.fetch(descriptor), !chapters.isEmpty else { return nil }
        var lengths: [Int] = []
        lengths.reserveCapacity(chapters.count)
        for chapter in chapters {
            guard let content = chapter.content, !content.isEmpty else { return nil }
            lengths.append(content.count)
        }
        return lengths
    }
}

// MARK: - 每章字数的落盘

/// 表按「书号 + 正文版本」存:版本一变旧表就不再命中,不会拿旧百分比糊弄人。
enum TocLengthStore {
    private struct Payload: Codable {
        let signature: String
        let indices: [Int]
        let lengths: [Int]
    }

    private static var directory: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let dir = base.appendingPathComponent("TocLengths", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func url(bookID: UUID) -> URL? {
        directory?.appendingPathComponent("\(bookID.uuidString).json")
    }

    static func load(bookID: UUID, signature: String, indices: [Int]) -> [Int]? {
        guard let url = url(bookID: bookID),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.signature == signature,
              payload.indices == indices,
              payload.lengths.count == indices.count else { return nil }
        return payload.lengths
    }

    static func save(bookID: UUID, signature: String, indices: [Int], lengths: [Int]) {
        guard let url = url(bookID: bookID) else { return }
        let payload = Payload(signature: signature, indices: indices, lengths: lengths)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
