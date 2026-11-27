import AppKit
import Foundation
import Observation

/// Owns the history and pinboards, persists them encrypted, and applies retention.
/// Used from the main thread only.
@Observable
final class HistoryStore {
    private(set) var items: [ClipItem] = []
    private(set) var pinboards: [Pinboard] = []

    private struct Snapshot: Codable {
        var items: [ClipItem]
        var pinboards: [Pinboard]
    }

    @ObservationIgnored private let folder: URL
    @ObservationIgnored private let blobs: URL
    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored private var imageCache = NSCache<NSString, NSImage>()

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = base.appendingPathComponent("Tray", isDirectory: true)
        blobs = folder.appendingPathComponent("blobs", isDirectory: true)
        try? FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        load()
        if pinboards.isEmpty {
            pinboards = [Pinboard(name: "Snippets", color: .sky)]
        }
    }

    private var historyURL: URL { folder.appendingPathComponent("history.bin") }

    // MARK: Persistence

    private func load() {
        guard let sealed = try? Data(contentsOf: historyURL),
              let data = try? Vault.open(sealed),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        items = snap.items
        pinboards = snap.pinboards
    }

    func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() {
        let snap = Snapshot(items: items, pinboards: pinboards)
        guard let data = try? JSONEncoder().encode(snap), let sealed = try? Vault.seal(data) else { return }
        try? sealed.write(to: historyURL, options: [.atomic])
    }

    // MARK: Blobs (images)

    func storeImage(_ png: Data) -> String? {
        let name = UUID().uuidString + ".bin"
        guard let sealed = try? Vault.seal(png) else { return nil }
        do {
            try sealed.write(to: blobs.appendingPathComponent(name), options: [.atomic])
            return name
        } catch { return nil }
    }

    func imageData(for item: ClipItem) -> Data? {
        guard let name = item.imageBlob,
              let sealed = try? Data(contentsOf: blobs.appendingPathComponent(name)) else { return nil }
        return try? Vault.open(sealed)
    }

    func image(for item: ClipItem) -> NSImage? {
        guard let name = item.imageBlob else { return nil }
        if let cached = imageCache.object(forKey: name as NSString) { return cached }
        guard let data = imageData(for: item), let img = NSImage(data: data) else { return nil }
        imageCache.setObject(img, forKey: name as NSString)
        return img
    }

    private func deleteBlob(of item: ClipItem) {
        guard let name = item.imageBlob else { return }
        try? FileManager.default.removeItem(at: blobs.appendingPathComponent(name))
        imageCache.removeObject(forKey: name as NSString)
    }

    // MARK: Capture

    /// Adds a captured item, or bumps the existing one with the same content.
    @discardableResult
    func add(_ item: ClipItem) -> ClipItem {
        if let i = items.firstIndex(where: { $0.contentHash == item.contentHash }) {
            var existing = items.remove(at: i)
            existing.lastCopied = Date()
            existing.copyCount += 1
            existing.sourceApp = item.sourceApp ?? existing.sourceApp
            existing.sourceBundleID = item.sourceBundleID ?? existing.sourceBundleID
            if item.imageBlob != nil, item.imageBlob != existing.imageBlob {
                deleteBlob(of: item) // duplicate image: keep the original blob
            }
            items.insert(existing, at: 0)
            scheduleSave()
            return existing
        }
        items.insert(item, at: 0)
        scheduleSave()
        return item
    }

    func update(_ id: UUID, _ change: (inout ClipItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
        scheduleSave()
    }

    func item(_ id: UUID) -> ClipItem? { items.first { $0.id == id } }

    // MARK: Organize

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        update(id) { $0.customName = trimmed.isEmpty ? nil : trimmed }
    }

    /// Replaces an item's text. With `keepOriginal`, the edited text becomes a new item and the original stays.
    func saveEdit(_ id: UUID, text newText: String, keepOriginal: Bool) -> UUID? {
        guard let original = item(id) else { return nil }
        let data = Data(newText.utf8)
        let hash = Vault.sha256(Data(original.kind.rawValue.utf8) + data)
        if keepOriginal {
            var copy = original
            copy.id = UUID()
            copy.text = newText
            copy.rtfData = nil
            copy.editedAt = Date()
            copy.lastCopied = Date()
            copy.copyCount = 1
            copy.contentHash = hash
            copy.byteSize = data.count
            items.insert(copy, at: 0)
            scheduleSave()
            return copy.id
        }
        update(id) {
            $0.text = newText
            $0.rtfData = nil
            if $0.kind == .richText { $0.kind = .text }
            $0.editedAt = Date()
            $0.contentHash = hash
            $0.byteSize = data.count
        }
        return id
    }

    func delete(_ ids: [UUID]) {
        for item in items where ids.contains(item.id) { deleteBlob(of: item) }
        items.removeAll { ids.contains($0.id) }
        scheduleSave()
    }

    func pin(_ ids: [UUID], to board: UUID) {
        for id in ids {
            update(id) { if !$0.pinboardIDs.contains(board) { $0.pinboardIDs.append(board) } }
        }
    }

    func unpin(_ ids: [UUID], from board: UUID? = nil) {
        for id in ids {
            update(id) { item in
                if let board { item.pinboardIDs.removeAll { $0 == board } } else { item.pinboardIDs.removeAll() }
            }
        }
    }

    /// Merges text items in the given order into one new item.
    func merge(_ ids: [UUID], separator: String) -> UUID? {
        let parts = ids.compactMap { item($0) }.filter { $0.kind.isTextual }.compactMap(\.text)
        guard parts.count > 1 else { return nil }
        let new = Self.makeTextItem(parts.joined(separator: separator), source: "Tray")
        return add(new).id
    }

    /// Splits a multi-line text item into one item per non-empty line.
    func split(_ id: UUID) -> Int {
        guard let it = item(id), let text = it.text else { return 0 }
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count > 1 else { return 0 }
        for line in lines.reversed() { add(Self.makeTextItem(line, source: it.sourceApp)) }
        return lines.count
    }

    func addTextItem(_ text: String, source: String?) -> UUID {
        add(Self.makeTextItem(text, source: source)).id
    }

    static func makeTextItem(_ text: String, source: String?) -> ClipItem {
        let data = Data(text.utf8)
        let kind = ContentClassifier.classify(text: text, bundleID: nil)
        return ClipItem(
            kind: kind, text: text, sourceApp: source,
            sensitiveLabel: SensitiveDetector.label(for: text),
            byteSize: data.count,
            contentHash: Vault.sha256(Data(kind.rawValue.utf8) + data)
        )
    }

    // MARK: Pinboards

    func addPinboard(name: String) -> UUID {
        let color = PinColor.allCases[pinboards.count % PinColor.allCases.count]
        let board = Pinboard(name: name, color: color)
        pinboards.append(board)
        scheduleSave()
        return board.id
    }

    func updatePinboard(_ board: Pinboard) {
        guard let i = pinboards.firstIndex(where: { $0.id == board.id }) else { return }
        pinboards[i] = board
        scheduleSave()
    }

    func deletePinboard(_ id: UUID) {
        pinboards.removeAll { $0.id == id }
        for i in items.indices { items[i].pinboardIDs.removeAll { $0 == id } }
        scheduleSave()
    }

    // MARK: Retention

    func applyRetention(_ settings: TraySettings) {
        let now = Date()
        let expired = items.filter { item in
            guard !item.isPinned, let interval = settings.retention(for: item.kind.group).interval else { return false }
            return now.timeIntervalSince(item.lastCopied) > interval
        }
        if !expired.isEmpty { delete(expired.map(\.id)) }
    }

    func clearAll(keepPinned: Bool = true) {
        let ids = items.filter { !keepPinned || !$0.isPinned }.map(\.id)
        delete(ids)
        saveNow()
    }

    // MARK: Export / import

    private struct ExportItem: Codable {
        var item: ClipItem
        var imagePNG: Data?
    }

    private struct ExportFile: Codable {
        var version = 1
        var items: [ExportItem]
        var pinboards: [Pinboard]
    }

    func exportData() throws -> Data {
        let exported = items.map { ExportItem(item: $0, imagePNG: imageData(for: $0)) }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        return try enc.encode(ExportFile(items: exported, pinboards: pinboards))
    }

    func importData(_ data: Data) throws -> Int {
        let file = try JSONDecoder().decode(ExportFile.self, from: data)
        for board in file.pinboards where !pinboards.contains(where: { $0.id == board.id }) {
            pinboards.append(board)
        }
        var count = 0
        for entry in file.items.reversed() where !items.contains(where: { $0.contentHash == entry.item.contentHash }) {
            var it = entry.item
            if let png = entry.imagePNG { it.imageBlob = storeImage(png) }
            items.insert(it, at: 0)
            count += 1
        }
        items.sort { $0.lastCopied > $1.lastCopied }
        scheduleSave()
        return count
    }
}
