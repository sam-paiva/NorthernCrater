//
//  ModProfileWriter.swift
//  NorthernCrater
//
//  Writes the engine's mod profile. The engine reads `<game folder>/../mods/profile.xml` at start-up: the
//  mods in priority order (first wins), each named by a file or folder inside that same `mods` folder, with
//  `Enabled="false"` to skip one and `<Option ID= Value=>` for the player's choices.
//
//  Mods stay where the player keeps them; each is linked into `mods`. Only symlinks are ever created,
//  replaced or removed here: a real file or folder in `mods` (a downloaded .iro, say) is never touched.
//

import Foundation

enum ModProfileWriter {
    static func write(mods: [ModItem], to modsDir: URL, conditionsFile: URL? = nil) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: modsDir, withIntermediateDirectories: true)
        
        // The conditions file some 7th Heaven mods refer to.
        let conditionsDest = modsDir.appendingPathComponent("7thHeaven.var")
        if let conditionsFile, fm.fileExists(atPath: conditionsFile.path), !exists(conditionsDest) {
            try fm.copyItem(at: conditionsFile, to: conditionsDest)
        }
        
        var usedNames = Set<String>()
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Profile Language=\"en\">\n"
        for mod in mods {
            let name = try entryName(for: mod.archiveURL, in: modsDir, taken: usedNames)
            usedNames.insert(name.lowercased())
            
            xml += "  <Mod Path=\"\(escape(name))\""
            if !mod.isEnabled { xml += " Enabled=\"false\"" }
            let chosen = mod.options.filter { !$0.selectedChoiceId.isEmpty }
            if chosen.isEmpty {
                xml += "/>\n"
            } else {
                xml += ">\n"
                for option in chosen {
                    xml += "    <Option ID=\"\(escape(option.id))\" Value=\"\(escape(option.selectedChoiceId))\"/>\n"
                }
                xml += "  </Mod>\n"
            }
        }
        xml += "</Profile>\n"
        try xml.write(to: modsDir.appendingPathComponent("profile.xml"), atomically: true, encoding: .utf8)
        
        // Links to mods that are no longer in the list go away (links only).
        for existing in (try? fm.contentsOfDirectory(atPath: modsDir.path)) ?? [] {
            let url = modsDir.appendingPathComponent(existing)
            if !usedNames.contains(existing.lowercased()), isSymlink(url) {
                try? fm.removeItem(at: url)
            }
        }
    }
    
    /// The name the profile uses for this mod, creating its link if needed.
    private static func entryName(for source: URL, in modsDir: URL, taken: Set<String>) throws -> String {
        let fm = FileManager.default
        let base = source.lastPathComponent
        var candidate = base
        var attempt = 1
        while true {
            let link = modsDir.appendingPathComponent(candidate)
            if !taken.contains(candidate.lowercased()) {
                if !exists(link) {
                    try fm.createSymbolicLink(at: link, withDestinationURL: source)
                    return candidate
                }
                if sameFile(link, source) { return candidate }              // the mod already lives in `mods`
                if isSymlink(link) {
                    if (try? fm.destinationOfSymbolicLink(atPath: link.path)) != source.path {
                        try fm.removeItem(at: link)                         // our own stale link: re-point it
                        try fm.createSymbolicLink(at: link, withDestinationURL: source)
                    }
                    return candidate
                }
                // a different real file or folder has this name: use another one
            }
            attempt += 1
            candidate = "\(attempt)-\(base)"
        }
    }
    
    // MARK: - File system helpers (lstat semantics: a broken link still "exists")
    
    private static func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }
    
    private static func isSymlink(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType == .typeSymbolicLink
    }
    
    /// Both paths lead to the same file or folder on disk (links followed).
    private static func sameFile(_ a: URL, _ b: URL) -> Bool {
        let fm = FileManager.default
        guard let x = try? fm.attributesOfItem(atPath: a.resolvingSymlinksInPath().path),
              let y = try? fm.attributesOfItem(atPath: b.resolvingSymlinksInPath().path),
              let xn = x[.systemFileNumber] as? Int, let yn = y[.systemFileNumber] as? Int,
              let xs = x[.systemNumber] as? Int, let ys = y[.systemNumber] as? Int else { return false }
        return xn == yn && xs == ys
    }
    
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
    }
}
