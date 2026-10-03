import AppKit
import Carbon.HIToolbox

/// The shortcut that opens the island, registered with the system (RegisterEventHotKey).
/// Needs no Accessibility permission, works in the App Store sandbox, and the key press
/// goes to Coucou only: the app in front never receives it.
@MainActor
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    /// Called on the main thread when the shortcut is pressed.
    var onPress: (() -> Void)?

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    /// Set while Settings records a new shortcut, so the current one reaches the recorder.
    private var paused = false

    private init() {}

    /// Registers the shortcut saved in Settings, or nothing when it is turned off.
    func refresh() {
        unregister()
        let state = AppState.shared
        guard state.hotkeyEnabled, !paused else { return }
        installHandlerIfNeeded()

        let flags = NSEvent.ModifierFlags(rawValue: state.hotkeyFlags)
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option)  { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
        guard mods != 0 else { return }

        let id = EventHotKeyID(signature: OSType(0x434F_5543), id: 1)  // 'COUC'
        let status = RegisterEventHotKey(UInt32(state.hotkeyCode), mods, id,
                                         GetEventDispatcherTarget(), 0, &hotKey)
        if status != noErr {
            hotKey = nil
            NSLog("GlobalHotKey: shortcut not registered (\(status)), another app may own it")
        }
    }

    func pause()  { paused = true;  unregister() }
    func resume() { paused = false; refresh() }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, _ in
            Task { @MainActor in GlobalHotKey.shared.onPress?() }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}
