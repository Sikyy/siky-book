# Phase 2: Reader UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the immersive reading experience — a WeChat Reading-inspired reader with single-layer menu, floating popups, and customizable settings.

**Architecture:** ReaderSettings holds all reader preferences via @AppStorage (UserDefaults-backed, no SwiftData needed). ReaderView is the main content view using ScrollView with position tracking. ReaderMenuOverlay provides the single-layer menu with floating popups. Navigation flows: bookshelf → reader (directly) or bookshelf → chapter list → reader.

**Tech Stack:** SwiftUI, SwiftData (existing models), @AppStorage, UIScreen brightness API

---

## File Structure

| File | Responsibility |
|------|---------------|
| `NovelReader/Models/ReaderSettings.swift` | Observable settings class backed by @AppStorage |
| `NovelReader/Models/ReaderTheme.swift` | Theme enum with color definitions |
| `NovelReader/Views/Reader/ReaderView.swift` | Immersive reading view with chapter text display |
| `NovelReader/Views/Reader/ReaderMenuOverlay.swift` | Top bar + bottom bar + popup management |
| `NovelReader/Views/Reader/FontSizePopup.swift` | Font size floating panel |
| `NovelReader/Views/Reader/BrightnessPopup.swift` | Brightness floating panel |
| `NovelReader/Views/Reader/ReaderSettingsView.swift` | Full settings page (font, spacing, margins, mode, theme) |
| `NovelReaderTests/ReaderSettingsTests.swift` | Settings defaults and logic tests |

---

## Task 1: ReaderSettings + ReaderTheme

**Files:**
- Create: `NovelReader/Models/ReaderTheme.swift`
- Create: `NovelReader/Models/ReaderSettings.swift`
- Create: `NovelReaderTests/ReaderSettingsTests.swift`

- [ ] **Step 1: Write failing tests**

`NovelReaderTests/ReaderSettingsTests.swift`:
```swift
import XCTest
@testable import NovelReader

final class ReaderSettingsTests: XCTestCase {
    var settings: ReaderSettings!

    override func setUp() {
        super.setUp()
        settings = ReaderSettings()
    }

    func testDefaultValues() {
        XCTAssertEqual(settings.fontSize, 17)
        XCTAssertEqual(settings.lineSpacing, 2.0, accuracy: 0.01)
        XCTAssertEqual(settings.fontFamily, .pingfang)
        XCTAssertEqual(settings.theme, .pureBlack)
        XCTAssertEqual(settings.horizontalPadding, 28)
        XCTAssertEqual(settings.pageMode, .scroll)
    }

    func testThemeColors() {
        let pureBlack = ReaderTheme.pureBlack
        XCTAssertEqual(pureBlack.backgroundHex, "#121212")
        XCTAssertEqual(pureBlack.textHex, "#d4d4d4")

        let warmBlack = ReaderTheme.warmBlack
        XCTAssertEqual(warmBlack.backgroundHex, "#1a1814")
    }

    func testFontSizeClamping() {
        settings.fontSize = 10
        XCTAssertEqual(settings.fontSize, 12)

        settings.fontSize = 50
        XCTAssertEqual(settings.fontSize, 32)
    }

    func testLineSpacingClamping() {
        settings.lineSpacing = 1.0
        XCTAssertEqual(settings.lineSpacing, 1.5, accuracy: 0.01)

        settings.lineSpacing = 3.0
        XCTAssertEqual(settings.lineSpacing, 2.5, accuracy: 0.01)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 17' -quiet 2>&1 | grep -E '(error:|FAIL)' | head -10
```

Expected: `ReaderSettings` and `ReaderTheme` not defined.

- [ ] **Step 3: Implement ReaderTheme**

