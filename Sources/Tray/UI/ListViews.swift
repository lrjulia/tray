import AppKit
import SwiftUI

struct ListColumn: View {
    @Bindable var model: AppModel
    let compact: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.sections) { section in
                        Text(section.title)
                            .font(Tokens.T.captionStrong)
                            .foregroundStyle(Tokens.C.inkMuted)
                            .padding(.horizontal, Tokens.S.s3)
                            .padding(.top, Tokens.S.s3)
                            .padding(.bottom, 6)
                        ForEach(section.items) { item in
                            row(item).id(item.id)
                        }
                    }
                }
                .padding(.horizontal, Tokens.S.s2)
                .padding(.vertical, Tokens.S.s1)
            }
            .onChange(of: model.selection) {
                if let id = model.selection.last { proxy.scrollTo(id) }
            }
        }
    }

    private func row(_ item: ClipItem) -> some View {
        let order = model.selection.count > 1 ? model.selection.firstIndex(of: item.id).map { $0 + 1 } : nil
        return HistoryRowView(
            item: item,
            selected: model.selection.contains(item.id),
            order: order,
            quick: model.quickIndex(of: item),
            masked: model.isMasked(item),
            editing: model.isEditing && model.selection.last == item.id,
            compact: compact,
            query: model.query,
            pinColor: item.pinboardIDs.first.flatMap { id in model.store.pinboards.first { $0.id == id }?.color.color },
            thumbnail: !compact && item.kind == .image ? model.store.image(for: item) : nil
        )
        .onTapGesture(count: 2) {
            model.select(item.id)
            model.performPrimary()
        }
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            model.select(item.id, extend: flags.contains(.shift) || flags.contains(.command))
        }
        .contextMenu { ItemContextMenu(model: model, item: item) }
    }
}

struct HistoryRowView: View {
    let item: ClipItem
    let selected: Bool
    let order: Int?
    let quick: Int?
    let masked: Bool
    let editing: Bool
    let compact: Bool
    let query: String
    let pinColor: Color?
    let thumbnail: NSImage?
    @Environment(\.trayAccent) private var accent

    var body: some View {
        HStack(spacing: Tokens.S.s3) {
            KindGlyph(item: item, masked: masked, thumbnail: thumbnail)
                .foregroundStyle(selected ? Tokens.C.onAccent : Tokens.C.inkMuted)
            title
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, Tokens.S.s3)
        .frame(height: compact ? Tokens.Size.rowHeight : Tokens.Size.rowHeightComfortable)
        .foregroundStyle(selected ? Tokens.C.onAccent : Tokens.C.ink)
        .background(RoundedRectangle(cornerRadius: Tokens.R.md).fill(selected ? accent.color : .clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var title: some View {
        if masked {
            HStack(spacing: 6) {
                Text(item.customName ?? item.sensitiveLabel ?? "Secret")
                Text(item.masked())
                    .font(Tokens.T.snippet)
                    .foregroundStyle(selected ? Tokens.C.onAccent : Tokens.C.inkMuted)
            }
            .font(Tokens.T.body)
        } else if item.kind == .code || item.kind == .color, item.customName == nil {
            Text(highlightMatches(item.title, query: query)).font(Tokens.T.snippet)
        } else {
            Text(highlightMatches(item.title, query: query)).font(Tokens.T.body)
        }
    }

    @ViewBuilder private var trailing: some View {
        if editing {
            Text("Editing").font(Tokens.T.caption)
        } else if let order {
            Text("\(order)").font(Tokens.T.captionStrong)
        } else if masked {
            Keycap(text: "⌘U", onAccent: selected)
        } else if let quick {
            Text("⌘\(quick)").font(Tokens.T.caption)
                .foregroundStyle(selected ? Tokens.C.onAccent : Tokens.C.inkMuted)
        } else if let pinColor {
            Circle().fill(pinColor).frame(width: 8, height: 8)
        }
    }

    private var accessibilityText: String {
        let what = masked ? (item.sensitiveLabel ?? "Secret") + ", hidden" : item.title
        return "\(item.kind.label), \(Fmt.relative(item.lastCopied)), from \(item.sourceApp ?? "unknown app"), \(what)"
    }
}

/// Right-click menu on a row or card: the most common actions.
struct ItemContextMenu: View {
    let model: AppModel
    let item: ClipItem

    var body: some View {
        Button("Paste") { model.select(item.id); model.paste(plain: false) }
        Button("Paste as plain text") { model.select(item.id); model.paste(plain: true) }
        Button("Copy") { model.select(item.id); model.copySelection() }
        Divider()
        Button("Rename…") { model.select(item.id); model.beginRename() }
        if item.kind.isTextual {
            Button("Edit…") { model.select(item.id); model.beginEdit() }
        }
        Menu("Pin to") {
            ForEach(model.store.pinboards) { board in
                Button(board.name) { model.select(item.id); model.pinSelection(to: board.id) }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { model.select(item.id); model.deleteSelection() }
    }
}

// MARK: - Grid view

struct GridColumn: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: Tokens.Size.cardSize, maximum: Tokens.Size.cardSize), spacing: Tokens.S.s4)],
                    spacing: Tokens.S.s4
                ) {
                    ForEach(model.visibleItems) { item in
                        ClipCardView(
                            item: item,
                            image: item.kind == .image ? model.store.image(for: item) : nil,
                            selected: model.selection.contains(item.id),
                            masked: model.isMasked(item),
                            quick: model.quickIndex(of: item),
                            coloring: model.settings.itemColoring
                        )
                        .id(item.id)
                        .onTapGesture(count: 2) { model.select(item.id); model.performPrimary() }
                        .onTapGesture {
                            let flags = NSEvent.modifierFlags
                            model.select(item.id, extend: flags.contains(.shift) || flags.contains(.command))
                        }
                        .contextMenu { ItemContextMenu(model: model, item: item) }
                    }
                }
                .padding(Tokens.S.s6)
            }
            .background(Tokens.C.surfaceSunken.opacity(model.backgroundStyle.sunkenOpacity))
            .onChange(of: model.selection) {
                if let id = model.selection.last { proxy.scrollTo(id) }
            }
        }
    }
}

