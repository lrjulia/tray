import Foundation

enum Appearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum AccentChoice: Codable, Hashable {
    case followSystem
    case option(AccentOption)

    var resolved: AccentOption {
        switch self {
        case .followSystem: return AccentOption.nearestToSystem()
        case .option(let o): return o
        }
    }
}

enum BackgroundStyle: String, Codable, CaseIterable, Identifiable {
    case solid, translucent, transparent
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    /// How much of the surface color sits over the blur. Keeps text readable on busy desktops.
    var tint: Double {
        switch self {
        case .solid: return 1
        case .translucent: return 0.7
        case .transparent: return 0.45
        }
    }
    var sunkenOpacity: Double {
        switch self {
        case .solid: return 1
        case .translucent: return 0.6
        case .transparent: return 0.35
        }
    }
}

enum ItemColoring: String, Codable, CaseIterable, Identifiable {
    case byKind, bySource, neutral
    var id: String { rawValue }
    var label: String {
        switch self {
        case .byKind: return "By kind"
        case .bySource: return "By source app"
        case .neutral: return "Neutral"
        }
    }
}

enum ViewMode: String, Codable, CaseIterable, Identifiable {
    case list, compact, grid
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .list: return "sidebar.left"
        case .compact: return "list.bullet"
        case .grid: return "square.grid.2x2"
        }
    }
}

enum WindowPosition: String, Codable, CaseIterable, Identifiable {
    case center, cursor, menuBar
    var id: String { rawValue }
    var label: String {
        switch self {
        case .center: return "Center of screen"
        case .cursor: return "At the cursor"
        case .menuBar: return "Under the menu-bar icon"
        }
    }
}

enum Retention: String, Codable, CaseIterable, Identifiable {
    case day, week, month, year, forever
    var id: String { rawValue }
    var label: String {
        switch self {
        case .day: return "1 day"
        case .week: return "1 week"
        case .month: return "1 month"
        case .year: return "1 year"
        case .forever: return "Forever"
        }
    }
    var interval: TimeInterval? {
        switch self {
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        case .year: return 365 * 86_400
        case .forever: return nil
        }
    }
}

enum PrimaryAction: String, Codable, CaseIterable, Identifiable {
    case paste, copy
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum PasteSeparator: String, Codable, CaseIterable, Identifiable {
    case newline, tab, space, comma, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .newline: return "New line"
        case .tab: return "Tab"
        case .space: return "Space"
        case .comma: return "Comma"
        case .none: return "None"
        }
    }
    var string: String {
        switch self {
        case .newline: return "\n"
        case .tab: return "\t"
        case .space: return " "
        case .comma: return ", "
        case .none: return ""
        }
    }
}

enum SortOrder: String, Codable, CaseIterable, Identifiable {
    case lastCopied, firstCopied, timesCopied, size
    var id: String { rawValue }
    var label: String {
        switch self {
        case .lastCopied: return "Last copied"
        case .firstCopied: return "First copied"
        case .timesCopied: return "Times copied"
        case .size: return "Size"
        }
    }
}

struct TraySettings: Codable, Equatable {
    // General
    var primaryAction: PrimaryAction = .paste
    var windowPosition: WindowPosition = .center
    var openInCompact = false
    var rememberLastView = true
    var lastViewMode: ViewMode = .list
    var showMenuBarIcon = true
    var pasteSeparator: PasteSeparator = .newline
    var copyAndAppend = true

    // History
    var retention: [String: Retention] = [
        KindGroup.text.rawValue: .month,
        KindGroup.links.rawValue: .month,
        KindGroup.images.rawValue: .week,
        KindGroup.code.rawValue: .month,
        KindGroup.colors.rawValue: .month,
        KindGroup.files.rawValue: .week,
    ]
    var sortOrder: SortOrder = .lastCopied
    var clearOnQuit = false
    var ocrEnabled = true

    // Privacy
    var maskSensitive = true
    var hideFromScreenSharing = true
    var ignoredBundleIDs: [String] = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
        "com.apple.keychainaccess", "com.apple.Passwords", "com.lastpass.LastPass",
        "com.dashlane.dashlanephonefinal", "org.keepassxc.keepassxc",
    ]
    var ignoredPasteboardTypes: [String] = [
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword", "de.petermaurer.TransientPasteboardType",
    ]

    // Appearance
    var appearance: Appearance = .system
    var accent: AccentChoice = .followSystem
    var itemColoring: ItemColoring = .byKind
    var background: BackgroundStyle = .transparent

    // Onboarding
    var hasCompletedOnboarding = false

    func retention(for group: KindGroup) -> Retention {
        retention[group.rawValue] ?? .month
    }

    /// Loads saved settings over the defaults, so settings added in a new version get their default
    /// instead of resetting everything.
    static func load() -> TraySettings {
        guard let data = UserDefaults.standard.data(forKey: "tray.settings"),
              let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let defaultsData = try? JSONEncoder().encode(TraySettings()),
              var merged = (try? JSONSerialization.jsonObject(with: defaultsData)) as? [String: Any]
        else { return TraySettings() }
        merged.merge(saved) { _, new in new }
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged),
              let s = try? JSONDecoder().decode(TraySettings.self, from: mergedData) else { return TraySettings() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "tray.settings")
        }
    }
}
