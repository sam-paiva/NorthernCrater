//
//  FF7SaveParser.swift
//  NorthernCrater
//
//  Reads FF7 PC save files (saveNN.ff7). Pure Foundation, no file system or app state, so it can
//  be tested on its own.
//
//  Layout (checked against real saves): a 9-byte header (magic 71 73 27 06) followed by 15 slots of
//  0x10F4 bytes. In each slot: 0x00 checksum (0x4D1D marks an empty slot), 0x04 level, 0x05-0x07
//  portrait ids of the party, 0x08 leader name (16 bytes of FF7 text), 0x20 gil (u32), 0x24 play
//  time in seconds (u32), 0x28 save location (32 bytes of FF7 text).
//

import Foundation

struct SaveSlot: Identifiable, Hashable {
    let index: Int                 // 1...15
    let leader: String
    let party: [String]            // up to 3 portrait names (leader first)
    let level: Int
    let gil: Int
    let playSeconds: Int
    let location: String

    var id: Int { index }

    var playTime: String {
        String(format: "%d:%02d:%02d", playSeconds / 3600, playSeconds / 60 % 60, playSeconds % 60)
    }
}

enum FF7SaveParser {
    static let headerSize = 9
    static let slotSize = 0x10F4
    static let slotsPerFile = 15
    static let fileSize = headerSize + slotsPerFile * slotSize
    static let magic: [UInt8] = [0x71, 0x73, 0x27, 0x06]

    /// Party portrait ids as the game stores them.
    private static let portraitNames: [UInt8: String] = [
        0: "Cloud", 1: "Barret", 2: "Tifa", 3: "Aeris", 4: "Red XIII",
        5: "Yuffie", 6: "Cait Sith", 7: "Vincent", 8: "Cid"
    ]

    static func isPCSave(_ data: Data) -> Bool {
        data.count == fileSize && Array(data.prefix(4)) == magic
    }

    /// The used slots of a PC save, in slot order. Empty for anything that is not a PC save.
    static func slots(in data: Data) -> [SaveSlot] {
        guard isPCSave(data) else { return [] }
        let bytes = [UInt8](data)
        return (0..<slotsPerFile).compactMap { slot(bytes, $0) }
    }

    private static func slot(_ bytes: [UInt8], _ n: Int) -> SaveSlot? {
        let at = headerSize + n * slotSize
        let checksum = Int(bytes[at]) | Int(bytes[at + 1]) << 8
        guard checksum != 0x4D1D, bytes[at..<(at + slotSize)].contains(where: { $0 != 0 }) else { return nil }

        func u32(_ offset: Int) -> Int {
            Int(bytes[at + offset]) | Int(bytes[at + offset + 1]) << 8
                | Int(bytes[at + offset + 2]) << 16 | Int(bytes[at + offset + 3]) << 24
        }
        let party = (0..<3).compactMap { portraitNames[bytes[at + 5 + $0]] }
        return SaveSlot(
            index: n + 1,
            leader: text(bytes[(at + 0x08)..<(at + 0x18)]),
            party: party,
            level: Int(bytes[at + 0x04]),
            gil: u32(0x20),
            playSeconds: u32(0x24),
            location: text(bytes[(at + 0x28)..<(at + 0x48)])
        )
    }

    /// FF7's text encoding: 0x00... is ASCII from space on, 0xFF ends the string.
    static func text<S: Sequence>(_ raw: S) -> String where S.Element == UInt8 {
        var out = ""
        for byte in raw {
            if byte == 0xFF { break }
            out.append(byte <= 0x5E ? Character(UnicodeScalar(byte + 0x20)) : "?")
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
