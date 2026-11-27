import AppKit
import SwiftUI

/// A small floating panel that collects copies in order while open.
/// ⌘V in any app pastes the next item; "Paste all" pastes everything at once.
final class PasteStackPanelController {
    private let panel: TrayPanel

    init(model: AppModel) {
        panel = TrayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 340),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = NSHostingView(rootView: PasteStackView(model: model))
    }

    func show() {
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - panel.frame.width - 24, y: screen.maxY - panel.frame.height - 24))
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

struct PasteStackView: View {
    @Bindable var model: AppModel

    var body: some View {
        let accent = model.accent
        VStack(alignment: .leading, spacing: Tokens.S.s2) {
            HStack {
                Text("Paste Stack").font(Tokens.T.headline)
                Text("\(model.stack.count)").font(Tokens.T.caption).foregroundStyle(Tokens.C.inkMuted)
                Spacer()
                Button { model.toggleStack() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Tokens.C.inkMuted)
                    .accessibilityLabel("Close Paste Stack")
            }

            if model.stack.isEmpty {
                Text("Copy things in the order you want to paste them. ⌘V then pastes them one by one.")
                    .font(Tokens.T.callout)
                    .foregroundStyle(Tokens.C.inkMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                List {
                    ForEach(Array(model.stack.enumerated()), id: \.element) { index, id in
                        if let item = model.store.item(id) {
                            HStack(spacing: Tokens.S.s2) {
                                Text("\(index + 1)").font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Tokens.C.inkMuted).frame(width: 16)
                                Text(model.isMasked(item) ? (item.sensitiveLabel ?? "Secret") : item.title)
                                    .font(Tokens.T.callout).lineLimit(1)
                                Spacer()
                                if index < model.stackNext {
                                    Image(systemName: "checkmark").font(.system(size: 10)).foregroundStyle(Tokens.C.inkMuted)
                                }
                            }
                            .padding(.horizontal, Tokens.S.s2)
                            .frame(height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: Tokens.R.md)
                                    .fill(index == model.stackNext ? accent.soft : .clear)
                            )
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .contextMenu {
                                Button("Remove") { model.removeFromStack(id) }
                            }
                        }
                    }
                    .onMove { model.moveStack(from: $0, to: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            HStack(spacing: Tokens.S.s3) {
                Text("⌘C adds · ⌘V pastes next").font(Tokens.T.caption).foregroundStyle(Tokens.C.inkMuted)
                Spacer()
                Button("Paste all") { model.pasteWholeStack() }
                    .disabled(model.stack.isEmpty)
            }
        }
        .foregroundStyle(Tokens.C.ink)
        .padding(Tokens.S.s3)
        .frame(width: 280, height: 340)
        .background(Tokens.C.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.R.xl, style: .continuous))
        .environment(\.trayAccent, accent)
        .tint(accent.color)
    }
}