`NovelReader/Models/ReaderTheme.swift`:
```swift
import SwiftUI

enum ReaderTheme: String, CaseIterable, Codable {
    case pureBlack
    case warmBlack
    case lightWhite
    case eyeCareGreen
    case system

    var backgroundHex: String {
        switch self {
        case .pureBlack: return "#121212"
        case .warmBlack: return "#1a1814"
        case .lightWhite: return "#f5f5f0"
        case .eyeCareGreen: return "#c7edcc"
        case .system: return "#121212"
        }
    }

    var textHex: String {
        switch self {
        case .pureBlack: return "#d4d4d4"
        case .warmBlack: return "#c8b89a"
        case .lightWhite: return "#2c2c2c"
        case .eyeCareGreen: return "#2c3e2c"
        case .system: return "#d4d4d4"
        }
    }

    var backgroundColor: Color {
        Color(hex: backgroundHex)
    }

    var textColor: Color {
        Color(hex: textHex)
    }

    var chapterTitleColor: Color {
        switch self {
        case .lightWhite, .eyeCareGreen: return Color(hex: "#999999")
        default: return Color(hex: "#555555")
        }
    }

    var statusBarColor: Color {
        switch self {
        case .lightWhite, .eyeCareGreen: return Color(hex: "#aaaaaa")
        default: return Color(hex: "#3a3a3a")
        }
    }

    var displayName: String {
        switch self {
        case .pureBlack: return "纯黑"
        case .warmBlack: return "暖黑"
        case .lightWhite: return "浅白"
        case .eyeCareGreen: return "护眼绿"
        case .system: return "跟随系统"
        }
    }

    var isDark: Bool {
        switch self {
        case .pureBlack, .warmBlack: return true
        case .lightWhite, .eyeCareGreen: return false
        case .system: return true
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        self.init(
            red: Double((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: Double((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgbValue & 0x0000FF) / 255.0
        )
    }
}
```

- [ ] **Step 4: Implement ReaderSettings**

`NovelReader/Models/ReaderSettings.swift`:
```swift
import SwiftUI

enum FontFamily: String, CaseIterable, Codable {
    case pingfang = "PingFang SC"
    case songti = "Songti SC"
    case kaiti = "Kaiti SC"

    var displayName: String {
        switch self {
        case .pingfang: return "苹方"
        case .songti: return "宋体"
        case .kaiti: return "楷体"
        }
    }
}

enum PageMode: String, CaseIterable, Codable {
    case scroll
    case horizontal
    case tap

    var displayName: String {
        switch self {
        case .scroll: return "上下滑动"
        case .horizontal: return "左右翻页"
        case .tap: return "点击翻页"
        }
    }
}

@Observable
class ReaderSettings {
    private static let fontSizeRange: ClosedRange<CGFloat> = 12...32
    private static let lineSpacingRange: ClosedRange<Double> = 1.5...2.5
    private static let paddingRange: ClosedRange<CGFloat> = 16...48

    var fontSize: CGFloat {
        didSet { fontSize = fontSize.clamped(to: Self.fontSizeRange) }
    }

    var lineSpacing: Double {
        didSet { lineSpacing = lineSpacing.clamped(to: Self.lineSpacingRange) }
    }

    var horizontalPadding: CGFloat {
        didSet { horizontalPadding = horizontalPadding.clamped(to: Self.paddingRange) }
    }

    var fontFamily: FontFamily
    var theme: ReaderTheme
    var pageMode: PageMode

    init() {
        let defaults = UserDefaults.standard
        self.fontSize = CGFloat(defaults.double(forKey: "reader.fontSize")).nonZeroOr(17)
        self.lineSpacing = defaults.double(forKey: "reader.lineSpacing").nonZeroOr(2.0)
        self.horizontalPadding = CGFloat(defaults.double(forKey: "reader.horizontalPadding")).nonZeroOr(28)
        self.fontFamily = FontFamily(rawValue: defaults.string(forKey: "reader.fontFamily") ?? "") ?? .pingfang
        self.theme = ReaderTheme(rawValue: defaults.string(forKey: "reader.theme") ?? "") ?? .pureBlack
        self.pageMode = PageMode(rawValue: defaults.string(forKey: "reader.pageMode") ?? "") ?? .scroll
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(Double(fontSize), forKey: "reader.fontSize")
        defaults.set(lineSpacing, forKey: "reader.lineSpacing")
        defaults.set(Double(horizontalPadding), forKey: "reader.horizontalPadding")
        defaults.set(fontFamily.rawValue, forKey: "reader.fontFamily")
        defaults.set(theme.rawValue, forKey: "reader.theme")
        defaults.set(pageMode.rawValue, forKey: "reader.pageMode")
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension Double {
    func nonZeroOr(_ fallback: Double) -> Double {
        self == 0 ? fallback : self
    }
}

private extension CGFloat {
    func nonZeroOr(_ fallback: CGFloat) -> CGFloat {
        self == 0 ? fallback : self
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild test -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:NovelReaderTests/ReaderSettingsTests -quiet 2>&1 | grep -E '(Test Case|passed|failed)'
```

Expected: all 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add NovelReader/Models/ReaderTheme.swift NovelReader/Models/ReaderSettings.swift NovelReaderTests/ReaderSettingsTests.swift
git commit -m "feat: add ReaderSettings and ReaderTheme models"
```

---

## Task 2: ReaderView — Immersive Reading

**Files:**
- Create: `NovelReader/Views/Reader/ReaderView.swift`

- [ ] **Step 1: Create ReaderView**

`NovelReader/Views/Reader/ReaderView.swift`:
```swift
import SwiftUI
import SwiftData

