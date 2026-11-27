import Carbon.HIToolbox
import Foundation

/// Global shortcuts via Carbon's RegisterEventHotKey (no Accessibility permission needed).
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    struct Shortcut {
        var keyCode: UInt32
        var modifiers: UInt32
    }

    static let openWindow = Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey))
    static let pasteNext = Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | shiftKey))
    static let pasteStack = Shortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey | shiftKey))
    static let pause = Shortcut(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey | optionKey))

    fileprivate var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var installed = false
    private var nextID: UInt32 = 1

    func register(_ shortcut: Shortcut, handler: @escaping () -> Void) {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        handlers[id] = handler
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5452_4159), id: id) // 'TRAY'
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs.append(ref) }
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            let id = hotKeyID.id
            DispatchQueue.main.async { HotKeyCenter.shared.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
