import Foundation
import SwiftUI

enum ClipKind: String, Codable, CaseIterable {
    case text, richText, link, email, code, color, image, file

    var label: String {
        switch self {
        case .text: return "Text"
        case .richText: return "Rich text"
        case .link: return "Link"
        case .email: return "Email"
        case .code: return "Code"
        case .color: return "Color"
        case .image: return "Image"
        case .file: return "File"
        }
    }

    /// SF Symbol for the kind glyph.
    var symbol: String {
        switch self {
        case .text, .richText: return "doc.text"
        case .link: return "link"
        case .email: return "envelope"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .color: return "paintpalette"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

    var group: KindGroup {
        switch self {
        case .text, .richText, .email: return .text
        case .link: return .links
        case .code: return .code
        case .color: return .colors
        case .image: return .images
        case .file: return .files
        }
    }

    var bandColor: Color {
        switch self {
        case .text, .richText, .email, .color: return Tokens.C.kindText
        case .link: return Tokens.C.kindLink
        case .image: return Tokens.C.kindImage
        case .code: return Tokens.C.kindCode
        case .file: return Tokens.C.kindFile
        }
    }

    var isTextual: Bool {
        switch self {
        case .image, .file: return false
        default: return true
        }
    }
}

/// The groups used by the Kind menu and per-kind retention.
enum KindGroup: String, Codable, CaseIterable, Identifiable {
    case text, links, images, code, colors, files
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

struct ClipItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: ClipKind
    /// Plain text content. For links: the URL; colors: the hex; files: the paths joined by newlines.
    var text: String?
    var rtfData: Data?
    /// File name of the encrypted image blob in the store's blobs folder.
    var imageBlob: String?
    var imageWidth: Int?
    var imageHeight: Int?
    var filePaths: [String]?
    var ocrText: String?
    var linkTitle: String?
    var customName: String?
    var sourceApp: String?
    var sourceBundleID: String?
    var firstCopied = Date()
    var lastCopied = Date()
    var copyCount = 1
    var editedAt: Date?
    var pinboardIDs: [UUID] = []
    var sensitiveLabel: String?
    var byteSize = 0
    /// SHA-256 of the content, for de-duplication.
    var contentHash: String

    var isSensitive: Bool { sensitiveLabel != nil }
    var isPinned: Bool { !pinboardIDs.isEmpty }

    var firstLine: String {
        switch kind {
        case .image:
            if let w = imageWidth, let h = imageHeight { return "Image · \(w) × \(h)" }
            return "Image"
        case .file:
            let paths = filePaths ?? []
            let first = paths.first.map { ($0 as NSString).lastPathComponent } ?? "File"
            return paths.count > 1 ? "\(first) and \(paths.count - 1) more" : first
        default:
            let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.split(whereSeparator: \.isNewline).first.map(String.init) ?? t
        }
    }

    /// What the list shows: the custom name if set, else the first line.
    var title: String { customName ?? firstLine }

    var searchableText: String {
        [customName, text, linkTitle, ocrText, sourceApp, filePaths?.joined(separator: " ")]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    var characterCount: Int { text?.count ?? 0 }
    var wordCount: Int {
        (text ?? "").split { $0.isWhitespace || $0.isNewline }.count
    }

    func masked() -> String {
        let t = text ?? ""
        let tail = t.count > 8 ? String(t.suffix(4)) : ""
        return "••••••••" + tail
    }
}

struct Pinboard: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var color: PinColor
}

/// A copy Tray deliberately didn't save, shown in the StatusBanner.
struct SkippedNotice: Equatable {
    var sourceApp: String
    var date = Date()
}
