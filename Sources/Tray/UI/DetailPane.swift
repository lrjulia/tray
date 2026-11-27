import AppKit
import SwiftUI

/// Right side of List view: the preview and Details, or the editor while editing.
struct DetailPane: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.isEditing, model.primaryItem != nil {
                EditorView(model: model)
            } else if model.selection.count > 1 {
                MultiSelectionSummary(model: model)
            } else if let item = model.primaryItem {
                VStack(spacing: 0) {
                    PreviewView(model: model, item: item, large: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    if model.showDetails {
                        DetailListView(model: model, item: item)
                    }
                }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MultiSelectionSummary: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.S.s2) {
            Text("\(model.selection.count) items selected").font(Tokens.T.headline)
            Text("Return pastes them in this order, joined by: \(model.settings.pasteSeparator.label.lowercased()).")
                .font(Tokens.T.callout).foregroundStyle(Tokens.C.inkMuted)
            ForEach(Array(model.selectedItems.enumerated()), id: \.element.id) { i, item in
                HStack(spacing: Tokens.S.s2) {
                    Text("\(i + 1)").font(Tokens.T.captionStrong).foregroundStyle(Tokens.C.inkMuted).frame(width: 16)
                    Text(model.isMasked(item) ? (item.sensitiveLabel ?? "Secret") : item.title).lineLimit(1)
                }
                .font(Tokens.T.body)
            }
            Spacer()
        }
        .foregroundStyle(Tokens.C.ink)
        .padding(Tokens.S.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

struct PreviewView: View {
    let model: AppModel
    let item: ClipItem
    let large: Bool

    var body: some View {
        Group {
            if model.isMasked(item) {
                maskedPreview
            } else {
                switch item.kind {
                case .image: imagePreview
                case .link: linkPreview
                case .color: colorPreview
                case .file: filePreview
                default: textPreview
                }
            }
        }
        .padding(.horizontal, Tokens.S.s6)
        .padding(.vertical, 20)
    }

    private var textPreview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.S.s2) {
                if let name = item.customName {
                    Text(name).font(Tokens.T.headline).foregroundStyle(Tokens.C.ink)
                }
                Text(item.text ?? "")
                    .font(item.kind == .code ? Tokens.T.snippet : (large ? .system(size: 15) : Tokens.T.body))
                    .lineSpacing(3)
                    .foregroundStyle(Tokens.C.ink)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var imagePreview: some View {
        VStack(alignment: .leading, spacing: Tokens.S.s3) {
            if let image = model.store.image(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.R.lg))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let ocr = item.ocrText, !large {
                Text("Text in image").font(Tokens.T.captionStrong).foregroundStyle(Tokens.C.inkMuted)
                Text(ocr).font(Tokens.T.callout).foregroundStyle(Tokens.C.ink).lineLimit(3).textSelection(.enabled)
            }
        }
    }

    private var linkPreview: some View {
        VStack(alignment: .leading, spacing: Tokens.S.s2) {
            Image(systemName: "link")
                .font(.system(size: 22))
                .foregroundStyle(Tokens.C.onKind)
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: Tokens.R.lg).fill(Tokens.C.kindLink))
            Text(item.customName ?? item.linkTitle ?? URL(string: item.text ?? "")?.host ?? "Link")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Tokens.C.ink)
            Text(item.text ?? "")
                .font(Tokens.T.snippet).foregroundStyle(Tokens.C.inkMuted)
                .textSelection(.enabled)
            Button("Open in browser") { model.openLink() }
                .padding(.top, Tokens.S.s1)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var colorPreview: some View {
        let c = ContentClassifier.rgb(from: item.text ?? "") ?? (r: 0, g: 0, b: 0)
        return VStack(alignment: .leading, spacing: Tokens.S.s3) {
            RoundedRectangle(cornerRadius: Tokens.R.lg)
                .fill(Color(.sRGB, red: c.r, green: c.g, blue: c.b))
                .overlay(RoundedRectangle(cornerRadius: Tokens.R.lg).strokeBorder(Tokens.C.line))
                .frame(maxHeight: 180)
            Group {
                Text((item.text ?? "").uppercased())
                Text("rgb(\(Int(c.r * 255)), \(Int(c.g * 255)), \(Int(c.b * 255)))")
                Text(AppModel.hsl(c))
            }
            .font(Tokens.T.snippet).foregroundStyle(Tokens.C.ink).textSelection(.enabled)
            Spacer()
        }
    }

    private var filePreview: some View {
        VStack(alignment: .leading, spacing: Tokens.S.s2) {
            if let path = item.filePaths?.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 64, height: 64)
            }
            Text(item.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Tokens.C.ink)
            ForEach(item.filePaths ?? [], id: \.self) { path in
                Text(path).font(Tokens.T.snippet).foregroundStyle(Tokens.C.inkMuted).lineLimit(1).truncationMode(.middle)
            }
            HStack {
                Button("Open") { model.openFile() }
                Button("Show in Finder") { model.revealInFinder() }
            }
            .padding(.top, Tokens.S.s1)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var maskedPreview: some View {
        VStack(alignment: .leading, spacing: Tokens.S.s2) {
            Image(systemName: "lock.fill").font(.system(size: 22)).foregroundStyle(Tokens.C.inkMuted)
            Text(item.customName ?? item.sensitiveLabel ?? "Secret").font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Tokens.C.ink)
            Text(item.masked()).font(Tokens.T.snippet).foregroundStyle(Tokens.C.inkMuted)
            HStack(spacing: 6) {
                Text("Hidden because it looks like a \((item.sensitiveLabel ?? "secret").lowercased()). Reveal with")
                Keycap(text: "⌘U")
            }
            .font(Tokens.T.callout).foregroundStyle(Tokens.C.inkMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Details

struct DetailListView: View {
    let model: AppModel
    let item: ClipItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Details").font(Tokens.T.captionStrong).foregroundStyle(Tokens.C.inkMuted).padding(.bottom, 6)
            ForEach(rows) { row in
                VStack(spacing: 0) {
                    Rectangle().fill(Tokens.C.line).frame(height: 1)
                    HStack {
                        Text(row.label).foregroundStyle(Tokens.C.inkMuted)
                        Spacer()
                        Text(row.value).foregroundStyle(Tokens.C.ink).lineLimit(1)
                    }
                    .font(Tokens.T.callout)
                    .padding(.vertical, 9)
                }
            }
        }
        .padding(.horizontal, Tokens.S.s6)
        .padding(.top, Tokens.S.s1)
        .padding(.bottom, Tokens.S.s3)
    }

    private struct Row: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    private var rows: [Row] {
        var r: [(String, String)] = [("Source", item.sourceApp ?? "Unknown")]
        r.append(("Kind", model.isMasked(item) ? (item.sensitiveLabel ?? "Secret") : item.kind.label))
        switch item.kind {
        case .image:
            if let w = item.imageWidth, let h = item.imageHeight { r.append(("Dimensions", "\(w) × \(h)")) }
            r.append(("Size", Fmt.bytes(item.byteSize)))
        case .file:
            r.append(("Size", Fmt.bytes(item.byteSize)))
            if (item.filePaths?.count ?? 0) > 1 { r.append(("Files", "\(item.filePaths?.count ?? 0)")) }
        case .color:
            break
        default:
            r.append(("Characters", "\(item.characterCount)"))
            if !model.isMasked(item) { r.append(("Words", "\(item.wordCount)")) }
        }
        let times = item.copyCount > 1 ? " · \(item.copyCount) times" : ""
        r.append(("Copied", Fmt.full(item.lastCopied) + times))
        if let edited = item.editedAt { r.append(("Edited", Fmt.full(edited))) }
        let boards = item.pinboardIDs.compactMap { id in model.store.pinboards.first { $0.id == id }?.name }
        r.append(("Pinboard", boards.isEmpty ? "None" : boards.joined(separator: ", ")))
        return r.map { Row(label: $0.0, value: $0.1) }
    }
}

// MARK: - Editor

struct EditorView: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool
    @Environment(\.trayAccent) private var accent
    @State private var escapeArmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.S.s3) {
            HStack(spacing: Tokens.S.s2) {
                Image(systemName: "pencil").foregroundStyle(Tokens.C.inkMuted)
                Text("Editing text").font(Tokens.T.headline)
                Text(model.keepOriginal ? "Saves as a new item" : "Changes replace this item")
                    .font(Tokens.T.caption).foregroundStyle(Tokens.C.inkMuted)
            }
            .foregroundStyle(Tokens.C.ink)

            TextEditor(text: $model.editText)
                .font(model.primaryItem?.kind == .code ? Tokens.T.snippet : Tokens.T.body)
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .padding(Tokens.S.s2)
                .background(RoundedRectangle(cornerRadius: Tokens.R.md).fill(Tokens.C.surfaceRaised))
                .overlay(RoundedRectangle(cornerRadius: Tokens.R.md).strokeBorder(Tokens.C.lineStrong))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.R.md + 3)
                        .strokeBorder(focused ? accent.color : .clear, lineWidth: 2)
                        .padding(-4)
                )
                .focused($focused)
                .onKeyPress(.escape) {
                    if model.editHasChanges && !escapeArmed {
                        escapeArmed = true
                        model.showInfo("Unsaved changes. Press Esc again to discard.")
                    } else {
                        model.cancelEdit()
                    }
                    return .handled
                }
                .accessibilityLabel("Item text")

            if model.primaryItem?.kind == .richText {
                Text("Formatting will be removed when you save.")
                    .font(Tokens.T.caption).foregroundStyle(Tokens.C.inkMuted)
            }

            HStack {
                Toggle("Keep the original as a separate item", isOn: $model.keepOriginal)
                    .toggleStyle(.checkbox)
                Spacer()
                Text("\(model.primaryItem?.characterCount ?? 0) → \(model.editText.count) chars")
                    .font(Tokens.T.caption).foregroundStyle(Tokens.C.inkMuted)
            }
            .font(Tokens.T.callout)
        }
        .padding(.horizontal, Tokens.S.s6)
        .padding(.vertical, Tokens.S.s4)
        .onAppear { focused = true }
        .onChange(of: model.editText) { escapeArmed = false }
    }
}

