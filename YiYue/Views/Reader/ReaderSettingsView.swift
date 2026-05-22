import SwiftUI

struct ReaderSettingsView: View {
    @Bindable var settings: ReaderSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            fontSection
            spacingSection
            pageModeSection
        }
        .navigationTitle("字体与间距")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") { dismiss() }
            }
        }
        .onDisappear { settings.save() }
    }

    private var fontSection: some View {
        Section("字体") {
            ForEach(FontFamily.allCases, id: \.self) { font in
                Button {
                    settings.fontFamily = font
                } label: {
                    HStack {
                        Text(font.displayName)
                            .font(font.isSystem ? .system(size: 17) : .custom(font.rawValue, size: 17))
                            .foregroundStyle(.primary)
                        Spacer()
                        if settings.fontFamily == font {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
    }

    private var spacingSection: some View {
        Section("排版") {
            VStack(alignment: .leading, spacing: 8) {
                Text("行距：\(String(format: "%.1f", settings.lineSpacing))x")
                    .font(.subheadline)
                Slider(
                    value: $settings.lineSpacing,
                    in: 1.5...2.5,
                    step: 0.1
                )
                .tint(.blue)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("页边距：\(Int(settings.horizontalPadding))pt")
                    .font(.subheadline)
                Slider(
                    value: Binding(
                        get: { Double(settings.horizontalPadding) },
                        set: { settings.horizontalPadding = CGFloat($0) }
                    ),
                    in: 16...48,
                    step: 4
                )
                .tint(.blue)
            }
            .padding(.vertical, 4)
        }
    }

    private var pageModeSection: some View {
        Section("翻页模式") {
            ForEach(PageMode.allCases, id: \.self) { mode in
                Button {
                    settings.pageMode = mode
                    settings.save(markPageModeExplicit: true)
                } label: {
                    HStack {
                        Text(mode.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if settings.pageMode == mode {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
    }
}
