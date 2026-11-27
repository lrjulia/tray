import SwiftUI

// MARK: - Actions (⌘K)

struct ActionEntry: Identifiable {
    let id: String
    let title: String
    var section: String
    var shortcut: String?
    let run: () -> Void
}

struct ActionsMenuView: View {
    @Bindable var model: AppModel
    @State private var filter = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool
    @Environment(\.trayAccent) private var accent

    var body: some View {
        ZStack {
            Color.black.opacity(0.15).onTapGesture { model.showActions = false }
            VStack(spacing: 0) {
                TextField("Search actions", text: $filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(.horizontal, Tokens.S.s4)
                    .frame(height: 44)
                    .focused($focused)
                    .onKeyPress(keys: [.upArrow, .downArrow, .return, .escape], phases: [.down, .repeat]) { press in
                        handle(press)
                    }
                    .accessibilityLabel("Search actions")
                Rectangle().fill(Tokens.C.line).frame(height: 1)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                if index == 0 || entries[index - 1].section != entry.section {
                                    Text(entry.section)
                                        .font(Tokens.T.captionStrong)
                                        .foregroundStyle(Tokens.C.inkMuted)
                                        .padding(.horizontal, Tokens.S.s3)
                                        .padding(.top, Tokens.S.s2)
                                        .padding(.bottom, 4)
                                }
                                row(entry, selected: index == highlighted)
                                    .id(entry.id)
                                    .onTapGesture { run(entry) }
                            }
                        }
                        .padding(Tokens.S.s2)
                    }
                    .onChange(of: highlighted) {
                        if entries.indices.contains(highlighted) { proxy.scrollTo(entries[highlighted].id) }
                    }
                }
            }
            .frame(width: 440, height: 380)
            .background(Tokens.C.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.R.lg))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        }
        .onAppear { focused = true; highlighted = 0 }
        .onChange(of: filter) { highlighted = 0 }
    }

    private func row(_ entry: ActionEntry, selected: Bool) -> some View {
        HStack {
            Text(entry.title).font(Tokens.T.body)
            Spacer()
            if let s = entry.shortcut { Keycap(text: s, quiet: true, onAccent: selected) }
        }
        .foregroundStyle(selected ? Tokens.C.onAccent : Tokens.C.ink)
        .padding(.horizontal, Tokens.S.s3)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: Tokens.R.md).fill(selected ? accent.color : .clear))
        .contentShape(Rectangle())
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .upArrow: highlighted = max(0, highlighted - 1); return .handled
        case .downArrow: highlighted = min(entries.count - 1, highlighted + 1); return .handled
        case .return:
            if entries.indices.contains(highlighted) { run(entries[highlighted]) }
            return .handled
        case .escape:
            model.showActions = false
            model.focusSearchToken += 1
            return .handled
        default: return .ignored
        }
    }

    private func run(_ entry: ActionEntry) {
        model.showActions = false
        entry.run()
    }

    private var entries: [ActionEntry] {
        let all = buildEntries()
        let q = filter.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { $0.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    private func buildEntries() -> [ActionEntry] {
        var e: [ActionEntry] = []
        let items = model.selectedItems
        guard let item = model.primaryItem else { return e }
        let multi = items.count > 1
        let textual = items.allSatisfy { $0.kind.isTextual }

        e.append(.init(id: "paste", title: multi ? "Paste \(items.count) items" : "Paste", section: "Paste", shortcut: "↵") { model.paste(plain: false) })
        e.append(.init(id: "plain", title: "Paste as plain text", section: "Paste", shortcut: "⌥↵") { model.paste(plain: true) })
        e.append(.init(id: "copy", title: "Copy", section: "Paste", shortcut: "⌘↵") { model.copySelection() })

        e.append(.init(id: "rename", title: "Rename…", section: "Organize", shortcut: "⌘R") { model.beginRename() })
        if item.kind.isTextual, !multi {
            e.append(.init(id: "edit", title: "Edit text…", section: "Organize", shortcut: "⌘E") { model.beginEdit() })
        }
        for board in model.store.pinboards {
            let pinned = items.allSatisfy { $0.pinboardIDs.contains(board.id) }
            e.append(.init(id: "pin-\(board.id)", title: pinned ? "Remove from \(board.name)" : "Pin to \(board.name)", section: "Organize") {
                model.pinSelection(to: board.id)
            })
        }
        if multi, textual {
            e.append(.init(id: "merge", title: "Merge into one item", section: "Organize") { model.mergeSelection() })
        }
        if !multi, item.kind.isTextual, (item.text ?? "").contains(where: \.isNewline) {
            e.append(.init(id: "split", title: "Split into one item per line", section: "Organize") { model.splitSelection() })
        }
        if item.isSensitive {
            e.append(.init(id: "reveal", title: model.revealed.contains(item.id) ? "Hide" : "Reveal", section: "Organize", shortcut: "⌘U") { model.toggleReveal() })
        }

        if !multi {
            switch item.kind {
            case .link, .email:
                e.append(.init(id: "open", title: item.kind == .email ? "Write email" : "Open in browser", section: "Open", shortcut: "⌘B") { model.openLink() })
            case .file:
                e.append(.init(id: "openfile", title: "Open", section: "Open") { model.openFile() })
                e.append(.init(id: "finder", title: "Show in Finder", section: "Open") { model.revealInFinder() })
            case .color:
                e.append(.init(id: "hex", title: "Copy as hex", section: "Color") { model.copyColor(as: "hex") })
                e.append(.init(id: "rgb", title: "Copy as RGB", section: "Color") { model.copyColor(as: "rgb") })
                e.append(.init(id: "hsl", title: "Copy as HSL", section: "Color") { model.copyColor(as: "hsl") })
            case .image:
                e.append(.init(id: "ocr", title: "Copy text from image", section: "Open") { model.copyTextFromImage() })
            default:
                break
            }
            if item.kind.isTextual, !model.isMasked(item) {
                for t in TextTransform.allCases {
                    e.append(.init(id: "t-\(t.rawValue)", title: t.label, section: "Transform") { model.applyTransform(t) })
                }
            }
        }

        e.append(.init(id: "details", title: model.showDetails ? "Hide details" : "Show details", section: "View", shortcut: "⌘I") { model.showDetails.toggle() })
        e.append(.init(id: "quicklook", title: "Quick Look", section: "View", shortcut: "Space") { model.showQuickLook = true })
        e.append(.init(id: "delete", title: multi ? "Delete \(items.count) items" : "Delete", section: "Delete", shortcut: "⌘⌫") { model.deleteSelection() })
        return e
    }
}

// MARK: - Rename

struct RenameOverlay: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.15).onTapGesture { model.renamingID = nil }
            VStack(alignment: .leading, spacing: Tokens.S.s3) {
                Text("Rename item").font(Tokens.T.headline)
                Text("The name shows in the list and is searchable. Leave it empty to show the content again.")
                    .font(Tokens.T.caption).foregroundStyle(Tokens.C.inkMuted)
                TextField("Name", text: $model.renameText)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { model.commitRename() }
                    .onKeyPress(.escape) {
                        model.renamingID = nil
                        model.focusSearchToken += 1
                        return .handled
                    }
                HStack {
                    Spacer()
                    Button("Cancel") { model.renamingID = nil }
                    Button("Rename") { model.commitRename() }.keyboardShortcut(.defaultAction)
                }
            }
            .foregroundStyle(Tokens.C.ink)
            .padding(Tokens.S.s4)
            .frame(width: 360)
            .background(Tokens.C.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.R.lg))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        }
        .onAppear { focused = true }
    }
}

