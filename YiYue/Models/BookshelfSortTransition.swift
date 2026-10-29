import CoreGraphics
import Foundation

/// Decides how the shelf animates the book that was just read back to the front.
///
/// The ordering itself already lives in `BookshelfItem.sortedByRecentRead`; this
/// type only answers "how does it move" so the answer can be unit-tested
/// without a running Grid. Durations and thresholds follow the design spec:
/// a book already on the first screen glides to the front, a book further down
/// is brought into view by scrolling to the top and popping it in.
enum BookshelfSortTransition {
    enum Mode: Equatable {
        /// The book was on the first screen: the grid carries it to the front.
        case reorderInPlace
        /// The book was further down: scroll to the top and let it pop in.
        case scrollAndPopIn
    }

    /// Nine cover slots cover the first screen of a phone grid (0.28 s of movement).
    static let firstScreenCapacity = 9
    static let reorderDuration: TimeInterval = 0.28
    static let scrollDuration: TimeInterval = 0.30
    /// The popped-in book shrinks from this scale back to 1 within this duration.
    static let popInDuration: TimeInterval = 0.45
    static let popInScale: CGFloat = 1.06
    /// Body-colour wash laid over the popped-in cover, faded out over the same time.
    static let popInTint: Double = 0.08
    /// The same book is highlighted at most once per interval, however often the
    /// reader is reopened and closed.
    static let minimumRepeatInterval: TimeInterval = 3
    /// The shelf settles from this scale up to 1 as the reader closes; sorting
    /// starts only after it has finished, so the two movements never overlap.
    static let shelfSettleScale: CGFloat = 0.98
    static let shelfSettleDuration: TimeInterval = 0.22

    /// - Parameter previousIndex: the item's position before returning from the
    ///   reader, or `nil` when it could not be found (treat as far down).
    static func mode(
        previousIndex: Int?,
        firstScreenCapacity: Int = firstScreenCapacity
    ) -> Mode {
        guard let previousIndex, previousIndex >= 0, previousIndex < firstScreenCapacity else {
            return .scrollAndPopIn
        }
        return .reorderInPlace
    }

    static func shouldAnimate(
        itemID: String,
        lastAnimated: (itemID: String, date: Date)?,
        now: Date,
        minimumInterval: TimeInterval = minimumRepeatInterval
    ) -> Bool {
        guard let lastAnimated, lastAnimated.itemID == itemID else { return true }
        return now.timeIntervalSince(lastAnimated.date) >= minimumInterval
    }
}
