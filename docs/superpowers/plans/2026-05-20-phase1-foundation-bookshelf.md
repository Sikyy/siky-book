# NovelReader Phase 1: Foundation + Bookshelf + TXT Import

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a functional iOS app with a 4-column bookshelf grid, reading status indicators, series grouping, and TXT file import with auto encoding detection and chapter splitting.

**Architecture:** SwiftUI + SwiftData in four layers (UI → Services → Helpers → Data). XcodeGen for project management. All books stored as Book → Chapter relationships in SwiftData.

**Tech Stack:** Swift 5.9, SwiftUI, SwiftData, XcodeGen, XCTest, iOS 17+

**Scope:** This is Plan 1 of 3. The deliverable is: import a .txt file → see it on the bookshelf with cover, status, and progress → tap to see chapter list. Plans 2 (Reader) and 3 (Book Source Engine) follow.

---

## File Structure

```
ios-book/
├── .gitignore
├── project.yml                              # XcodeGen config
├── NovelReader/
│   ├── App/
│   │   └── NovelReaderApp.swift             # Entry point + ModelContainer
│   ├── Models/
│   │   ├── Enums.swift                      # ReadingStatus, SourceType
│   │   ├── Book.swift                       # Book SwiftData model
│   │   ├── Chapter.swift                    # Chapter SwiftData model
│   │   └── BookSource.swift                 # BookSource SwiftData model
│   ├── Views/
│   │   ├── ContentView.swift                # Root tab view
│   │   ├── Bookshelf/
│   │   │   ├── BookshelfView.swift          # Main grid + import button
│   │   │   ├── BookCoverView.swift          # Single book cell
│   │   │   ├── SeriesBookView.swift         # Stacked series cell
│   │   │   └── BookshelfItem.swift          # Enum for grid items
│   │   └── Reader/
│   │       └── ChapterListView.swift        # Placeholder reader (chapter list)
│   ├── Services/
│   │   ├── BookManager.swift                # Book CRUD
│   │   └── ImportService.swift              # TXT file import
│   ├── Helpers/
│   │   ├── EncodingDetector.swift           # UTF-8/GBK/GB2312 detection
│   │   ├── ChapterSplitter.swift            # Split TXT by chapter markers
│   │   └── DocumentPicker.swift             # UIDocumentPicker wrapper
│   └── Assets.xcassets/
│       └── Contents.json
├── NovelReaderTests/
│   ├── ModelTests.swift
│   ├── BookManagerTests.swift
│   ├── EncodingDetectorTests.swift
│   ├── ChapterSplitterTests.swift
│   └── ImportServiceTests.swift
└── docs/
```

---

## Task 1: Project Scaffolding

**Files:**
- Create: `.gitignore`
- Create: `project.yml`
- Create: `NovelReader/App/NovelReaderApp.swift`
- Create: `NovelReader/Views/ContentView.swift`
- Create: `NovelReader/Assets.xcassets/Contents.json`
- Create: `NovelReaderTests/PlaceholderTest.swift`

- [ ] **Step 1: Create directory structure and .gitignore**

```bash
mkdir -p NovelReader/{App,Models,Views/{Bookshelf,Reader},Services,Helpers}
mkdir -p NovelReader/Assets.xcassets
mkdir -p NovelReaderTests
```

`.gitignore`:
```gitignore
# Xcode
*.xcodeproj/project.xcworkspace/xcuserdata/
*.xcodeproj/xcuserdata/
xcuserdata/
DerivedData/
*.xccheckout
*.moved-aside
*.hmap
*.ipa
*.dSYM.zip
*.dSYM

# Swift Package Manager
.build/
Packages/
Package.resolved

# Misc
.DS_Store
*.swp

# Superpowers brainstorm files
.superpowers/
```

- [ ] **Step 2: Create project.yml**

```yaml
name: NovelReader
options:
  bundleIdPrefix: com.novelreader
  deploymentTarget:
    iOS: "17.0"
  groupSortPosition: top
targets:
  NovelReader:
    type: application
    platform: iOS
    sources:
      - path: NovelReader
    info:
      properties:
        UILaunchScreen: {}
        CFBundleDocumentTypes:
          - CFBundleTypeName: Text File
            CFBundleTypeRole: Viewer
            LSItemContentTypes:
              - public.plain-text
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.novelreader.app
        MARKETING_VERSION: "1.0.0"
        CURRENT_PROJECT_VERSION: "1"
        SWIFT_VERSION: "5.9"
  NovelReaderTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: NovelReaderTests
    dependencies:
      - target: NovelReader
```

- [ ] **Step 3: Create app entry point and placeholder views**

`NovelReader/App/NovelReaderApp.swift`:
```swift
import SwiftUI
import SwiftData

@main
struct NovelReaderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Book.self, Chapter.self, BookSource.self])
    }
}
```

`NovelReader/Views/ContentView.swift`:
```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("NovelReader")
            .font(.largeTitle)
    }
}
```

`NovelReader/Assets.xcassets/Contents.json`:
```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

`NovelReaderTests/PlaceholderTest.swift`:
```swift
import XCTest

