//
//  BinaryIROParser.swift
//  NorthernCrater
//
//  Turns a mod on disk into a ModItem: a .iro archive, or a folder that holds a mod.xml (a mod that was
//  unpacked, which 7th Heaven and the engine both accept).
//

import Foundation

struct BinaryIROParser: IROParsing {
    func parseMod(at url: URL) throws -> ModItem {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw IROParserError.unreadableFile
        }
        return isDirectory.boolValue ? try parseFolder(url) : try parseArchive(url)
    }
    
    private func parseArchive(_ url: URL) throws -> ModItem {
        let archive = try IROArchive(url: url)
        guard let entry = archive.entry(named: "mod.xml") else { throw IROParserError.modXMLNotFound }
        return try ModInfoParser.parse(try archive.read(entry), archiveURL: url)
    }
    
    /// The folder itself, or (when an archive was unpacked into a wrapper folder) the one folder inside it,
    /// that holds a mod.xml. The mod is that inner folder: the engine needs mod.xml at its root.
    private func parseFolder(_ url: URL) throws -> ModItem {
        guard let root = Self.modRoot(in: url) else { throw IROParserError.modXMLNotFound }
        let xml = try Data(contentsOf: root.appendingPathComponent("mod.xml"))
        return try ModInfoParser.parse(xml, archiveURL: root)
    }
    
    nonisolated static func modRoot(in folder: URL) -> URL? {
        let fm = FileManager.default
        func hasModXML(_ dir: URL) -> Bool {
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return false }
            return names.contains { $0.lowercased() == "mod.xml" }
        }
        if hasModXML(folder) { return folder }
        let children = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        let candidates = children
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .filter(hasModXML)
        return candidates.first
    }
}
