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