final class PlaceholderTest: XCTestCase {
    func testAppLaunches() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 4: Install xcodegen and generate project**

```bash
which xcodegen || brew install xcodegen
xcodegen generate
```

Expected: `⚙ Generating plists...` → `📝 Writing project...` → `Created project at NovelReader.xcodeproj`

- [ ] **Step 5: Build to verify**

```bash
xcodebuild build -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add .gitignore project.yml NovelReader/ NovelReaderTests/
git commit -m "feat: scaffold NovelReader Xcode project"
```

---

## Task 2: SwiftData Models

**Files:**
- Create: `NovelReader/Models/Enums.swift`
- Create: `NovelReader/Models/Book.swift`
- Create: `NovelReader/Models/Chapter.swift`
- Create: `NovelReader/Models/BookSource.swift`
- Create: `NovelReaderTests/ModelTests.swift`

- [ ] **Step 1: Write failing tests for models**

`NovelReaderTests/ModelTests.swift`:
```swift
import XCTest
import SwiftData
@testable import NovelReader

final class ModelTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(
            for: Book.self, Chapter.self, BookSource.self,
            configurations: config
        )
        context = ModelContext(container)
    }

    func testBookCreation() {
        let book = Book(title: "斗破苍穹", author: "天蚕土豆", sourceType: .localFile, totalChapters: 1647)
        context.insert(book)

        XCTAssertEqual(book.title, "斗破苍穹")
        XCTAssertEqual(book.author, "天蚕土豆")
        XCTAssertEqual(book.readingStatus, .unread)
        XCTAssertEqual(book.lastReadChapterIndex, 0)
        XCTAssertEqual(book.totalChapters, 1647)
    }

    func testProgressComputation() {
        let book = Book(title: "Test", author: "A", sourceType: .localFile, totalChapters: 100)
        book.lastReadChapterIndex = 45
        XCTAssertEqual(book.progress, 0.45, accuracy: 0.001)
    }

    func testProgressZeroDivision() {
        let book = Book(title: "Test", author: "A", sourceType: .localFile, totalChapters: 0)
        XCTAssertEqual(book.progress, 0)
    }

    func testChapterRelationship() {
        let book = Book(title: "Test", author: "A", sourceType: .localFile, totalChapters: 2)
        context.insert(book)

        let ch1 = Chapter(index: 0, title: "第一章", content: "内容一")
        let ch2 = Chapter(index: 1, title: "第二章", content: "内容二")
        ch1.book = book
        ch2.book = book
        context.insert(ch1)
        context.insert(ch2)

        XCTAssertEqual(book.chapters.count, 2)
        XCTAssertTrue(ch1.isCached)
    }

    func testChapterWithoutContentIsNotCached() {
        let ch = Chapter(index: 0, title: "Ch1", content: nil)
        XCTAssertFalse(ch.isCached)
    }

    func testBookSourceCreation() {
        let source = BookSource(name: "笔趣阁", sourceURL: "https://example.com", ruleJSON: "{}")
        context.insert(source)

        XCTAssertEqual(source.name, "笔趣阁")
        XCTAssertTrue(source.enabled)
        XCTAssertFalse(source.isQualityVerified)
        XCTAssertNil(source.qualityScore)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | grep -E '(Test Case|FAIL|error:)' | head -20
```

Expected: compilation errors — `Book`, `Chapter`, `BookSource` not defined.

- [ ] **Step 3: Implement enums and models**

`NovelReader/Models/Enums.swift`:
```swift
import Foundation

enum ReadingStatus: String, Codable {
    case unread
    case reading
    case finished
}

enum SourceType: String, Codable {
    case bookSource
    case localFile
}
```

`NovelReader/Models/Book.swift`:
```swift
import Foundation
import SwiftData

@Model
final class Book {
    var id: UUID
    var title: String
    var author: String
    var coverURL: String?
    var sourceType: SourceType
    var sourceId: UUID?
    var sourceBookURL: String?
    var readingStatus: ReadingStatus
    var lastReadChapterIndex: Int
    var lastReadPosition: Double
    var totalChapters: Int
    var addedDate: Date
    var lastReadDate: Date?
    var seriesName: String?
    var seriesIndex: Int?

    @Relationship(deleteRule: .cascade, inverse: \Chapter.book)
    var chapters: [Chapter] = []

    var progress: Double {
        guard totalChapters > 0 else { return 0 }
        return Double(lastReadChapterIndex) / Double(totalChapters)
    }

    init(
        title: String,
        author: String,
        sourceType: SourceType,
        totalChapters: Int = 0
    ) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.sourceType = sourceType
        self.readingStatus = .unread
        self.lastReadChapterIndex = 0
        self.lastReadPosition = 0
        self.totalChapters = totalChapters
        self.addedDate = Date()
    }
}
```

`NovelReader/Models/Chapter.swift`:
```swift
import Foundation
import SwiftData

@Model
final class Chapter {
    var id: UUID
    var book: Book?
    var index: Int
    var title: String
    var content: String?
    var isCached: Bool
    var sourceURL: String?

    init(index: Int, title: String, content: String? = nil) {
        self.id = UUID()
        self.index = index
        self.title = title
        self.content = content
        self.isCached = content != nil
    }
}
```

`NovelReader/Models/BookSource.swift`:
```swift
import Foundation
import SwiftData

@Model
final class BookSource {
    var id: UUID
    var name: String
    var sourceURL: String
    var sourceGroup: String?
    var enabled: Bool
    var ruleJSON: String
    var lastUpdateDate: Date
    var qualityScore: Double?
    var lastTestDate: Date?
    var avgResponseTime: Double?
    var contentValidRate: Double?
    var encodingScore: Double?
    var catalogSize: Int?
    var isQualityVerified: Bool

    init(name: String, sourceURL: String, ruleJSON: String) {
        self.id = UUID()
        self.name = name
        self.sourceURL = sourceURL
        self.ruleJSON = ruleJSON
        self.enabled = true
        self.lastUpdateDate = Date()
        self.isQualityVerified = false
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | grep -E '(Test Case|passed|failed)'
```

Expected: all 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add NovelReader/Models/ NovelReaderTests/ModelTests.swift
git commit -m "feat: add SwiftData models (Book, Chapter, BookSource)"
```

---

## Task 3: BookManager Service

**Files:**
- Create: `NovelReader/Services/BookManager.swift`
- Create: `NovelReaderTests/BookManagerTests.swift`

- [ ] **Step 1: Write failing tests**

`NovelReaderTests/BookManagerTests.swift`:
```swift
import XCTest
import SwiftData
@testable import NovelReader

final class BookManagerTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var manager: BookManager!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(
            for: Book.self, Chapter.self, BookSource.self,
            configurations: config
        )
        context = ModelContext(container)
        manager = BookManager(modelContext: context)
    }

    func testAddBook() throws {
        let book = manager.addBook(title: "三体", author: "刘慈欣", sourceType: .localFile)
        try context.save()

        let descriptor = FetchDescriptor<Book>()
        let books = try context.fetch(descriptor)
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books.first?.title, "三体")
    }

    func testDeleteBook() throws {
        let book = manager.addBook(title: "三体", author: "刘慈欣", sourceType: .localFile)
        try context.save()

        manager.deleteBook(book)
        try context.save()

        let descriptor = FetchDescriptor<Book>()
        let books = try context.fetch(descriptor)
        XCTAssertEqual(books.count, 0)
    }

    func testUpdateReadingProgress() {
        let book = manager.addBook(title: "三体", author: "刘慈欣", sourceType: .localFile)
        book.totalChapters = 100

        manager.updateProgress(book: book, chapterIndex: 30, position: 0.5)

        XCTAssertEqual(book.lastReadChapterIndex, 30)
        XCTAssertEqual(book.lastReadPosition, 0.5)
        XCTAssertEqual(book.readingStatus, .reading)
        XCTAssertNotNil(book.lastReadDate)
    }

    func testMarkAsFinished() {
        let book = manager.addBook(title: "三体", author: "刘慈欣", sourceType: .localFile)
        book.totalChapters = 100

        manager.updateProgress(book: book, chapterIndex: 100, position: 0)

        XCTAssertEqual(book.readingStatus, .finished)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | grep -E '(error:|FAIL)' | head -5
```

Expected: `BookManager` not defined.

- [ ] **Step 3: Implement BookManager**

`NovelReader/Services/BookManager.swift`:
```swift
import Foundation
import SwiftData

class BookManager {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func addBook(title: String, author: String, sourceType: SourceType) -> Book {
        let book = Book(title: title, author: author, sourceType: sourceType)
        modelContext.insert(book)
        return book
    }

    func deleteBook(_ book: Book) {
        modelContext.delete(book)
    }

    func updateProgress(book: Book, chapterIndex: Int, position: Double) {
        book.lastReadChapterIndex = chapterIndex
        book.lastReadPosition = position
        book.lastReadDate = Date()

        if chapterIndex >= book.totalChapters && book.totalChapters > 0 {
            book.readingStatus = .finished
        } else if chapterIndex > 0 {
            book.readingStatus = .reading
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | grep -E '(Test Case|passed|failed)'
```

Expected: all 4 BookManager tests pass.

- [ ] **Step 5: Commit**

```bash
git add NovelReader/Services/BookManager.swift NovelReaderTests/BookManagerTests.swift
git commit -m "feat: add BookManager service with CRUD and progress tracking"
```

---

## Task 4: Bookshelf Grid + Cover View

**Files:**
- Create: `NovelReader/Views/Bookshelf/BookCoverView.swift`
- Create: `NovelReader/Views/Bookshelf/BookshelfView.swift`
- Modify: `NovelReader/Views/ContentView.swift`

- [ ] **Step 1: Create BookCoverView**

`NovelReader/Views/Bookshelf/BookCoverView.swift`:
```swift
import SwiftUI

struct BookCoverView: View {
    let book: Book

    var body: some View {
        VStack(spacing: 4) {
            coverImage
            titleLabel
            statusLabel
        }
    }

    private var coverImage: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                if let coverURL = book.coverURL, let url = URL(string: coverURL) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        placeholderGradient
                    }
                } else {
                    placeholderGradient
                }
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(alignment: .bottom) {
                if book.readingStatus == .reading {
                    progressBar
                }
            }

            badge
        }
    }

    private var placeholderGradient: some View {
        let hue = Double(abs(book.title.hashValue) % 360) / 360.0
        return ZStack {
            LinearGradient(
                colors: [
                    Color(hue: hue, saturation: 0.5, brightness: 0.3),
                    Color(hue: hue, saturation: 0.3, brightness: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(book.title.prefix(4))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(4)
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer()
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.white.opacity(0.15))
                        .frame(height: 3)
                    Rectangle()
                        .fill(.blue)
                        .frame(width: geo.size.width * book.progress, height: 3)
                }
            }
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch book.readingStatus {
        case .unread:
            Text("新")
                .font(.system(size: 8))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.9))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .padding(4)
        case .finished:
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .padding(4)
                .background(Color.green.opacity(0.9))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .padding(4)
        case .reading:
            EmptyView()
        }
    }

    private var titleLabel: some View {
        Text(book.title)
            .font(.caption2)
            .foregroundStyle(.gray)
            .lineLimit(1)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch book.readingStatus {
        case .reading:
            Text("\(Int(book.progress * 100))%")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        case .unread:
            Text("未读")
                .font(.system(size: 10))
                .foregroundStyle(.secondary.opacity(0.5))
        case .finished:
            Text("已读完")
                .font(.system(size: 10))
                .foregroundStyle(.secondary.opacity(0.5))
        }
    }
}
```

- [ ] **Step 2: Create BookshelfView**

`NovelReader/Views/Bookshelf/BookshelfView.swift`:
```swift
import SwiftUI
import SwiftData

