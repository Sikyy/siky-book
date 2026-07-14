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
                CachedCoverImage(
                    urlString: book.coverURL,
                    targetSize: CGSize(width: 120, height: 160)
                ) {
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
