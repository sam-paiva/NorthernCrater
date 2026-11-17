//
//  IROArchive.swift
//  NorthernCrater
//
//  Reads 7th Heaven .iro mod archives. Layout (checked against real mods and the engine's own reader):
//    header      4 x u32: "IROS", version (0x10000...0x10002), unused, directory offset
//    directory   i32 count (-1 means "the directory moved": u64 new offset follows), then `count` records
//    record      u16 total size, u16 name bytes, name (UTF-16LE), u32 flags, offset (u32 before version
//                0x10001, else u64), u32 stored length
//    flags       & 0xF: 0 stored, 1 LZS (FF7's LZSS), 2 LZMA (i32 unpacked size, i32 property bytes,
//                properties, raw LZMA stream); & 0xFF0000: obfuscated (not supported, as in 7th Heaven)
//

import Foundation

nonisolated enum IROParserError: LocalizedError {
    case unreadableFile
    case notAnIRO
    case unsupportedVersion(UInt32)
    case badDirectory
    case obfuscatedEntry(String)
    case unsupportedCompression(UInt32)
    case decompressionFailed(String)
    case entryTooLarge(String)
    case modXMLNotFound
    case malformedModXML
    
    var errorDescription: String? {
        switch self {
        case .unreadableFile: return "Could not open the file."
        case .notAnIRO: return "Not a 7th Heaven .iro archive (missing the IROS header)."
        case .unsupportedVersion(let v): return String(format: "Unsupported .iro version 0x%X.", v)
        case .badDirectory: return "The .iro archive's file list is damaged."
        case .obfuscatedEntry(let name): return "\(name) is obfuscated, which is not supported."
        case .unsupportedCompression(let flags): return "Unsupported compression type \(flags & 0xF)."
        case .decompressionFailed(let name): return "Could not decompress \(name)."
        case .entryTooLarge(let name): return "\(name) is too large to read into memory."
        case .modXMLNotFound: return "No mod.xml found: this does not look like a 7th Heaven mod."
        case .malformedModXML: return "mod.xml could not be read."
        }
    }
}

nonisolated struct IROEntry {
    let name: String
    let flags: UInt32
    let offset: UInt64
    let length: UInt32
}

