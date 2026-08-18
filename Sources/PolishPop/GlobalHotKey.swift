import Carbon.HIToolbox

/// Registers the app's user-configurable global shortcuts.
///
/// One Carbon event handler serves every shortcut; each registration gets its own id so the
/// handler can tell "polish with review" from "polish and replace".
@MainActor
final class GlobalHotKey {
    enum Command: UInt32, CaseIterable {
        case polish = 1
        case quickReplace = 2
    }

    var action: ((Command) -> Void)?

    private var references: [Command: EventHotKeyRef] = [:]
    private var eventHandlerReference: EventHandlerRef?

    /// Registers a shortcut, replacing any previous binding for the same command.
    ///
    /// - Returns: `false` when macOS refuses the combination, which normally means another
    ///   application already owns it.
    @discardableResult
    func register(_ shortcut: ShortcutDefinition?, for command: Command) -> Bool {
        unregister(command)
        guard let shortcut, shortcut.isValid else { return true }
        guard installHandlerIfNeeded() else { return false }

        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: Self.signature, id: command.rawValue)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else { return false }
        references[command] = reference
        return true
    }

    func unregister(_ command: Command) {
        guard let reference = references.removeValue(forKey: command) else { return }
        UnregisterEventHotKey(reference)
    }

    func unregisterAll() {
        for command in references.keys {
            unregister(command)
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
    }

    private func installHandlerIfNeeded() -> Bool {
        guard eventHandlerReference == nil else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else { return noErr }
                var identifier = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard parameterStatus == noErr,
                      let command = Command(rawValue: identifier.id) else {
                    return noErr
                }
                let owner = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in owner.action?(command) }
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandlerReference
        )
        guard status == noErr else {
            eventHandlerReference = nil
            return false
        }
        return true
    }

    private static let signature: OSType = "PLSH".utf8.reduce(0) { ($0 << 8) + OSType($1) }
}
