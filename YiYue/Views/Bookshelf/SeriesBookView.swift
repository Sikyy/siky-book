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

    var body: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .topTrailing) {
                stackedCovers
                cornerBadge
            }
            .frame(width: BookCoverView.coverWidth, height: BookCoverView.coverHeight)

            Text(seriesName)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(
                    width: BookCoverView.coverWidth,
                    height: 16,
                    alignment: .topLeading
                )
        }
        .frame(width: BookCoverView.coverWidth)
    }

    private var stackedCovers: some View {
        let hue = Double(abs(seriesName.hashValue) % 360) / 360.0
        return ZStack {
            RoundedRectangle(cornerRadius: 5)
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

            RoundedRectangle(cornerRadius: 5)
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
                RoundedRectangle(cornerRadius: 5)
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
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }

    @ViewBuilder
    private var cornerBadge: some View {
        if allFinished {
            ShelfCornerBadge(text: "读完", background: Color.black.opacity(0.45))
        } else if let book = currentBook, book.readingStatus == .reading {
            ShelfCornerBadge(
                text: "\(Int(book.progress * 100))%",
                background: .shelfReadingAccent
            )
        } else {
            ShelfCornerBadge(
                text: "\(books.count)部",
                background: Color.black.opacity(0.45)
            )
        }
    }
}
