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
    var isCaching: Bool = false
    var cacheProgress: String? = nil

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
            if let onCache {
                if isCaching {
                    Button {
                        onCancelCache?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.7))
                            if let cacheProgress {
                                Text(cacheProgress)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                    .frame(width: 44)
                } else {
                    Menu {
                        Button("缓存后100章") { onCache(100) }
                        Button("缓存全部") { onCache(nil) }
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .frame(width: 44)
                }
            } else {
                Color.clear.frame(width: 44, height: 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial.opacity(0.98), ignoresSafeAreaEdges: .top)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Bottom Panel

    private var bottomPanel: some View {
        VStack(spacing: 16) {
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
                    } else if chapter.isCached || chapter.content != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green.opacity(0.6))
                            .font(.caption2)
                    }
                }
            }
        }
        .navigationTitle("目录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if isCaching, let progress = cacheProgress {
                    Button {
                        onCancelCache?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 10))
                            Text(progress)
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                } else if onCache != nil {
                    Button("缓存全部") { onCache?(nil) }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("关闭") { showChapterList = false }
            }
        }
    }
}
