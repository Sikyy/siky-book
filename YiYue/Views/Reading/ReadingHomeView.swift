import SwiftUI
import SwiftData

/// 「阅读」tab:接着上次读。大卡 + 在读列表,点一下直接进阅读器。
struct ReadingHomeView: View {
    @Query(sort: \Book.addedDate, order: .reverse) private var books: [Book]
    @State private var readerBook: Book?

    /// 在读的书,最近读过的排前面;没读过日期的按加入时间。
    private var readingBooks: [Book] {
        books
            .filter { $0.readingStatus == .reading }
            .sorted { lhs, rhs in
                let l = lhs.lastReadDate ?? lhs.addedDate
                let r = rhs.lastReadDate ?? rhs.addedDate
                return l > r
            }
    }

    private var current: Book? { readingBooks.first }
    private var rest: [Book] { Array(readingBooks.dropFirst().prefix(6)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("阅读")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 8)

                if let current {
                    Button {
                        readerBook = current
                    } label: {
                        continueCard(current)
                    }
                    .buttonStyle(.plain)
                }

                if !rest.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("在读")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(.bottom, 4)

                        ForEach(rest) { book in
                            Button {
                                readerBook = book
                            } label: {
                                row(book)
                            }
                            .buttonStyle(.plain)

                            if book.id != rest.last?.id {
                                Rectangle()
                                    .fill(Color.white.opacity(0.06))
                                    .frame(height: 0.5)
                                    .padding(.leading, 56)
                            }
                        }
                    }
                }

                if readingBooks.isEmpty {
                    emptyState
                }
            }
            .padding(.horizontal, 20)
        }
        .background(Color.black)
        .fullScreenCover(item: $readerBook) { book in
            ReaderView(book: book, startChapterIndex: book.lastReadChapterIndex)
        }
        .preferredColorScheme(.dark)
    }

    private func continueCard(_ book: Book) -> some View {
        HStack(spacing: 16) {
            CachedCoverImage(
                urlString: book.coverURL,
                targetSize: CGSize(width: 96, height: 144)
            ) {
                cardPlaceholder(book)
            }
            .frame(width: 96, height: 144)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("继续阅读")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))

                Text(book.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text("第 \(book.lastReadChapterIndex + 1) 章 · \(Int(book.progress * 100))%")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))

                progressLine(book)

                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func progressLine(_ book: Book) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(Color.shelfReadingAccent)
                    .frame(width: max(2, geo.size.width * book.progress))
            }
        }
        .frame(height: 3)
    }

    private func row(_ book: Book) -> some View {
        HStack(spacing: 12) {
            CachedCoverImage(
                urlString: book.coverURL,
                targetSize: CGSize(width: 40, height: 60)
            ) {
                cardPlaceholder(book)
            }
            .frame(width: 40, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("第 \(book.lastReadChapterIndex + 1) 章")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(Int(book.progress * 100))%")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(height: 72)
        .contentShape(Rectangle())
    }

    private func cardPlaceholder(_ book: Book) -> some View {
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
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(4)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "book.pages")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.18))
            Text("还没有在读的书")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.55))
            Text("去书架挑一本,读到哪儿这儿都会记着")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }
}
