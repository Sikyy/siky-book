import SwiftUI
import Nuke
import NukeUI

/// 统一的封面加载视图。远程图片使用 Nuke 的内存/磁盘缓存，且按展示尺寸直接下采样。
struct CachedCoverImage<Placeholder: View>: View {
    private let url: URL?
    private let targetSize: CGSize
    private let contentMode: SwiftUI.ContentMode
    private let placeholder: () -> Placeholder

    init(
        url: URL?,
        targetSize: CGSize,
        contentMode: SwiftUI.ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.targetSize = targetSize
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    init(
        urlString: String?,
        targetSize: CGSize,
        contentMode: SwiftUI.ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.init(
            url: CoverURLResolver.resolve(urlString),
            targetSize: targetSize,
            contentMode: contentMode,
            placeholder: placeholder
        )
    }

    var body: some View {
        LazyImage(request: imageRequest) { state in
            if let image = state.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        // LazyImage 默认即为 cancel；显式声明，避免列表离屏后继续占用网络与解码资源。
        .onDisappear(.cancel)
    }

    private var imageRequest: ImageRequest? {
        guard let url else { return nil }

        var request = ImageRequest(url: url)
        request.thumbnail = ImageRequest.ThumbnailOptions(
            size: targetSize,
            unit: .points,
            contentMode: contentMode == .fit ? .aspectFit : .aspectFill
        )
        return request
    }
}

enum CoverURLResolver {
    /// 支持远程 URL、file URL，以及 Documents 下的相对路径（如 covers/xxx.jpg）。
    static func resolve(_ value: String?) -> URL? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        if let url = URL(string: value),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" || scheme == "file" {
            return url
        }

        let documents = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .standardizedFileURL
        let localFile = documents
            .appendingPathComponent(value)
            .standardizedFileURL

        guard localFile.path == documents.path ||
                localFile.path.hasPrefix(documents.path + "/") else {
            return nil
        }
        return localFile
    }
}

extension Color {
    /// 书架「在读」角标:阅读器强调色 #9A4A31,不跟随系统蓝。
    static let shelfReadingAccent = Color(hex: "#9A4A31")
}

/// 书架角标:25×15,只圆左上角,贴在封面右上角。
struct ShelfCornerBadge: View {
    let text: String
    let background: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 25, height: 15)
            .background(
                background,
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 5,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )
    }
}

struct BookCoverView: View {
    let book: Book

    /// 封面 108×156(9:13)、圆角 5,封面到书名 14,书名一行 13 点。
    static let coverWidth: CGFloat = 108
    static let coverHeight: CGFloat = 156

    var body: some View {
        VStack(spacing: 12) {
            coverImage
            titleLabel
        }
        .frame(width: Self.coverWidth)
    }

    private var coverImage: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                CachedCoverImage(
                    urlString: book.coverURL,
                    targetSize: CGSize(width: Self.coverWidth, height: Self.coverHeight)
                ) {
                    placeholderGradient
                }
            }
            .frame(width: Self.coverWidth, height: Self.coverHeight)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            badge
        }
        .overlay(alignment: .topLeading) {
            if book.pinnedDate != nil {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Color.black.opacity(0.5), in: Circle())
                    .padding(4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let prefix = SampleBookService.isSample(book) ? "示例书，" : ""
        switch book.readingStatus {
        case .reading: return "\(prefix)《\(book.title)》，读到 \(Int(book.progress * 100))%"
        case .finished: return "\(prefix)《\(book.title)》，已读完"
        case .unread: return "\(prefix)《\(book.title)》，未读"
        }
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

    @ViewBuilder
    private var badge: some View {
        if SampleBookService.isSample(book) {
            // 内置示例书固定用右上角这颗角标:25×15、墨 18% 底、白字。
            ShelfCornerBadge(text: "示例", background: Color.black.opacity(0.18))
        } else {
            switch book.readingStatus {
            case .reading:
                ShelfCornerBadge(
                    text: "\(Int(book.progress * 100))%",
                    background: .shelfReadingAccent
                )
            case .finished:
                ShelfCornerBadge(
                    text: "读完",
                    background: Color.black.opacity(0.45)
                )
            case .unread:
                EmptyView()
            }
        }
    }

    private var titleLabel: some View {
        Text(book.title)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: Self.coverWidth, height: 16, alignment: .topLeading)
    }
}
