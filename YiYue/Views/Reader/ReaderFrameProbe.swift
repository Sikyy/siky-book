import SwiftUI
import UIKit

/// 临时的帧率探针:用 CADisplayLink 记录真实的帧间隔,
/// 面板滑入这类一次性的动画,判定标准是「最长一帧」和「超过 33ms 的帧数」。
/// 只给性能排查用,排查完删掉。
@MainActor
final class ReaderFrameProbe: ObservableObject {
    static let shared = ReaderFrameProbe()

    /// 最近 5 秒里最长的一帧(毫秒)。
    @Published private(set) var worstFrameMs: Double = 0
    /// 最近 5 秒里超过 33ms 的帧数。
    @Published private(set) var slowFrames: Int = 0
    /// 最近 5 秒里的帧数。
    @Published private(set) var frameCount: Int = 0
    /// ReaderView.body 的求值次数(最近 5 秒)。
    @Published private(set) var bodyCount: Int = 0

    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var windowStart: CFTimeInterval = 0
    private var bodies = 0

    private init() {}

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        windowStart = CACurrentMediaTime()
    }

    func noteBodyEvaluation() {
        bodies += 1
    }

    /// 手动归零:开始一个动作之前调用,读到的就是这一个动作的数。
    func reset() {
        worstFrameMs = 0
        slowFrames = 0
        frameCount = 0
        bodyCount = 0
        bodies = 0
        windowStart = CACurrentMediaTime()
        lastTimestamp = 0
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { lastTimestamp = now }
        guard lastTimestamp > 0 else { return }
        let delta = (now - lastTimestamp) * 1000
        if delta > worstFrameMs { worstFrameMs = delta }
        if delta > 33 { slowFrames += 1 }
        frameCount += 1
        // 每 4 秒收一次窗口,避免数字一直挂着不动。
        if (CACurrentMediaTime() - windowStart) > 4, delta < 20 {
            worstFrameMs = 0
            slowFrames = 0
            frameCount = 0
            bodyCount = 0
            bodies = 0
            windowStart = CACurrentMediaTime()
        }
    }

    func flushBodyCount() {
        bodyCount = bodies
    }
}

/// 屏幕上那三行小字。
struct ReaderPerfHUD: View {
    @ObservedObject var probe: ReaderFrameProbe

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(String(format: "worst %.0fms", probe.worstFrameMs))
            Text("slow \(probe.slowFrames) fr \(probe.frameCount)")
            Text("body \(probe.bodyCount)")
        }
        .font(.system(size: 9, design: .monospaced))
        .foregroundStyle(.red)
        .padding(3)
        .background(.white.opacity(0.75))
        .allowsHitTesting(false)
    }
}
