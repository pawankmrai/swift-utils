import Foundation

/// A type-safe, `Codable` representation of arbitrary JSON.
///
/// Use `JSONValue` when a payload's shape isn't known at compile time — analytics
/// properties, remote-config blobs, webhook bodies, or a loosely-typed `metadata`
/// field inside an otherwise strongly-typed model.
///
/// ```swift
/// let json = try JSONValue(data: responseData)
/// let city = json[path: "user.addresses.0.city"]?.stringValue
/// ```
public enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: - Typed accessors

    /// The wrapped string, or `nil` if this isn't `.string`.
    public var stringValue: String? { if case .string(let v) = self { return v }; return nil }
    /// The wrapped number, or `nil` if this isn't `.number`.
    public var doubleValue: Double? { if case .number(let v) = self { return v }; return nil }
    /// The wrapped Bool, or `nil` if this isn't `.bool`.
    public var boolValue: Bool? { if case .bool(let v) = self { return v }; return nil }
    /// The wrapped array, or `nil` if this isn't `.array`.
    public var arrayValue: [JSONValue]? { if case .array(let v) = self { return v }; return nil }
    /// The wrapped dictionary, or `nil` if this isn't `.object`.
    public var objectValue: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }
    /// `true` when this value is JSON `null`.
    public var isNull: Bool { self == .null }

    /// The number as an `Int`, only if it is integral and fits in `Int`.
    /// Note: numbers are stored as `Double`, so integers beyond 2^53 lose precision.
    public var intValue: Int? {
        guard case .number(let v) = self, v.rounded() == v,
              v >= Double(Int.min), v < Double(Int.max) else { return nil }
        return Int(v)
    }

    // MARK: - Subscripts

    /// Member lookup on an object. Returns `nil` for missing keys or non-objects.
    public subscript(key: String) -> JSONValue? { objectValue?[key] }

    /// Element lookup on an array. Returns `nil` when out of bounds or not an array.
    public subscript(index: Int) -> JSONValue? {
        guard let array = arrayValue, array.indices.contains(index) else { return nil }
        return array[index]
    }

    /// Walks a dot-separated path such as `"data.items.0.title"`.
    /// Numeric components index into arrays; all others look up object keys.
    public subscript(path path: String) -> JSONValue? {
        var current: JSONValue? = self
        for component in path.split(separator: ".", omittingEmptySubsequences: false).map(String.init) {
            guard let node = current else { return nil }
            if case .array = node, let index = Int(component) {
                current = node[index]
            } else {
                current = node[component]
            }
        }
        return current
    }

    // MARK: - Conversions

    /// Parses raw JSON bytes. Fragments (e.g. a bare `"text"` or `42`) are allowed.
    public init(data: Data) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Builds a `JSONValue` from any `Encodable` model.
    public init<T: Encodable>(encoding value: T, encoder: JSONEncoder = JSONEncoder()) throws {
        self = try JSONValue(data: encoder.encode(value))
    }

    /// Decodes this value into a concrete `Decodable` type.
    public func decode<T: Decodable>(_ type: T.Type = T.self, decoder: JSONDecoder = JSONDecoder()) throws -> T {
        try decoder.decode(T.self, from: data())
    }

    /// Serializes this value to JSON bytes.
    public func data(prettyPrinted: Bool = false, sortedKeys: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = [.withoutEscapingSlashes]
        if prettyPrinted { formatting.insert(.prettyPrinted) }
        if sortedKeys { formatting.insert(.sortedKeys) }
        encoder.outputFormatting = formatting
        return try encoder.encode(self)
    }

    /// Deep-merges `other` into `self`. Nested objects merge recursively;
    /// for any other conflict the value from `other` wins.
    public func merging(_ other: JSONValue) -> JSONValue {
        guard case .object(var base) = self, case .object(let overlay) = other else { return other }
        for (key, value) in overlay {
            base[key] = base[key].map { $0.merging(value) } ?? value
        }
        return .object(base)
    }
}

// MARK: - Codable

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Double.self) { self = .number(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode([JSONValue].self) { self = .array(v) }
        else if let v = try? container.decode([String: JSONValue].self) { self = .object(v) }
        else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }
}

// MARK: - Literals

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
                     ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral,
                     ExpressibleByDictionaryLiteral {
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

// MARK: - CustomStringConvertible

extension JSONValue: CustomStringConvertible {
    /// Compact JSON text with sorted keys, handy for logging.
    public var description: String {
        (try? data()).flatMap { String(data: $0, encoding: .utf8) } ?? "<invalid JSON>"
    }
}