struct BookshelfView: View {
    @Query(sort: \Book.addedDate, order: .reverse) private var books: [Book]
    @Environment(\.modelContext) private var modelContext

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                if books.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(books) { book in
                            BookCoverView(book: book)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .background(Color.black)
            .navigationTitle("书架")
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "book.closed")
                .font(.system(size: 48))
                .foregroundStyle(.gray.opacity(0.3))
            Text("书架空空如也")
                .foregroundStyle(.gray.opacity(0.5))
                .font(.subheadline)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }
}
```

- [ ] **Step 3: Wire into ContentView**

`NovelReader/Views/ContentView.swift`:
```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        BookshelfView()
    }
}
```

- [ ] **Step 4: Build and verify with preview data**

Add this to the bottom of `BookshelfView.swift` for visual verification:

```swift
#Preview("Bookshelf with books") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Book.self, Chapter.self, BookSource.self,
        configurations: config
    )
    let context = container.mainContext

    let b1 = Book(title: "斗破苍穹", author: "天蚕土豆", sourceType: .localFile, totalChapters: 1647)
    b1.lastReadChapterIndex = 741
    b1.readingStatus = .reading
    context.insert(b1)

    let b2 = Book(title: "遮天", author: "辰东", sourceType: .localFile, totalChapters: 1500)
    b2.lastReadChapterIndex = 1170
    b2.readingStatus = .reading
    context.insert(b2)

    let b3 = Book(title: "三体", author: "刘慈欣", sourceType: .localFile, totalChapters: 100)
    b3.readingStatus = .unread
    context.insert(b3)

    let b4 = Book(title: "活着", author: "余华", sourceType: .localFile, totalChapters: 12)
    b4.lastReadChapterIndex = 12
    b4.readingStatus = .finished
    context.insert(b4)

    let b5 = Book(title: "百年孤独", author: "马尔克斯", sourceType: .localFile, totalChapters: 20)
    b5.readingStatus = .unread
    context.insert(b5)

    return BookshelfView()
        .modelContainer(container)
}

