import Foundation

enum BookshelfItem: Identifiable {
    case single(Book)
    case series(name: String, books: [Book])

    var id: String {
        switch self {
        case .single(let book):
            return book.id.uuidString
        case .series(let name, _):
            return "series-\(name)"
        }
    }

    static func sortedByRecentRead(_ items: [BookshelfItem]) -> [BookshelfItem] {
        func books(_ i: BookshelfItem) -> [Book] {
            switch i { case .single(let b): return [b]; case .series(_, let bs): return bs }
        }
        func recent(_ i: BookshelfItem) -> Date { books(i).compactMap(\.lastReadDate).max() ?? .distantPast }
        func added(_ i: BookshelfItem) -> Date { books(i).map(\.addedDate).max() ?? .distantPast }
        return items.sorted { (recent($0), added($0)) > (recent($1), added($1)) }
    }

    static func group(_ books: [Book]) -> [BookshelfItem] {
        var singles: [BookshelfItem] = []
        var seriesMap: [String: [Book]] = [:]

        for book in books {
            if let name = book.seriesName {
                seriesMap[name, default: []].append(book)
            } else {
                singles.append(.single(book))
            }
        }

        var items: [BookshelfItem] = []
        for (name, seriesBooks) in seriesMap.sorted(by: { $0.key < $1.key }) {
            let sorted = seriesBooks.sorted { ($0.seriesIndex ?? 0) < ($1.seriesIndex ?? 0) }
            items.append(.series(name: name, books: sorted))
        }
        items.append(contentsOf: singles)
        return items
    }
}
