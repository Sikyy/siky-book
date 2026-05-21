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
    var isCaching: Bool = false
    var cacheProgress: String? = nil

    @State private var showChapterList = false
    @State private var showSettings = false
    @State private var sliderValue: Double = 0
    @State private var bottomMode: BottomMode = .main

    enum BottomMode: Equatable {
        case main
        case fontSize
        case brightness
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
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
        .fullScreenCover(isPresented: $showSettings) {
            NavigationStack {
                ReaderSettingsView(settings: settings)
            }
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
                    HStack(spacing: 4) {
                        ProgressView()
                            .tint(.white.opacity(0.7))
                            .scaleEffect(0.7)
                        if let cacheProgress {
                            Text(cacheProgress)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.7))
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
        VStack(spacing: 0) {
            switch bottomMode {
            case .main:
                mainControls
            case .fontSize:
                fontSizeControls
            case .brightness:
                brightnessControls
            }
        }
        .padding(.top, 9)
        .padding(.bottom, 8)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial.opacity(0.98), ignoresSafeAreaEdges: .bottom)
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.15), value: bottomMode)
    }

    // MARK: - Main Controls

    private var mainControls: some View {
        VStack(spacing: 20) {
            chapterSlider
            iconRow
        }
        .padding(.bottom, -7)
    }

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

    private var iconRow: some View {
        HStack(spacing: 0) {
            toolButton(icon: "list.bullet", label: "目录") {
                showChapterList = true
            }
            toolButton(icon: "sun.max", label: "亮度") {
                bottomMode = bottomMode == .brightness ? .main : .brightness
            }
            toolButton(icon: "textformat.size", label: "字号") {
                bottomMode = bottomMode == .fontSize ? .main : .fontSize
            }
            toolButton(icon: "gearshape", label: "设置") {
                showSettings = true
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

    // MARK: - Font Size Panel

    private var fontSizeControls: some View {
        VStack(spacing: 16) {
            HStack {
                Text("字号")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("\(Int(settings.fontSize))")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
            }

            HStack(spacing: 16) {
                Button {
                    settings.fontSize = max(settings.fontSize - 1, 12)
                    settings.save()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.1), in: Circle())
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
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
            }

            backToMainButton
        }
    }

    // MARK: - Brightness Panel

    private var brightnessControls: some View {
        VStack(spacing: 16) {
            HStack {
                Text("亮度")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
            }

            HStack(spacing: 16) {
                Image(systemName: "sun.min")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))

                BrightnessSlider()

                Image(systemName: "sun.max.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.8))
            }

            backToMainButton
        }
    }

    private var backToMainButton: some View {
        Button { bottomMode = .main } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .medium))
                Text("收起")
                    .font(.system(size: 13))
            }
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
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
                    Text(progress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

private struct BrightnessSlider: View {
    @State private var brightness: Double = Double(UIScreen.main.brightness)

    var body: some View {
        Slider(value: $brightness, in: 0...1)
            .tint(.white.opacity(0.5))
            .onChange(of: brightness) { _, newValue in
                UIScreen.main.brightness = CGFloat(newValue)
            }
    }
}