#Preview("Empty bookshelf") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Book.self, Chapter.self, BookSource.self,
        configurations: config
    )
    return BookshelfView()
        .modelContainer(container)
}
```

Build:
```bash
xcodebuild build -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add NovelReader/Views/
git commit -m "feat: add bookshelf grid view with cover and status indicators"
```

---

## Task 5: Series Book Display

**Files:**
- Create: `NovelReader/Views/Bookshelf/BookshelfItem.swift`
- Create: `NovelReader/Views/Bookshelf/SeriesBookView.swift`
- Modify: `NovelReader/Views/Bookshelf/BookshelfView.swift`

- [ ] **Step 1: Create BookshelfItem enum for grid grouping**

`NovelReader/Views/Bookshelf/BookshelfItem.swift`:
```swift
import Foundation

enum BookshelfItem: Identifiable {
    case single(Book)
    case series(name: String, books: [Book])

    var id: String {
        switch self {
        case .single(let book):
            return book.id.uuidString
        case .series(let name, _):
            return "series-\(name)"
        }
    }

    static func group(_ books: [Book]) -> [BookshelfItem] {
        var singles: [BookshelfItem] = []
        var seriesMap: [String: [Book]] = [:]

        for book in books {
            if let name = book.seriesName {
                seriesMap[name, default: []].append(book)
            } else {
                singles.append(.single(book))
            }
        }

        var items: [BookshelfItem] = []
        for (name, seriesBooks) in seriesMap.sorted(by: { $0.key < $1.key }) {
            let sorted = seriesBooks.sorted { ($0.seriesIndex ?? 0) < ($1.seriesIndex ?? 0) }
            items.append(.series(name: name, books: sorted))
        }
        items.append(contentsOf: singles)
        return items
    }
}
```

- [ ] **Step 2: Create SeriesBookView**

`NovelReader/Views/Bookshelf/SeriesBookView.swift`:
```swift
import SwiftUI

