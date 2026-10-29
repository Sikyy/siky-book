import XCTest
import SwiftData
@testable import YiYue

@MainActor
final class BookshelfSortTransitionTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(
            for: Book.self, Chapter.self, BookSource.self,
            configurations: config
        )
        context = ModelContext(container)
    }

    // MARK: - Which animation

    func testBookOnFirstScreenMovesInPlace() {
        for index in 0..<BookshelfSortTransition.firstScreenCapacity {
            XCTAssertEqual(
                BookshelfSortTransition.mode(previousIndex: index),
                .reorderInPlace,
                "index \(index) is on the first screen"
            )
        }
    }

    func testBookFurtherDownScrollsAndPopsIn() {
        XCTAssertEqual(
            BookshelfSortTransition.mode(previousIndex: BookshelfSortTransition.firstScreenCapacity),
            .scrollAndPopIn
        )
        XCTAssertEqual(BookshelfSortTransition.mode(previousIndex: 40), .scrollAndPopIn)
    }

    func testUnknownPreviousPositionScrollsAndPopsIn() {
        XCTAssertEqual(BookshelfSortTransition.mode(previousIndex: nil), .scrollAndPopIn)
        XCTAssertEqual(BookshelfSortTransition.mode(previousIndex: -1), .scrollAndPopIn)
    }

    // MARK: - Repeat guard

    func testFirstReturnAlwaysAnimates() {
        XCTAssertTrue(
            BookshelfSortTransition.shouldAnimate(
                itemID: "book-a",
                lastAnimated: nil,
                now: Date()
            )
        )
    }

    func testSameBookDoesNotAnimateTwiceInsideTheInterval() {
        let now = Date()
        XCTAssertFalse(
            BookshelfSortTransition.shouldAnimate(
                itemID: "book-a",
                lastAnimated: (itemID: "book-a", date: now.addingTimeInterval(-2.9)),
                now: now
            )
        )
        XCTAssertTrue(
            BookshelfSortTransition.shouldAnimate(
                itemID: "book-a",
                lastAnimated: (itemID: "book-a", date: now.addingTimeInterval(-3.1)),
                now: now
            )
        )
    }

    func testAnotherBookAnimatesEvenRightAfterOneWasHighlighted() {
        let now = Date()
        XCTAssertTrue(
            BookshelfSortTransition.shouldAnimate(
                itemID: "book-b",
                lastAnimated: (itemID: "book-a", date: now),
                now: now
            )
        )
    }

    // MARK: - Frozen order while the reader is open

    func testFrozenOrderIsRestoredExactly() {
        let books = [book("一", readAt: 1), book("二", readAt: 2), book("三", readAt: 3)]
        let live = BookshelfItem.sortedByRecentRead(BookshelfItem.group(books))
        let frozen = live.map(\.id)

        // Reading the oldest book pushes it to the front of the live order.
        books[0].lastReadDate = Date(timeIntervalSince1970: 99)
        let reordered = BookshelfItem.sortedByRecentRead(BookshelfItem.group(books))
        XCTAssertEqual(reordered.first?.id, books[0].id.uuidString)

        let stillFrozen = BookshelfItem.applying(order: frozen, to: reordered)
        XCTAssertEqual(stillFrozen.map(\.id), frozen)
    }

    func testBooksThatArriveWhileFrozenKeepTheirLivePlacement() {
        let books = [book("一", readAt: 1), book("二", readAt: 2)]
        let live = BookshelfItem.sortedByRecentRead(BookshelfItem.group(books))
        let frozen = live.map(\.id)

        let newcomer = book("三", readAt: 50)
        let withNewcomer = BookshelfItem.sortedByRecentRead(BookshelfItem.group(books + [newcomer]))
        let applied = BookshelfItem.applying(order: frozen, to: withNewcomer)

        XCTAssertEqual(applied.count, 3)
        XCTAssertEqual(Array(applied.map(\.id).prefix(2)), frozen)
        XCTAssertEqual(applied.last?.id, newcomer.id.uuidString)
    }

    func testIDsNoLongerPresentAreDropped() {
        let books = [book("一", readAt: 1), book("二", readAt: 2)]
        let live = BookshelfItem.sortedByRecentRead(BookshelfItem.group(books))
        let applied = BookshelfItem.applying(order: live.map(\.id) + ["missing-id"], to: live)
        XCTAssertEqual(applied.map(\.id), live.map(\.id))
    }

    func testContainsLookupFindsSingleBook() {
        let books = [book("一", readAt: 1), book("二", readAt: 2)]
        let items = BookshelfItem.sortedByRecentRead(BookshelfItem.group(books))
        XCTAssertEqual(
            BookshelfItem.itemID(containing: books[1].id, in: items),
            books[1].id.uuidString
        )
    }

    func testContainsLookupFindsSeriesItem() {
        let first = book("卷一", readAt: 1)
        let second = book("卷二", readAt: 2)
        first.seriesName = "山海"
        second.seriesName = "山海"
        first.seriesIndex = 1
        second.seriesIndex = 2
        let items = BookshelfItem.sortedByRecentRead(BookshelfItem.group([first, second]))

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(BookshelfItem.itemID(containing: second.id, in: items), "series-山海")
    }

    // MARK: - Helpers

    private func book(_ title: String, readAt seconds: TimeInterval) -> Book {
        let book = Book(title: title, author: "", sourceType: .localFile)
        book.addedDate = Date(timeIntervalSince1970: 0)
        book.lastReadDate = Date(timeIntervalSince1970: seconds)
        return book
    }
}
