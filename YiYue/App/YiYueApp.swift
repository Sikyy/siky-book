import SwiftUI
import SwiftData

@main
struct YiYueApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Book.self, Chapter.self, BookSource.self])
    }
}