struct SeriesBookView: View {
    let seriesName: String
    let books: [Book]

    private var currentBook: Book? {
        books.first { $0.readingStatus == .reading }
            ?? books.first { $0.readingStatus == .unread }
            ?? books.last
    }

    private var allFinished: Bool {
        books.allSatisfy { $0.readingStatus == .finished }
    }

    private var currentIndex: Int {
        guard let current = currentBook,
              let idx = books.firstIndex(where: { $0.id == current.id }) else { return 0 }
        return idx + 1
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                stackedCovers
                countBadge
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)

            Text(seriesName)
                .font(.caption2)
                .foregroundStyle(.gray)
                .lineLimit(1)

            progressLabel
        }
    }

    private var stackedCovers: some View {
        let hue = Double(abs(seriesName.hashValue) % 360) / 360.0
        return ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hue: hue, saturation: 0.4, brightness: 0.25),
                            Color(hue: hue, saturation: 0.3, brightness: 0.12)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .opacity(0.5)
                .offset(x: 4, y: -4)

            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hue: hue, saturation: 0.45, brightness: 0.3),
                            Color(hue: hue, saturation: 0.3, brightness: 0.15)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .opacity(0.7)
                .offset(x: 2, y: -2)

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hue: hue, saturation: 0.5, brightness: 0.35),
                                Color(hue: hue, saturation: 0.35, brightness: 0.18)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )

                Text(seriesName.prefix(4))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let book = currentBook, book.readingStatus == .reading {
                    GeometryReader { geo in
                        VStack(spacing: 0) {
                            Spacer()
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.white.opacity(0.15)).frame(height: 3)
                                Rectangle().fill(.orange).frame(width: geo.size.width * book.progress, height: 3)
                            }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private var countBadge: some View {
        Text("\(books.count)部")
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(allFinished ? Color.green.opacity(0.9) : Color.orange.opacity(0.9))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .offset(x: 2, y: -2)
    }

    @ViewBuilder
    private var progressLabel: some View {
        if allFinished {
            Text("全部读完")
                .font(.system(size: 10))
                .foregroundStyle(.green)
        } else if let book = currentBook, book.readingStatus == .reading {
            Text("第\(currentIndex)部 \(Int(book.progress * 100))%")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        } else {
            Text("第\(currentIndex)部")
                .font(.system(size: 10))
                .foregroundStyle(.secondary.opacity(0.5))
        }
    }
}
```

- [ ] **Step 3: Update BookshelfView to use grouping**

Replace the body of `BookshelfView` with:

```swift
struct BookshelfView: View {
    @Query(sort: \Book.addedDate, order: .reverse) private var books: [Book]
    @Environment(\.modelContext) private var modelContext

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    private var groupedItems: [BookshelfItem] {
        BookshelfItem.group(books)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if books.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(groupedItems) { item in
                            switch item {
                            case .single(let book):
                                BookCoverView(book: book)
                            case .series(let name, let seriesBooks):
                                SeriesBookView(seriesName: name, books: seriesBooks)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .background(Color.black)
            .navigationTitle("书架")
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "book.closed")
                .font(.system(size: 48))
                .foregroundStyle(.gray.opacity(0.3))
            Text("书架空空如也")
                .foregroundStyle(.gray.opacity(0.5))
                .font(.subheadline)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }
}
```

Update the preview to include series books:

```swift
#Preview("Bookshelf with series") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Book.self, Chapter.self, BookSource.self,
        configurations: config
    )
    let context = container.mainContext

    let b1 = Book(title: "斗破苍穹", author: "天蚕土豆", sourceType: .localFile, totalChapters: 1647)
    b1.lastReadChapterIndex = 741
    b1.readingStatus = .reading
    context.insert(b1)

    let b2 = Book(title: "三体", author: "刘慈欣", sourceType: .localFile, totalChapters: 100)
    b2.readingStatus = .unread
    context.insert(b2)

    // Series: 盗墓笔记
    for i in 1...8 {
        let b = Book(title: "盗墓笔记\(i)", author: "南派三叔", sourceType: .localFile, totalChapters: 200)
        b.seriesName = "盗墓笔记"
        b.seriesIndex = i
        if i < 3 {
            b.readingStatus = .finished
            b.lastReadChapterIndex = 200
        } else if i == 3 {
            b.readingStatus = .reading
            b.lastReadChapterIndex = 66
        }
        context.insert(b)
    }

    let b3 = Book(title: "活着", author: "余华", sourceType: .localFile, totalChapters: 12)
    b3.lastReadChapterIndex = 12
    b3.readingStatus = .finished
    context.insert(b3)

    return BookshelfView()
        .modelContainer(container)
}
```

- [ ] **Step 4: Build and verify**

```bash
xcodebuild build -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add NovelReader/Views/Bookshelf/
git commit -m "feat: add series book grouping with stacked cover display"
```

---

## Task 6: Encoding Detection + Chapter Splitting

**Files:**
- Create: `NovelReader/Helpers/EncodingDetector.swift`
- Create: `NovelReader/Helpers/ChapterSplitter.swift`
- Create: `NovelReaderTests/EncodingDetectorTests.swift`
- Create: `NovelReaderTests/ChapterSplitterTests.swift`
- Create: `NovelReaderTests/Fixtures/sample_utf8.txt`
- Create: `NovelReaderTests/Fixtures/sample_gbk.txt`

- [ ] **Step 1: Write failing tests for encoding detection**

`NovelReaderTests/EncodingDetectorTests.swift`:
```swift
import XCTest
@testable import NovelReader

