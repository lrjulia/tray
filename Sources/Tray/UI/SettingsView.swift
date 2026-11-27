import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            GeneralSettings(model: model).tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings(model: model).tabItem { Label("Appearance", systemImage: "paintpalette") }
            HistorySettings(model: model).tabItem { Label("History", systemImage: "clock") }
            PinboardSettings(model: model).tabItem { Label("Pinboards", systemImage: "pin") }
            PrivacySettings(model: model).tabItem { Label("Privacy", systemImage: "lock") }
            DataSettings(model: model).tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .frame(width: 620, height: 520)
        .tint(model.accent.color)
    }
}

private struct GeneralSettings: View {
    @Bindable var model: AppModel
    @State private var trusted = Paster.isTrusted

    var body: some View {
        Form {
            Section("Shortcuts") {
                LabeledContent("Open Tray", value: "⌘⇧V")
                LabeledContent("Paste next without opening", value: "⌃⇧V")
                LabeledContent("Paste Stack", value: "⌘⇧C")
                LabeledContent("Pause recording", value: "⌥⌘P")
            }
            Section("Window") {
                Picker("Open the window", selection: $model.settings.windowPosition) {
                    ForEach(WindowPosition.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Open in Compact view", isOn: $model.settings.openInCompact)
                Toggle("Remember the last view", isOn: $model.settings.rememberLastView)
                Toggle("Show menu-bar icon", isOn: $model.settings.showMenuBarIcon)
            }
            Section("Paste") {
                Picker("Return key", selection: $model.settings.primaryAction) {
                    Text("Pastes into the front app").tag(PrimaryAction.paste)
                    Text("Copies only").tag(PrimaryAction.copy)
                }
                Picker("Join several items with", selection: $model.settings.pasteSeparator) {
                    ForEach(PasteSeparator.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Press ⌘C twice to add to the previous item", isOn: $model.settings.copyAndAppend)
                LabeledContent("Accessibility") {
                    if trusted {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                    } else {
                        Button("Allow…") {
                            Paster.requestTrust()
                            Paster.openAccessibilitySettings()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            trusted = Paster.isTrusted
        }
    }
}

private struct AppearanceSettings: View {
    @Bindable var model: AppModel

    private var accentSelection: Binding<String> {
        Binding(
            get: {
                if case .option(let o) = model.settings.accent { return o.rawValue }
                return "system"
            },
            set: { value in
                if let option = AccentOption(rawValue: value) {
                    model.settings.accent = .option(option)
                } else {
                    model.settings.accent = .followSystem
                }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $model.settings.appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Accent color") {
                Picker("Accent", selection: accentSelection) {
                    Text("Follow macOS").tag("system")
                    ForEach(AccentOption.allCases) { option in
                        HStack {
                            Circle().fill(option.color).frame(width: 10, height: 10)
                            Text(option.label)
                        }
                        .tag(option.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
                Text("Every option is tested for readable text in light and dark.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Items") {
                Picker("Color cards", selection: $model.settings.itemColoring) {
                    ForEach(ItemColoring.allCases) { Text($0.label).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct HistorySettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Keep items for") {
                ForEach(KindGroup.allCases) { group in
                    Picker(group.label, selection: Binding(
                        get: { model.settings.retention(for: group) },
                        set: { model.settings.retention[group.rawValue] = $0 }
                    )) {
                        ForEach(Retention.allCases) { Text($0.label).tag($0) }
                    }
                }
                Text("Pinned items are never deleted.").font(.caption).foregroundStyle(.secondary)
            }
            Section("List") {
                Picker("Sort by", selection: $model.settings.sortOrder) {
                    ForEach(SortOrder.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Find text in images (on-device)", isOn: $model.settings.ocrEnabled)
            }
            Section {
                Toggle("Clear history when Tray quits", isOn: $model.settings.clearOnQuit)
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.settings.retention) { model.store.applyRetention(model.settings) }
    }
}

private struct PinboardSettings: View {
    @Bindable var model: AppModel
    @State private var newName = ""

    var body: some View {
        Form {
            Section("Pinboards") {
                ForEach(model.store.pinboards) { board in
                    HStack {
                        Picker("", selection: Binding(
                            get: { board.color },
                            set: { var b = board; b.color = $0; model.store.updatePinboard(b) }
                        )) {
                            ForEach(PinColor.allCases) { c in
                                Text(c.rawValue.capitalized).tag(c)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                        Circle().fill(board.color.color).frame(width: 10, height: 10)
                        TextField("Name", text: Binding(
                            get: { board.name },
                            set: { var b = board; b.name = $0; model.store.updatePinboard(b) }
                        ))
                        Button(role: .destructive) { model.store.deletePinboard(board.id) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Delete \(board.name)")
                    }
                }
                HStack {
                    TextField("New pinboard", text: $newName)
                    Button("Add") {
                        let name = newName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        _ = model.store.addPinboard(name: name)
                        newName = ""
                    }
                }
                Text("Deleting a pinboard keeps its items in History.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PrivacySettings: View {
    @Bindable var model: AppModel
    @State private var selectedApp: String?

    var body: some View {
        Form {
            Section {
                Toggle("Mask passwords, keys, tokens and card numbers", isOn: $model.settings.maskSensitive)
                Toggle("Hide the window from screen sharing and recordings", isOn: $model.settings.hideFromScreenSharing)
                LabeledContent("Recording") {
                    Button(model.isPaused ? "Resume" : "Pause") { model.togglePause() }
                }
            }
            Section("Never save copies from") {
                List(selection: $selectedApp) {
                    ForEach(model.settings.ignoredBundleIDs, id: \.self) { id in
                        Text(appName(for: id)).tag(id)
                    }
                }
                .frame(minHeight: 140)
                HStack {
                    Button("Add app…") { addApp() }
                    Button("Remove") {
                        if let id = selectedApp { model.settings.ignoredBundleIDs.removeAll { $0 == id } }
                    }
                    .disabled(selectedApp == nil)
                }
                Text("Passwords and other content apps mark as concealed or temporary are never saved.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !model.settings.ignoredBundleIDs.contains(id) {
                model.settings.ignoredBundleIDs.append(id)
            }
        }
    }
}

private struct DataSettings: View {
    @Bindable var model: AppModel
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Items", value: "\(model.store.items.count)")
                LabeledContent("Storage", value: "Encrypted on this Mac only")
            }
            Section("Move to another Mac") {
                HStack {
                    Button("Export history…") { export() }
                    Button("Import…") { importFile() }
                }
                Text("The export file is not encrypted. Keep it somewhere safe and delete it after importing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Clear history…", role: .destructive) { confirmClear() }
                Text("Pinned items are kept.").font(.caption).foregroundStyle(.secondary)
            }
            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Tray history.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.store.exportData().write(to: url, options: .atomic)
            message = "Exported \(model.store.items.count) items."
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let n = try model.store.importData(Data(contentsOf: url))
            message = "Imported \(n) new items."
        } catch {
            message = "That file couldn't be imported."
        }
    }

    private func confirmClear() {
        let alert = NSAlert()
        alert.messageText = "Clear history?"
        alert.informativeText = "This deletes every item that isn't pinned. It can't be undone."
        alert.addButton(withTitle: "Clear history")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            model.store.clearAll(keepPinned: true)
            message = "History cleared."
        }
    }
}