struct ClipCardView: View {
    let item: ClipItem
    let image: NSImage?
    let selected: Bool
    let masked: Bool
    let quick: Int?
    let coloring: ItemColoring
    @Environment(\.trayAccent) private var accent

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(masked ? (item.sensitiveLabel ?? "Secret") : item.kind.label).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(Fmt.relative(item.lastCopied)).font(Tokens.T.caption)
            }
            .foregroundStyle(Tokens.C.onKind)
            .padding(.horizontal, Tokens.S.s3)
            .frame(height: 40)
            .background(band)

            cardBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack {
                Text(footer).lineLimit(1)
                Spacer()
                if let quick { Keycap(text: "⌘\(quick)") }
            }
            .font(Tokens.T.caption)
            .foregroundStyle(Tokens.C.inkMuted)
            .padding(.horizontal, Tokens.S.s3)
            .padding(.bottom, Tokens.S.s3)
        }
        .frame(width: Tokens.Size.cardSize, height: Tokens.Size.cardSize)
        .background(Tokens.C.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.R.lg, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.R.lg + 3, style: .continuous)
                .strokeBorder(selected ? accent.color : .clear, lineWidth: 3)
                .padding(-5)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var band: Color {
        switch coloring {
        case .byKind: return item.kind.bandColor
        case .bySource: return SourceColor.color(for: item.sourceBundleID) ?? item.kind.bandColor
        case .neutral: return Tokens.C.kindText
        }
    }

    @ViewBuilder private var cardBody: some View {
        if masked {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "lock").foregroundStyle(Tokens.C.inkMuted)
                Text(item.masked()).font(Tokens.T.snippet).foregroundStyle(Tokens.C.inkMuted)
            }
            .padding(Tokens.S.s3)
        } else {
            switch item.kind {
            case .image:
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.R.md))
                        .padding([.horizontal, .top], Tokens.S.s3)
                        .padding(.bottom, Tokens.S.s2)
                } else {
                    Color.clear
                }
            case .color:
                let c = ContentClassifier.rgb(from: item.text ?? "") ?? (r: 0.5, g: 0.5, b: 0.5)
                RoundedRectangle(cornerRadius: Tokens.R.md)
                    .fill(Color(.sRGB, red: c.r, green: c.g, blue: c.b))
                    .padding([.horizontal, .top], Tokens.S.s3)
                    .padding(.bottom, Tokens.S.s2)
            case .file:
                VStack(spacing: Tokens.S.s2) {
                    if let path = item.filePaths?.first {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 48, height: 48)
                    }
                    Text(item.title).font(Tokens.T.callout).foregroundStyle(Tokens.C.ink).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(Tokens.S.s3)
            case .link:
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.customName ?? item.linkTitle ?? URL(string: item.text ?? "")?.host ?? item.title)
                        .font(Tokens.T.headline).foregroundStyle(Tokens.C.ink).lineLimit(3)
                    Text(item.text ?? "").font(Tokens.T.caption).foregroundStyle(Tokens.C.inkMuted).lineLimit(2)
                }
                .padding(Tokens.S.s3)
            case .code:
                Text(item.text ?? "").font(Tokens.T.snippet).foregroundStyle(Tokens.C.ink)
                    .lineLimit(8).padding(Tokens.S.s3)
            default:
                Text(item.customName ?? item.text ?? "").font(Tokens.T.callout).foregroundStyle(Tokens.C.ink)
                    .lineLimit(8).padding(Tokens.S.s3)
            }
        }
    }

    private var footer: String {
        let source = item.sourceApp ?? "Unknown app"
        switch item.kind {
        case .image:
            if let w = item.imageWidth, let h = item.imageHeight { return "\(source) · \(w) × \(h)" }
            return source
        case .file: return "\(source) · \(Fmt.bytes(item.byteSize))"
        case .color: return (item.text ?? "").uppercased()
        default: return masked ? source : "\(source) · \(item.characterCount) chars"
        }
    }
}
