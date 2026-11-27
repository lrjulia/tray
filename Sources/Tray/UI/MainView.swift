import SwiftUI

/// The detached window: header, list (+ preview and details), action bar, and overlays.
struct MainView: View {
    @Bindable var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        let accent = model.accent
        ZStack {
            VStack(spacing: 0) {
                HeaderView(model: model, searchFocused: $searchFocused)
                if let banner = model.banner {
                    StatusBannerView(
                        banner: banner,
                        onResume: { model.setPaused(false) },
                        onSettings: { model.onShowSettings?() }
                    )
                }
                Rectangle().fill(Tokens.C.line).frame(height: 1)
                content
                ActionBarView(model: model)
            }
            .background(Tokens.C.surface)

            if model.showActions { ActionsMenuView(model: model) }
            if model.renamingID != nil { RenameOverlay(model: model) }
            if model.showQuickLook, let item = model.primaryItem { QuickLookOverlay(model: model, item: item) }
        }
        .clipShape(RoundedRectangle(cornerRadius: Tokens.R.xl, style: .continuous))
        .environment(\.trayAccent, accent)
        .tint(accent.color)
        .background(KeyCommands(model: model))
        .onAppear { searchFocused = true }
        .onChange(of: model.focusSearchToken) { searchFocused = true }
    }

    @ViewBuilder private var content: some View {
        if model.visibleItems.isEmpty {
            EmptyStateView(model: model)
        } else {
            switch model.viewMode {
            case .list:
                HStack(spacing: 0) {
                    ListColumn(model: model, compact: false)
                        .frame(width: Tokens.Size.listWidth)
                    Rectangle().fill(Tokens.C.line).frame(width: 1)
                    DetailPane(model: model)
                }
            case .compact:
                ListColumn(model: model, compact: true)
            case .grid:
                GridColumn(model: model)
            }
        }
    }
}

// MARK: - Header

struct HeaderView: View {
    @Bindable var model: AppModel
    var searchFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: Tokens.S.s3) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(Tokens.C.inkMuted)
            TextField(placeholder, text: $model.query)
                .textFieldStyle(.plain)
                .font(Tokens.T.search)
                .foregroundStyle(Tokens.C.ink)
                .focused(searchFocused)
                .disabled(model.isEditing)
                .onKeyPress(keys: [.upArrow, .downArrow, .return, .escape, .space], phases: [.down, .repeat]) { press in
                    handle(press)
                }
                .accessibilityLabel("Search history")

            ViewModePicker(model: model)

            Menu {
                Button("History") { model.boardID = nil }
                Divider()
                ForEach(model.store.pinboards) { board in
                    Button(board.name) { model.boardID = board.id }
                }
            } label: {
                Text(model.currentBoard?.name ?? "History")
            }
            .menuStyle(.button)
            .fixedSize()
            .accessibilityLabel("Board")

            Menu {
                Button("All kinds") { model.kindFilter = nil }
                Divider()
                ForEach(KindGroup.allCases) { group in
                    Button(group.label) { model.kindFilter = group }
                }
            } label: {
                Text(model.kindFilter?.label ?? "All kinds")
            }
            .menuStyle(.button)
            .fixedSize()
            .accessibilityLabel("Kind")

            Button {
                model.keepOnTop.toggle()
            } label: {
                Image(systemName: model.keepOnTop ? "pin.fill" : "pin")
                    .foregroundStyle(model.keepOnTop ? model.accent.color : Tokens.C.inkMuted)
            }
            .buttonStyle(.plain)
            .help(model.keepOnTop ? "Stop keeping on top" : "Keep on top")
            .accessibilityLabel("Keep window on top")
        }
        .padding(.leading, 20)
        .padding(.trailing, Tokens.S.s4)
        .frame(height: 64)
    }

    private var placeholder: String {
        if let board = model.currentBoard { return "Search \(board.name)" }
        return "Search history"
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        let shift = press.modifiers.contains(.shift)
        switch press.key {
        case .upArrow:
            model.moveSelection(-1, extend: shift)
            return .handled
        case .downArrow:
            model.moveSelection(1, extend: shift)
            return .handled
        case .return:
            if press.modifiers.contains(.command) { model.copySelection() }
            else if press.modifiers.contains(.option) { model.paste(plain: true) }
            else { model.performPrimary() }
            return .handled
        case .escape:
            if !model.query.isEmpty { model.query = "" } else { model.closePanel() }
            return .handled
        case .space:
            guard model.query.isEmpty else { return .ignored }
            model.showQuickLook.toggle()
            return .handled
        default:
            return .ignored
        }
    }
}

struct ViewModePicker: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ViewMode.allCases) { mode in
                Button {
                    model.viewMode = mode
                } label: {
                    Image(systemName: mode.symbol)
                        .frame(width: 30, height: 26)
                        .foregroundStyle(model.viewMode == mode ? Tokens.C.ink : Tokens.C.inkMuted)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(model.viewMode == mode ? Tokens.C.surfaceRaised : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(mode.label) view")
                .accessibilityLabel("\(mode.label) view")
                .accessibilityAddTraits(model.viewMode == mode ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: Tokens.R.md).fill(Tokens.C.surfaceSunken))
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: Tokens.S.s2) {
            Image(systemName: icon).font(.system(size: 28)).foregroundStyle(Tokens.C.inkMuted)
            Text(title).font(Tokens.T.headline).foregroundStyle(Tokens.C.ink)
            Text(detail).font(Tokens.T.callout).foregroundStyle(Tokens.C.inkMuted)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hasFilter: Bool { !model.query.isEmpty || model.kindFilter != nil }

    private var icon: String {
        if hasFilter { return "magnifyingglass" }
        if model.boardID != nil { return "pin" }
        return model.isPaused ? "pause.circle" : "list.clipboard"
    }

    private var title: String {
        if hasFilter { return "No matches" }
        if let board = model.currentBoard { return "\(board.name) is empty" }
        return model.isPaused ? "Recording is paused" : "Nothing copied yet"
    }

    private var detail: String {
        if hasFilter { return "Search looks in text, link titles, file names, custom names and text inside images." }
        if model.boardID != nil { return "Pin items here with ⌘P. Pinned items never expire." }
        return model.isPaused ? "Resume recording to start saving copies again." : "Copy something in any app and it shows up here."
    }
}
