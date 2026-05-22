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
                if let coverURL = book.coverURL, !coverURL.isEmpty, let url = Self.resolveURL(coverURL) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            placeholderGradient
                        }
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

    /// 解析封面 URL：本地相对路径 → Documents 下绝对路径，远程 URL 直接返回
    private static func resolveURL(_ coverURL: String) -> URL? {
        if coverURL.hasPrefix("http://") || coverURL.hasPrefix("https://") || coverURL.hasPrefix("file://") {
            return URL(string: coverURL)
        }
        // 本地相对路径，如 "covers/xxx.jpg"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let localFile = docs.appendingPathComponent(coverURL)
        return FileManager.default.fileExists(atPath: localFile.path) ? localFile : nil
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
