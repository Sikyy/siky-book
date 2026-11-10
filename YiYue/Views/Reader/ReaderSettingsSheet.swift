import SwiftUI

/// 独立设置页:字体 / 行距 / 边距 / 翻页方式 / 背景。
/// 从阅读页「更多」进入;字号本身在阅读页底部面板里,不占这一页的行。
/// 字体 / 翻页方式 / 首行缩进三行推入 `ReaderSettingsDetailView`,
/// 和字号面板底部三颗按钮共用同一套详情页。
struct ReaderSettingsSheet: View {
    let settings: ReaderSettings

    @Environment(\.dismiss) private var dismiss
    @State private var showMore = false

    private var theme: ReaderTheme { settings.theme }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    fontRow
                    rowSeparator
                    lineSpacingRow
                    rowSeparator
                    paddingRow
                    rowSeparator
                    pageModeRow
                    rowSeparator
                    backgroundRow
                    moreSettings
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollContentBackground(.hidden)
            .background(theme.menuBackground.ignoresSafeArea())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ReaderSettingsDestination.self) { destination in
                // 和字号面板底部三颗按钮同一个详情页,不另写一套。
                ReaderSettingsDetailView(destination: destination, settings: settings)
            }
            .toolbarBackground(theme.menuBackground, for: .navigationBar)
            .toolbarColorScheme(theme.isDark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(theme.accentColor)
                }
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }

    // MARK: - Rows

    private var fontRow: some View {
        settingsEntryRow(
            title: "字体",
            value: settings.fontFamily.displayName,
            destination: .fontStyle
        )
    }

    private var lineSpacingRow: some View {
        HStack(spacing: 12) {
            rowLabel("行距")
            ReaderLevelSlider(
                normalizedValue: levelBinding(
                    levels: ReaderTypography.lineSpacingLevels,
                    current: { Double(settings.lineSpacing) },
                    commit: { settings.lineSpacing = $0; settings.save() }
                ),
                tint: theme.menuSecondary,
                label: "行距",
                spokenValue: levelAccessibilityString(
                    index: settings.lineSpacingLevelIndex,
                    count: ReaderTypography.lineSpacingLevels.count
                ),
                levelCount: ReaderTypography.lineSpacingLevels.count
            )
            .frame(height: 40)
            .overlay {
                ReaderSliderTicks(
                    count: ReaderTypography.lineSpacingLevels.count,
                    selectedIndex: settings.lineSpacingLevelIndex,
                    color: theme.menuSecondary
                )
            }
            Text(String(format: "%.2f", settings.lineSpacing))
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(theme.menuSecondary)
                .frame(width: 38, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .frame(height: 64)
    }

    private var paddingRow: some View {
        HStack(spacing: 12) {
            rowLabel("边距")
            ReaderLevelSlider(
                normalizedValue: levelBinding(
                    levels: ReaderTypography.horizontalPaddingLevels,
                    current: { Double(settings.horizontalPadding) },
                    commit: { settings.horizontalPadding = $0; settings.save() }
                ),
                tint: theme.menuSecondary,
                label: "边距",
                spokenValue: levelAccessibilityString(
                    index: settings.horizontalPaddingLevelIndex,
                    count: ReaderTypography.horizontalPaddingLevels.count
                ),
                levelCount: ReaderTypography.horizontalPaddingLevels.count
            )
            .frame(height: 40)
            .overlay {
                ReaderSliderTicks(
                    count: ReaderTypography.horizontalPaddingLevels.count,
                    selectedIndex: settings.horizontalPaddingLevelIndex,
                    color: theme.menuSecondary
                )
            }
            Text("\(Int(settings.horizontalPadding))")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(theme.menuSecondary)
                .frame(width: 38, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .frame(height: 64)
    }

    private var pageModeRow: some View {
        settingsEntryRow(
            title: "翻页方式",
            value: settings.pageMode.displayName,
            destination: .pageMode
        )
    }

    private var backgroundRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            rowLabel("背景")
            HStack(spacing: 20) {
                ForEach(ReaderTheme.allCases, id: \.self) { item in
                    let selected = settings.theme == item
                    Button {
                        settings.theme = item
                        settings.save()
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(item.backgroundColor)
                                    .frame(width: 40, height: 40)
                                Circle()
                                    .strokeBorder(
                                        theme.isDark ? Color.white.opacity(0.18) : theme.menuPrimary.opacity(0.18),
                                        lineWidth: 1
                                    )
                                    .frame(width: 40, height: 40)
                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(item.isDark ? Color.white : Color(hex: "#2A2017"))
                                }
                            }
                            Text(item.displayName)
                                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? theme.menuPrimary : theme.menuSecondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .frame(width: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.displayName)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
    }

    /// 字号在阅读页底部面板里;其余原有功能行收在默认折叠的「更多设置」里,不丢。
    @ViewBuilder
    private var moreSettings: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showMore.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("更多设置")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.menuSecondary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.menuSecondary)
                        .rotationEffect(.degrees(showMore ? 180 : 0))
                }
                .frame(height: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("更多设置")
            .accessibilityValue(showMore ? "已展开" : "已收起")

            if showMore {
                settingsEntryRow(
                    title: "首行缩进",
                    value: settings.firstLineIndentEnabled ? "开" : "关",
                    destination: .firstLineIndent,
                    height: 52
                )
                toggleRow("段间距", isOn: settings.paragraphSpacingEnabled) { value in
                    settings.paragraphSpacingEnabled = value
                    settings.save()
                }
                toggleRow("保持屏幕常亮", isOn: settings.keepScreenAwake) { value in
                    settings.keepScreenAwake = value
                    settings.save()
                }
            }
        }
        .padding(.top, 8)
    }

    private func toggleRow(_ title: String, isOn: Bool, onChange: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(theme.menuPrimary)
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(get: { isOn }, set: onChange))
                .labelsHidden()
                .tint(theme.accentColor)
                .accessibilityLabel(title)
                .accessibilityValue(isOn ? "已开启" : "已关闭")
        }
        .frame(height: 52)
    }

    // MARK: - Components

    /// 设置页里通往共用详情页的一行:左标签、右当前值 + 雪佛龙。
    private func settingsEntryRow(
        title: String,
        value: String,
        destination: ReaderSettingsDestination,
        height: CGFloat = 64
    ) -> some View {
        NavigationLink(value: destination) {
            HStack(spacing: 12) {
                rowLabel(title)
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.menuSecondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.menuSecondary.opacity(0.7))
            }
            .frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，当前\(value)")
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(theme.menuPrimary)
            .frame(width: 72, alignment: .leading)
    }

    private var rowSeparator: some View {
        Rectangle()
            .fill(theme.separatorColor)
            .frame(height: 1)
    }

    private func levelBinding<T: BinaryFloatingPoint>(
        levels: [T],
        current: @escaping () -> Double,
        commit: @escaping (T) -> Void
    ) -> Binding<Double> {
        // 每次读都现场取值:设置第一次打开时可能还没加载完,
        // 早先按快照取数会让数字和滑块错开一档。
        Binding(
            get: {
                guard levels.count > 1 else { return 0 }
                let live = current()
                let index = levels.enumerated()
                    .min { abs(Double($0.element) - live) < abs(Double($1.element) - live) }?
                    .offset ?? 0
                return Double(index) / Double(levels.count - 1)
            },
            set: { value in
                guard levels.count > 1 else { return }
                let index = min(max(Int((value * Double(levels.count - 1)).rounded()), 0), levels.count - 1)
                let level = levels[index]
                guard abs(Double(level) - current()) > 0.0001 else { return }
                commit(level)
            }
        )
    }

    private func levelAccessibilityString(index: Int, count: Int) -> String {
        let total = max(count, 1)
        let clamped = min(max(index, 0), total - 1)
        let base = "第 \(clamped + 1) 档，共 \(total) 档"
        if clamped == 0 { return "\(base)，已是最小" }
        if clamped == total - 1 { return "\(base)，已是最大" }
        return base
    }
}
