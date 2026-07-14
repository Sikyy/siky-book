import SwiftUI

struct ContentView: View {
    var body: some View {
        BookshelfView()
            .task {
                await ChapterDownloadManager.shared.bootstrap()
            }
    }
}
