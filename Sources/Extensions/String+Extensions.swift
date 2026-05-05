import Foundation

public extension String {
    
    /// Returns true if the string is a valid email address
    var isValidEmail: Bool {
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return range(of: pattern, options: .regularExpression) != nil
    }
    
    /// Returns the string with leading and trailing whitespace removed
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Returns true if the string contains only numeric characters
    var isNumeric: Bool {
        !isEmpty && rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil
    }
    
    /// Truncates the string to the specified length with an optional trailing string
    func truncated(to length: Int, trailing: String = "…") -> String {
        if count > length {
            return String(prefix(length)) + trailing
        }
        return self
    }
    
    /// Returns a URL-safe slug version of the string
    var slugified: String {
        lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined()
    }
    
    /// Converts a camelCase string to snake_case
    var snakeCased: String {
        let pattern = "([a-z])([A-Z])"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(startIndex..., in: self)
        return regex?.stringByReplacingMatches(in: self, range: range, withTemplate: "$1_$2").lowercased() ?? self
    }
}
