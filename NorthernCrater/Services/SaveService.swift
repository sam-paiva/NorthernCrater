//
//  SaveService.swift
//  NorthernCrater
//
//  Reads and imports FF7 PC save files. Parsing lives in FF7SaveParser.
//

import Foundation

struct SaveFile: Identifiable, Hashable {
    let url: URL
    let slots: [SaveSlot]
    let modified: Date?
    
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

enum SaveError: LocalizedError {
    case notAPCSave(String)
    case emptySave(String)
    case allFilesUsed
    
    var errorDescription: String? {
        switch self {
        case .notAPCSave(let name):
            return "\(name) is not an FF7 PC save file (saveNN.ff7)."
        case .emptySave(let name):
            return "\(name) contains no saved games."
        case .allFilesUsed:
            return "All 10 save files (save00 to save09) are in use. Remove one in the game's save folder first."
        }
    }
}

protocol SaveManaging {
    func gameSaves() -> [SaveFile]
    func read(_ url: URL) throws -> SaveFile
    func importSave(_ url: URL) throws -> SaveFile
}

struct SaveService: SaveManaging {
    static let fileCount = 10
    
    private var directory: URL { AppPaths.saveDirectory }
    
    private func fileURL(_ n: Int) -> URL {
        directory.appendingPathComponent(String(format: "save%02d.ff7", n))
    }
    
    /// The save files the game currently has (save00.ff7 ... save09.ff7), in order.
    func gameSaves() -> [SaveFile] {
        (0..<Self.fileCount).compactMap { n in
            let url = fileURL(n)
            return try? read(url, allowEmpty: true)
        }
    }
    
    /// Reads any save file, from anywhere, without changing it.
    func read(_ url: URL) throws -> SaveFile {
        try read(url, allowEmpty: false)
    }
    
    private func read(_ url: URL, allowEmpty: Bool) throws -> SaveFile {
        let data = try Data(contentsOf: url)
        guard FF7SaveParser.isPCSave(data) else { throw SaveError.notAPCSave(url.lastPathComponent) }
        let slots = FF7SaveParser.slots(in: data)
        if slots.isEmpty && !allowEmpty { throw SaveError.emptySave(url.lastPathComponent) }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return SaveFile(url: url, slots: slots, modified: modified)
    }
    
    /// Copies a save file into the first free saveNN.ff7 of the game. Nothing is ever overwritten.
    func importSave(_ url: URL) throws -> SaveFile {
        _ = try read(url)   // validates it first
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        for n in 0..<Self.fileCount where !fm.fileExists(atPath: fileURL(n).path) {
            try fm.copyItem(at: url, to: fileURL(n))
            return try read(fileURL(n))
        }
        throw SaveError.allFilesUsed
    }
}
