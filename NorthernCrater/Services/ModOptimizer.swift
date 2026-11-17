//
//  ModOptimizer.swift
//  NorthernCrater
//
//  Some mods patch the game's code. Unless that code is lifted into the engine again ("re-lift", about two
//  minutes), the engine runs it in an x86 interpreter and battles are slow. The engine is optimized for one
//  set of mods at a time: this remembers which, so Play re-lifts only when the enabled mods or their
//  options change.
//

import CryptoKit
import Foundation

enum ModOptimizer {
    /// Identifies what the lifted code depends on: the enabled mods in load order (file, size, date) and the
    /// options chosen for them. Disabled mods do not count.
    static func fingerprint(of mods: [ModItem], config: GameLaunchConfig = GameLaunchConfig()) -> String {
        // mods choose code patches by FFNx settings (their conditions read FFNx.toml), so those count too
        // (purely visual settings never select a mod's code patches, so changing them does not re-lift)
        let visualOnly: Set<String> = [
            "enable_vsync", "show_fps", "enable_antialiasing",
            "left_analog_stick_deadzone", "right_analog_stick_deadzone", "enable_auto_run",
            "enable_inverted_vertical_camera_controls", "enable_inverted_horizontal_camera_controls",
        ]
        var text = (FFNxConfigWriter.settings(for: config) + FFNxConfigWriter.forcedSettings(for: config))
            .filter { !visualOnly.contains($0.key) }.map { "\($0.key)=\($0.value)" }.joined(separator: ",") + "\n"
        text += FFNxConfigWriter.overrides(from: mods).map { "\($0.key)=\($0.value)" }.joined(separator: ",") + "\n"
        for mod in mods where mod.isEnabled {
            let path = mod.archiveURL.resolvingSymlinksInPath().path
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
            let date = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            text += "\(path)|\(size)|\(Int(date))\n"
            for option in mod.options.sorted(by: { $0.id < $1.id }) {
                text += "  \(option.id)=\(option.selectedChoiceId)\n"
            }
        }
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static var stampURL: URL {
        AppPaths.engineDirectory.appendingPathComponent(".relifted-mods")
    }

    /// True when the engine's lifted code is not for this set of mods. A fresh build has no stamp and is
    /// lifted for no mods at all.
    static func needsOptimizing(for mods: [ModItem], config: GameLaunchConfig) -> Bool {
        let current = fingerprint(of: mods, config: config)
        let stamped = (try? String(contentsOf: stampURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return current != (stamped ?? fingerprint(of: [], config: config))
    }

    static func markOptimized(for mods: [ModItem], config: GameLaunchConfig) {
        try? fingerprint(of: mods, config: config).write(to: stampURL, atomically: true, encoding: .utf8)
    }
}
