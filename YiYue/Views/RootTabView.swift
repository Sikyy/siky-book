import SwiftUI

/// 底部两个真 tab:阅读(继续阅读首页)/ 书架。
/// 底栏是 nowdex 那种悬浮胶囊:高 64、圆角 32、距底 20,浮在内容之上。
enum RootTab: String, CaseIterable, Identifiable {
    case reading
    case shelf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reading: return "阅读"
        case .shelf: return "书架"
        }
    }

    var icon: String {
        switch self {
        case .reading: return "book.pages"
        case .shelf: return "books.vertical"
        }
    }
}

/// 阅读页是叠在书架上的 overlay(不是 fullScreenCover),所以外层胶囊要知道
/// 它开没开,开着就把胶囊藏起来,不然会浮在正文上面。
@Observable
final class ReaderPresence {
    static let shared = ReaderPresence()
    var isOpen = false
}

struct RootTabView: View {
    @State private var tab: RootTab = .shelf
    private let readerPresence = ReaderPresence.shared

    /// 悬浮胶囊占的高度 + 与屏幕底的距离,页面内容要让开这么多。
    static let barHeight: CGFloat = 64
    static let barBottomInset: CGFloat = 20
    static let contentBottomPadding: CGFloat = barHeight + barBottomInset + 12

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .reading:
                    ReadingHomeView()
                case .shelf:
                    BookshelfView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: Self.contentBottomPadding)
            }

            capsuleBar
                .padding(.bottom, Self.barBottomInset)
                .opacity(readerPresence.isOpen ? 0 : 1)
                .allowsHitTesting(!readerPresence.isOpen)
                .animation(.easeInOut(duration: 0.18), value: readerPresence.isOpen)
        }
        .preferredColorScheme(.dark)
    }

    private var capsuleBar: some View {
        HStack(spacing: 4) {
            ForEach(RootTab.allCases) { item in
                Button {
                    guard tab != item else { return }
                    tab = item
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.icon)
                            .font(.system(size: 20, weight: .regular))
                        Text(item.title)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(tab == item ? Color.primary : Color.secondary)
                    .frame(width: 84, height: 56)
                    .background {
                        if tab == item {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.10))
                        }
                    }
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(tab == item ? [.isSelected] : [])
            }
        }
        .padding(4)
        .frame(height: Self.barHeight)
        .modifier(FloatingCapsuleChrome())
        .animation(.snappy(duration: 0.22), value: tab)
    }
}

/// iOS 26 起用 Liquid Glass;iOS 17–25 回落毛玻璃 + 发丝描边。
private struct FloatingCapsuleChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                }
        }
    }
}

#Preview {
    RootTabView()
}