struct ReaderView: View {
    let book: Book
    @Query private var chapters: [Chapter]
    @State private var currentChapterIndex: Int
    @State private var showMenu = false
    @State private var scrollPosition: String?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var settings = ReaderSettings()

    init(book: Book, startChapterIndex: Int = 0) {
        self.book = book
        self._currentChapterIndex = State(initialValue: startChapterIndex)
        let bookId = book.id
        _chapters = Query(
            filter: #Predicate<Chapter> { $0.book?.id == bookId },
            sort: [SortDescriptor(\Chapter.index)]
        )
    }

    private var currentChapter: Chapter? {
        chapters.first { $0.index == currentChapterIndex }
    }

    private var chapterText: String {
        currentChapter?.content ?? ""
    }

    private var characterCount: Int {
        chapterText.count
    }

    var body: some View {
        ZStack {
            settings.theme.backgroundColor
                .ignoresSafeArea()

            readingContent

            if showMenu {
                ReaderMenuOverlay(
                    book: book,
                    currentChapterIndex: $currentChapterIndex,
                    totalChapters: book.totalChapters,
                    chapterTitle: currentChapter?.title ?? "",
                    settings: settings,
                    onDismiss: { showMenu = false },
                    onBack: { dismiss() },
                    chapters: chapters
                )
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(!showMenu)
        .onChange(of: currentChapterIndex) { _, newValue in
            let manager = BookManager(modelContext: modelContext)
            manager.updateProgress(book: book, chapterIndex: newValue, position: 0)
            settings.save()
        }
        .onDisappear {
            let manager = BookManager(modelContext: modelContext)
            manager.updateProgress(book: book, chapterIndex: currentChapterIndex, position: 0)
        }
        .preferredColorScheme(settings.theme.isDark ? .dark : .light)
    }

    private var paragraphs: [String] {
        chapterText
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var readingContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: settings.fontSize * (settings.lineSpacing - 1)) {
                Text(currentChapter?.title ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(settings.theme.chapterTitleColor)
                    .padding(.bottom, 8)

                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, para in
                    Text("\u{3000}\u{3000}" + para)
                        .font(.custom(settings.fontFamily.rawValue, size: settings.fontSize))
                        .foregroundStyle(settings.theme.textColor)
                        .lineSpacing(settings.fontSize * (settings.lineSpacing - 1))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, settings.horizontalPadding)
            .padding(.top, 20)
            .padding(.bottom, 60)
        }
        .onTapGesture { location in
            let screenWidth = UIScreen.main.bounds.width
            let screenHeight = UIScreen.main.bounds.height
            let centerXRange = (screenWidth / 3)...(screenWidth * 2 / 3)
            let centerYRange = (screenHeight / 3)...(screenHeight * 2 / 3)

            if centerXRange.contains(location.x) && centerYRange.contains(location.y) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showMenu.toggle()
                }
            }
        }
        .overlay(alignment: .bottom) {
            if !showMenu {
                statusBar
            }
        }
    }

    private var statusBar: some View {
        HStack {
            Text(book.title)
                .font(.system(size: 11))
                .foregroundStyle(settings.theme.statusBarColor)
            Spacer()
            Text("\(currentChapterIndex + 1) / \(book.totalChapters)")
                .font(.system(size: 11))
                .foregroundStyle(settings.theme.statusBarColor)
        }
        .padding(.horizontal, settings.horizontalPadding)
        .padding(.bottom, 8)
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
xcodebuild build -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 17' -quiet
```

Note: This will fail because `ReaderMenuOverlay` doesn't exist yet. That's expected — we create a stub to allow building.

- [ ] **Step 3: Create ReaderMenuOverlay stub**

Create a minimal stub so ReaderView compiles. The real implementation comes in Task 3.

`NovelReader/Views/Reader/ReaderMenuOverlay.swift`:
```swift
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

    var body: some View {
        Color.black.opacity(0.01)
            .ignoresSafeArea()
            .onTapGesture { onDismiss() }
    }
}
```

- [ ] **Step 4: Build and verify**

```bash
xcodebuild build -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 17' -quiet
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add NovelReader/Views/Reader/ReaderView.swift NovelReader/Views/Reader/ReaderMenuOverlay.swift
git commit -m "feat: add immersive ReaderView with chapter display and tap-to-menu"
```

---

## Task 3: ReaderMenuOverlay — Full Implementation

**Files:**
- Modify: `NovelReader/Views/Reader/ReaderMenuOverlay.swift`

- [ ] **Step 1: Implement full ReaderMenuOverlay**

Replace the entire content of `NovelReader/Views/Reader/ReaderMenuOverlay.swift`:

```swift
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
```

- [ ] **Step 2: Build and verify**

Note: This will fail because `FontSizePopup`, `BrightnessPopup`, and `ReaderSettingsView` don't exist yet. Create stubs.

- [ ] **Step 3: Create FontSizePopup stub**

`NovelReader/Views/Reader/FontSizePopup.swift`:
```swift
import SwiftUI

