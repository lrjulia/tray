import AppKit
import SwiftUI

/// A floating, non-activating panel: it takes keyboard focus without making Tray the active app,
/// so the app you were in stays frontmost and receives the paste.
final class TrayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class TrayPanelController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let panel: TrayPanel

    init(model: AppModel) {
        self.model = model
        panel = TrayPanel(
            contentRect: NSRect(x: 0, y: 0, width: Tokens.Size.windowWidth, height: Tokens.Size.windowHeight),
            styleMask: [.titled, .nonactivatingPanel, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        super.init()
        panel.isFloatingPanel = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 560, height: 380)
        panel.delegate = self
        panel.setFrameAutosaveName("TrayWindow")

        let host = NSHostingView(rootView: MainView(model: model))
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        applyPrivacy()
    }

    var isVisible: Bool { panel.isVisible }

    /// Hidden from screen sharing, recordings and screenshots when the setting is on.
    func applyPrivacy() {
        panel.sharingType = model.settings.hideFromScreenSharing ? .none : .readOnly
    }

    func show(anchor: NSRect?) {
        position(anchor: anchor)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.15
            self.panel.animator().alphaValue = 1
        }
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func position(anchor: NSRect?) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        var frame = panel.frame
        frame.size.width = min(frame.width, visible.width - 40)
        frame.size.height = min(frame.height, visible.height - 40)

        switch model.settings.windowPosition {
        case .center:
            frame.origin.x = visible.midX - frame.width / 2
            frame.origin.y = visible.midY - frame.height / 2 + visible.height * 0.08
        case .cursor:
            frame.origin.x = mouse.x - frame.width / 2
            frame.origin.y = mouse.y - frame.height + 24
        case .menuBar:
            if let anchor {
                frame.origin.x = anchor.midX - frame.width / 2
                frame.origin.y = anchor.minY - frame.height - 6
            } else {
                frame.origin.x = visible.maxX - frame.width - 12
                frame.origin.y = visible.maxY - frame.height - 6
            }
        }
        frame.origin.x = max(visible.minX + 8, min(frame.origin.x, visible.maxX - frame.width - 8))
        frame.origin.y = max(visible.minY + 8, min(frame.origin.y, visible.maxY - frame.height - 8))
        panel.setFrame(frame, display: false)
    }

    // Close on click outside, unless the window is kept on top.
    func windowDidResignKey(_ notification: Notification) {
        guard !model.keepOnTop, !model.isEditing else { return }
        model.closePanel()
    }
}
