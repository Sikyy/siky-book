import Foundation

enum ChapterCacheRetention: String, Sendable {
    case automatic
    case userManaged
}

struct CachedChapterContent: Sendable, Equatable {
    let content: String
    let retention: ChapterCacheRetention
}

enum ChapterContentStoreOutcome: Sendable, Equatable {
    case stored(retention: ChapterCacheRetention, evictedAutomaticCount: Int)
    case alreadyUserManaged
    case skippedTooLarge

    var isStored: Bool {
        switch self {
        case .stored, .alreadyUserManaged: true
        case .skippedTooLarge: false
        }
    }

    var effectiveRetention: ChapterCacheRetention {
        switch self {
        case .alreadyUserManaged: .userManaged
        case .stored(let retention, _): retention
        case .skippedTooLarge: .automatic
        }
    }
}

struct ChapterCacheStatistics: Sendable, Equatable {
    let automaticBytes: Int64
    let automaticCount: Int
    let userManagedBytes: Int64
    let userManagedCount: Int

    var totalBytes: Int64 { automaticBytes + userManagedBytes }
    var totalCount: Int { automaticCount + userManagedCount }
}

struct ChapterCacheTrimOutcome: Sendable, Equatable {
    let removedCount: Int
    let removedBytes: Int64
    let remainingBytes: Int64
}

/// Captures the current book generation plus the global chapter-invalidation
/// clock. Book clears reject every older token; a single-chapter replacement
/// rejects older work only for that chapter without cancelling the rest of a
/// whole-book download run.
struct ChapterContentWriteToken: Sendable, Equatable {
    fileprivate let bookID: UUID
    fileprivate let bookRevision: UInt64
    fileprivate let issuedChapterRevision: UInt64
}

/// Result of a single-chapter source replacement. `outcome == nil` means the
/// cache directory was temporarily unavailable and the caller should retain
/// the replacement body in SwiftData as a durable fallback.
struct ChapterContentReplacement: Sendable, Equatable {
    let outcome: ChapterContentStoreOutcome?
    let retention: ChapterCacheRetention
    let writeToken: ChapterContentWriteToken
}

