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

    @State private var activePopup: MenuPopup?
    @State private var showChapterList = false
    @State private var showSettings = false
    @State private var sliderValue: Double = 0

    enum MenuPopup {
        case fontSize
        case brightness
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    if activePopup != nil {
                        activePopup = nil
                    } else {
                        onDismiss()
                    }
                }

            VStack {
                topBar
                Spacer()
                bottomPanel
            }

            if activePopup == .fontSize {
                FontSizePopup(settings: settings)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            if activePopup == .brightness {
                BrightnessPopup()
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: activePopup)
        .onAppear { sliderValue = Double(currentChapterIndex) }
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

    private var topBar: some View {
        HStack {
            Button(action: { onBack() }) {
                Text("‹ 返回")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: "#8e8e93"))
            }
            Spacer()
            Text(chapterTitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(hex: "#e5e5e7"))
                .lineLimit(1)
            Spacer()
            Button(action: { showChapterList = true }) {
                Text("目录")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: "#8e8e93"))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
    }

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            chapterSlider
                .padding(.bottom, 24)
            iconRow
        }
        .padding(20)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
    }

    private var chapterSlider: some View {
        HStack(spacing: 12) {
            Text("\(max(currentChapterIndex, 1))")
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: "#636366"))
                .frame(width: 30, alignment: .trailing)

            Slider(
                value: $sliderValue,
                in: 0...max(Double(totalChapters - 1), 1),
                step: 1
            ) { editing in
                if !editing {
                    currentChapterIndex = Int(sliderValue)
                }
            }
            .tint(Color(hex: "#636366"))

            Text("\(min(currentChapterIndex + 2, totalChapters))")
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: "#636366"))
                .frame(width: 30, alignment: .leading)
        }
    }

    private var iconRow: some View {
        HStack {
            Spacer()
            menuButton(icon: "☰", label: "目录", isActive: false) {
                showChapterList = true
            }
            Spacer()
            menuButton(icon: "☀", label: "亮度", isActive: activePopup == .brightness) {
                activePopup = activePopup == .brightness ? nil : .brightness
            }
            Spacer()
            menuButton(iconView: AnyView(
                Text("Aa")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(activePopup == .fontSize ? Color(hex: "#3b82f6") : Color(hex: "#e5e5e7"))
            ), label: "字号", isActive: activePopup == .fontSize) {
                activePopup = activePopup == .fontSize ? nil : .fontSize
            }
            Spacer()
            menuButton(icon: "⚙", label: "设置", isActive: false) {
                showSettings = true
            }
            Spacer()
        }
    }

    private func menuButton(icon: String? = nil, iconView: AnyView? = nil, label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isActive ? Color(hex: "#3b82f6").opacity(0.3) : Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isActive ? Color(hex: "#3b82f6") : Color.clear, lineWidth: 1.5)
                        )
                        .frame(width: 36, height: 36)

                    if let iconView = iconView {
                        iconView
                    } else if let icon = icon {
                        Text(icon)
                            .font(.system(size: 16))
                    }
                }
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(isActive ? Color(hex: "#3b82f6") : Color(hex: "#8e8e93"))
            }
        }
        .buttonStyle(.plain)
    }

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
                    }
                }
            }
        }
        .navigationTitle("目录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("关闭") { showChapterList = false }
            }
        }
    }
}