nonisolated final class IROArchive {
    private static let signature: UInt32 = 0x534F_5249          // "IROS"
    private static let maxEntryBytes = 256 << 20                // we only read small files (mod.xml, patches)
    
    let url: URL
    private(set) var entries: [IROEntry] = []
    private var lookup: [String: Int] = [:]
    private let handle: FileHandle
    
    init(url: URL) throws {
        self.url = url
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw IROParserError.unreadableFile }
        self.handle = handle
        do {
            try readDirectory()
        } catch {
            try? handle.close()
            throw error
        }
    }
    
    deinit { try? handle.close() }
    
    /// Case-insensitive, and "/" and "\" are the same.
    private static func key(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "\\").lowercased()
    }
    
    func entry(named name: String) -> IROEntry? {
        lookup[Self.key(name)].map { entries[$0] }
    }
    
    // MARK: - Directory
    
    private func readExact(at offset: UInt64, count: Int) throws -> Data {
        try handle.seek(toOffset: offset)
        return try readNext(count)
    }
    
    private func readNext(_ count: Int) throws -> Data {
        guard count >= 0, let data = try handle.read(upToCount: count), data.count == count else {
            throw IROParserError.badDirectory
        }
        return data
    }
    
    private func readDirectory() throws {
        let header = try readExact(at: 0, count: 16)
        guard header.u32(0) == Self.signature else { throw IROParserError.notAnIRO }
        let version = header.u32(4)
        guard (0x10000...0x10002).contains(version) else { throw IROParserError.unsupportedVersion(version) }
        
        // A patched archive relocates its directory: a count of -1 points to the new one.
        var position = UInt64(header.u32(12))
        var count: Int32 = 0
        for hop in 0...8 {
            count = Int32(bitPattern: try readExact(at: position, count: 4).u32(0))
            if count != -1 { break }
            if hop == 8 { throw IROParserError.badDirectory }
            position = try readNext(8).u64(0)
        }
        guard count >= 0 else { throw IROParserError.badDirectory }
        
        try handle.seek(toOffset: position + 4)   // the records follow one another
        entries.reserveCapacity(Int(count))
        for _ in 0..<Int(count) {
            let prefix = try readNext(4)
            let recordSize = Int(prefix.u16(0)), nameBytes = Int(prefix.u16(2))
            let tail = (version < 0x10001) ? 12 : 16     // flags + offset + length
            guard recordSize >= 4 + nameBytes + tail else { throw IROParserError.badDirectory }
            let rest = try readNext(recordSize - 4)
            let name = String(data: rest.subdata(in: 0..<nameBytes), encoding: .utf16LittleEndian) ?? ""
            let flags = rest.u32(nameBytes)
            let offset: UInt64 = version < 0x10001 ? UInt64(rest.u32(nameBytes + 4)) : rest.u64(nameBytes + 4)
            let length = rest.u32(nameBytes + (version < 0x10001 ? 8 : 12))
            lookup[Self.key(name)] = entries.count
            entries.append(IROEntry(name: name, flags: flags, offset: offset, length: length))
        }
    }
    
    // MARK: - Entries
    
    /// The decompressed contents of one entry.
    func read(_ entry: IROEntry) throws -> Data {
        guard entry.flags & 0xFF_0000 == 0 else { throw IROParserError.obfuscatedEntry(entry.name) }
        guard Int(entry.length) <= Self.maxEntryBytes else { throw IROParserError.entryTooLarge(entry.name) }
        let stored = try readExact(at: entry.offset, count: Int(entry.length))
        
        switch entry.flags & 0xF {
        case 0:
            return stored
        case 1:
            return Data(LZSDecoder.decode([UInt8](stored)))
        case 2:
            guard stored.count >= 8 else { throw IROParserError.decompressionFailed(entry.name) }
            let unpacked = Int(Int32(bitPattern: stored.u32(0)))
            let propertyBytes = Int(Int32(bitPattern: stored.u32(4)))
            guard unpacked >= 0, propertyBytes >= 5, 8 + propertyBytes <= stored.count else {
                throw IROParserError.decompressionFailed(entry.name)
            }
            guard unpacked <= Self.maxEntryBytes else { throw IROParserError.entryTooLarge(entry.name) }
            let bytes = [UInt8](stored)
            do {
                return Data(try LZMADecoder.decode(
                    properties: Array(bytes[8..<(8 + propertyBytes)]),
                    stream: Array(bytes[(8 + propertyBytes)...]),
                    unpackedSize: unpacked))
            } catch {
                throw IROParserError.decompressionFailed(entry.name)
            }
        default:
            throw IROParserError.unsupportedCompression(entry.flags)
        }
    }
}

// MARK: - LZS (FF7's LZSS: 4096-byte ring, 18-byte matches, threshold 2)

nonisolated enum LZSDecoder {
    static func decode(_ input: [UInt8]) -> [UInt8] {
        let ringSize = 4096, maxMatch = 18, threshold = 2
        var ring = [UInt8](repeating: 0, count: ringSize)
        var output: [UInt8] = []
        output.reserveCapacity(input.count * 2)
        var position = 0
        var r = ringSize - maxMatch
        var flags = 0
        
        func emit(_ byte: UInt8) {
            output.append(byte)
            ring[r] = byte
            r = (r + 1) & (ringSize - 1)
        }
        
        while true {
            flags >>= 1
            if flags & 256 == 0 {
                guard position < input.count else { break }
                flags = Int(input[position]) | 0xFF00      // the high byte counts the eight flags
                position += 1
            }
            if flags & 1 != 0 {
                guard position < input.count else { break }
                emit(input[position])
                position += 1
            } else {
                guard position + 1 < input.count else { break }
                var i = Int(input[position]), j = Int(input[position + 1])
                position += 2
                i |= (j & 0xF0) << 4
                j = (j & 0x0F) + threshold
                for k in 0...j { emit(ring[(i + k) & (ringSize - 1)]) }
            }
        }
        return output
    }
}

// MARK: - Little-endian reads

nonisolated extension Data {
    func u16(_ offset: Int) -> UInt16 {
        let b = startIndex + offset
        return UInt16(self[b]) | UInt16(self[b + 1]) << 8
    }
    func u32(_ offset: Int) -> UInt32 {
        let b = startIndex + offset
        return UInt32(self[b]) | UInt32(self[b + 1]) << 8 | UInt32(self[b + 2]) << 16 | UInt32(self[b + 3]) << 24
    }
    func u64(_ offset: Int) -> UInt64 {
        UInt64(u32(offset)) | UInt64(u32(offset + 4)) << 32
    }
}
