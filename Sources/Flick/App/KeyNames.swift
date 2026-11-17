import AppKit
import Carbon
import FlickCore

/// Names of keys as printed on the user's keyboard.
@MainActor
enum KeyNames {
    static var special: [UInt16: String] { [
        36: "↩", 48: "⇥", 49: tr("Espace", "Space"), 51: "⌫", 53: tr("Échap", "Esc"), 117: "⌦", 76: "⌤",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ] }

    /// Number-row keys, shown as digits whatever the layout (on AZERTY they type & é " ' … unshifted).
    static let digits: [UInt16: String] = [
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
    ]

    static func name(_ keyCode: UInt16) -> String {
        special[keyCode] ?? digits[keyCode] ?? KeyboardLayout.shared.characters(keyCode, shift: false)?.uppercased() ?? "#\(keyCode)"
    }

    static func describe(hold: Modifiers, keyCode: UInt16) -> String { hold.symbols + name(keyCode) }

    /// The key code typing `character` on the current layout (so the default for "close window" is W on any layout).
    static func keyCode(typing character: Character) -> UInt16? {
        let target = String(character).lowercased()
        for code in UInt16(0)..<UInt16(51) where KeyboardLayout.shared.characters(code, shift: false)?.lowercased() == target {
            return code
        }
        return nil
    }

    static func modifiers(_ flags: NSEvent.ModifierFlags) -> Modifiers {
        var m: Modifiers = []
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.shift) { m.insert(.shift) }
        return m
    }
}
