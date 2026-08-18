import AppKit
import Carbon.HIToolbox

/// A user-configurable global keyboard shortcut, stored as a Carbon virtual key code plus
/// Carbon modifier mask so it can be handed straight to `RegisterEventHotKey`.
struct ShortcutDefinition: Equatable, Sendable {
    let keyCode: UInt32
    let carbonModifiers: UInt32

    static let polishDefault = ShortcutDefinition(
        keyCode: UInt32(kVK_ANSI_P),
        carbonModifiers: UInt32(optionKey | cmdKey)
    )

    static let quickDefault = ShortcutDefinition(
        keyCode: UInt32(kVK_ANSI_P),
        carbonModifiers: UInt32(optionKey | cmdKey | shiftKey)
    )

    /// Rejects shortcuts that would fire constantly, such as a bare letter with no modifier.
    var isValid: Bool {
        let meaningful = UInt32(cmdKey | controlKey | optionKey)
        return carbonModifiers & meaningful != 0
    }

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        self.init(keyCode: UInt32(event.keyCode), carbonModifiers: carbon)
        guard isValid else { return nil }
    }

    var cocoaModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }

    /// Menu-style rendering, e.g. `⌥⌘P`.
    var displayString: String {
        var text = ""
        if carbonModifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        text += Self.keyName(for: keyCode)
        return text
    }

    /// `NSMenuItem.keyEquivalent` holds exactly one character. Anything this cannot express as a
    /// single character returns nil so the caller can spell the shortcut out in the title instead
    /// of assigning a string that would render literally and never match a key press.
    var menuKeyEquivalentCharacter: String? {
        switch keyCode {
        case UInt32(kVK_Space): " "
        case UInt32(kVK_Return), UInt32(kVK_ANSI_KeypadEnter): "\r"
        case UInt32(kVK_Tab): "\t"
        case UInt32(kVK_Delete): "\u{8}"
        case UInt32(kVK_ForwardDelete): "\u{7F}"
        case UInt32(kVK_Escape): "\u{1B}"
        case UInt32(kVK_LeftArrow): String(UnicodeScalar(UInt32(NSLeftArrowFunctionKey))!)
        case UInt32(kVK_RightArrow): String(UnicodeScalar(UInt32(NSRightArrowFunctionKey))!)
        case UInt32(kVK_UpArrow): String(UnicodeScalar(UInt32(NSUpArrowFunctionKey))!)
        case UInt32(kVK_DownArrow): String(UnicodeScalar(UInt32(NSDownArrowFunctionKey))!)
        default:
            {
                let name = Self.keyName(for: keyCode).lowercased()
                return name.count == 1 ? name : nil
            }()
        }
    }

    // MARK: - Storage

    var storageValue: String { "\(keyCode):\(carbonModifiers)" }

    init?(storageValue: String) {
        let parts = storageValue.split(separator: ":")
        guard parts.count == 2,
              let keyCode = UInt32(parts[0]),
              let modifiers = UInt32(parts[1]) else {
            return nil
        }
        self.init(keyCode: keyCode, carbonModifiers: modifiers)
        guard isValid else { return nil }
    }

    // MARK: - Key names

    private static let namedKeys: [UInt32: String] = [
        UInt32(kVK_Return): "↩",
        UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Delete): "⌫",
        UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_Escape): "⎋",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_Home): "↖",
        UInt32(kVK_End): "↘",
        UInt32(kVK_PageUp): "⇞",
        UInt32(kVK_PageDown): "⇟",
        UInt32(kVK_ANSI_KeypadEnter): "⌤"
    ]

    /// Resolves the key code through the active keyboard layout so a Dvorak or AZERTY user sees
    /// the letter actually printed on the key they pressed.
    static func keyName(for keyCode: UInt32) -> String {
        if let named = namedKeys[keyCode] { return named }
        if let translated = translate(keyCode: keyCode), !translated.isEmpty {
            return translated.uppercased()
        }
        return "Key \(keyCode)"
    }

    private static func translate(keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 8)
        var length = 0

        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return -1 }
            return UCKeyTranslate(
                base.assumingMemoryBound(to: UCKeyboardLayout.self),
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}
