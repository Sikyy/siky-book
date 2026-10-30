import SwiftUI
import UIKit

/// 一页正文,用 UITextView 渲染:排版参数与原来 SwiftUI Text 逐项对齐,
/// 这样换渲染方式之后每一页的字位、行位都不变,换来的是系统级的选字。
struct PageTextView: UIViewRepresentable {
    let fragments: [ReaderView.PageFragment]
    let fontSize: CGFloat
    let lineSpacing: Double
    let fontFamily: String
    let textColor: Color
    /// 选中的段落(书签/笔记高亮),用于页面重画时的兜底高亮。
    var highlightedParagraph: Int?
    /// 主题强调色:选中高亮和两端手柄用它。
    var accentColor: Color = .accentColor
    /// 跨页选中时,整页都算在选区里。
    var highlightAll: Bool = false
    /// 本页里要再单独上一遍底色的字符区间(跨页选中的另一头)。
    var extraHighlight: NSRange?
    /// 这一页希望系统选中的区间(跨页翻过去以后接着选)。
    var desiredSelection: NSRange?
    /// 选中变化时回报本页内的字符区间。
    var onSelectionChanged: ((NSRange) -> Void)?
    /// 手指在上下边缘 24 点内停住 0.45 秒:true 是上边缘。
    var onEdgeHold: ((Bool) -> Void)?
    /// 文本视图会吃掉单击,这里把屏幕坐标回传给外面的点击分流。
    var onScreenTap: ((CGPoint) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PageUITextView {
        // 用 TextKit 1:它认 minimumLineHeight,能把行高钉回 SwiftUI Text 的高度。
        let view = PageUITextView(usingTextLayoutManager: false)
        view.backgroundColor = .clear
        view.isEditable = false
        view.isScrollEnabled = false
        view.isSelectable = true
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.widthTracksTextView = true
        view.textContainer.heightTracksTextView = true
        view.adjustsFontForContentSizeCategory = false
        view.delegate = context.coordinator
        view.pageFragments = fragments
        view.linkTextAttributes = [:]
        return view
    }

    func updateUIView(_ view: PageUITextView, context: Context) {
        view.tintColor = UIColor(accentColor)
        view.onSelectionChanged = onSelectionChanged
        view.onScreenTap = onScreenTap
        view.onEdgeHold = onEdgeHold
        view.highlightAll = highlightAll
        view.desiredSelection = desiredSelection
        view.extraHighlight = extraHighlight
        view.attributedText = attributed(gap: 0)
        view.layoutManager.ensureLayout(for: view.textContainer)
        let natural = view.layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).height
        let targetPitch = uiFont.lineHeight + fontSize * CGFloat(lineSpacing - 1)
        let adjusted = max(0, targetPitch - natural)
        view.attributedText = attributed(gap: adjusted)
        view.pageFragments = fragments
        view.applyHighlightState()
    }

    private var uiFont: UIFont {
        if fontFamily == FontFamily.system.rawValue {
            return .systemFont(ofSize: fontSize)
        }
        return UIFont(name: fontFamily, size: fontSize) ?? .systemFont(ofSize: fontSize)
    }

    /// 每段一个 paragraph,段间距、行间距、段首两字缩进都和原来的 Text 一致。
    private func attributed(gap: CGFloat) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = gap
        // TextKit 换行本身就是一整行,和原来 VStack 里段与段之间的间距是同一个值。
        style.paragraphSpacing = 0
        style.alignment = .natural
        style.lineBreakMode = .byWordWrapping
        // 中文断行的避头尾交给系统,和之前 Text 用的是同一套。

        let font = uiFont


        let result = NSMutableAttributedString()
        var highlightRange: NSRange?
        for (index, fragment) in fragments.enumerated() {
            let body = fragment.indent ? "\u{3000}\u{3000}" + fragment.text : fragment.text
            let text = index == fragments.count - 1 ? body : body + "\n"
            let piece = NSMutableAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: UIColor(textColor),
                    .paragraphStyle: style
                ]
            )
            if let highlightedParagraph, highlightedParagraph == fragment.paragraphIndex {
                highlightRange = NSRange(location: result.length, length: piece.length)
            }
            result.append(piece)
        }
        if let highlightRange {
            result.addAttribute(
                .backgroundColor,
                value: UIColor(textColor).withAlphaComponent(0.12),
                range: highlightRange
            )
        }
        return result
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            // 工具条只留复制。
            var actions: [UIMenuElement] = []
            if let copy = suggestedActions.first(where: {
                let title = ($0 as? UIAction)?.title ?? ""
                return title == "复制" || title.lowercased() == "copy"
            }) {
                actions.append(copy)
            } else {
                actions.append(UIAction(title: "复制", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = (textView.text as NSString).substring(with: range)
                })
            }
            return UIMenu(children: actions)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard let page = textView as? PageUITextView else { return }
            page.onSelectionChanged?(page.selectedRange)
            page.watchSelectionEdge()
        }
    }
}

