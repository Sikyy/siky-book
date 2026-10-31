import SwiftUI

/// 阅读明细只放真有的数:没有数据的行整行不显示,四项都空时只说一句。
struct ReaderReadingStats: Equatable {
    struct Row: Equatable, Identifiable {
        let title: String
        let value: String
        var id: String { title }
    }

    let readingDays: Int
    let readingTime: TimeInterval
    let pagesRead: Int
    let bookmarkCount: Int
    let finishedChapters: Int

    var isEmpty: Bool {
        readingDays <= 0 && readingTime < 1 && pagesRead <= 0 && bookmarkCount <= 0 && finishedChapters <= 0
    }

    var rows: [Row] {
        var rows: [Row] = []
        if readingDays > 0 {
            rows.append(Row(title: "阅读天数", value: "\(readingDays) 天"))
        }
        if readingTime >= 1 {
            rows.append(Row(title: "阅读时长", value: ReadingTimeFormat.spoken(readingTime)))
        }
        if pagesRead > 0 {
            rows.append(Row(title: "翻页", value: "\(pagesRead) 页"))
        }
        if bookmarkCount > 0 {
            rows.append(Row(title: "书签", value: "\(bookmarkCount) 条"))
        }
        if finishedChapters > 0 {
            rows.append(Row(title: "读完", value: "\(finishedChapters) 章"))
        }
        return rows
    }
}

/// 轻量阅读记录:按书记「读过哪几天」「翻了多少页」,只记本机,
/// 不新增 SwiftData 字段。没有历史时阅读明细不摆 0,直接不显示那一行。
enum ReaderActivityStore {
    private static func daysKey(_ bookID: UUID) -> String {
        "reader.activity.days.\(bookID.uuidString)"
    }

    private static func pagesKey(_ bookID: UUID) -> String {
        "reader.activity.pages.\(bookID.uuidString)"
    }

    private static func dayStamp(_ date: Date) -> String {
        let start = Calendar.current.startOfDay(for: date)
        return String(Int(start.timeIntervalSince1970))
    }

    static func recordReadingDay(
        bookID: UUID,
        date: Date = Date(),
        defaults: UserDefaults = .standard
    ) {
        let key = daysKey(bookID)
        var days = Set((defaults.string(forKey: key) ?? "").split(separator: ",").map(String.init))
        days.insert(dayStamp(date))
        defaults.set(days.sorted().joined(separator: ","), forKey: key)
    }

    static func readingDays(bookID: UUID, defaults: UserDefaults = .standard) -> Int {
        let raw = defaults.string(forKey: daysKey(bookID)) ?? ""
        return Set(raw.split(separator: ",").map(String.init)).count
    }

    static func recordPageFlip(bookID: UUID, defaults: UserDefaults = .standard) {
        let key = pagesKey(bookID)
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
    }

    static func pagesRead(bookID: UUID, defaults: UserDefaults = .standard) -> Int {
        max(0, defaults.integer(forKey: pagesKey(bookID)))
    }
}

struct ReaderReadingDetailsView: View {
    let stats: ReaderReadingStats
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("阅读明细")
                    .font(.system(size: 20, weight: .semibold))
                Spacer(minLength: 12)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 12)

            if stats.isEmpty {
                Text("这本书还没读几页")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            } else {
                ForEach(stats.rows) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.title)
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 16)
                        Text(row.value)
                            .font(.system(size: 15, weight: .medium))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 24)
                    .frame(height: 52)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.06))
                            .frame(height: 1)
                            .padding(.leading, 24)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.height(stats.isEmpty ? 220 : min(420, 100 + CGFloat(stats.rows.count) * 52))])
        .presentationDragIndicator(.visible)
    }
}

/// 章节位置用的字数:中文正文按可见字符算,分页硬换行与空白不算。
enum ReaderCharacterCount {
    static func count(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { partial, scalar in
            partial + (scalar.properties.isWhitespace ? 0 : 1)
        }
    }
}

/// 阅读时长按书累计,存 UserDefaults——和阅读明细一样不新增 SwiftData 字段,
/// 老库不用迁移,删了书也不留孤儿。
enum ReaderTimeStore {
    private static func key(_ bookID: UUID) -> String {
        "reader.time.seconds.\(bookID.uuidString)"
    }

    static func total(bookID: UUID, defaults: UserDefaults = .standard) -> TimeInterval {
        max(0, defaults.double(forKey: key(bookID)))
    }

    static func add(_ seconds: TimeInterval, bookID: UUID, defaults: UserDefaults = .standard) {
        guard seconds > 0 else { return }
        defaults.set(total(bookID: bookID, defaults: defaults) + seconds, forKey: key(bookID))
    }
}

/// 把秒数写成微信读书那种样子:数字大、单位小,满一小时才出现小时。
/// 不满一分钟不写 0,写「不到 1 分钟」。
enum ReadingTimeFormat {
    struct Piece: Equatable {
        let text: String
        /// 数字用主字号,单位用小一号。
        let isNumber: Bool
    }

