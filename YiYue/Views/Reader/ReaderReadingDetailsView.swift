import SwiftUI

/// 阅读明细只放真有的数:没有数据的行整行不显示,四项都空时只说一句。
struct ReaderReadingStats: Equatable {
    struct Row: Equatable, Identifiable {
        let title: String
        let value: String
        var id: String { title }
    }

    let readingDays: Int
    let pagesRead: Int
    let bookmarkCount: Int
    let finishedChapters: Int

    var isEmpty: Bool {
        readingDays <= 0 && pagesRead <= 0 && bookmarkCount <= 0 && finishedChapters <= 0
    }

    var rows: [Row] {
        var rows: [Row] = []
        if readingDays > 0 {
            rows.append(Row(title: "阅读天数", value: "\(readingDays) 天"))
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
