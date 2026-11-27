import AppKit

/// Watches the general pasteboard and records copies.
/// macOS has no change notification for the pasteboard, so it checks `changeCount` every 0.5 s,
/// which is cheap and reads no content until something changed.
final class ClipboardMonitor {
    private unowned let model: AppModel
    private var timer: Timer?
    private var lastChangeCount: Int
    private var lastCaptureTime = Date.distantPast
    private var lastCapturedID: UUID?

    init(model: AppModel) {
        self.model = model
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        if pb.changeCount == model.paster.ownChangeCount { return }
        capture(pb)
    }

    private func capture(_ pb: NSPasteboard) {
        let settings = model.settings
        let store = model.store
        let front = NSWorkspace.shared.frontmostApplication
        let appName = front?.localizedName
        let bundleID = front?.bundleIdentifier
        let types = (pb.types ?? []).map(\.rawValue)

        // A source clearing its own copy (password managers do this) removes it from history too.
        if types.isEmpty {
            if let id = lastCapturedID, let item = store.item(id), item.isSensitive,
               Date().timeIntervalSince(item.lastCopied) < 180 {
                store.delete([id])
            }
            return
        }

        if model.isPaused { return }
        if bundleID != nil, bundleID == Bundle.main.bundleIdentifier { return }

        let ignoredType = types.contains { settings.ignoredPasteboardTypes.contains($0) }
        let ignoredApp = bundleID.map { settings.ignoredBundleIDs.contains($0) } ?? false
        if ignoredType || ignoredApp {
            model.noteSkipped(source: appName ?? "a private source")
            return
        }

        guard let newItem = makeItem(pb, appName: appName, bundleID: bundleID) else { return }

        if settings.copyAndAppend, appendIfDoubleCopy(newItem) { return }

        lastCaptureTime = Date()
        let added = store.add(newItem)
        lastCapturedID = added.id
        model.didCapture(added)

        if added.kind == .image, settings.ocrEnabled, added.ocrText == nil, let image = store.image(for: added) {
            OCR.recognize(image) { text in
                guard let text else { return }
                store.update(added.id) { $0.ocrText = text }
            }
        }
    }

    private func makeItem(_ pb: NSPasteboard, appName: String?, bundleID: String?) -> ClipItem? {
        let store = model.store

        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            let paths = urls.map(\.path)
            let joined = paths.joined(separator: "\n")
            let size = paths.reduce(0) { total, path in
                total + ((try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0)
            }
            return ClipItem(
                kind: .file, text: joined, filePaths: paths, sourceApp: appName, sourceBundleID: bundleID,
                byteSize: size, contentHash: Vault.sha256(Data(("file:" + joined).utf8))
            )
        }

        if let string = pb.string(forType: .string), !string.isEmpty {
            let rtf = pb.data(forType: .rtf)
            let kind = ContentClassifier.classify(text: string, bundleID: bundleID, hasRTF: rtf != nil)
            let data = Data(string.utf8)
            return ClipItem(
                kind: kind, text: string, rtfData: kind == .richText ? rtf : nil,
                sourceApp: appName, sourceBundleID: bundleID,
                sensitiveLabel: SensitiveDetector.label(for: string),
                byteSize: data.count, contentHash: Vault.sha256(Data(kind.rawValue.utf8) + data)
            )
        }

        if let image = NSImage(pasteboard: pb), let png = image.pngData() {
            let hash = Vault.sha256(png)
            let isDuplicate = store.items.contains { $0.contentHash == hash }
            let blob = isDuplicate ? nil : store.storeImage(png)
            let rep = NSBitmapImageRep(data: png)
            return ClipItem(
                kind: .image, imageBlob: blob, imageWidth: rep?.pixelsWide, imageHeight: rep?.pixelsHigh,
                sourceApp: appName, sourceBundleID: bundleID, byteSize: png.count, contentHash: hash
            )
        }
        return nil
    }

    /// "Copy and append": pressing ⌘C twice quickly on the same selection adds it to the end of the previous item.
    private func appendIfDoubleCopy(_ newItem: ClipItem) -> Bool {
        let store = model.store
        guard newItem.kind.isTextual, Date().timeIntervalSince(lastCaptureTime) < 0.6,
              store.items.count >= 2,
              store.items[0].contentHash == newItem.contentHash,
              store.items[1].kind.isTextual else { return false }
        let first = store.items[0]
        let target = store.items[1]
        let addition = newItem.text ?? ""
        store.update(target.id) { item in
            item.text = (item.text ?? "") + "\n" + addition
            item.rtfData = nil
            if item.kind == .richText { item.kind = .text }
            item.lastCopied = Date()
            item.contentHash = Vault.sha256(Data(item.kind.rawValue.utf8) + Data((item.text ?? "").utf8))
        }
        if first.copyCount > 1 {
            store.update(first.id) { $0.copyCount -= 1 }
        } else {
            store.delete([first.id])
        }
        lastCaptureTime = .distantPast
        model.showInfo("Added to the previous item")
        return true
    }
}
