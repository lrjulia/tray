import Foundation

/// Detects secrets so they can be masked. Returns a label ("API key", "Card number"…) or nil.
enum SensitiveDetector {
    private static let patterns: [(String, String)] = [
        ("Private key", #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#),
        ("API key", #"\bsk-[A-Za-z0-9_\-]{20,}\b"#),
        ("API key", #"\bAKIA[0-9A-Z]{16}\b"#),
        ("Access token", #"\bgh[pousr]_[A-Za-z0-9]{36,}\b"#),
        ("Access token", #"\bxox[abprs]-[A-Za-z0-9\-]{10,}\b"#),
        ("API key", #"\bAIza[0-9A-Za-z_\-]{35}\b"#),
        ("Access token", #"\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\b"#),
        ("Access token", #"(?i)\bbearer\s+[A-Za-z0-9._\-]{20,}"#),
    ]

    static func label(for text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count < 10_000 else { return nil }
        for (label, pattern) in patterns where t.range(of: pattern, options: .regularExpression) != nil {
            return label
        }
        if isCardNumber(t) { return "Card number" }
        if t.range(of: #"^\d{4,8}$"#, options: .regularExpression) != nil { return "One-time code" }
        if looksLikePassword(t) { return "Password" }
        return nil
    }

    private static func isCardNumber(_ s: String) -> Bool {
        guard s.range(of: #"^[\d \-]{13,23}$"#, options: .regularExpression) != nil else { return false }
        let digits = s.compactMap { $0.wholeNumberValue }
        guard (13...19).contains(digits.count) else { return false }
        var sum = 0
        for (i, d) in digits.reversed().enumerated() {
            if i % 2 == 1 { let x = d * 2; sum += x > 9 ? x - 9 : x } else { sum += d }
        }
        return sum % 10 == 0
    }

    private static func looksLikePassword(_ s: String) -> Bool {
        guard (12...64).contains(s.count), !s.contains(where: { $0.isWhitespace }) else { return false }
        if ContentClassifier.isLink(s) || ContentClassifier.isEmail(s) { return false }
        let hasUpper = s.contains(where: \.isUppercase)
        let hasLower = s.contains(where: \.isLowercase)
        let hasDigit = s.contains(where: \.isNumber)
        let hasSymbol = s.contains { !$0.isLetter && !$0.isNumber }
        return hasUpper && hasLower && hasDigit && hasSymbol
    }
}
