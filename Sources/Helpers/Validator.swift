import Foundation

// MARK: - ValidationResult

/// Represents the outcome of a validation check.
public enum ValidationResult: Equatable {
    case valid
    case invalid(reason: String)

    /// `true` when the result is `.valid`.
    public var isValid: Bool {
        if case .valid = self { return true }
        return false
    }

    /// Returns the failure reason, or `nil` when valid.
    public var failureReason: String? {
        if case .invalid(let reason) = self { return reason }
        return nil
    }
}

// MARK: - ValidationRule

/// A single, reusable validation rule that can be applied to a value of type `Value`.
///
/// Create rules using the built-in static factories on `ValidationRule`
/// or define your own with the closure-based initializer.
///
/// ```swift
/// let rule = ValidationRule<String>.nonEmpty(message: "Name is required")
/// let result = rule.validate("")  // .invalid(reason: "Name is required")
/// ```
public struct ValidationRule<Value> {
    /// A human-readable label for this rule (useful for debugging / logging).
    public let name: String

    private let _validate: (Value) -> ValidationResult

    /// Creates a custom validation rule.
    /// - Parameters:
    ///   - name: A short label describing the rule.
    ///   - validate: A closure that returns `.valid` or `.invalid(reason:)`.
    public init(name: String, validate: @escaping (Value) -> ValidationResult) {
        self.name = name
        self._validate = validate
    }

    /// Runs the rule against the given value.
    public func validate(_ value: Value) -> ValidationResult {
        _validate(value)
    }
}

// MARK: - Validator

/// A composable validator that aggregates multiple `ValidationRule`s for a given type.
///
/// ```swift
/// let emailValidator = Validator<String>()
///     .add(.nonEmpty(message: "Email is required"))
///     .add(.email())
///
/// let results = emailValidator.validateAll("bad-email")
/// // [.valid, .invalid(reason: "Must be a valid email address")]
/// ```
public struct Validator<Value> {
    private var rules: [ValidationRule<Value>] = []

    public init() {}

    /// Appends a rule and returns a new `Validator` (value-type chaining).
    public func adding(_ rule: ValidationRule<Value>) -> Validator<Value> {
        var copy = self
        copy.rules.append(rule)
        return copy
    }

    /// Appends a rule in place.
    @discardableResult
    public mutating func add(_ rule: ValidationRule<Value>) -> Validator<Value> {
        rules.append(rule)
        return self
    }

    /// Validates the value against **all** rules and returns every result.
    public func validateAll(_ value: Value) -> [ValidationResult] {
        rules.map { $0.validate(value) }
    }

    /// Returns only the failure reasons, or an empty array when everything passes.
    public func errors(for value: Value) -> [String] {
        validateAll(value).compactMap(\.failureReason)
    }

    /// Returns `true` only when every rule passes.
    public func isValid(_ value: Value) -> Bool {
        errors(for: value).isEmpty
    }

    /// Validates and returns the **first** failure, or `.valid` if all rules pass.
    /// Useful for short-circuit UX where you show one error at a time.
    public func firstError(for value: Value) -> ValidationResult {
        for rule in rules {
            let result = rule.validate(value)
            if !result.isValid { return result }
        }
        return .valid
    }
}

// MARK: - Built-in String Rules

extension ValidationRule where Value == String {

    /// Fails when the string is empty or contains only whitespace.
    public static func nonEmpty(message: String = "This field is required") -> ValidationRule {
        ValidationRule(name: "nonEmpty") { value in
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .invalid(reason: message)
                : .valid
        }
    }

    /// Fails when the string has fewer than `min` characters.
    public static func minLength(_ min: Int, message: String? = nil) -> ValidationRule {
        ValidationRule(name: "minLength(\(min))") { value in
            value.count < min
                ? .invalid(reason: message ?? "Must be at least \(min) characters")
                : .valid
        }
    }

