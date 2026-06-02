import Foundation

// MARK: - Safe Access & Querying

public extension Collection {

    /// Returns `true` if the collection is not empty.
    ///
    ///     [1, 2, 3].isNotEmpty  // true
    ///     [].isNotEmpty         // false
    var isNotEmpty: Bool { !isEmpty }

    /// Returns the element at the specified index if within bounds, otherwise `nil`.
    ///
    /// Works on any `Collection` (not just `Array`). For array-specific safe access,
    /// see `Array[safe:]`.
    ///
    ///     let names: ArraySlice = ["a", "b", "c"][1...]
    ///     names[safe: 2]  // Optional("c")
    ///     names[safe: 9]  // nil
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Conditional Access

public extension Collection {

    /// Returns `nil` if the collection is empty, otherwise returns `self`.
    ///
    /// Useful for optional chaining on potentially-empty collections:
    ///
    ///     let results: [String] = []
    ///     results.nilIfEmpty ?? ["No results"]  // ["No results"]
    var nilIfEmpty: Self? {
        isEmpty ? nil : self
    }

    /// Returns the only element if the collection contains exactly one, otherwise `nil`.
    ///
    ///     [42].onlyElement       // Optional(42)
    ///     [1, 2].onlyElement     // nil
    ///     [Int]().onlyElement    // nil
    var onlyElement: Element? {
        count == 1 ? first : nil
    }
}

// MARK: - Partitioning & Splitting

public extension Collection {

    /// Splits the collection into two arrays based on a predicate.
    ///
    /// The first array contains elements satisfying the predicate,
    /// the second contains the rest. Order is preserved.
    ///
    ///     let (evens, odds) = [1, 2, 3, 4, 5].partitioned { $0.isMultiple(of: 2) }
    ///     // evens: [2, 4], odds: [1, 3, 5]
    func partitioned(by predicate: (Element) throws -> Bool) rethrows -> (matching: [Element], nonMatching: [Element]) {
        var matching: [Element] = []
        var nonMatching: [Element] = []
        for element in self {
            if try predicate(element) {
                matching.append(element)
            } else {
                nonMatching.append(element)
            }
        }
        return (matching, nonMatching)
    }
}

// MARK: - Aggregation

public extension Collection where Element: Numeric {

    /// Returns the sum of all elements.
    ///
    ///     [1, 2, 3, 4].sum()  // 10
    ///     [1.5, 2.5].sum()    // 4.0
    func sum() -> Element {
        reduce(.zero, +)
    }
}

public extension Collection where Element: BinaryInteger {

    /// Returns the average of all elements as a `Double`, or `nil` if empty.
    ///
    ///     [2, 4, 6].average()  // Optional(4.0)
    ///     [Int]().average()    // nil
    func average() -> Double? {
        guard isNotEmpty else { return nil }
        return Double(sum()) / Double(count)
    }
}

public extension Collection where Element: BinaryFloatingPoint {

    /// Returns the average of all elements, or `nil` if empty.
    ///
    ///     [1.0, 2.0, 3.0].average()  // Optional(2.0)
    func average() -> Element? {
        guard isNotEmpty else { return nil }
        return sum() / Element(count)
    }
}

// MARK: - Key-Path Helpers

public extension Collection {

    /// Returns the sum of values at a key path.
    ///
    ///     struct Item { let price: Double }
    ///     let items = [Item(price: 9.99), Item(price: 19.99)]
    ///     items.sum(of: \.price)  // 29.98
    func sum<T: Numeric>(of keyPath: KeyPath<Element, T>) -> T {
        reduce(.zero) { $0 + $1[keyPath: keyPath] }
    }

    /// Returns the average of values at a numeric key path.
    ///
    ///     struct Score { let value: Double }
    ///     [Score(value: 80), Score(value: 100)].average(of: \.value)  // Optional(90.0)
    func average<T: BinaryFloatingPoint>(of keyPath: KeyPath<Element, T>) -> T? {
        guard isNotEmpty else { return nil }
        return sum(of: keyPath) / T(count)
    }

    /// Builds a dictionary keyed by a key path, using the last element for duplicates.
    ///
    ///     struct User { let id: Int; let name: String }
    ///     let users = [User(id: 1, name: "A"), User(id: 2, name: "B")]
    ///     users.keyed(by: \.id)
    ///     // [1: User(id: 1, name: "A"), 2: User(id: 2, name: "B")]
    func keyed<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Key: Element] {
        reduce(into: [:]) { dict, element in
            dict[element[keyPath: keyPath]] = element
        }
    }
}

// MARK: - Inspection

public extension Collection where Element: Equatable {

    /// Returns `true` if all elements in the collection are equal.
    ///
    ///     [5, 5, 5].allEqual()    // true
    ///     [1, 2, 3].allEqual()    // false
    ///     [Int]().allEqual()      // true (vacuously)
    func allEqual() -> Bool {
        guard let first = first else { return true }
        return allSatisfy { $0 == first }
    }

    /// Returns the number of occurrences of the given element.
    ///
    ///     "hello world".count(of: "l")  // Works on any Collection of Equatable
    ///     [1, 2, 1, 3, 1].count(of: 1) // 3
    func count(of element: Element) -> Int {
        reduce(0) { $0 + ($1 == element ? 1 : 0) }
    }
}

// MARK: - Index Helpers

public extension Collection {

    /// Returns the indices where elements satisfy the predicate.
    ///
    ///     [10, 20, 30, 40, 50].indices(where: { $0 > 25 })
    ///     // [2, 3, 4]
    func indices(where predicate: (Element) throws -> Bool) rethrows -> [Index] {
        try zip(indices, self)
            .filter { try predicate($1) }
            .map(\.0)
    }
}