// MARK: - Action bar

struct ActionBarView: View {
    @Bindable var model: AppModel
    @Environment(\.trayAccent) private var accent

    var body: some View {
        HStack(spacing: Tokens.S.s3) {
            Text("Tray").font(Tokens.T.headline).foregroundStyle(Tokens.C.ink)
            Text(status).font(Tokens.T.caption).foregroundStyle(Tokens.C.inkMuted).lineLimit(1)
            Spacer()
            if model.isEditing {
                actionButton("Cancel", key: "Esc") { model.cancelEdit() }
                Button { model.saveEdit() } label: {
                    HStack(spacing: 6) {
                        Text("Save").fontWeight(.semibold)
                        Text("⌘S").font(Tokens.T.caption)
                    }
                    .foregroundStyle(Tokens.C.onAccent)
                    .padding(.horizontal, Tokens.S.s3)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: Tokens.R.md).fill(accent.color))
                }
                .buttonStyle(.plain)
            } else {
                Button { model.performPrimary() } label: {
                    HStack(spacing: Tokens.S.s2) {
                        Text(primaryLabel).fontWeight(.semibold).foregroundStyle(Tokens.C.ink)
                        Keycap(text: "↵")
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.selection.isEmpty)
                Rectangle().fill(Tokens.C.line).frame(width: 1, height: 20)
                actionButton(isPinnedHere ? "Unpin" : "Pin", key: "⌘P") { model.pinSelection() }
                actionButton("Actions", key: "⌘K") { model.showActions = true }
            }
        }
        .font(Tokens.T.callout)
        .padding(.leading, 20)
        .padding(.trailing, Tokens.S.s4)
        .frame(height: 48)
        .background(Tokens.C.surfaceSunken.opacity(model.backgroundStyle.sunkenOpacity))
        .overlay(alignment: .top) { Rectangle().fill(Tokens.C.line).frame(height: 1) }
    }

    private func actionButton(_ title: String, key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Tokens.S.s2) {
                Text(title).foregroundStyle(Tokens.C.inkMuted)
                Keycap(text: key)
            }
        }
        .buttonStyle(.plain)
    }

    private var isPinnedHere: Bool {
        guard let target = model.boardID ?? model.store.pinboards.first?.id, !model.selection.isEmpty else { return false }
        return model.selectedItems.allSatisfy { $0.pinboardIDs.contains(target) }
    }

    private var primaryLabel: String {
        let n = model.selection.count
        if model.settings.primaryAction == .copy { return n > 1 ? "Copy \(n) items" : "Copy" }
        return n > 1 ? "Paste \(n) items" : "Paste to \(model.targetAppName)"
    }

    private var status: String {
        if model.isEditing { return "Editing · paste and shortcuts are paused" }
        if model.isPaused { return "Recording paused" }
        if model.stackActive { return "Paste Stack · \(model.stack.count) items" }
        let count = model.store.items.count
        let kept = model.settings.retention(for: .text).label.lowercased()
        return "\(count) item\(count == 1 ? "" : "s") · text kept for \(kept)"
    }
}
