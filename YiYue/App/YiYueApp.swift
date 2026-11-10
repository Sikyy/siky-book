import SwiftUI
import SwiftData
import Nuke

@main
struct YiYueApp: App {
    @Environment(\.scenePhase) private var scenePhase

    /// One container for the whole app run. `.modelContainer(for:)` builds the
    /// container inside the scene and can build it again when the scene is
    /// rebuilt; a second container resets the first one's context, which
    /// destroys every model instance a view is still holding — the reader's
    /// book, for instance — and the next property access traps in SwiftData.
    private static let sharedContainer: ModelContainer = {
        let schema = Schema([Book.self, Chapter.self, BookSource.self, ReadingMark.self, Shelf.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("无法打开数据存储：\(error)")
        }
    }()

    init() {
        ChapterDownloadSystemTask.shared.register()
        var configuration = ImagePipeline.Configuration.withDataCache(
            name: "com.mistyislet.yiyue.cover-images",
            sizeLimit: 256 * 1024 * 1024
        )
        configuration.dataCachePolicy = .storeOriginalData
        configuration.imageCache = ImageCache(costLimit: 64 * 1024 * 1024)
        configuration.isTaskCoalescingEnabled = true
        ImagePipeline.shared = ImagePipeline(configuration: configuration)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(Self.sharedContainer)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                ChapterDownloadSystemTask.shared.sceneWillEnterForeground()
            case .background:
                ChapterDownloadSystemTask.shared.sceneDidEnterBackground()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}