    static func pieces(_ seconds: TimeInterval) -> [Piece] {
        let whole = Int(max(0, seconds))
        if whole < 60 {
            return [Piece(text: "不到", isNumber: false),
                    Piece(text: "1", isNumber: true),
                    Piece(text: "分钟", isNumber: false)]
        }
        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        if hours == 0 {
            return [Piece(text: "\(minutes)", isNumber: true),
                    Piece(text: "分钟", isNumber: false)]
        }
        if minutes == 0 {
            return [Piece(text: "\(hours)", isNumber: true),
                    Piece(text: "小时", isNumber: false)]
        }
        return [Piece(text: "\(hours)", isNumber: true),
                Piece(text: "小时", isNumber: false),
                Piece(text: "\(minutes)", isNumber: true),
                Piece(text: "分钟", isNumber: false)]
    }

    /// 读屏念完整的一句,数字和单位之间留空格。
    static func spoken(_ seconds: TimeInterval) -> String {
        let whole = Int(max(0, seconds))
        if whole < 60 { return "不到 1 分钟" }
        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        if hours == 0 { return "\(minutes) 分钟" }
        if minutes == 0 { return "\(hours) 小时" }
        return "\(hours) 小时 \(minutes) 分钟"
    }

    /// 按真实读速推「约 24 小时后读完」:用已读时长和已读进度反推剩余。
    /// 进度太小或时长太短时不给估计——那时候推出来的数没意义。
    static func remainingEstimate(progress: Double, seconds: TimeInterval) -> String? {
        let clamped = min(max(progress, 0), 1)
        if clamped >= 0.999 { return "已读完" }
        guard seconds >= 60, clamped >= 0.01 else { return nil }
        let remaining = seconds * (1 - clamped) / clamped
        let minutes = Int((remaining / 60).rounded())
        if minutes < 60 {
            return "约 \(max(1, minutes)) 分钟后读完"
        }
        let hours = Int((remaining / 3600).rounded())
        if hours < 48 {
            return "约 \(max(1, hours)) 小时后读完"
        }
        let days = Int((remaining / 86400).rounded())
        return "约 \(max(1, days)) 天后读完"
    }
}

/// 一次阅读页停留的走表:进页面起表,切后台停表,回前台接着走,
/// 退出时结算存进这本书。每分钟落一次盘,App 被系统杀掉最多丢一分钟。
/// 走表时每秒更新 live,菜单里的时长是真在走的数,不是上次落盘的旧数。
@MainActor
@Observable
final class ReadingTimeSession {
    /// 这本书已经落盘的秒数。
    private(set) var stored: TimeInterval = 0
    /// 本次还没落盘的部分(上次落盘到现在的)。
    private(set) var pending: TimeInterval = 0
    /// 当前这一段已经走了多久,每秒刷新一次。
    private(set) var live: TimeInterval = 0

    private var bookID: UUID?
    private var startedAt: Date?
    private var flushTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    var isRunning: Bool { startedAt != nil }

    /// 这本书此刻的时长:已落盘 + 未落盘 + 正在走的一段。
    func total(bookID: UUID) -> TimeInterval {
        guard self.bookID == bookID else { return ReaderTimeStore.total(bookID: bookID) }
        return stored + pending + live
    }

    func begin(bookID: UUID) {
        if self.bookID == bookID, isRunning { return }
        end()
        self.bookID = bookID
        stored = ReaderTimeStore.total(bookID: bookID)
        pending = 0
        live = 0
        resume()
    }

    func resume() {
        guard bookID != nil, startedAt == nil else { return }
        startedAt = Date()
        live = 0
        startTicking()
    }

    func pause() {
        guard let started = startedAt else { return }
        startedAt = nil
        pending += max(0, Date().timeIntervalSince(started))
        live = 0
        tickTask?.cancel()
        tickTask = nil
        flushTask?.cancel()
        flushTask = nil
        flush()
    }

    func end() {
        pause()
        bookID = nil
        stored = 0
        pending = 0
        live = 0
    }

    private func flush() {
        guard let bookID, pending >= 1 else { return }
        let whole = pending.rounded(.down)
        ReaderTimeStore.add(whole, bookID: bookID)
        stored += whole
        pending -= whole
    }

    /// 每秒把当前这一段的时间刷到 live,菜单里的时长跟着走。
    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            var secondsSinceFlush = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard let started = self.startedAt else { return }
                self.live = max(0, Date().timeIntervalSince(started))
                secondsSinceFlush += 1
                if secondsSinceFlush >= 60 {
                    secondsSinceFlush = 0
                    self.accumulateAndFlush()
                }
            }
        }
    }

    /// 走表中途落一次盘,表不停:把已走的一段记进 pending,起点挪到现在。
    private func accumulateAndFlush() {
        guard let started = startedAt else { return }
        let now = Date()
        pending += max(0, now.timeIntervalSince(started))
        startedAt = now
        live = 0
        flush()
    }
}
