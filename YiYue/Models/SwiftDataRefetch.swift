import Foundation
import SwiftData

/// iOS 27 resets the SwiftData main context when the scene goes to the
/// background. Every model instance a long-lived view still holds is destroyed
/// at that moment, and touching one traps with
/// "This model instance was destroyed by calling ModelContext.reset".
///
/// A view that sits on a model therefore has to swap in a fresh instance once
/// the scene is active again. These lookups go through a plain id, which stays
/// valid across the reset, so they are safe to call before anything is drawn.
enum SwiftDataRefetch {
    static func book(id: UUID, in context: ModelContext) -> Book? {
        let descriptor = FetchDescriptor<Book>(
            predicate: #Predicate<Book> { $0.id == id }
        )
        return try? context.fetch(descriptor).first
    }

    static func bookSource(id: UUID, in context: ModelContext) -> BookSource? {
        let descriptor = FetchDescriptor<BookSource>(
            predicate: #Predicate<BookSource> { $0.id == id }
        )
        return try? context.fetch(descriptor).first
    }

    static func readingMark(id: UUID, in context: ModelContext) -> ReadingMark? {
        let descriptor = FetchDescriptor<ReadingMark>(
            predicate: #Predicate<ReadingMark> { $0.id == id }
        )
        return try? context.fetch(descriptor).first
    }
}
