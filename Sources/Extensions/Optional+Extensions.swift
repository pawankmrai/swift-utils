import Foundation

// MARK: - Optional Unwrapping Helpers

extension Optional {
    
    /// Returns the wrapped value or throws the provided error.
    ///
    /// Useful for converting optionals into throwing expressions in async/await flows.
    ///
    /// ```swift
    /// let user = optionalUser.orThrow(AppError.userNotFound)
    /// ```
    ///
    /// - Parameter error: The error to throw if the optional is `nil`.
    /// - Returns: The unwrapped value.
    /// - Throws: The provided error when the optional is `nil`.
    public func orThrow(_ error: @autoclosure () -> Error) throws -> Wrapped {
        guard let value = self else { throw error() }
        return value
    }
    
    /// Returns the wrapped value or the result of the `defaultValue` closure.
    ///
    /// Unlike the `??` operator, this communicates intent more clearly in complex expressions
    /// and supports side effects in the default path.
    ///
    /// - Parameter defaultValue: A closure that produces the fallback value.
    /// - Returns: The wrapped value, or the result of `defaultValue()`.
    public func or(_ defaultValue: @autoclosure () -> Wrapped) -> Wrapped {
        return self ?? defaultValue()
    }
    
    /// Returns the wrapped value or the result of an async closure.
    ///
    /// - Parameter defaultValue: An async closure that produces the fallback value.
    /// - Returns: The wrapped value, or the awaited result of `defaultValue()`.
    public func orAsync(_ defaultValue: () async -> Wrapped) async -> Wrapped {
        if let value = self {
            return value
        }
        return await defaultValue()
    }
    
    /// Executes a closure with the unwrapped value if present, then returns self for chaining.
    ///
    /// ```swift
    /// optionalUser
    ///     .ifLet { print("Found user: \($0.name)") }
    /// ```
    ///
    /// - Parameter action: A closure to execute with the unwrapped value.
    /// - Returns: The original optional for further chaining.
    @discardableResult
    public func ifLet(_ action: (Wrapped) -> Void) -> Optional {
        if let value = self {
            action(value)
        }
        return self
    }
    
    /// Executes a closure if the optional is `nil`, then returns self for chaining.
    ///
    /// ```swift
    /// optionalUser
    ///     .ifNil { print("No user found, using default") }
    /// ```
    ///
    /// - Parameter action: A closure to execute when the value is `nil`.
    /// - Returns: The original optional for further chaining.
    @discardableResult
    public func ifNil(_ action: () -> Void) -> Optional {
        if self == nil {
            action()
        }
        return self
    }
    
    /// Returns `true` if the optional is `nil`.
    public var isNil: Bool {
        return self == nil
    }
    
    /// Returns `true` if the optional contains a value.
    public var isNotNil: Bool {
        return self != nil
    }
    
    /// Transforms the wrapped value using the provided closure, returning `nil` if the optional is `nil`
    /// or if the transform returns `nil`.
    ///
    /// This is equivalent to `flatMap` but named for clarity when working with failable transforms.
    ///
    /// - Parameter transform: A closure that takes the wrapped value and returns an optional result.
    /// - Returns: The transformed value, or `nil`.
    public func flatMapNil(_ transform: (Wrapped) -> Wrapped?) -> Wrapped? {
        guard let value = self else { return nil }
        return transform(value)
    }
    
    /// Returns the optional value if it satisfies the predicate, otherwise returns `nil`.
    ///
    /// ```swift
    /// let validAge = optionalAge.filter { $0 >= 18 }
    /// ```
    ///
    /// - Parameter predicate: A closure that evaluates the wrapped value.
    /// - Returns: The wrapped value if the predicate is satisfied, otherwise `nil`.
    public func filter(_ predicate: (Wrapped) -> Bool) -> Wrapped? {
        guard let value = self else { return nil }
        return predicate(value) ? value : nil
    }
    
    /// Zips this optional with another, returning a tuple if both contain values.
    ///
    /// ```swift
    /// let combined = optionalName.zip(optionalAge) // (String, Int)?
    /// ```
    ///
    /// - Parameter other: Another optional to zip with.
    /// - Returns: A tuple of both unwrapped values, or `nil` if either is `nil`.
    public func zip<U>(_ other: U?) -> (Wrapped, U)? {
        guard let a = self, let b = other else { return nil }
        return (a, b)
    }
    
    /// Zips this optional with two others, returning a tuple if all contain values.
    ///
    /// - Parameters:
    ///   - second: The second optional.
    ///   - third: The third optional.
    /// - Returns: A tuple of all three unwrapped values, or `nil`.
    public func zip<B, C>(_ second: B?, _ third: C?) -> (Wrapped, B, C)? {
        guard let a = self, let b = second, let c = third else { return nil }
        return (a, b, c)
    }
}

// MARK: - Optional where Wrapped: Collection

extension Optional where Wrapped: Collection {
    
    /// Returns `true` if the optional is `nil` or the collection is empty.
    ///
    /// ```swift
    /// let names: [String]? = []
    /// names.isNilOrEmpty // true
    /// ```
    public var isNilOrEmpty: Bool {
        return self?.isEmpty ?? true
    }
    
    /// Returns the collection if it is non-nil and non-empty, otherwise returns `nil`.
    ///
    /// Useful for guard statements where you want to ensure a collection has content.
    ///
    /// ```swift
    /// guard let items = optionalArray.nilIfEmpty else { return }
    /// ```
    public var nilIfEmpty: Wrapped? {
        guard let collection = self, !collection.isEmpty else { return nil }
        return collection
    }
}

// MARK: - Optional where Wrapped == String

extension Optional where Wrapped == String {
    
    /// Returns `true` if the optional is `nil`, empty, or contains only whitespace.
    ///
    /// ```swift
    /// let input: String? = "   "
    /// input.isNilOrBlank // true
    /// ```
    public var isNilOrBlank: Bool {
        return self?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }
    
    /// Returns the string if it is non-nil and non-blank, otherwise returns `nil`.
    public var nilIfBlank: String? {
        guard let str = self, !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return str
    }
    
    /// Returns the string or an empty string if `nil`.
    public var orEmpty: String {
        return self ?? ""
    }
}

// MARK: - Optional where Wrapped: Numeric

extension Optional where Wrapped: Numeric {
    
    /// Returns the numeric value or zero if `nil`.
    ///
    /// ```swift
    /// let count: Int? = nil
    /// let total = count.orZero + 5 // 5
    /// ```
    public var orZero: Wrapped {
        return self ?? 0
    }
}

// MARK: - Optional where Wrapped == Bool

extension Optional where Wrapped == Bool {
    
    /// Returns the boolean value or `false` if `nil`.
    public var orFalse: Bool {
        return self ?? false
    }
    
    /// Returns the boolean value or `true` if `nil`.
    public var orTrue: Bool {
        return self ?? true
    }
}