final class EncodingDetectorTests: XCTestCase {
    func testUTF8String() {
        let data = "第一章 开始\n这是正文内容。".data(using: .utf8)!
        let result = EncodingDetector.decodeToString(data)
        XCTAssertTrue(result.contains("第一章"))
    }

    func testUTF8BOM() {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append("你好世界".data(using: .utf8)!)
        let result = EncodingDetector.decodeToString(data)
        XCTAssertEqual(result, "你好世界")
    }

    func testGBKString() {
        let gbkEncoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        let original = "第一章 测试内容"
        let data = (original as NSString).data(using: gbkEncoding.rawValue)!
        let result = EncodingDetector.decodeToString(data)
        XCTAssertTrue(result.contains("第一章"))
    }

    func testPureASCII() {
        let data = "Hello World".data(using: .utf8)!
        let result = EncodingDetector.decodeToString(data)
        XCTAssertEqual(result, "Hello World")
    }

    func testEmptyData() {
        let data = Data()
        let result = EncodingDetector.decodeToString(data)
        XCTAssertEqual(result, "")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | grep -E '(error:|FAIL)' | head -5
```

Expected: `EncodingDetector` not defined.

- [ ] **Step 3: Implement EncodingDetector**

`NovelReader/Helpers/EncodingDetector.swift`:
```swift
import Foundation

struct EncodingDetector {
    static func decodeToString(_ data: Data) -> String {
        if data.isEmpty { return "" }

        // Check UTF-8 BOM
        if data.count >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF {
            return String(data: data.dropFirst(3), encoding: .utf8) ?? ""
        }

        // Try UTF-8
        if let str = String(data: data, encoding: .utf8) {
            return str
        }

        // Try GBK (GB18030 is a superset that covers GBK and GB2312)
        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        if let str = String(data: data, encoding: gb18030) {
            return str
        }

        // Fallback: ISO Latin 1 never fails
        return String(data: data, encoding: .isoLatin1) ?? ""
    }
}
```

- [ ] **Step 4: Run encoding tests to verify they pass**

```bash
xcodebuild test -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NovelReaderTests/EncodingDetectorTests -quiet 2>&1 | grep -E '(Test Case|passed|failed)'
```

Expected: all 5 encoding tests pass.

- [ ] **Step 5: Write failing tests for chapter splitting**

`NovelReaderTests/ChapterSplitterTests.swift`:
```swift
import XCTest
@testable import NovelReader

final class ChapterSplitterTests: XCTestCase {
    func testBasicChineseChapters() {
        let text = """
        第一章 少年
        少年站在山巅之上。

        第二章 下山
        他决定下山去看看。
        """
        let chapters = ChapterSplitter.split(text)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].title, "第一章 少年")
        XCTAssertTrue(chapters[0].content.contains("少年站在山巅"))
        XCTAssertEqual(chapters[1].title, "第二章 下山")
    }

    func testNumericChapterMarkers() {
        let text = """
        第1章 开始
        内容一。

        第2章 发展
        内容二。

        第10章 高潮
        内容十。
        """
        let chapters = ChapterSplitter.split(text)
        XCTAssertEqual(chapters.count, 3)
    }

    func testChineseNumerals() {
        let text = """
        第一百二十三章 大战
        战斗开始了。

        第一百二十四章 结束
        战斗结束了。
        """
        let chapters = ChapterSplitter.split(text)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].title, "第一百二十三章 大战")
    }

    func testNoChapterMarkers() {
        let text = "这是一段没有章节标记的纯文本内容。\n就是一段文字。"
        let chapters = ChapterSplitter.split(text)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters[0].title, "全文")
    }

    func testPrologueBeforeFirstChapter() {
        let text = """
        这是序言内容。

        第一章 正文开始
        正文内容。
        """
        let chapters = ChapterSplitter.split(text)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].title, "序")
        XCTAssertEqual(chapters[1].title, "第一章 正文开始")
    }

    func testSectionAndVolumeMarkers() {
        let text = """
        第一节 引子
        内容。

        第一回 开场
        内容。
        """
        let chapters = ChapterSplitter.split(text)
        XCTAssertEqual(chapters.count, 2)
    }
}
```

- [ ] **Step 6: Run tests to verify they fail**

```bash
xcodebuild test -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NovelReaderTests/ChapterSplitterTests -quiet 2>&1 | grep -E '(error:|FAIL)' | head -3
```

Expected: `ChapterSplitter` not defined.

- [ ] **Step 7: Implement ChapterSplitter**

`NovelReader/Helpers/ChapterSplitter.swift`:
```swift
import Foundation

