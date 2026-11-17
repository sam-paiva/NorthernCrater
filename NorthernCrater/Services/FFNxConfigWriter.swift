//
//  FFNxConfigWriter.swift
//  NorthernCrater
//
//  Writes the game folder's FFNx.toml at each Play. The engine's default file (FFNx.template.toml, kept by
//  the build) is the base; on top go the player's settings, then the `<FFNxConfig>` entries of the enabled
//  mods whose conditions hold (a higher mod in the load order wins). Starting from the default every time
//  means a mod the player turns off stops affecting the game.
//
//  The old launcher did this; the engine itself does not read mods' FFNxConfig.
//

import Foundation

enum FFNxConfigWriter {
    typealias Setting = (key: String, value: String)

    /// FFNx.toml settings that come from the player's settings screen.
    static func settings(for config: GameLaunchConfig) -> [Setting] {
        [
            ("internal_resolution_scale", String(config.internalResolutionScale)),
            ("aspect_ratio", String(config.aspectCode)),
            ("enable_uncrop", config.aspectCode == 0 ? "false" : "true"),
            ("ff7_fps_limiter", config.enable60FPS ? "3" : "1"),
            ("enable_analogue_controls", config.analogControls ? "true" : "false"),
            ("left_analog_stick_deadzone", String(format: "%.2f", config.leftStickDeadzone)),
            ("right_analog_stick_deadzone", String(format: "%.2f", config.rightStickDeadzone)),
            ("enable_auto_run", config.autoRun ? "true" : "false"),
            ("enable_inverted_vertical_camera_controls", config.invertCameraVertical ? "true" : "false"),
            ("enable_inverted_horizontal_camera_controls", config.invertCameraHorizontal ? "true" : "false"),
            ("enable_vsync", config.vsync ? "true" : "false"),
            ("enable_antialiasing", String(config.antialiasing)),
            ("show_fps", config.showFPS ? "true" : "false")
        ]
    }

    /// Settings that win over the mods: only what the player switched on deliberately.
    static func forcedSettings(for config: GameLaunchConfig) -> [Setting] {
        config.lighting ? [("enable_lighting", "true")] : []
    }

    /// What the enabled mods ask for, lowest priority first so that later (higher) mods win when applied in order.
    static func overrides(from mods: [ModItem]) -> [Setting] {
        var result: [Setting] = []
        for mod in mods.reversed() where mod.isEnabled {
            for entry in mod.ffnxConfig ?? [] where conditionsHold(entry, in: mod) {
                result.append((entry.key, entry.value))
            }
        }
        return result
    }

    private static func conditionsHold(_ entry: FFNxEntry, in mod: ModItem) -> Bool {
        entry.when.allSatisfy { id, wanted in
            guard let option = mod.options.first(where: { $0.id.lowercased() == id.lowercased() }) else { return false }
            return option.selectedChoiceId == wanted
        }
    }

    /// Sets each key in the TOML text: the first uncommented `key = value` line is rewritten (keeping its
    /// quoted/unquoted style); a key the file lacks is appended. The last value given for a key wins.
    static func apply(_ settings: [Setting], to text: String) -> String {
        var final: [String: String] = [:]
        var order: [String] = []
        for s in settings {
            if final[s.key] == nil { order.append(s.key) }
            final[s.key] = s.value
        }
        var lines = text.components(separatedBy: "\n")
        var done = Set<String>()
        for i in lines.indices {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), !trimmed.hasPrefix("["), let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
            guard let value = final[key], !done.contains(key) else { continue }
            let current = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            lines[i] = "\(key) = \(format(value, quoted: current.hasPrefix("\"")))"
            done.insert(key)
        }
        if lines.last == "" { lines.removeLast() }
        for key in order where !done.contains(key) {
            lines.append("\(key) = \(format(final[key]!, quoted: nil))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// `quoted` nil = the key is new: numbers and booleans stay bare, anything else is a string.
    private static func format(_ value: String, quoted: Bool?) -> String {
        let bare = value == "true" || value == "false" || Int(value) != nil || Double(value) != nil
        if quoted == false || (quoted == nil && bare) { return value }
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Writes `<gameDir>/FFNx.toml` from the template (or, for an older build without one, the current file).
    static func write(gameDirectory: URL, config: GameLaunchConfig, mods: [ModItem]) throws {
        let fm = FileManager.default
        let target = gameDirectory.appendingPathComponent("FFNx.toml")
        let template = gameDirectory.appendingPathComponent("FFNx.template.toml")
        let source = fm.fileExists(atPath: template.path) ? template : target
        guard let base = try? String(contentsOf: source, encoding: .utf8) else { return }   // not staged yet
        let text = apply(settings(for: config) + overrides(from: mods) + forcedSettings(for: config), to: base)
        try text.write(to: target, atomically: true, encoding: .utf8)
    }
}
