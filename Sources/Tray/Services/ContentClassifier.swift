import Foundation

/// Decides what kind a copied string is.
enum ContentClassifier {
    private static let codeApps: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.apple.dt.Xcode", "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92", "dev.zed.Zed", "com.sublimetext.4", "com.jetbrains.intellij",
        "com.jetbrains.intellij.ce", "com.jetbrains.pycharm", "com.github.atom", "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty", "net.kovidgoyal.kitty",
    ]

    static func classify(text: String, bundleID: String?, hasRTF: Bool = false) -> ClipKind {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let singleLine = !t.contains(where: \.isNewline)

        if singleLine, isColor(t) { return .color }
        if singleLine, isLink(t) { return .link }
        if singleLine, isEmail(t) { return .email }
        if let bundleID, codeApps.contains(bundleID) { return .code }
        if looksLikeCode(t) { return .code }
        return hasRTF ? .richText : .text
    }

    static func isColor(_ s: String) -> Bool {
        if s.range(of: #"^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"#, options: .regularExpression) != nil { return true }
        // Bare 6-digit hex only when it mixes letters and digits ("2f6f4e"), so words like "decade" don't count.
        if s.range(of: #"^[0-9a-fA-F]{6}$"#, options: .regularExpression) != nil,
           s.range(of: "[a-fA-F]", options: .regularExpression) != nil,
           s.range(of: "[0-9]", options: .regularExpression) != nil { return true }
        return s.range(of: #"^(rgb|rgba|hsl|hsla)\([\d\s.,%]+\)$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func isLink(_ s: String) -> Bool {
        guard !s.contains(" "), let url = URL(string: s), let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "ftp", "mailto", "file"].contains(scheme) && (url.host != nil || scheme == "mailto" || scheme == "file")
    }

    static func isEmail(_ s: String) -> Bool {
        s.range(of: #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func looksLikeCode(_ s: String) -> Bool {
        let lines = s.split(whereSeparator: \.isNewline)
        let markers = [";", "{", "}", "=>", "->", "()", "func ", "def ", "const ", "let ", "var ", "import ", "return ", "</", "$ "]
        let hits = markers.reduce(0) { $0 + (s.contains($1) ? 1 : 0) }
        if lines.count >= 2 { return hits >= 3 }
        return s.hasPrefix("$ ") || s.hasPrefix("git ") || s.hasPrefix("npm ") || s.hasPrefix("brew ") || hits >= 4
    }

    /// Parses a color string into sRGB components (0–1).
    static func rgb(from s: String) -> (r: Double, g: Double, b: Double)? {
        var hex = s.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        if hex.count == 8 { hex = String(hex.prefix(6)) }
        guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
}
