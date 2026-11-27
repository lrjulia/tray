import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Writes items to the pasteboard and pastes them into the frontmost app.
/// Pasting into other apps simulates ⌘V, which needs Accessibility permission.
final class Paster {
    private let store: HistoryStore
    /// The pasteboard's changeCount right after Tray wrote to it, so the monitor ignores Tray's own writes.
    private(set) var ownChangeCount = -1

    init(store: HistoryStore) {
        self.store = store
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Writing

    func write(_ items: [ClipItem], plainText: Bool, separator: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if items.count == 1, let item = items.first {
            writeSingle(item, plainText: plainText, to: pb)
        } else {
            let joined = items.compactMap(textValue).joined(separator: separator)
            pb.setString(joined, forType: .string)
        }
        ownChangeCount = pb.changeCount
    }

    func writeString(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        ownChangeCount = pb.changeCount
    }

    private func writeSingle(_ item: ClipItem, plainText: Bool, to pb: NSPasteboard) {
        switch item.kind {
        case .image:
            guard let data = store.imageData(for: item) else { return }
            pb.setData(data, forType: .png)
            if let tiff = NSImage(data: data)?.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
        case .file:
            let urls = (item.filePaths ?? []).map { URL(fileURLWithPath: $0) as NSURL }
            pb.writeObjects(urls)
        case .richText:
            if !plainText, let rtf = item.rtfData { pb.setData(rtf, forType: .rtf) }
            pb.setString(item.text ?? "", forType: .string)
        case .link:
            pb.setString(item.text ?? "", forType: .string)
            if !plainText, let s = item.text, let url = URL(string: s) {
                pb.setString(url.absoluteString, forType: .URL)
            }
        default:
            pb.setString(item.text ?? "", forType: .string)
        }
    }

    private func textValue(_ item: ClipItem) -> String? {
        switch item.kind {
        case .image: return item.ocrText
        case .file: return item.filePaths?.joined(separator: "\n")
        default: return item.text
        }
    }

    // MARK: Pasting

    /// Simulates ⌘V in the frontmost app. Returns false if Accessibility permission is missing.
    @discardableResult
    func sendCommandV() -> Bool {
        guard Self.isTrusted else {
            Self.requestTrust()
            return false
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        return true
    }
}

extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