/// 只读但可选:原生选中、系统菜单、放大镜都保留,
/// 另外盯住手指在页面上下边缘的停留,用来跨页接着选。
final class PageUITextView: UITextView, UIGestureRecognizerDelegate {
    var pageFragments: [ReaderView.PageFragment] = []
    var onSelectionChanged: ((NSRange) -> Void)?
    var onEdgeHold: ((Bool) -> Void)?
    var highlightAll = false
    var desiredSelection: NSRange?
    var extraHighlight: NSRange?

    /// 单击:文本视图会把单击吃掉,外面 SwiftUI 的 onTapGesture 收不到,所以自己装一个识别器把位置传出去。
    var onScreenTap: ((CGPoint) -> Void)?

    private lazy var screenTapRecognizer: UITapGestureRecognizer = {
        let r = UITapGestureRecognizer(target: self, action: #selector(handleScreenTap(_:)))
        r.numberOfTapsRequired = 1
        r.cancelsTouchesInView = false
        r.delegate = self
        return r
    }()

    private let edgeZone: CGFloat = 24
    private let holdDuration: TimeInterval = 0.45
    private var edgeTimer: Timer?
    private var firedForThisDrag = false

    /// 尺寸完全交给外面的 SwiftUI frame 决定,不要按文字内容自己撑宽。
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    deinit { edgeTimer?.invalidate() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, screenTapRecognizer.view == nil {
            addGestureRecognizer(screenTapRecognizer)
        }
    }

    @objc private func handleScreenTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        guard selectedRange.length == 0 else { return }
        let inView = recognizer.location(in: self)
        guard let window else { return }
        let inWindow = convert(inView, to: window)
        onScreenTap?(window.convert(inWindow, to: window.screen.coordinateSpace))
    }

    /// 不去抢文本视图自己的手势:盯选中变化。手柄拖到上下 24 点内停住 0.45 秒就翻页。
    func watchSelectionEdge() {
        guard selectedRange.length > 0 else {
            cancelEdgeTimer()
            return
        }
        guard let side = edgeSideForSelection() else {
            cancelEdgeTimer()
            return
        }
        guard !firedForThisDrag else { return }
        if edgeTimer == nil {
            edgeTimer = Timer.scheduledTimer(withTimeInterval: holdDuration, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.edgeTimer = nil
                guard self.edgeSideForSelection() != nil else { return }
                self.firedForThisDrag = true
                self.onEdgeHold?(side)
            }
        }
    }

    private func edgeSideForSelection() -> Bool? {
        let end = selectedRange.location + selectedRange.length
        guard end > 0 else { return nil }
        guard let endPosition = position(from: beginningOfDocument, offset: end) else { return nil }
        let caret = caretRect(for: endPosition)
        let y = caret.minY
        if y <= edgeZone { return true }
        if y >= bounds.height - edgeZone { return false }
        return nil
    }

    func cancelEdgeTimer() {
        edgeTimer?.invalidate()
        edgeTimer = nil
        firedForThisDrag = false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(copy(_:)) { return super.canPerformAction(action, withSender: sender) }
        return false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        textContainer.size = CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
    }

    /// 把「整页选中 / 局部高亮 / 指定选区」画到这一页上。
    func applyHighlightState() {
        guard let store = attributedText.mutableCopy() as? NSMutableAttributedString else { return }
        let full = NSRange(location: 0, length: store.length)
        store.removeAttribute(.backgroundColor, range: full)
        if highlightAll, store.length > 0 {
            store.addAttribute(
                .backgroundColor,
                value: tintColor.withAlphaComponent(0.18),
                range: full
            )
        } else if let extraHighlight, extraHighlight.location + extraHighlight.length <= store.length {
            store.addAttribute(
                .backgroundColor,
                value: tintColor.withAlphaComponent(0.18),
                range: extraHighlight
            )
        }
        if store.isEqual(to: attributedText) == false {
            let hadFocus = isFirstResponder
            attributedText = store
            if hadFocus { becomeFirstResponder() }
        }
        if let desiredSelection, desiredSelection.location + desiredSelection.length <= store.length,
           selectedRange != desiredSelection {
            selectedRange = desiredSelection
            onSelectionChanged?(desiredSelection)
        } else if highlightAll, store.length > 0 {
            selectedRange = full
        }
    }


}
