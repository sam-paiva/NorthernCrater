//
//  KeyBindings.swift
//  NorthernCrater
//
//  The keyboard layout of the game. The engine turns keys into the buttons of an Xbox-style pad (the game's
//  own Config menu then assigns actions to those buttons). It reads `keymap.txt` beside the game folder:
//  one line per button, "name keycode keycode ...", with macOS virtual key codes (0-127). If the file has any
//  valid line it REPLACES the engine's defaults, so all buttons are always written.
//

import Foundation

/// A pad button the keyboard can press, named as the engine names it in keymap.txt.
struct GameButton: Identifiable, Hashable {
    let id: String          // the engine's name for it (the first word of a keymap.txt line)
    let title: String
    let padButton: String   // the Xbox-style button the engine presses
}

struct KeyBindings: Equatable {
    static let buttons: [GameButton] = [
        GameButton(id: "up", title: "Move up", padButton: "D-pad up"),
        GameButton(id: "down", title: "Move down", padButton: "D-pad down"),
        GameButton(id: "left", title: "Move left", padButton: "D-pad left"),
        GameButton(id: "right", title: "Move right", padButton: "D-pad right"),
        GameButton(id: "ok", title: "OK / confirm", padButton: "B"),
        GameButton(id: "cancel", title: "Cancel", padButton: "A"),
        GameButton(id: "menu", title: "Menu", padButton: "Y"),
        GameButton(id: "square", title: "Switch / special", padButton: "X"),
        GameButton(id: "l1", title: "L1", padButton: "LB"),
        GameButton(id: "r1", title: "R1", padButton: "RB"),
        GameButton(id: "l2", title: "L2", padButton: "LT"),
        GameButton(id: "r2", title: "R2", padButton: "RT"),
        GameButton(id: "select", title: "Select", padButton: "Back"),
        GameButton(id: "start", title: "Start", padButton: "Start"),
        GameButton(id: "l3", title: "L3 (FFNx shortcut mode)", padButton: "Left stick click"),
        GameButton(id: "r3", title: "R3", padButton: "Right stick click"),
    ]

    /// The engine's built-in layout (ff7_mac_main.mm k_keymap_default).
    static let defaults = KeyBindings(keys: [
        "up": [126], "down": [125], "left": [123], "right": [124],
        "ok": [36, 76, 40], "cancel": [51, 38], "menu": [49, 34], "square": [56, 60, 32],
        "l1": [12], "r1": [13], "l2": [18], "r2": [19],
        "select": [48], "start": [35], "l3": [37], "r3": [15],
    ])

    /// Key codes per button id, in the order the player added them.
    var keys: [String: [Int]]

    func keys(for button: String) -> [Int] { keys[button] ?? [] }

    /// The button a key is bound to, if any.
    func button(for key: Int) -> String? {
        Self.buttons.first { keys(for: $0.id).contains(key) }?.id
    }
}

enum KeyNames {
    /// Physical key positions as labelled on a US keyboard (the codes are positions, not letters).
    private static let table: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W",
        14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
        48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc",
        56: "Left Shift", 57: "Caps Lock", 58: "Left Option", 59: "Left Control",
        60: "Right Shift", 61: "Right Option", 62: "Right Control",
        65: "Keypad .", 67: "Keypad *", 69: "Keypad +", 71: "Keypad Clear", 75: "Keypad /", 76: "Keypad Enter",
        78: "Keypad -", 81: "Keypad =", 82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3",
        86: "Keypad 4", 87: "Keypad 5", 88: "Keypad 6", 89: "Keypad 7", 91: "Keypad 8", 92: "Keypad 9",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13", 107: "F14",
        109: "F10", 111: "F12", 113: "F15", 114: "Help", 115: "Home", 116: "Page Up", 117: "Forward Delete",
        118: "F4", 119: "End", 120: "F2", 121: "Page Down", 122: "F1",
        123: "Left Arrow", 124: "Right Arrow", 125: "Down Arrow", 126: "Up Arrow",
    ]

    static func name(_ code: Int) -> String { table[code] ?? "Key \(code)" }
}
