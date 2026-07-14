import SwiftUI
import SwiftData
import Nuke

@main
struct YiYueApp: App {
    @Environment(\.scenePhase) private var scenePhase

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
        .modelContainer(for: [Book.self, Chapter.self, BookSource.self])
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