    /// Fails when the string exceeds `max` characters.
    public static func maxLength(_ max: Int, message: String? = nil) -> ValidationRule {
        ValidationRule(name: "maxLength(\(max))") { value in
            value.count > max
                ? .invalid(reason: message ?? "Must be at most \(max) characters")
                : .valid
        }
    }

    /// Validates against a regular expression pattern.
    public static func pattern(_ regex: String, message: String = "Invalid format") -> ValidationRule {
        ValidationRule(name: "pattern") { value in
            let range = value.range(of: regex, options: .regularExpression)
            return range != nil ? .valid : .invalid(reason: message)
        }
    }

    /// Validates a typical email format (RFC 5322 simplified).
    public static func email(message: String = "Must be a valid email address") -> ValidationRule {
        let emailRegex = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return .pattern(emailRegex, message: message)
    }

    /// Validates a URL string can be parsed into a valid `URL` with an http(s) scheme.
    public static func url(message: String = "Must be a valid URL") -> ValidationRule {
        ValidationRule(name: "url") { value in
            guard let url = URL(string: value),
                  let scheme = url.scheme,
                  ["http", "https"].contains(scheme.lowercased()),
                  url.host != nil else {
                return .invalid(reason: message)
            }
            return .valid
        }
    }

    /// Requires at least one uppercase letter, one lowercase letter, one digit,
    /// and a minimum length (default 8). Useful for password strength checks.
    public static func strongPassword(
        minLength: Int = 8,
        message: String = "Password must contain uppercase, lowercase, and a digit"
    ) -> ValidationRule {
        ValidationRule(name: "strongPassword") { value in
            guard value.count >= minLength else {
                return .invalid(reason: "Password must be at least \(minLength) characters")
            }
            let hasUpper = value.range(of: "[A-Z]", options: .regularExpression) != nil
            let hasLower = value.range(of: "[a-z]", options: .regularExpression) != nil
            let hasDigit = value.range(of: "[0-9]", options: .regularExpression) != nil
            return (hasUpper && hasLower && hasDigit)
                ? .valid
                : .invalid(reason: message)
        }
    }
}

// MARK: - Built-in Numeric Rules

extension ValidationRule where Value: Comparable {

    /// Fails when the value is below the given minimum.
    public static func minimum(_ min: Value, message: String = "Value is too small") -> ValidationRule {
        ValidationRule(name: "minimum") { value in
            value < min ? .invalid(reason: message) : .valid
        }
    }

    /// Fails when the value exceeds the given maximum.
    public static func maximum(_ max: Value, message: String = "Value is too large") -> ValidationRule {
        ValidationRule(name: "maximum") { value in
            value > max ? .invalid(reason: message) : .valid
        }
    }

    /// Fails when the value is outside the closed range.
    public static func range(
        _ range: ClosedRange<Value>,
        message: String = "Value is out of range"
    ) -> ValidationRule {
        ValidationRule(name: "range") { value in
            range.contains(value) ? .valid : .invalid(reason: message)
        }
    }
}

// MARK: - Built-in Optional Rules

extension ValidationRule {

    /// A rule that requires the value to be non-nil.
    /// Works with any `Optional`-wrapped type by accepting a key path.
    public static func required<Wrapped>(
        message: String = "This field is required"
    ) -> ValidationRule where Value == Optional<Wrapped> {
        ValidationRule(name: "required") { value in
            value == nil ? .invalid(reason: message) : .valid
        }
    }
}

// MARK: - Custom Rule Helper

extension ValidationRule {

    /// Creates a rule from a simple Boolean predicate.
    ///
    /// ```swift
    /// let even = ValidationRule<Int>.predicate("Must be even") { $0 % 2 == 0 }
    /// ```
    public static func predicate(
        _ message: String,
        name: String = "custom",
        _ isValid: @escaping (Value) -> Bool
    ) -> ValidationRule {
        ValidationRule(name: name) { value in
            isValid(value) ? .valid : .invalid(reason: message)
        }
    }
}
