import Foundation

/// Text transforms offered in Actions (⌘K). Each makes a new item; the original stays.
enum TextTransform: String, CaseIterable, Identifiable {
    case uppercase, lowercase, titleCase, sentenceCase
    case trimWhitespace, removeLineBreaks, collapseSpaces, sortLines, reverseLines, removeDuplicateLines
    case formatJSON, minifyJSON, urlEncode, urlDecode, base64Encode, base64Decode
    case stripQuotes, slugify

    var id: String { rawValue }

    var label: String {
        switch self {
        case .uppercase: return "UPPERCASE"
        case .lowercase: return "lowercase"
        case .titleCase: return "Title Case"
        case .sentenceCase: return "Sentence case"
        case .trimWhitespace: return "Trim whitespace"
        case .removeLineBreaks: return "Remove line breaks"
        case .collapseSpaces: return "Collapse spaces"
        case .sortLines: return "Sort lines"
        case .reverseLines: return "Reverse lines"
        case .removeDuplicateLines: return "Remove duplicate lines"
        case .formatJSON: return "Format JSON"
        case .minifyJSON: return "Minify JSON"
        case .urlEncode: return "URL-encode"
        case .urlDecode: return "URL-decode"
        case .base64Encode: return "Base64-encode"
        case .base64Decode: return "Base64-decode"
        case .stripQuotes: return "Strip surrounding quotes"
        case .slugify: return "Make slug"
        }
    }

    func apply(_ s: String) -> String? {
        switch self {
        case .uppercase: return s.uppercased()
        case .lowercase: return s.lowercased()
        case .titleCase: return s.capitalized
        case .sentenceCase:
            let lower = s.lowercased()
            guard let first = lower.first else { return s }
            return first.uppercased() + lower.dropFirst()
        case .trimWhitespace: return s.trimmingCharacters(in: .whitespacesAndNewlines)
        case .removeLineBreaks:
            return s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        case .collapseSpaces: return s.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        case .sortLines: return lines(s).sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: "\n")
        case .reverseLines: return lines(s).reversed().joined(separator: "\n")
        case .removeDuplicateLines:
            var seen = Set<String>()
            return lines(s).filter { seen.insert($0).inserted }.joined(separator: "\n")
        case .formatJSON: return json(s, pretty: true)
        case .minifyJSON: return json(s, pretty: false)
        case .urlEncode: return s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        case .urlDecode: return s.removingPercentEncoding
        case .base64Encode: return Data(s.utf8).base64EncodedString()
        case .base64Decode:
            guard let d = Data(base64Encoded: s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
            return String(data: d, encoding: .utf8)
        case .stripQuotes:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            let pairs: [(Character, Character)] = [("\"", "\""), ("'", "'"), ("“", "”"), ("‘", "’"), ("`", "`")]
            for (a, b) in pairs where t.count >= 2 && t.first == a && t.last == b {
                return String(t.dropFirst().dropLast())
            }
            return t
        case .slugify:
            let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
            return folded.replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }
    }

    private func lines(_ s: String) -> [String] {
        s.split(whereSeparator: \.isNewline).map(String.init)
    }

    private func json(_ s: String, pretty: Bool) -> String? {
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        var opts: JSONSerialization.WritingOptions = [.fragmentsAllowed, .withoutEscapingSlashes]
        if pretty { opts.insert(.prettyPrinted); opts.insert(.sortedKeys) }
        guard let out = try? JSONSerialization.data(withJSONObject: obj, options: opts) else { return nil }
        return String(data: out, encoding: .utf8)
    }
}