struct ChapterSplitter {
    struct RawChapter {
        let title: String
        let content: String
    }

    static func split(_ text: String) -> [RawChapter] {
        let pattern = #"^[　\s]*(第[零一二三四五六七八九十百千万0-9]+[章节回集卷部]\s*.+)$"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            return [RawChapter(title: "全文", content: text.trimmingCharacters(in: .whitespacesAndNewlines))]
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        guard !matches.isEmpty else {
            return [RawChapter(title: "全文", content: text.trimmingCharacters(in: .whitespacesAndNewlines))]
        }

        var chapters: [RawChapter] = []

        // Prologue: content before first chapter marker
        let firstStart = matches[0].range.location
        if firstStart > 0 {
            let prologue = nsText.substring(with: NSRange(location: 0, length: firstStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !prologue.isEmpty {
                chapters.append(RawChapter(title: "序", content: prologue))
            }
        }

        for i in 0..<matches.count {
            let titleRange = matches[i].range(at: 1)
            let title = nsText.substring(with: titleRange)
                .trimmingCharacters(in: .whitespaces)

            let contentStart = matches[i].range.location + matches[i].range.length
            let contentEnd = (i + 1 < matches.count) ? matches[i + 1].range.location : nsText.length
            let contentRange = NSRange(location: contentStart, length: contentEnd - contentStart)
            let content = nsText.substring(with: contentRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            chapters.append(RawChapter(title: title, content: content))
        }

        return chapters
    }
}
```

- [ ] **Step 8: Run all tests**

```bash
xcodebuild test -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | grep -E '(Test Case|passed|failed)'
```

Expected: all encoding + chapter splitter tests pass (11 new tests).

- [ ] **Step 9: Commit**

```bash
git add NovelReader/Helpers/ NovelReaderTests/EncodingDetectorTests.swift NovelReaderTests/ChapterSplitterTests.swift
git commit -m "feat: add encoding detection (UTF-8/GBK) and chapter splitting"
```

---

## Task 7: TXT Import Service + File Picker

**Files:**
- Create: `NovelReader/Services/ImportService.swift`
- Create: `NovelReader/Helpers/DocumentPicker.swift`
- Create: `NovelReaderTests/ImportServiceTests.swift`
- Modify: `NovelReader/Views/Bookshelf/BookshelfView.swift`

- [ ] **Step 1: Write failing test for ImportService**

`NovelReaderTests/ImportServiceTests.swift`:
```swift
import XCTest
import SwiftData
@testable import NovelReader

final class ImportServiceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var importService: ImportService!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(
            for: Book.self, Chapter.self, BookSource.self,
            configurations: config
        )
        context = ModelContext(container)
        importService = ImportService(modelContext: context)
    }

    func testImportTXTWithChapters() throws {
        let content = """
        第一章 开始
        这是第一章的正文内容。非常精彩。

        第二章 发展
        这是第二章的正文内容。更加精彩。

        第三章 高潮
        这是第三章的正文内容。最为精彩。
        """

        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_novel.txt")
        try content.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let book = try importService.importTXT(from: tmpFile)

        XCTAssertEqual(book.title, "test_novel")
        XCTAssertEqual(book.sourceType, .localFile)
        XCTAssertEqual(book.totalChapters, 3)
        XCTAssertEqual(book.readingStatus, .unread)

        let descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.book?.id == book.id },
            sortBy: [SortDescriptor(\Chapter.index)]
        )
        let chapters = try context.fetch(descriptor)
        XCTAssertEqual(chapters.count, 3)
        XCTAssertEqual(chapters[0].title, "第一章 开始")
        XCTAssertTrue(chapters[0].isCached)
        XCTAssertTrue(chapters[0].content?.contains("非常精彩") ?? false)
    }

    func testImportTXTWithoutChapters() throws {
        let content = "这是一段没有章节的纯文本小说。很短。"

        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("short.txt")
        try content.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let book = try importService.importTXT(from: tmpFile)

        XCTAssertEqual(book.totalChapters, 1)

        let descriptor = FetchDescriptor<Chapter>(
            predicate: #Predicate { $0.book?.id == book.id }
        )
        let chapters = try context.fetch(descriptor)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters[0].title, "全文")
    }

    func testImportTXTCustomTitle() throws {
        let content = "第一章 Test\n内容。"

        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("file.txt")
        try content.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let book = try importService.importTXT(from: tmpFile, title: "自定义书名")

        XCTAssertEqual(book.title, "自定义书名")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NovelReaderTests/ImportServiceTests -quiet 2>&1 | grep -E '(error:|FAIL)' | head -3
```

Expected: `ImportService` not defined.

- [ ] **Step 3: Implement ImportService**

`NovelReader/Services/ImportService.swift`:
```swift
import Foundation
import SwiftData

class ImportService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func importTXT(from url: URL, title: String? = nil) throws -> Book {
        let data = try Data(contentsOf: url)
        let text = EncodingDetector.decodeToString(data)
        let rawChapters = ChapterSplitter.split(text)

        let bookTitle = title ?? url.deletingPathExtension().lastPathComponent
        let book = Book(
            title: bookTitle,
            author: "未知",
            sourceType: .localFile,
            totalChapters: rawChapters.count
        )
        modelContext.insert(book)

        for (index, raw) in rawChapters.enumerated() {
            let chapter = Chapter(index: index, title: raw.title, content: raw.content)
            chapter.book = book
            modelContext.insert(chapter)
        }

        try modelContext.save()
        return book
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NovelReaderTests/ImportServiceTests -quiet 2>&1 | grep -E '(Test Case|passed|failed)'
```

Expected: all 3 ImportService tests pass.

- [ ] **Step 5: Create DocumentPicker and wire into BookshelfView**

`NovelReader/Helpers/DocumentPicker.swift`:
```swift
import SwiftUI
import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.plainText])
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            onPick(url)
        }
    }
}
```

Update `BookshelfView.swift` — add import button and sheet. Add these properties and modifier to the existing struct:

```swift
// Add these @State properties at the top of BookshelfView
@State private var showingFilePicker = false
@State private var importError: String?
@State private var showingError = false
```

Add toolbar to the NavigationStack:
```swift
.toolbar {
    ToolbarItem(placement: .topBarTrailing) {
        Button(action: { showingFilePicker = true }) {
            Image(systemName: "plus")
                .foregroundStyle(.white)
        }
    }
}
.sheet(isPresented: $showingFilePicker) {
    DocumentPicker { url in
        let service = ImportService(modelContext: modelContext)
        do {
            _ = try service.importTXT(from: url)
        } catch {
            importError = error.localizedDescription
            showingError = true
        }
    }
}
.alert("导入失败", isPresented: $showingError) {
    Button("确定") {}
} message: {
    Text(importError ?? "")
}
```

- [ ] **Step 6: Build and verify**

```bash
xcodebuild build -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add NovelReader/Services/ImportService.swift NovelReader/Helpers/DocumentPicker.swift NovelReader/Views/Bookshelf/BookshelfView.swift NovelReaderTests/ImportServiceTests.swift
git commit -m "feat: add TXT import with encoding detection and file picker"
```

---

## Task 8: Navigation + End-to-End Integration

**Files:**
- Create: `NovelReader/Views/Reader/ChapterListView.swift`
- Modify: `NovelReader/Views/Bookshelf/BookshelfView.swift`

- [ ] **Step 1: Create ChapterListView placeholder**

`NovelReader/Views/Reader/ChapterListView.swift`:
```swift
import SwiftUI
import SwiftData