// MARK: - Quick Look (Space)

struct QuickLookOverlay: View {
    @Bindable var model: AppModel
    let item: ClipItem

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).onTapGesture { model.showQuickLook = false }
            VStack(spacing: 0) {
                HStack {
                    Text(model.isMasked(item) ? (item.sensitiveLabel ?? "Secret") : item.title)
                        .font(Tokens.T.headline).lineLimit(1)
                    Spacer()
                    Text("Space or Esc to close").font(Tokens.T.caption).foregroundStyle(Tokens.C.inkMuted)
                }
                .foregroundStyle(Tokens.C.ink)
                .padding(.horizontal, Tokens.S.s4)
                .frame(height: 40)
                Rectangle().fill(Tokens.C.line).frame(height: 1)
                PreviewView(model: model, item: item, large: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(Tokens.C.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.R.lg))
            .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
            .padding(Tokens.S.s8)
        }
    }
}

// MARK: - Window shortcuts

/// Invisible buttons that give the window its ⌘ shortcuts. Disabled while editing, except Save.
struct KeyCommands: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            Group {
                ForEach(1...9, id: \.self) { n in
                    Button("") { model.pasteQuick(n) }
                        .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
                }
                Button("") { model.beginEdit() }.keyboardShortcut("e", modifiers: .command)
                Button("") { model.beginRename() }.keyboardShortcut("r", modifiers: .command)
                Button("") { model.showDetails.toggle() }.keyboardShortcut("i", modifiers: .command)
                Button("") { model.showActions.toggle() }.keyboardShortcut("k", modifiers: .command)
                Button("") { model.toggleReveal() }.keyboardShortcut("u", modifiers: .command)
                Button("") { model.openLink() }.keyboardShortcut("b", modifiers: .command)
                Button("") { model.pinSelection() }.keyboardShortcut("p", modifiers: .command)
                Button("") { model.deleteSelection() }.keyboardShortcut(.delete, modifiers: .command)
                Button("") { model.showQuickLook.toggle() }.keyboardShortcut("y", modifiers: .command)
            }
            .disabled(model.isEditing || model.renamingID != nil)

            Group {
                Button("") { model.viewMode = .list }.keyboardShortcut("1", modifiers: [.command, .option])
                Button("") { model.viewMode = .compact }.keyboardShortcut("2", modifiers: [.command, .option])
                Button("") { model.viewMode = .grid }.keyboardShortcut("3", modifiers: [.command, .option])
                Button("") { model.cycleBoard(-1) }.keyboardShortcut("[", modifiers: .command)
                Button("") { model.cycleBoard(1) }.keyboardShortcut("]", modifiers: .command)
                Button("") { model.onShowSettings?() }.keyboardShortcut(",", modifiers: .command)
                Button("") {
                    if model.showQuickLook { model.showQuickLook = false } else { model.closePanel() }
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .disabled(model.isEditing || model.renamingID != nil || model.showActions)

            Button("") { model.saveEdit() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.isEditing)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
