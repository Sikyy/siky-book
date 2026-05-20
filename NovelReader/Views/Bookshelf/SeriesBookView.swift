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
