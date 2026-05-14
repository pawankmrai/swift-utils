//
//  Array+Extensions.swift
//  SwiftUtils
//
//  A collection of production-ready Array and Sequence extensions
//  for common operations in iOS development.
//
//  Target: iOS 15+ / Swift 5.9+
//

import Foundation

// MARK: - Safe Subscript

public extension Array {
    /// Returns the element at the specified index if it is within bounds, otherwise `nil`.
    ///
    /// Eliminates the risk of `Index out of range` crashes when accessing
    /// elements by index from dynamic data sources (API responses, user input, etc.).
    ///
    /// ```swift
    /// let items = ["a", "b", "c"]
    /// items[safe: 1]  // Optional("b")
    /// items[safe: 10] // nil
    /// ```
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Chunking

public extension Array {
    /// Splits the array into sub-arrays of the given size.
    ///
    /// The last chunk may contain fewer elements if the array length
    /// is not evenly divisible by `size`.
    ///
    /// ```swift
    /// [1, 2, 3, 4, 5].chunked(into: 2)
    /// // [[1, 2], [3, 4], [5]]
    /// ```
    ///
    /// - Parameter size: The maximum number of elements per chunk. Must be greater than 0.
    /// - Returns: An array of sub-arrays, each containing at most `size` elements.
    func chunked(into size: Int) -> [[Element]] {
        precondition(size > 0, "Chunk size must be greater than 0")
        return stride(from: 0, to: count, by: size).map { startIndex in
            Array(self[startIndex..<Swift.min(startIndex + size, count)])
        }
    }
}

// MARK: - Unique (Equatable)

public extension Array where Element: Equatable {
    /// Returns a new array with duplicate elements removed, preserving the
    /// order of first occurrence.
    ///
    /// ```swift
    /// [1, 2, 3, 2, 1, 4].uniqued()
    /// // [1, 2, 3, 4]
    /// ```
    func uniqued() -> [Element] {
        var result: [Element] = []
        result.reserveCapacity(count)
        for element in self where !result.contains(element) {
            result.append(element)
        }
        return result
    }
}

// MARK: - Unique (Hashable)

public extension Array where Element: Hashable {
    /// Returns a new array with duplicate elements removed, preserving
    /// order of first occurrence. Uses a `Set` for O(n) performance.
    ///
    /// Prefer this over the `Equatable` variant when elements are `Hashable`.
    ///
    /// ```swift
    /// ["apple", "banana", "apple", "cherry"].uniquedFast()
    /// // ["apple", "banana", "cherry"]
    /// ```
    func uniquedFast() -> [Element] {
        var seen = Set<Element>()
        seen.reserveCapacity(count)
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - Unique by Key Path

public extension Array {
    /// Returns a new array with elements deduplicated by a key path value,
    /// preserving the order of first occurrence.
    ///
    /// ```swift
    /// struct User { let id: Int; let name: String }
    /// let users = [User(id: 1, name: "A"), User(id: 2, name: "B"), User(id: 1, name: "C")]
    /// users.uniqued(by: \.id)
    /// // [User(id: 1, name: "A"), User(id: 2, name: "B")]
    /// ```
    ///
    /// - Parameter keyPath: A key path to a `Hashable` property used for comparison.
    /// - Returns: An array with the first occurrence of each unique key value.
    func uniqued<T: Hashable>(by keyPath: KeyPath<Element, T>) -> [Element] {
        var seen = Set<T>()
        seen.reserveCapacity(count)
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}

// MARK: - Grouping by Key Path

public extension Sequence {
    /// Groups elements by the value at the given key path.
    ///
    /// A convenience wrapper around `Dictionary(grouping:by:)` that
    /// accepts a key path instead of a closure.
    ///
    /// ```swift
    /// struct Task { let priority: String; let title: String }
    /// let tasks = [Task(priority: "high", title: "Fix crash"),
    ///              Task(priority: "low", title: "Update docs"),
    ///              Task(priority: "high", title: "Ship feature")]
    /// let grouped = tasks.grouped(by: \.priority)
    /// // ["high": [...], "low": [...]]
    /// ```
    ///
    /// - Parameter keyPath: A key path to a `Hashable` property.
    /// - Returns: A dictionary of arrays keyed by the property value.
    func grouped<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Key: [Element]] {
        Dictionary(grouping: self, by: { $0[keyPath: keyPath] })
    }
}

// MARK: - Frequency Count

public extension Sequence where Element: Hashable {
    /// Returns a dictionary mapping each element to its occurrence count.
    ///
    /// ```swift
    /// ["a", "b", "a", "c", "a", "b"].frequencies()
    /// // ["a": 3, "b": 2, "c": 1]
    /// ```
    func frequencies() -> [Element: Int] {
        reduce(into: [:]) { counts, element in
            counts[element, default: 0] += 1
        }
    }
}

// MARK: - Min / Max by Key Path

public extension Sequence {
    /// Returns the element with the minimum value at the given key path,
    /// or `nil` if the sequence is empty.
    ///
    /// ```swift
    /// struct Product { let name: String; let price: Double }
    /// let products = [Product(name: "A", price: 29.99),
    ///                 Product(name: "B", price: 9.99)]
    /// products.min(by: \.price)  // Product(name: "B", price: 9.99)
    /// ```
    func min<T: Comparable>(by keyPath: KeyPath<Element, T>) -> Element? {
        self.min { $0[keyPath: keyPath] < $1[keyPath: keyPath] }
    }

    /// Returns the element with the maximum value at the given key path,
    /// or `nil` if the sequence is empty.
    func max<T: Comparable>(by keyPath: KeyPath<Element, T>) -> Element? {
        self.max { $0[keyPath: keyPath] < $1[keyPath: keyPath] }
    }
}

// MARK: - Sorted by Key Path

public extension Sequence {
    /// Returns the elements sorted by the value at the given key path
    /// in ascending order.
    ///
    /// ```swift
    /// struct User { let name: String; let age: Int }
    /// let users = [User(name: "B", age: 30), User(name: "A", age: 25)]
    /// users.sorted(by: \.age)
    /// // [User(name: "A", age: 25), User(name: "B", age: 30)]
    /// ```
    func sorted<T: Comparable>(by keyPath: KeyPath<Element, T>, ascending: Bool = true) -> [Element] {
        sorted {
            ascending
                ? $0[keyPath: keyPath] < $1[keyPath: keyPath]
                : $0[keyPath: keyPath] > $1[keyPath: keyPath]
        }
    }
}

// MARK: - Compact Map Key Path

public extension Sequence {
    /// Extracts non-nil values at the given key path, discarding elements
    /// where the property is `nil`.
    ///
    /// ```swift
    /// struct Contact { let email: String? }
    /// let contacts = [Contact(email: "a@b.com"), Contact(email: nil), Contact(email: "c@d.com")]
    /// contacts.compactMap(\.email)
    /// // ["a@b.com", "c@d.com"]  — (already works natively, shown for completeness)
    /// ```
    ///
    /// This method is provided for `Optional` key paths where the native
    /// `compactMap(\.keyPath)` syntax requires an explicit closure.
    func compactMap<T>(unwrapping keyPath: KeyPath<Element, T?>) -> [T] {
        compactMap { $0[keyPath: keyPath] }
    }
}

// MARK: - Prepend / Append if absent

public extension Array where Element: Equatable {
    /// Appends the element only if it is not already present in the array.
    ///
    /// ```swift
    /// var tags = ["swift", "ios"]
    /// tags.appendIfAbsent("swift")  // no-op
    /// tags.appendIfAbsent("macOS")  // tags == ["swift", "ios", "macOS"]
    /// ```
    ///
    /// - Parameter element: The element to conditionally append.
    /// - Returns: `true` if the element was appended, `false` if it already existed.
    @discardableResult
    mutating func appendIfAbsent(_ element: Element) -> Bool {
        guard !contains(element) else { return false }
        append(element)
        return true
    }
}
