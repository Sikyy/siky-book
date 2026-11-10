import SwiftUI

struct ContentView: View {
    var body: some View {
        RootTabView()
            .task {
                await ChapterDownloadManager.shared.bootstrap()
            }
    }
}