struct ChapterListView: View {
    let book: Book

    @Query private var chapters: [Chapter]

    init(book: Book) {
        self.book = book
        let bookId = book.id
        _chapters = Query(
            filter: #Predicate<Chapter> { $0.book?.id == bookId },
            sort: [SortDescriptor(\Chapter.index)]
        )
    }

    var body: some View {
        List(chapters) { chapter in
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
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

- [ ] **Step 2: Wire navigation from bookshelf to chapter list**

In `BookshelfView.swift`, wrap the grid items with `NavigationLink`. Replace the `ForEach` content:

```swift
LazyVGrid(columns: columns, spacing: 16) {
    ForEach(groupedItems) { item in
        switch item {
        case .single(let book):
            NavigationLink(value: book) {
                BookCoverView(book: book)
            }
            .buttonStyle(.plain)
        case .series(let name, let seriesBooks):
            SeriesBookView(seriesName: name, books: seriesBooks)
        }
    }
}
.padding(.horizontal, 16)
.padding(.top, 8)
```

Add `.navigationDestination` inside the `NavigationStack`:

```swift
.navigationDestination(for: Book.self) { book in
    ChapterListView(book: book)
}
```

- [ ] **Step 3: Run all tests**

```bash
xcodebuild test -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | grep -E '(Executed|passed|failed)'
```

Expected: all tests pass (placeholder + model + manager + encoding + splitter + import = ~20 tests).

- [ ] **Step 4: Build and run in simulator for manual verification**

```bash
xcodebuild build -project NovelReader.xcodeproj -scheme NovelReader -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
```

Manual test checklist:
1. App launches with empty bookshelf and "书架空空如也" message
2. Tap "+" → file picker opens
3. Select a .txt file → book appears on bookshelf with "新" badge
4. Tap book → chapter list view shows all detected chapters
5. Bookshelf shows 4-column grid on standard iPhone

- [ ] **Step 5: Commit**

```bash
git add NovelReader/Views/
git commit -m "feat: add chapter list view and bookshelf navigation"
```

---

## Summary

After completing all 8 tasks, the app delivers:

- **Bookshelf**: 4-column cover grid on black background with status badges (新/progress%/✓) and series stacking
- **TXT Import**: "+" button opens file picker, auto-detects encoding (UTF-8/GBK), splits by chapter markers
- **Navigation**: Tap a book → see chapter list
- **Data**: SwiftData persistence across launches
- **Tests**: ~20 unit tests covering models, services, encoding detection, and chapter splitting

**Next plans:**
- Plan 2: Reader UI (reading view, menu overlay, settings, EPUB import)
- Plan 3: Book Source Engine (Legado-compatible engine, search flow, source management, quality detection)
