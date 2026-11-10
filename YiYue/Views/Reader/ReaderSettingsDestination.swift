import SwiftUI

/// 设置页和字号面板共用的三个入口。
///
/// 字号面板底部三颗按钮「字体样式 / 首行缩进 / 翻页方式」不各写一套逻辑:
/// 它们和设置页对应的三行都指向这里,由同一个 `ReaderSettingsDetailView` 承载。
enum ReaderSettingsDestination: String, CaseIterable, Identifiable {
    case fontStyle
    case firstLineIndent
    case pageMode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fontStyle: return "字体样式"
        case .firstLineIndent: return "首行缩进"
        case .pageMode: return "翻页方式"
        }
    }

    /// 从字号面板弹 sheet 时用:内容不多,给一档够用的高度。
    var sheetHeight: CGFloat {
        switch self {
        case .fontStyle: return 330
        case .firstLineIndent: return 260
        case .pageMode: return 350
        }
    }
}

/// 三个入口共用的详情页。设置页用导航推入,字号面板用 sheet 包一层
/// `ReaderSettingsDetailSheet`;里面的控件只有这一份。
struct ReaderSettingsDetailView: View {
    let destination: ReaderSettingsDestination
    let settings: ReaderSettings

    private var theme: ReaderTheme { settings.theme }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch destination {
                case .fontStyle:
                    fontStyleContent
                case .firstLineIndent:
                    firstLineIndentContent
                case .pageMode:
                    pageModeContent
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .scrollContentBackground(.hidden)
        .background(theme.menuBackground.ignoresSafeArea())
        .navigationTitle(destination.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.menuBackground, for: .navigationBar)
        .toolbarColorScheme(theme.isDark ? .dark : .light, for: .navigationBar)
    }

    // MARK: - 字体样式

    private var fontStyleContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择正文字体")
                .font(.system(size: 13))
                .foregroundStyle(theme.menuSecondary)

            ForEach(FontFamily.allCases, id: \.self) { font in
                let selected = settings.fontFamily == font
                Button {
                    settings.fontFamily = font
                    settings.save()
                } label: {
                    HStack(spacing: 12) {
                        Text(font.displayName)
                            .font(.system(size: 16, weight: selected ? .semibold : .regular))
                            .foregroundStyle(theme.menuPrimary)
                        Spacer(minLength: 0)
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.accentColor)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selected
                                ? theme.accentColor.opacity(0.12)
                                : theme.menuPrimary.opacity(0.05))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(font.displayName)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }

    // MARK: - 首行缩进

    private var firstLineIndentContent: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("首行缩进")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.menuPrimary)
                Text("每段开头空两个字")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.menuSecondary)
            }
            Spacer(minLength: 0)
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
        .frame(height: 64)
    }

    // MARK: - 翻页方式

    private var pageModeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择翻页方式")
                .font(.system(size: 13))
                .foregroundStyle(theme.menuSecondary)

            ForEach(PageMode.allCases, id: \.self) { mode in
                let selected = settings.pageMode == mode
                Button {
                    settings.pageMode = mode
                    settings.save(markPageModeExplicit: true)
                } label: {
                    HStack(spacing: 12) {
                        Text(mode.displayName)
                            .font(.system(size: 16, weight: selected ? .semibold : .regular))
                            .foregroundStyle(theme.menuPrimary)
                        Spacer(minLength: 0)
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.accentColor)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selected
                                ? theme.accentColor.opacity(0.12)
                                : theme.menuPrimary.opacity(0.05))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.displayName)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }
}

/// 字号面板三颗按钮弹出来的同一张详情页。设置页走导航推入,不套这一层。
struct ReaderSettingsDetailSheet: View {
    let destination: ReaderSettingsDestination
    let settings: ReaderSettings

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ReaderSettingsDetailView(destination: destination, settings: settings)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                            .foregroundStyle(settings.theme.accentColor)
                    }
                }
        }
        .preferredColorScheme(settings.theme.isDark ? .dark : .light)
        .presentationDetents([.height(destination.sheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(settings.theme.menuBackground)
    }
}