/// Disk-backed storage for remote chapter bodies.
///
/// Existing `v1/<book>/<chapter>.txt` files and explicit downloads are protected as
/// user-managed cache. Reading and prefetch use a bounded `.automatic` LRU tier.
actor ChapterContentStore {
    static let shared = ChapterContentStore()

    static let defaultAutomaticHighWaterBytes: Int64 = 256 * 1024 * 1024
    static let defaultAutomaticLowWaterBytes: Int64 = 224 * 1024 * 1024

    private struct FileEntry: Equatable {
        let url: URL
        let size: Int64
        let modificationDate: Date
    }

    private struct BookIndex {
        var entries: [UUID: FileEntry]
        var directoryModificationDate: Date?
        var isComplete: Bool
    }

    private struct RetentionIndex {
        var books: [UUID: BookIndex] = [:]
        var totalBytes: Int64 = 0
        var totalCount: Int = 0
        var isFullyLoaded = false
    }

    private struct IndexedFile {
        let bookID: UUID
        let chapterID: UUID
        let entry: FileEntry
    }

    private let rootDirectory: URL
    private let fileManager: FileManager
    private let automaticHighWaterBytes: Int64
    private let automaticLowWaterBytes: Int64
    private let now: @Sendable () -> Date
    private var automaticIndex = RetentionIndex()
    private var userManagedIndex = RetentionIndex()
    private var bookWriteRevisions: [UUID: UInt64] = [:]
    private var chapterWriteRevisionClock: UInt64 = 0
    private var chapterWriteRevisions: [UUID: [UUID: UInt64]] = [:]

    init(
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default,
        automaticHighWaterBytes: Int64 = ChapterContentStore.defaultAutomaticHighWaterBytes,
        automaticLowWaterBytes: Int64 = ChapterContentStore.defaultAutomaticLowWaterBytes,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileManager = fileManager
        self.automaticHighWaterBytes = max(0, automaticHighWaterBytes)
        self.automaticLowWaterBytes = min(
            max(0, automaticLowWaterBytes),
            max(0, automaticHighWaterBytes)
        )
        self.now = now
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory
            self.rootDirectory = applicationSupport
                .appendingPathComponent("YiYue", isDirectory: true)
                .appendingPathComponent("ChapterContent", isDirectory: true)
                .appendingPathComponent("v1", isDirectory: true)
        }
    }

    func load(bookID: UUID, chapterID: UUID) -> CachedChapterContent? {
        guard !Task.isCancelled else { return nil }
        let signposter = PerformanceSignposts.cache
        let signpostID = signposter.makeSignpostID()
        var result = "miss"
        var byteCount = 0
        let intervalState = signposter.beginInterval("ContentDiskRead", id: signpostID)
        defer {
            signposter.endInterval(
                "ContentDiskRead",
                intervalState,
                "result=\(result, privacy: .public) bytes=\(byteCount)"
            )
        }

        for retention in [ChapterCacheRetention.userManaged, .automatic] {
            guard !Task.isCancelled else { return nil }
            let url = fileURL(bookID: bookID, chapterID: chapterID, retention: retention)
            guard fileManager.fileExists(atPath: url.path) else {
                removeIndexedEntry(
                    bookID: bookID,
                    chapterID: chapterID,
                    retention: retention
                )
                continue
            }
            do {
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                guard let content = String(data: data, encoding: .utf8),
                      SourceEngine.isValidContent(content) else {
                    if retention == .automatic {
                        try? fileManager.removeItem(at: url)
                    }
                    removeIndexedEntry(
                        bookID: bookID,
                        chapterID: chapterID,
                        retention: retention
                    )
                    result = "invalid"
                    continue
                }
                if retention == .automatic {
                    try? fileManager.setAttributes(
                        [.modificationDate: now()],
                        ofItemAtPath: url.path
                    )
                }
                upsertIndexedEntry(
                    FileEntry(
                        url: url,
                        size: Int64(data.count),
                        modificationDate: fileModificationDate(at: url) ?? .distantPast
                    ),
                    bookID: bookID,
                    chapterID: chapterID,
                    retention: retention
                )
                result = retention == .userManaged ? "userManaged" : "automatic"
                byteCount = data.count
                return CachedChapterContent(content: content, retention: retention)
            } catch {
                if retention == .automatic {
                    try? fileManager.removeItem(at: url)
                }
                removeIndexedEntry(
                    bookID: bookID,
                    chapterID: chapterID,
                    retention: retention
                )
                result = "ioError"
            }
        }
        return nil
    }

    func makeWriteToken(bookID: UUID) -> ChapterContentWriteToken {
        ChapterContentWriteToken(
            bookID: bookID,
            bookRevision: bookWriteRevisions[bookID, default: 0],
            issuedChapterRevision: chapterWriteRevisionClock
        )
    }

    func isWriteTokenCurrent(
        _ token: ChapterContentWriteToken,
        bookID: UUID,
        chapterID: UUID
    ) -> Bool {
        guard token.bookID == bookID,
              token.bookRevision == bookWriteRevisions[bookID, default: 0] else {
            return false
        }
        let invalidatedAt = chapterWriteRevisions[bookID]?[chapterID] ?? 0
        return token.issuedChapterRevision >= invalidatedAt
    }

    @discardableResult
    func store(
        _ content: String,
        bookID: UUID,
        chapterID: UUID,
        retention: ChapterCacheRetention,
        writeToken: ChapterContentWriteToken? = nil
    ) throws -> ChapterContentStoreOutcome {
        try Task.checkCancellation()
        try validateWriteToken(writeToken, bookID: bookID, chapterID: chapterID)
        guard SourceEngine.isValidContent(content) else {
            throw ChapterContentStoreError.invalidContent
        }
        guard let data = content.data(using: .utf8) else {
            throw ChapterContentStoreError.encodingFailed
        }

        let signposter = PerformanceSignposts.cache
        let signpostID = signposter.makeSignpostID()
        var result = "error"
        var evictedCount = 0
        let intervalState = signposter.beginInterval(
            "ContentDiskWrite",
            id: signpostID,
            "bytes=\(data.count) tier=\(retention.rawValue, privacy: .public)"
        )
        defer {
            signposter.endInterval(
                "ContentDiskWrite",
                intervalState,
                "result=\(result, privacy: .public) evicted=\(evictedCount)"
            )
        }

        let userManagedURL = fileURL(
            bookID: bookID,
            chapterID: chapterID,
            retention: .userManaged
        )
        if retention == .automatic {
            if let userManagedEntry = validatedFileEntry(at: userManagedURL) {
                upsertIndexedEntry(
                    userManagedEntry,
                    bookID: bookID,
                    chapterID: chapterID,
                    retention: .userManaged
                )
                result = "alreadyUserManaged"
                return .alreadyUserManaged
            }
            removeIndexedEntry(
                bookID: bookID,
                chapterID: chapterID,
                retention: .userManaged
            )
        }
        if retention == .automatic, Int64(data.count) > automaticHighWaterBytes {
            result = "skippedTooLarge"
            return .skippedTooLarge
        }

        let destination = fileURL(bookID: bookID, chapterID: chapterID, retention: retention)
        if retention == .automatic {
            try ensureFullyIndexed(retention: .automatic)
        }
        try Task.checkCancellation()
        try validateWriteToken(writeToken, bookID: bookID, chapterID: chapterID)
        try ensureDirectory(destination.deletingLastPathComponent())
        try data.write(to: destination, options: .atomic)
        if retention == .automatic {
            try? fileManager.setAttributes(
                [.modificationDate: now()],
                ofItemAtPath: destination.path
            )
        }
        upsertIndexedEntry(
            FileEntry(
                url: destination,
                size: Int64(data.count),
                modificationDate: fileModificationDate(at: destination) ?? .distantPast
            ),
            bookID: bookID,
            chapterID: chapterID,
            retention: retention
        )

        if retention == .userManaged {
            let automaticURL = fileURL(bookID: bookID, chapterID: chapterID, retention: .automatic)
            if fileManager.fileExists(atPath: automaticURL.path) {
                do {
                    try fileManager.removeItem(at: automaticURL)
                    removeIndexedEntry(
                        bookID: bookID,
                        chapterID: chapterID,
                        retention: .automatic
                    )
                } catch {
                    // The protected copy is already durable. Preserve the automatic
                    // index entry when cleanup fails so statistics still match disk.
                }
            }
        } else {
            if automaticIndex.totalBytes > automaticHighWaterBytes {
                let trim = try trimAutomaticCache(to: automaticLowWaterBytes)
                evictedCount = trim.removedCount
            }
        }

        result = "success"
        return .stored(retention: retention, evictedAutomaticCount: evictedCount)
    }

    /// Atomically invalidates older writes for one chapter and replaces its
    /// durable body. The caller's token still protects against a book clear or
    /// a newer replacement that happened while alternative content was fetched.
    @discardableResult
    func replace(
        _ content: String,
        bookID: UUID,
        chapterID: UUID,
        retention: ChapterCacheRetention,
        writeToken: ChapterContentWriteToken
    ) throws -> ChapterContentReplacement {
        try Task.checkCancellation()
        try validateWriteToken(writeToken, bookID: bookID, chapterID: chapterID)
        guard SourceEngine.isValidContent(content) else {
            throw ChapterContentStoreError.invalidContent
        }
        guard content.data(using: .utf8) != nil else {
            throw ChapterContentStoreError.encodingFailed
        }

        // Never downgrade an explicitly cached chapter. This check also covers
        // a user-managed write that completed while the alternative source was
        // being fetched.
        let userManagedURL = fileURL(
            bookID: bookID,
            chapterID: chapterID,
            retention: .userManaged
        )
        let replacementRetention: ChapterCacheRetention = retention == .userManaged
            || fileManager.fileExists(atPath: userManagedURL.path)
            ? .userManaged
            : .automatic

        invalidateWrites(bookID: bookID, chapterID: chapterID)
        let replacementToken = makeWriteToken(bookID: bookID)
        do {
            let outcome = try store(
                content,
                bookID: bookID,
                chapterID: chapterID,
                retention: replacementRetention,
                writeToken: replacementToken
            )
            if case .skippedTooLarge = outcome {
                // Do not leave the old source body discoverable after a
                // successful logical replacement that must use SwiftData.
                let oldAutomaticURL = fileURL(
                    bookID: bookID,
                    chapterID: chapterID,
                    retention: .automatic
                )
                if fileManager.fileExists(atPath: oldAutomaticURL.path) {
                    try? fileManager.removeItem(at: oldAutomaticURL)
                }
                removeIndexedEntry(
                    bookID: bookID,
                    chapterID: chapterID,
                    retention: .automatic
                )
            }
            return ChapterContentReplacement(
                outcome: outcome,
                retention: replacementRetention,
                writeToken: replacementToken
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch ChapterContentStoreError.staleWrite {
            throw ChapterContentStoreError.staleWrite
        } catch {
            return ChapterContentReplacement(
                outcome: nil,
                retention: replacementRetention,
                writeToken: replacementToken
            )
        }
    }

    /// Moves an automatic entry to the protected tier without another network request.
    func promote(
        bookID: UUID,
        chapterID: UUID,
        writeToken: ChapterContentWriteToken? = nil
    ) throws -> Bool {
        try Task.checkCancellation()
        try validateWriteToken(writeToken, bookID: bookID, chapterID: chapterID)
        let userURL = fileURL(bookID: bookID, chapterID: chapterID, retention: .userManaged)
        if !fileManager.fileExists(atPath: userURL.path) {
            removeIndexedEntry(
                bookID: bookID,
                chapterID: chapterID,
                retention: .userManaged
            )
        }
        if fileManager.fileExists(atPath: userURL.path),
           let cached = load(bookID: bookID, chapterID: chapterID),
           cached.retention == .userManaged {
            return true
        }

        let automaticURL = fileURL(bookID: bookID, chapterID: chapterID, retention: .automatic)
        guard fileManager.fileExists(atPath: automaticURL.path) else {
            removeIndexedEntry(
                bookID: bookID,
                chapterID: chapterID,
                retention: .automatic
            )
            return false
        }
        guard let cached = load(bookID: bookID, chapterID: chapterID),
              cached.retention == .automatic else { return false }
        try Task.checkCancellation()
        try validateWriteToken(writeToken, bookID: bookID, chapterID: chapterID)
        try ensureDirectory(userURL.deletingLastPathComponent())
        do {
            if fileManager.fileExists(atPath: userURL.path) {
                let data = try Data(contentsOf: automaticURL, options: [.mappedIfSafe])
                try data.write(to: userURL, options: .atomic)
                try fileManager.removeItem(at: automaticURL)
            } else {
                try fileManager.moveItem(at: automaticURL, to: userURL)
            }
            removeIndexedEntry(
                bookID: bookID,
                chapterID: chapterID,
                retention: .automatic
            )
            if let entry = validatedFileEntry(at: userURL) {
                upsertIndexedEntry(
                    entry,
                    bookID: bookID,
                    chapterID: chapterID,
                    retention: .userManaged
                )
            } else {
                removeIndexedEntry(
                    bookID: bookID,
                    chapterID: chapterID,
                    retention: .userManaged
                )
            }
            return true
        } catch {
            // Leave the automatic source untouched when promotion cannot be completed.
            throw error
        }
    }

    func contains(
        bookID: UUID,
        chapterID: UUID,
        retention: ChapterCacheRetention? = nil
    ) -> Bool {
        if let retention {
            return fileManager.fileExists(
                atPath: fileURL(bookID: bookID, chapterID: chapterID, retention: retention).path
            )
        }
        return contains(bookID: bookID, chapterID: chapterID, retention: .userManaged)
            || contains(bookID: bookID, chapterID: chapterID, retention: .automatic)
    }

    func remove(bookID: UUID, chapterID: UUID) throws {
        invalidateWrites(bookID: bookID, chapterID: chapterID)
        for retention in [ChapterCacheRetention.userManaged, .automatic] {
            let url = fileURL(bookID: bookID, chapterID: chapterID, retention: retention)
            guard fileManager.fileExists(atPath: url.path) else {
                removeIndexedEntry(
                    bookID: bookID,
                    chapterID: chapterID,
                    retention: retention
                )
                continue
            }
            try fileManager.removeItem(at: url)
            removeIndexedEntry(
                bookID: bookID,
                chapterID: chapterID,
                retention: retention
            )
        }
    }

    func removeBook(_ bookID: UUID) throws {
        invalidateWrites(bookID: bookID)
        for retention in [ChapterCacheRetention.userManaged, .automatic] {
            let directory = bookDirectory(bookID, retention: retention)
            guard fileManager.fileExists(atPath: directory.path) else {
                removeIndexedBook(bookID, retention: retention)
                continue
            }
            try fileManager.removeItem(at: directory)
            removeIndexedBook(bookID, retention: retention)
        }
    }

    func storedChapterIDs(
        bookID: UUID,
        retention: ChapterCacheRetention
    ) throws -> Set<UUID> {
        try Task.checkCancellation()
        if let bookIndex = index(for: retention).books[bookID],
           bookIndex.isComplete,
           !bookIndexNeedsRescan(
                bookIndex,
                bookID: bookID,
                retention: retention
           ) {
            return Set(bookIndex.entries.keys)
        }
        let bookIndex = try scanBook(bookID: bookID, retention: retention)
        replaceIndexedBook(bookIndex, bookID: bookID, retention: retention)
        return Set(bookIndex?.entries.keys.map { $0 } ?? [])
    }

    func statistics() throws -> ChapterCacheStatistics {
        try Task.checkCancellation()
        try synchronizeIndexWithDisk(retention: .automatic)
        try Task.checkCancellation()
        try synchronizeIndexWithDisk(retention: .userManaged)
        return ChapterCacheStatistics(
            automaticBytes: automaticIndex.totalBytes,
            automaticCount: automaticIndex.totalCount,
            userManagedBytes: userManagedIndex.totalBytes,
            userManagedCount: userManagedIndex.totalCount
        )
    }

    @discardableResult
    func trimAutomaticCache() throws -> ChapterCacheTrimOutcome {
        try trimAutomaticCache(to: automaticLowWaterBytes)
    }

    @discardableResult
    func clearAutomaticCache() throws -> ChapterCacheTrimOutcome {
        try trimAutomaticCache(to: 0)
    }

    func removeOrphanedBooks(validBookIDs: Set<UUID>) throws {
        try removeOrphans(retention: .userManaged, validBookIDs: validBookIDs)
        try removeOrphans(retention: .automatic, validBookIDs: validBookIDs)
    }

    private var automaticRootDirectory: URL {
        rootDirectory.appendingPathComponent(".automatic", isDirectory: true)
    }

    private func bookDirectory(_ bookID: UUID, retention: ChapterCacheRetention) -> URL {
        let base = retention == .userManaged ? rootDirectory : automaticRootDirectory
        return base.appendingPathComponent(bookID.uuidString.lowercased(), isDirectory: true)
    }

    private func fileURL(
        bookID: UUID,
        chapterID: UUID,
        retention: ChapterCacheRetention
    ) -> URL {
        bookDirectory(bookID, retention: retention)
            .appendingPathComponent(chapterID.uuidString.lowercased())
            .appendingPathExtension("txt")
    }

    private func ensureDirectory(_ directory: URL) throws {
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableRoot = rootDirectory
        try? mutableRoot.setResourceValues(values)
    }

    private func validateWriteToken(
        _ token: ChapterContentWriteToken?,
        bookID: UUID,
        chapterID: UUID
    ) throws {
        guard let token else { return }
        guard isWriteTokenCurrent(
            token,
            bookID: bookID,
            chapterID: chapterID
        ) else {
            throw ChapterContentStoreError.staleWrite
        }
    }

    private func invalidateWrites(bookID: UUID) {
        bookWriteRevisions[bookID, default: 0] &+= 1
        chapterWriteRevisions.removeValue(forKey: bookID)
    }

    private func invalidateWrites(bookID: UUID, chapterID: UUID) {
        chapterWriteRevisionClock &+= 1
        chapterWriteRevisions[bookID, default: [:]][chapterID] = chapterWriteRevisionClock
    }

    private func trimAutomaticCache(to targetBytes: Int64) throws -> ChapterCacheTrimOutcome {
        try synchronizeIndexWithDisk(retention: .automatic)
        let sorted = indexedFiles(retention: .automatic)
            .sorted { $0.entry.modificationDate < $1.entry.modificationDate }
        var removedBytes: Int64 = 0
        var removedCount = 0
        for indexedFile in sorted where automaticIndex.totalBytes > targetBytes {
            if fileManager.fileExists(atPath: indexedFile.entry.url.path) {
                try fileManager.removeItem(at: indexedFile.entry.url)
                removedBytes += indexedFile.entry.size
                removedCount += 1
            }
            removeIndexedEntry(
                bookID: indexedFile.bookID,
                chapterID: indexedFile.chapterID,
                retention: .automatic
            )
        }
        return ChapterCacheTrimOutcome(
            removedCount: removedCount,
            removedBytes: removedBytes,
            remainingBytes: automaticIndex.totalBytes
        )
    }

    private func removeOrphans(
        retention: ChapterCacheRetention,
        validBookIDs: Set<UUID>
    ) throws {
        let directory = retention == .userManaged ? rootDirectory : automaticRootDirectory
        guard fileManager.fileExists(atPath: directory.path) else {
            for bookID in index(for: retention).books.keys {
                removeIndexedBook(bookID, retention: retention)
            }
            return
        }
        let entries = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        for entry in entries {
            if retention == .userManaged, entry.lastPathComponent == ".automatic" { continue }
            guard let bookID = UUID(uuidString: entry.lastPathComponent),
                  !validBookIDs.contains(bookID) else { continue }
            invalidateWrites(bookID: bookID)
            try fileManager.removeItem(at: entry)
            removeIndexedBook(bookID, retention: retention)
        }

        let indexedBookIDs = Set(index(for: retention).books.keys)
        for bookID in indexedBookIDs {
            guard !fileManager.fileExists(
                atPath: bookDirectory(bookID, retention: retention).path
            ) else { continue }
            removeIndexedBook(bookID, retention: retention)
        }
    }

    private func ensureFullyIndexed(retention: ChapterCacheRetention) throws {
        guard !index(for: retention).isFullyLoaded else { return }
        let bookIDs = try diskBookIDs(retention: retention)
        var newIndex = RetentionIndex()
        for bookID in bookIDs {
            try Task.checkCancellation()
            guard let bookIndex = try scanBook(bookID: bookID, retention: retention) else {
                continue
            }
            newIndex.books[bookID] = bookIndex
            newIndex.totalBytes += bookIndex.entries.values.reduce(0) { $0 + $1.size }
            newIndex.totalCount += bookIndex.entries.count
        }
        newIndex.isFullyLoaded = true
        setIndex(newIndex, for: retention)
    }

    /// Keeps the index cheap during normal actor-owned writes, while still detecting
    /// files that were added, removed, or replaced outside this actor before reporting
    /// aggregate statistics or trimming the automatic tier.
    private func synchronizeIndexWithDisk(retention: ChapterCacheRetention) throws {
        try ensureFullyIndexed(retention: retention)

        let bookIDs = try diskBookIDs(retention: retention)
        let indexedBookIDs = Set(index(for: retention).books.keys)
        for removedBookID in indexedBookIDs.subtracting(bookIDs) {
            removeIndexedBook(removedBookID, retention: retention)
        }

        for bookID in bookIDs {
            try Task.checkCancellation()
            let currentBookIndex = index(for: retention).books[bookID]
            if currentBookIndex == nil
                || currentBookIndex?.isComplete == false
                || bookIndexNeedsRescan(
                    currentBookIndex,
                    bookID: bookID,
                    retention: retention
                ) {
                let rescanned = try scanBook(bookID: bookID, retention: retention)
                replaceIndexedBook(rescanned, bookID: bookID, retention: retention)
            }
        }
    }

    private func diskBookIDs(retention: ChapterCacheRetention) throws -> Set<UUID> {
        let directory = retention == .userManaged ? rootDirectory : automaticRootDirectory
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let entries = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return Set(entries.compactMap { entry in
            if retention == .userManaged, entry.lastPathComponent == ".automatic" {
                return nil
            }
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { return nil }
            return UUID(uuidString: entry.lastPathComponent)
        })
    }

    private func scanBook(
        bookID: UUID,
        retention: ChapterCacheRetention
    ) throws -> BookIndex? {
        let directory = bookDirectory(bookID, retention: retention)
        guard fileManager.fileExists(atPath: directory.path) else { return nil }
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var entries: [UUID: FileEntry] = [:]
        for (offset, file) in files.enumerated() where file.pathExtension.lowercased() == "txt" {
            if offset.isMultiple(of: 50) {
                try Task.checkCancellation()
            }
            guard let chapterID = UUID(
                uuidString: file.deletingPathExtension().lastPathComponent
            ) else {
                if retention == .automatic {
                    try? fileManager.removeItem(at: file)
                }
                continue
            }
            guard let entry = validatedFileEntry(at: file) else {
                if retention == .automatic {
                    try? fileManager.removeItem(at: file)
                }
                continue
            }
            entries[chapterID] = entry
        }
        return BookIndex(
            entries: entries,
            directoryModificationDate: directoryModificationDate(at: directory),
            isComplete: true
        )
    }

    private func validatedFileEntry(at url: URL) -> FileEntry? {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let content = String(data: data, encoding: .utf8),
              SourceEngine.isValidContent(content) else { return nil }
        return FileEntry(
            url: url,
            size: Int64(data.count),
            modificationDate: fileModificationDate(at: url) ?? .distantPast
        )
    }

    private func fileModificationDate(at url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func directoryModificationDate(at url: URL) -> Date? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? url.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate
    }

    private func bookIndexNeedsRescan(
        _ bookIndex: BookIndex?,
        bookID: UUID,
        retention: ChapterCacheRetention
    ) -> Bool {
        guard let bookIndex else { return true }
        let directory = bookDirectory(bookID, retention: retention)
        // Every app-owned mutation flows through this actor and updates the
        // index directly. For out-of-process changes, adding, removing, or
        // atomically replacing a file advances the parent directory mtime.
        // Trusting that single value keeps a warm `storedChapterIDs` lookup
        // O(1) instead of issuing one filesystem stat per cached chapter.
        // A changed directory still takes the full validating scan below, and
        // `load` independently validates the requested file before returning it.
        return directoryModificationDate(at: directory) != bookIndex.directoryModificationDate
    }

    private func index(for retention: ChapterCacheRetention) -> RetentionIndex {
        switch retention {
        case .automatic: return automaticIndex
        case .userManaged: return userManagedIndex
        }
    }

    private func setIndex(_ index: RetentionIndex, for retention: ChapterCacheRetention) {
        switch retention {
        case .automatic: automaticIndex = index
        case .userManaged: userManagedIndex = index
        }
    }

    private func updateIndex(
        for retention: ChapterCacheRetention,
        _ update: (inout RetentionIndex) -> Void
    ) {
        switch retention {
        case .automatic: update(&automaticIndex)
        case .userManaged: update(&userManagedIndex)
        }
    }

    private func upsertIndexedEntry(
        _ entry: FileEntry,
        bookID: UUID,
        chapterID: UUID,
        retention: ChapterCacheRetention
    ) {
        let directoryDate = directoryModificationDate(
            at: bookDirectory(bookID, retention: retention)
        )
        updateIndex(for: retention) { index in
            var bookIndex = index.books[bookID] ?? BookIndex(
                entries: [:],
                directoryModificationDate: directoryDate,
                isComplete: false
            )
            if let previous = bookIndex.entries.updateValue(entry, forKey: chapterID) {
                index.totalBytes -= previous.size
            } else {
                index.totalCount += 1
            }
            index.totalBytes += entry.size
            bookIndex.directoryModificationDate = directoryDate
            index.books[bookID] = bookIndex
        }
    }

    private func removeIndexedEntry(
        bookID: UUID,
        chapterID: UUID,
        retention: ChapterCacheRetention
    ) {
        let directory = bookDirectory(bookID, retention: retention)
        let directoryDate = directoryModificationDate(at: directory)
        let directoryExists = fileManager.fileExists(atPath: directory.path)
        updateIndex(for: retention) { index in
            guard var bookIndex = index.books[bookID] else { return }
            if let previous = bookIndex.entries.removeValue(forKey: chapterID) {
                index.totalBytes -= previous.size
                index.totalCount -= 1
            }
            bookIndex.directoryModificationDate = directoryDate
            if !directoryExists, bookIndex.entries.isEmpty {
                index.books.removeValue(forKey: bookID)
            } else {
                index.books[bookID] = bookIndex
            }
        }
    }

    private func replaceIndexedBook(
        _ replacement: BookIndex?,
        bookID: UUID,
        retention: ChapterCacheRetention
    ) {
        updateIndex(for: retention) { index in
            if let previous = index.books.removeValue(forKey: bookID) {
                index.totalBytes -= previous.entries.values.reduce(0) { $0 + $1.size }
                index.totalCount -= previous.entries.count
            }
            if let replacement {
                index.books[bookID] = replacement
                index.totalBytes += replacement.entries.values.reduce(0) { $0 + $1.size }
                index.totalCount += replacement.entries.count
            }
        }
    }

    private func removeIndexedBook(
        _ bookID: UUID,
        retention: ChapterCacheRetention
    ) {
        replaceIndexedBook(nil, bookID: bookID, retention: retention)
    }

    private func indexedFiles(retention: ChapterCacheRetention) -> [IndexedFile] {
        index(for: retention).books.flatMap { bookID, bookIndex in
            bookIndex.entries.map { chapterID, entry in
                IndexedFile(bookID: bookID, chapterID: chapterID, entry: entry)
            }
        }
    }
}

enum ChapterContentStoreError: Error {
    case invalidContent
    case encodingFailed
    case staleWrite
}