struct FontSizePopup: View {
    let settings: ReaderSettings

    var body: some View {
        Text("Font Size")
    }
}
```

- [ ] **Step 4: Create BrightnessPopup stub**

`NovelReader/Views/Reader/BrightnessPopup.swift`:
```swift
import SwiftUI

struct BrightnessPopup: View {
    var body: some View {
        Text("Brightness")
    }
}
```

- [ ] **Step 5: Create ReaderSettingsView stub**

`NovelReader/Views/Reader/ReaderSettingsView.swift`:
```swift
import SwiftUI

struct ReaderSettingsView: View {
    let settings: ReaderSettings

    var body: some View {
        Text("Settings")
    }
}
```

- [ ] **Step 6: Build and verify**

```bash
xcodebuild build -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 17' -quiet
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add NovelReader/Views/Reader/
git commit -m "feat: add reader menu overlay with chapter slider and icon buttons"
```

---

## Task 4: FontSizePopup + BrightnessPopup

**Files:**
- Modify: `NovelReader/Views/Reader/FontSizePopup.swift`
- Modify: `NovelReader/Views/Reader/BrightnessPopup.swift`

- [ ] **Step 1: Implement FontSizePopup**

Replace the entire content of `NovelReader/Views/Reader/FontSizePopup.swift`:

```swift
import SwiftUI

struct FontSizePopup: View {
    @Bindable var settings: ReaderSettings

    var body: some View {
        VStack(spacing: 16) {
            Text("字号")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "#e5e5e7"))

            HStack(spacing: 12) {
                Button {
                    settings.fontSize = max(settings.fontSize - 1, 12)
                    settings.save()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 32, height: 32)
                        Text("A")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "#e5e5e7"))
                    }
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
                .tint(Color(hex: "#636366"))

                Button {
                    settings.fontSize = min(settings.fontSize + 1, 32)
                    settings.save()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 32, height: 32)
                        Text("A")
                            .font(.system(size: 18))
                            .foregroundStyle(Color(hex: "#e5e5e7"))
                    }
                }
                .buttonStyle(.plain)
            }

            Text("\(Int(settings.fontSize))")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Color(hex: "#8e8e93"))
        }
        .padding(24)
        .frame(width: 240)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "#2c2c2e").opacity(0.98))
                .shadow(color: .black.opacity(0.4), radius: 16)
        )
        .offset(y: -40)
    }
}
```

- [ ] **Step 2: Implement BrightnessPopup**

Replace the entire content of `NovelReader/Views/Reader/BrightnessPopup.swift`:

```swift
import SwiftUI

struct BrightnessPopup: View {
    @State private var brightness: Double = Double(UIScreen.main.brightness)

    var body: some View {
        VStack(spacing: 16) {
            Text("亮度")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "#e5e5e7"))

            HStack(spacing: 12) {
                Image(systemName: "sun.min")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#e5e5e7"))

                Slider(value: $brightness, in: 0...1) { editing in
                    if !editing {
                        UIScreen.main.brightness = CGFloat(brightness)
                    }
                }
                .tint(Color(hex: "#636366"))
                .onChange(of: brightness) { _, newValue in
                    UIScreen.main.brightness = CGFloat(newValue)
                }

                Image(systemName: "sun.max")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "#e5e5e7"))
            }
        }
        .padding(24)
        .frame(width: 240)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "#2c2c2e").opacity(0.98))
                .shadow(color: .black.opacity(0.4), radius: 16)
        )
        .offset(y: -40)
    }
}
```

- [ ] **Step 3: Build and verify**

```bash
xcodebuild build -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 17' -quiet
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add NovelReader/Views/Reader/FontSizePopup.swift NovelReader/Views/Reader/BrightnessPopup.swift
git commit -m "feat: add font size and brightness floating popups"
```

---

## Task 5: ReaderSettingsView

**Files:**
- Modify: `NovelReader/Views/Reader/ReaderSettingsView.swift`

- [ ] **Step 1: Implement full ReaderSettingsView**

Replace the entire content of `NovelReader/Views/Reader/ReaderSettingsView.swift`:

```swift
import SwiftUI

