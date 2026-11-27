import AppKit
import Carbon.HIToolbox
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var panel: TrayPanelController!
    private var stackPanel: PasteStackPanelController!
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var keyMonitor: Any?
    private var retentionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()
        model.applyAppearance()

        panel = TrayPanelController(model: model)
        stackPanel = PasteStackPanelController(model: model)

        model.onShowPanel = { [weak self] in self?.panel.show(anchor: self?.statusItem?.button?.window?.frame) }
        model.onHidePanel = { [weak self] in self?.panel.hide() }
        model.onShowSettings = { [weak self] in self?.showSettings() }
        model.onShowStack = { [weak self] active in active ? self?.stackPanel.show() : self?.stackPanel.hide() }
        model.onPrivacyChange = { [weak self] in self?.panel.applyPrivacy() }
        model.onMenuBarIconChange = { [weak self] in self?.updateStatusItem() }

        updateStatusItem()
        registerHotKeys()
        watchPasteForStack()

        model.store.applyRetention(model.settings)
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.model.store.applyRetention(self.model.settings)
        }

        NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.model.accentVersion += 1 }

        model.monitor.start()

        if !model.settings.hasCompletedOnboarding { showOnboarding() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if model.settings.clearOnQuit { model.store.clearAll(keepPinned: true) }
        model.store.saveNow()
    }

    // MARK: Hotkeys

    private func registerHotKeys() {
        HotKeyCenter.shared.register(HotKeyCenter.openWindow) { [weak self] in
            guard let self else { return }
            self.model.togglePanel(isVisible: self.panel.isVisible)
        }
        HotKeyCenter.shared.register(HotKeyCenter.pasteNext) { [weak self] in self?.model.pasteNext() }
        HotKeyCenter.shared.register(HotKeyCenter.pasteStack) { [weak self] in self?.model.toggleStack() }
        HotKeyCenter.shared.register(HotKeyCenter.pause) { [weak self] in self?.model.togglePause() }
    }

    /// While the Paste Stack is open, watch for ⌘V in other apps and load the next item.
    /// Global key monitoring needs Accessibility permission, which pasting needs anyway.
    private func watchPasteForStack() {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.model.stackActive,
                  event.keyCode == UInt16(kVK_ANSI_V),
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.model.stackDidPaste() }
        }
    }

    // MARK: Menu-bar icon

    private func updateStatusItem() {
        guard model.settings.showMenuBarIcon else {
            if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Tray")
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }

    @objc func openTray() { model.openPanel() }
    @objc func togglePauseMenu() { model.togglePause() }
    @objc func toggleStackMenu() { model.toggleStack() }
    @objc func quit() { NSApp.terminate(nil) }

    // MARK: Windows

    @objc func showSettings() {
        model.closePanel()
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
                styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false
            )
            window.title = "Tray Settings"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func showOnboarding() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = true
        window.title = "Welcome to Tray"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: OnboardingView(model: model) { [weak self] in
            self?.model.settings.hasCompletedOnboarding = true
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
        })
        window.center()
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    /// Rebuilt on open so "Pause" / "Resume" and the Paste Stack title stay current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let open = menu.addItem(withTitle: "Open Tray", action: #selector(openTray), keyEquivalent: "v")
        open.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        let pause = menu.addItem(
            withTitle: model.isPaused ? "Resume recording" : "Pause recording",
            action: #selector(togglePauseMenu), keyEquivalent: "p"
        )
        pause.keyEquivalentModifierMask = [.command, .option]
        let stack = menu.addItem(
            withTitle: model.stackActive ? "Close Paste Stack" : "Paste Stack",
            action: #selector(toggleStackMenu), keyEquivalent: "c"
        )
        stack.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Quit Tray", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
    }
}
