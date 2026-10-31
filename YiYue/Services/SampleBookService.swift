import Foundation
import SwiftData

/// 内置示例书《红楼梦》前二十回(通行本,前八十回属庚辰本一路;不是程甲本)。。
///
/// 只在书架为空时导入一次;用户删掉以后记一个标记,不再自动塞回来。
/// 导入走 `ImportService` 的普通 TXT 路径,封面也放进 EPUB 导入用的
/// `Application Support/EPUBCovers` 目录,和用户自己导入的书完全一致。
@MainActor
enum SampleBookService {
    static let bookTitle = "红楼梦"
    static let bookAuthor = "曹雪芹"

    private static let bookIDKey = "sampleBook.id"
    private static let userDeletedKey = "sampleBook.userDeleted"

    /// 右上角角标靠它判断这本是不是示例书。
    static func isSample(_ book: Book) -> Bool {
        isSample(bookID: book.id)
    }

    static func isSample(bookID: UUID) -> Bool {
        UserDefaults.standard.string(forKey: bookIDKey) == bookID.uuidString
    }

    /// 删除成功后调用:清掉示例书 id 并记下「用户不想要它」。
    static func markUserDeleted() {
        UserDefaults.standard.set(true, forKey: userDeletedKey)
        UserDefaults.standard.removeObject(forKey: bookIDKey)
    }

    static func seedIfNeeded(modelContext: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: userDeletedKey) else { return }

        let existingCount = (try? modelContext.fetchCount(FetchDescriptor<Book>())) ?? 0
        guard existingCount == 0 else { return }

        // 已经成功导入过就不用再来一次(正常启动时上面已经有书,这里是兜底)。
        if let id = UserDefaults.standard.string(forKey: bookIDKey), UUID(uuidString: id) != nil {
            return
        }

        guard let url = Bundle.main.url(forResource: "SampleBook", withExtension: "txt") else {
            return
        }

        do {
            let book = try ImportService(modelContext: modelContext).importTXT(
                from: url,
                title: bookTitle
            )
            book.author = bookAuthor
            attachCover(to: book)
            try modelContext.save()
            UserDefaults.standard.set(book.id.uuidString, forKey: bookIDKey)
        } catch {
            // 示例书不该拦住正常启动;书架保持空态,用户仍可手动导入。
            print("示例书导入失败: \(error)")
        }
    }

    private static func attachCover(to book: Book) {
        guard let source = Bundle.main.url(forResource: "SampleBookCover", withExtension: "png"),
              let directory = try? FileManager.default.url(
                  for: .applicationSupportDirectory,
                  in: .userDomainMask,
                  appropriateFor: nil,
                  create: true
              ).appendingPathComponent("EPUBCovers", isDirectory: true) else {
            return
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent("\(book.id.uuidString).img")
            let data = try Data(contentsOf: source)
            try data.write(to: destination, options: .atomic)
            book.coverURL = destination.absoluteString
        } catch {
            print("示例书封面写入失败: \(error)")
        }
    }
}
