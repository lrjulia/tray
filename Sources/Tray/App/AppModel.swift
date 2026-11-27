import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

struct ListSection: Identifiable {
    let id: String
    let title: String
    let items: [ClipItem]
}

enum Banner: Equatable {
    case paused
    case skipped(String)
    case info(String)
}

/// The app's state and every user action. Views read it; services report into it. Main thread only.
@Observable
final class AppModel {
    let store = HistoryStore()
    @ObservationIgnored lazy var paster = Paster(store: store)
    @ObservationIgnored lazy var monitor = ClipboardMonitor(model: self)

    var settings = TraySettings.load() {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            applyAppearance()
            if settings.hideFromScreenSharing != oldValue.hideFromScreenSharing { onPrivacyChange?() }
            if settings.showMenuBarIcon != oldValue.showMenuBarIcon { onMenuBarIconChange?() }
        }
    }

    // Window state
    var query = "" { didSet { if query != oldValue { selectFirst() } } }
    var boardID: UUID? { didSet { selectFirst() } }
    var kindFilter: KindGroup? { didSet { selectFirst() } }
    var viewMode: ViewMode = .list {
        didSet { if settings.rememberLastView { settings.lastViewMode = viewMode } }
    }
    var selection: [UUID] = []
    var showDetails = true
    var keepOnTop = false
    var targetAppName = "front app"

    // Editing, renaming, overlays
    var isEditing = false
    var editText = ""
    var keepOriginal = false
    var renamingID: UUID?
    var renameText = ""
    var showActions = false
    var showQuickLook = false
    var revealed: Set<UUID> = []
    var focusSearchToken = 0

    // Status
    var isPaused = false
    var banner: Banner?
    /// Bumped when the system accent changes, so views re-read it.
    var accentVersion = 0

    // Paste Stack
    var stackActive = false
    var stack: [UUID] = []
    var stackNext = 0

    // Paste next (without opening)
    @ObservationIgnored private var pasteNextIndex = 0
    @ObservationIgnored private var pasteNextLast = Date.distantPast
    @ObservationIgnored private var infoWork: DispatchWorkItem?
    @ObservationIgnored private var pauseWork: DispatchWorkItem?

    // Hooks set by the AppDelegate
    @ObservationIgnored var onShowPanel: (() -> Void)?
    @ObservationIgnored var onHidePanel: (() -> Void)?
    @ObservationIgnored var onShowSettings: (() -> Void)?
    @ObservationIgnored var onShowStack: ((Bool) -> Void)?
    @ObservationIgnored var onPrivacyChange: (() -> Void)?
    @ObservationIgnored var onMenuBarIconChange: (() -> Void)?

    init() {
        viewMode = settings.openInCompact ? .compact : (settings.rememberLastView ? settings.lastViewMode : .list)
    }

    // MARK: Theme

    var accent: AccentOption {
        _ = accentVersion
        return settings.accent.resolved
    }

    func applyAppearance() {
        switch settings.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // MARK: Derived lists

    var currentBoard: Pinboard? { store.pinboards.first { $0.id == boardID } }

    private func matches(_ item: ClipItem) -> Bool {
        if let boardID, !item.pinboardIDs.contains(boardID) { return false }
        if let kindFilter, item.kind.group != kindFilter { return false }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        let masked = item.isSensitive && settings.maskSensitive && !revealed.contains(item.id)
        let haystack = masked
            ? [item.customName, item.sensitiveLabel, item.sourceApp].compactMap { $0 }.joined(separator: " ")
            : item.searchableText
        return q.split(separator: " ").allSatisfy {
            haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private func sorted(_ items: [ClipItem]) -> [ClipItem] {
        switch settings.sortOrder {
        case .lastCopied: return items.sorted { $0.lastCopied > $1.lastCopied }
        case .firstCopied: return items.sorted { $0.firstCopied > $1.firstCopied }
        case .timesCopied: return items.sorted { $0.copyCount > $1.copyCount }
        case .size: return items.sorted { $0.byteSize > $1.byteSize }
        }
    }

    var sections: [ListSection] {
        let filtered = sorted(store.items.filter(matches))
        if let board = currentBoard {
            return filtered.isEmpty ? [] : [ListSection(id: board.id.uuidString, title: board.name, items: filtered)]
        }
        var result: [ListSection] = []
        let pinned = filtered.filter(\.isPinned)
        if !pinned.isEmpty { result.append(ListSection(id: "pinned", title: "Pinned", items: pinned)) }
        let rest = filtered.filter { !$0.isPinned }
        guard settings.sortOrder == .lastCopied || settings.sortOrder == .firstCopied else {
            if !rest.isEmpty { result.append(ListSection(id: "all", title: "History", items: rest)) }
            return result
        }
        let cal = Calendar.current
        let now = Date()
        var buckets: [(String, [ClipItem])] = []
        for item in rest {
            let date = settings.sortOrder == .lastCopied ? item.lastCopied : item.firstCopied
            let title: String
            if cal.isDateInToday(date) { title = "Today" }
            else if cal.isDateInYesterday(date) { title = "Yesterday" }
            else if let days = cal.dateComponents([.day], from: date, to: now).day, days < 7 { title = "This week" }
            else { title = date.formatted(.dateTime.month(.wide).year()) }
            if let i = buckets.firstIndex(where: { $0.0 == title }) { buckets[i].1.append(item) }
            else { buckets.append((title, [item])) }
        }
        result += buckets.map { ListSection(id: $0.0, title: $0.0, items: $0.1) }
        return result
    }

    var visibleItems: [ClipItem] { sections.flatMap(\.items) }

    /// ⌘1–⌘9 go to the first nine history items (pinned items are excluded).
    func quickIndex(of item: ClipItem) -> Int? {
        guard !item.isPinned || boardID != nil else { return nil }
        let order = visibleItems.filter { boardID != nil || !$0.isPinned }
        guard let i = order.firstIndex(where: { $0.id == item.id }), i < 9 else { return nil }
        return i + 1
    }

    var selectedItems: [ClipItem] { selection.compactMap { store.item($0) } }
    var primaryItem: ClipItem? { selection.last.flatMap { store.item($0) } }

    func isMasked(_ item: ClipItem) -> Bool {
        item.isSensitive && settings.maskSensitive && !revealed.contains(item.id)
    }

    // MARK: Selection

    func selectFirst() {
        if let first = visibleItems.first { selection = [first.id] } else { selection = [] }
    }

    func select(_ id: UUID, extend: Bool = false) {
        guard !isEditing else { return }
        if extend {
            if let i = selection.firstIndex(of: id) { if selection.count > 1 { selection.remove(at: i) } }
            else { selection.append(id) }
        } else {
            selection = [id]
        }
    }

    func moveSelection(_ delta: Int, extend: Bool = false) {
        guard !isEditing else { return }
        let items = visibleItems
        guard !items.isEmpty else { return }
        let current = selection.last.flatMap { id in items.firstIndex { $0.id == id } } ?? -1
        let next = max(0, min(items.count - 1, current + delta))
        let id = items[next].id
        if extend {
            if !selection.contains(id) { selection.append(id) }
        } else {
            selection = [id]
        }
    }

    // MARK: Panel

    func openPanel() {
        targetAppName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "front app"
        query = ""
        isEditing = false
        showActions = false
        showQuickLook = false
        renamingID = nil
        revealed = []
        if settings.openInCompact { viewMode = .compact }
        selectFirst()
        focusSearchToken += 1
        onShowPanel?()
    }

    func closePanel() {
        isEditing = false
        showActions = false
        showQuickLook = false
        renamingID = nil
        onHidePanel?()
    }

    func togglePanel(isVisible: Bool) {
        isVisible ? closePanel() : openPanel()
    }

    // MARK: Paste and copy

    func performPrimary() {
        settings.primaryAction == .paste ? paste(plain: false) : copySelection()
    }

    func paste(plain: Bool) {
        let items = selectedItems
        guard !items.isEmpty, !isEditing else { return }
        paster.write(items, plainText: plain, separator: settings.pasteSeparator.string)
        closePanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            if !self.paster.sendCommandV() {
                self.showInfo("Copied. Allow Accessibility in Settings so Tray can paste for you.")
            }
        }
    }

    func copySelection() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        paster.write(items, plainText: false, separator: settings.pasteSeparator.string)
        closePanel()
    }

    func pasteQuick(_ n: Int) {
        let order = visibleItems.filter { boardID != nil || !$0.isPinned }
        guard n >= 1, n <= order.count else { return }
        selection = [order[n - 1].id]
        performPrimary()
    }

    /// Pastes the next history item without opening the window (⌃⇧V). Starts over after 20 s.
    func pasteNext() {
        if Date().timeIntervalSince(pasteNextLast) > 20 { pasteNextIndex = 0 }
        let items = store.items.filter { !$0.isPinned }
        guard pasteNextIndex < items.count else { return }
        paster.write([items[pasteNextIndex]], plainText: false, separator: "")
        pasteNextIndex += 1
        pasteNextLast = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.paster.sendCommandV()
        }
    }

    // MARK: Capture callbacks

    func didCapture(_ item: ClipItem) {
        if stackActive {
            if !stack.contains(item.id) { stack.append(item.id) }
            loadStackNext()
        }
    }

    func noteSkipped(source: String) {
        banner = .skipped(source)
        scheduleBannerDismiss(after: 6)
    }

    func showInfo(_ text: String) {
        banner = .info(text)
        scheduleBannerDismiss(after: 4)
    }

    private func scheduleBannerDismiss(after seconds: Double) {
        infoWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.banner = self.isPaused ? .paused : nil
        }
        infoWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: Pause

    func togglePause() {
        setPaused(!isPaused)
    }

    func setPaused(_ paused: Bool, for minutes: Int? = nil) {
        isPaused = paused
        banner = paused ? .paused : nil
        pauseWork?.cancel()
        if paused, let minutes {
            let work = DispatchWorkItem { [weak self] in self?.setPaused(false) }
            pauseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(minutes * 60), execute: work)
        }
    }

    // MARK: Edit

    func beginEdit() {
        guard let item = primaryItem, item.kind.isTextual else {
            showInfo("Only text items can be edited.")
            return
        }
        if isMasked(item) {
            showInfo("Reveal it first (⌘U) to edit.")
            return
        }
        selection = [item.id]
        editText = item.text ?? ""
        keepOriginal = false
        showActions = false
        isEditing = true
    }

    func saveEdit() {
        guard isEditing, let item = primaryItem else { return }
        if editText != item.text, let id = store.saveEdit(item.id, text: editText, keepOriginal: keepOriginal) {
            selection = [id]
            showInfo(keepOriginal ? "Saved as a new item" : "Saved")
        }
        isEditing = false
        focusSearchToken += 1
    }

    func cancelEdit() {
        isEditing = false
        focusSearchToken += 1
    }

    var editHasChanges: Bool { isEditing && editText != (primaryItem?.text ?? "") }

    // MARK: Other actions

    func beginRename() {
        guard let item = primaryItem else { return }
        renameText = item.customName ?? ""
        renamingID = item.id
        showActions = false
    }

    func commitRename() {
        if let id = renamingID { store.rename(id, to: renameText) }
        renamingID = nil
        focusSearchToken += 1
    }

    func toggleReveal() {
        guard let item = primaryItem, item.isSensitive else { return }
        if revealed.contains(item.id) { revealed.remove(item.id) } else { revealed.insert(item.id) }
    }

    func deleteSelection() {
        let ids = selection
        guard !ids.isEmpty else { return }
        let items = visibleItems
        let lastIndex = items.firstIndex { $0.id == ids.last } ?? 0
        store.delete(ids)
        let remaining = visibleItems
        if remaining.isEmpty { selection = [] }
        else { selection = [remaining[min(lastIndex, remaining.count - 1)].id] }
    }

    func pinSelection(to board: UUID? = nil) {
        guard let target = board ?? boardID ?? store.pinboards.first?.id else { return }
        let ids = selection
        let allPinned = selectedItems.allSatisfy { $0.pinboardIDs.contains(target) }
        if allPinned { store.unpin(ids, from: target) } else { store.pin(ids, to: target) }
        let name = store.pinboards.first { $0.id == target }?.name ?? "pinboard"
        showInfo(allPinned ? "Removed from \(name)" : "Pinned to \(name)")
    }

    func mergeSelection() {
        guard selection.count > 1, let id = store.merge(selection, separator: settings.pasteSeparator.string) else {
            showInfo("Select two or more text items to merge.")
            return
        }
        selection = [id]
        showInfo("Merged into a new item")
    }

    func splitSelection() {
        guard let item = primaryItem else { return }
        let n = store.split(item.id)
        if n > 0 { selectFirst(); showInfo("Split into \(n) items") } else { showInfo("Nothing to split: it's one line.") }
    }

    func applyTransform(_ t: TextTransform) {
        guard let item = primaryItem, let text = item.text, item.kind.isTextual else { return }
        guard let out = t.apply(text) else {
            showInfo("\(t.label) didn't work on this item.")
            return
        }
        let id = store.addTextItem(out, source: item.sourceApp)
        selection = [id]
        showInfo("\(t.label): new item added")
    }

    func copyTextFromImage() {
        guard let item = primaryItem, item.kind == .image else { return }
        guard let text = item.ocrText, !text.isEmpty else {
            showInfo("No text found in this image.")
            return
        }
        let id = store.addTextItem(text, source: item.sourceApp)
        selection = [id]
        showInfo("Text from image added")
    }

    func openLink() {
        guard let item = primaryItem else { return }
        if item.kind == .link, let s = item.text, let url = URL(string: s) {
            NSWorkspace.shared.open(url)
            closePanel()
        } else if item.kind == .email, let s = item.text, let url = URL(string: "mailto:" + s) {
            NSWorkspace.shared.open(url)
            closePanel()
        }
    }

    func openFile() {
        guard let item = primaryItem, item.kind == .file, let path = item.filePaths?.first else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
        closePanel()
    }

    func revealInFinder() {
        guard let item = primaryItem, item.kind == .file else { return }
        NSWorkspace.shared.activateFileViewerSelecting((item.filePaths ?? []).map { URL(fileURLWithPath: $0) })
    }

    func copyColor(as format: String) {
        guard let item = primaryItem, let s = item.text, let c = ContentClassifier.rgb(from: s) else { return }
        let value: String
        switch format {
        case "rgb": value = "rgb(\(Int(c.r * 255)), \(Int(c.g * 255)), \(Int(c.b * 255)))"
        case "hsl": value = Self.hsl(c)
        default: value = s
        }
        paster.writeString(value)
        showInfo("Copied \(value)")
    }

    static func hsl(_ c: (r: Double, g: Double, b: Double)) -> String {
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b)
        let l = (mx + mn) / 2
        var h = 0.0, s = 0.0
        if mx != mn {
            let d = mx - mn
            s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
            if mx == c.r { h = (c.g - c.b) / d + (c.g < c.b ? 6 : 0) }
            else if mx == c.g { h = (c.b - c.r) / d + 2 }
            else { h = (c.r - c.g) / d + 4 }
            h /= 6
        }
        return "hsl(\(Int(h * 360)), \(Int(s * 100))%, \(Int(l * 100))%)"
    }

    func cycleBoard(_ delta: Int) {
        let ids: [UUID?] = [nil] + store.pinboards.map { Optional($0.id) }
        let i = ids.firstIndex(of: boardID) ?? 0
        boardID = ids[(i + delta + ids.count) % ids.count]
    }

    // MARK: Paste Stack

    func toggleStack() {
        stackActive.toggle()
        stack = []
        stackNext = 0
        onShowStack?(stackActive)
        if stackActive, !Paster.isTrusted { Paster.requestTrust() }
    }

    /// Keeps the next stack item on the pasteboard, so the next ⌘V pastes it.
    func loadStackNext() {
        guard stackActive, stackNext < stack.count, let item = store.item(stack[stackNext]) else { return }
        paster.write([item], plainText: false, separator: "")
    }

    /// Called just after the user pressed ⌘V while the stack is active.
    func stackDidPaste() {
        guard stackActive, stackNext < stack.count else { return }
        stackNext += 1
        if stackNext >= stack.count {
            showInfo("Paste Stack finished")
            toggleStack()
        } else {
            loadStackNext()
        }
    }

    func pasteWholeStack() {
        let items = stack.compactMap { store.item($0) }
        guard !items.isEmpty else { return }
        paster.write(items, plainText: false, separator: settings.pasteSeparator.string)
        toggleStack()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.paster.sendCommandV() }
    }

    func removeFromStack(_ id: UUID) {
        guard let i = stack.firstIndex(of: id) else { return }
        stack.remove(at: i)
        if i < stackNext { stackNext -= 1 }
        loadStackNext()
    }

    func moveStack(from source: IndexSet, to destination: Int) {
        stack.move(fromOffsets: source, toOffset: destination)
        loadStackNext()
    }
}
