//
//  KeymapStore.swift
//  NorthernCrater
//
//  Reads and writes `keymap.txt`, the engine's keyboard layout (see KeyBindings). The file sits beside the
//  game folder: the engine looks for `<game folder>/../keymap.txt`.
//

import Foundation

enum KeymapStore {
    static var fileURL: URL {
        AppPaths.applicationSupport.appendingPathComponent("keymap.txt")
    }

    /// The layout in the file as the engine reads it; the engine's defaults when there is no usable file.
    static func load(from url: URL = fileURL) -> KeyBindings {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return .defaults }
        return parse(text) ?? .defaults
    }

    /// nil when no line names a known button (the engine then ignores the file too).
    static func parse(_ text: String) -> KeyBindings? {
        let known = Set(KeyBindings.buttons.map(\.id))
        var keys: [String: [Int]] = [:]
        var lines = 0
        for line in text.split(whereSeparator: \.isNewline) {
            let words = line.split(separator: " ", omittingEmptySubsequences: true)
            guard let name = words.first.map(String.init), known.contains(name) else { continue }
            lines += 1
            keys[name] = words.dropFirst().compactMap { Int($0) }.filter { (0..<128).contains($0) }
        }
        guard lines > 0 else { return nil }
        // like the engine: a button the file does not mention has no keys
        for id in known where keys[id] == nil { keys[id] = [] }
        return KeyBindings(keys: keys)
    }

    /// All buttons, one per line (a file with any valid line replaces the engine's defaults).
    static func text(for bindings: KeyBindings) -> String {
        var out = "# NorthernCrater keyboard layout: button, then macOS key codes\n"
        for button in KeyBindings.buttons {
            out += ([button.id] + bindings.keys(for: button.id).map(String.init)).joined(separator: " ") + "\n"
        }
        return out
    }

    /// The default layout needs no file: it is removed so the engine uses its own.
    static func save(_ bindings: KeyBindings, to url: URL = fileURL) throws {
        if bindings == .defaults {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text(for: bindings).write(to: url, atomically: true, encoding: .utf8)
    }
}
