import AppKit
import SwiftUI

// MARK: - Accent in the environment

private struct TrayAccentKey: EnvironmentKey {
    static let defaultValue: AccentOption = .blue
}

extension EnvironmentValues {
    var trayAccent: AccentOption {
        get { self[TrayAccentKey.self] }
        set { self[TrayAccentKey.self] = newValue }
    }
}

// MARK: - Keycap

struct Keycap: View {
    let text: String
    var quiet = false
    var onAccent = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(onAccent ? Tokens.C.onAccent : (quiet ? Tokens.C.inkMuted : Tokens.C.ink))
            .padding(.horizontal, quiet ? 0 : 5)
            .frame(minWidth: quiet ? nil : 22, minHeight: 20)
            .overlay {
                if !quiet {
                    RoundedRectangle(cornerRadius: Tokens.R.sm)
                        .strokeBorder(onAccent ? Tokens.C.onAccent : Tokens.C.lineStrong, lineWidth: 1)
                }
            }
    }
}

// MARK: - Kind glyph / thumbnail

struct KindGlyph: View {
    let item: ClipItem
    let masked: Bool
    var thumbnail: NSImage?
    var size: CGFloat = 16

    var body: some View {
        Group {
            if masked {
                Image(systemName: "lock")
            } else if item.kind == .color, let c = ContentClassifier.rgb(from: item.text ?? "") {
                Circle().fill(Color(.sRGB, red: c.r, green: c.g, blue: c.b))
                    .overlay(Circle().strokeBorder(Tokens.C.line, lineWidth: 1))
                    .frame(width: size, height: size)
            } else if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: item.kind.symbol)
            }
        }
        .font(.system(size: 13))
        .frame(width: size, height: size)
    }
}

// MARK: - Highlighting search matches (bold, not colored, so it reads on the accent fill too)

func highlightMatches(_ text: String, query: String) -> AttributedString {
    var attr = AttributedString(text)
    let terms = query.split(separator: " ").map(String.init).filter { !$0.isEmpty }
    for term in terms {
        var searchRange = text.startIndex..<text.endIndex
        while let r = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
            if let ar = Range(r, in: attr) { attr[ar].font = .system(size: 13, weight: .bold) }
            searchRange = r.upperBound..<text.endIndex
        }
    }
    return attr
}

// MARK: - Source-app color (for "Color items by source app")

enum SourceColor {
    private static var cache: [String: Color] = [:]

    /// The average color of the app's icon, darkened until white text on it passes 4.5:1.
    static func color(for bundleID: String?) -> Color? {
        guard let bundleID else { return nil }
        if let c = cache[bundleID] { return c }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(x: 0, y: 0, width: 1, height: 1))
        NSGraphicsContext.restoreGraphicsState()
        guard var c = rep.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB) else { return nil }
        func lum(_ c: NSColor) -> CGFloat {
            func f(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * f(c.redComponent) + 0.7152 * f(c.greenComponent) + 0.0722 * f(c.blueComponent)
        }
        var steps = 0
        while 1.05 / (lum(c) + 0.05) < 4.5, steps < 20 {
            c = c.blended(withFraction: 0.12, of: .black) ?? c
            steps += 1
        }
        let color = Color(nsColor: c)
        cache[bundleID] = color
        return color
    }
}

// MARK: - Status banner

struct StatusBannerView: View {
    let banner: Banner
    let onResume: () -> Void
    let onSettings: () -> Void
    @Environment(\.trayAccent) private var accent

    var body: some View {
        HStack(spacing: Tokens.S.s2) {
            switch banner {
            case .paused:
                Image(systemName: "pause.fill").foregroundStyle(Tokens.C.inkMuted)
                (Text("Recording paused").bold() + Text(" · new copies aren't saved"))
                Spacer()
                Button("Resume", action: onResume).buttonStyle(.plain).fontWeight(.semibold)
            case .skipped(let source):
                Image(systemName: "lock.fill").foregroundStyle(Tokens.C.danger)
                (Text("Not saved: ").bold() + Text("copied from \(source)"))
                Spacer()
                Button("Settings", action: onSettings).buttonStyle(.plain).fontWeight(.semibold)
            case .info(let text):
                Image(systemName: "checkmark.circle").foregroundStyle(Tokens.C.inkMuted)
                Text(text)
                Spacer()
            }
        }
        .font(Tokens.T.callout)
        .foregroundStyle(Tokens.C.ink)
        .padding(.horizontal, Tokens.S.s3)
        .padding(.vertical, Tokens.S.s2)
        .background(RoundedRectangle(cornerRadius: Tokens.R.md).fill(background))
        .padding(.horizontal, Tokens.S.s4)
        .padding(.bottom, Tokens.S.s2)
    }

    private var background: Color {
        if case .skipped = banner { return Tokens.C.dangerSoft }
        return accent.soft
    }
}

// MARK: - Formatting

enum Fmt {
    static func relative(_ date: Date) -> String {
        let s = Date().timeIntervalSince(date)
        if s < 60 { return "Just now" }
        if s < 3600 { return "\(Int(s / 60)) min ago" }
        if Calendar.current.isDateInToday(date) { return "\(Int(s / 3600)) h ago" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    static func full(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return "Today at \(time)" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday at \(time)" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func bytes(_ n: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }
}