struct ReaderSettingsView: View {
    @Bindable var settings: ReaderSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            fontSection
            spacingSection
            pageModeSection
            themeSection
        }
        .navigationTitle("阅读设置")
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
                            .font(.custom(font.rawValue, size: 17))
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

    private var themeSection: some View {
        Section("主题") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                ForEach(ReaderTheme.allCases, id: \.self) { theme in
                    Button {
                        settings.theme = theme
                    } label: {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(theme.backgroundColor)
                                .frame(height: 44)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(settings.theme == theme ? Color.blue : Color.gray.opacity(0.3), lineWidth: settings.theme == theme ? 2 : 1)
                                )
                                .overlay(
                                    Text("文")
                                        .font(.system(size: 14))
                                        .foregroundStyle(theme.textColor)
                                )
                            Text(theme.displayName)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
        }
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
xcodebuild build -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 17' -quiet
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add NovelReader/Views/Reader/ReaderSettingsView.swift
git commit -m "feat: add reader settings page (font, spacing, margins, theme)"
```

---

## Task 6: Navigation Wiring — Bookshelf → Reader

**Files:**
- Modify: `NovelReader/Views/Bookshelf/BookshelfView.swift`
- Modify: `NovelReader/Views/Reader/ChapterListView.swift`

- [ ] **Step 1: Update BookshelfView navigation destination**

In `NovelReader/Views/Bookshelf/BookshelfView.swift`, change the `.navigationDestination` to open `ReaderView` instead of `ChapterListView`:

Find:
```swift
            .navigationDestination(for: Book.self) { book in
                ChapterListView(book: book)
            }
```

Replace with:
```swift
            .navigationDestination(for: Book.self) { book in
                ReaderView(book: book, startChapterIndex: book.lastReadChapterIndex)
            }
```

- [ ] **Step 2: Update ChapterListView to navigate to reader**

Replace the entire content of `NovelReader/Views/Reader/ChapterListView.swift`:

```swift
import SwiftUI
import SwiftData

struct ChapterListView: View {
    let book: Book
    let onSelectChapter: (Int) -> Void

    @Query private var chapters: [Chapter]

    init(book: Book, onSelectChapter: @escaping (Int) -> Void) {
        self.book = book
        self.onSelectChapter = onSelectChapter
        let bookId = book.id
        _chapters = Query(
            filter: #Predicate<Chapter> { $0.book?.id == bookId },
            sort: [SortDescriptor(\Chapter.index)]
        )
    }

    var body: some View {
        List(chapters) { chapter in
            Button {
                onSelectChapter(chapter.index)
            } label: {
                HStack {
                    Text(chapter.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer()
                    if chapter.isCached {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

- [ ] **Step 3: Update ReaderMenuOverlay chapter list**

In `NovelReader/Views/Reader/ReaderMenuOverlay.swift`, the `chapterListContent` property already handles chapter selection inline with a sheet. No further changes needed — the inline chapter list in the overlay is separate from the standalone `ChapterListView`.

- [ ] **Step 4: Run all tests**

```bash
xcodebuild test -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 17' -quiet 2>&1 | grep -E '(Executed|passed|failed)'
```

Expected: all existing tests pass (~24 from Phase 1 + 4 from Task 1 = ~28 tests).

- [ ] **Step 5: Build and verify**

```bash
xcodebuild build -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 17' -quiet
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add NovelReader/Views/Bookshelf/BookshelfView.swift NovelReader/Views/Reader/ChapterListView.swift
git commit -m "feat: wire bookshelf → reader navigation with reading progress resume"
```

---

## Summary

After completing all 6 tasks, the app adds:

- **Immersive reader**: Dark background, PingFang font, configurable font size/line spacing/margins
- **Single-layer menu**: Top bar (back/title/TOC) + bottom bar (chapter slider + 4 icons), tap center to toggle
- **Floating popups**: Font size (A—slider—A with number), brightness (sun—slider—sun)
- **Reader settings page**: Font family (苹方/宋体/楷体), line spacing, margins, page mode, theme (5 choices)
- **5 themes**: Pure black, warm black, light white, eye-care green, system
- **Navigation**: Bookshelf → reader (resumes last position), chapter list accessible from menu
- **Progress tracking**: Auto-saves reading position on chapter change and reader exit

**Next plans:**
- Plan 3: Book Source Engine (Legado-compatible JSCore engine, search flow, source management, quality detection)
