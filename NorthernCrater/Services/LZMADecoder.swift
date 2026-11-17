//
//  LZMADecoder.swift
//  NorthernCrater
//
//  A decoder for raw LZMA streams (no header): the compression 7th Heaven uses for IRO entries. It follows
//  the public LZMA specification. Apple's Compression framework cannot read these streams, and the files
//  we read it for (mod.xml, small text patches) are tiny, so a compact decoder is enough.
//

import Foundation

nonisolated enum LZMAError: LocalizedError {
    case badProperties
    case corrupt
    case truncated

    var errorDescription: String? {
        switch self {
        case .badProperties: return "Invalid LZMA properties."
        case .corrupt: return "Corrupt LZMA data."
        case .truncated: return "Truncated LZMA data."
        }
    }
}

nonisolated enum LZMADecoder {
    /// Decodes `stream` (a raw LZMA body) into exactly `unpackedSize` bytes.
    /// `properties` is the 5-byte header LZMA stores separately: the lc/lp/pb byte and a 32-bit dictionary size.
    static func decode(properties: [UInt8], stream: [UInt8], unpackedSize: Int) throws -> [UInt8] {
        guard properties.count >= 5, unpackedSize >= 0 else { throw LZMAError.badProperties }
        var d = Int(properties[0])
        guard d < 9 * 5 * 5 else { throw LZMAError.badProperties }
        let lc = d % 9
        d /= 9
        let lp = d % 5
        let pb = d / 5

        let decoder = State(stream: stream, lc: lc, lp: lp, pb: pb, size: unpackedSize)
        try decoder.run()
        return decoder.output
    }
}

private nonisolated final class State {
    // Probability model constants (from the specification)
    private static let moveBits: UInt32 = 5
    private static let bitModelTotalBits: UInt32 = 11
    private static let topValue: UInt32 = 1 << 24
    private static let initialProbability: UInt16 = 1 << 10

    let stream: [UInt8]
    let lc: Int, lp: Int, pb: Int
    let size: Int
    var output: [UInt8] = []

    private var position = 0
    private var range: UInt32 = 0xFFFF_FFFF
    private var code: UInt32 = 0

    private var literalProbs: [UInt16]
    private var isMatch = [UInt16](repeating: initialProbability, count: 12 << 4)
    private var isRep = [UInt16](repeating: initialProbability, count: 12)
    private var isRepG0 = [UInt16](repeating: initialProbability, count: 12)
    private var isRepG1 = [UInt16](repeating: initialProbability, count: 12)
    private var isRepG2 = [UInt16](repeating: initialProbability, count: 12)
    private var isRep0Long = [UInt16](repeating: initialProbability, count: 12 << 4)
    private var posSlot = [UInt16](repeating: initialProbability, count: 4 * 64)
    private var posDecoders = [UInt16](repeating: initialProbability, count: 1 + 128 - 14)
    private var align = [UInt16](repeating: initialProbability, count: 16)
    private var lenDecoder = LenModel()
    private var repLenDecoder = LenModel()

    struct LenModel {
        var choice = initialProbability
        var choice2 = initialProbability
        var low = [UInt16](repeating: initialProbability, count: 16 * 8)
        var mid = [UInt16](repeating: initialProbability, count: 16 * 8)
        var high = [UInt16](repeating: initialProbability, count: 256)
    }

    init(stream: [UInt8], lc: Int, lp: Int, pb: Int, size: Int) {
        self.stream = stream
        self.lc = lc
        self.lp = lp
        self.pb = pb
        self.size = size
        self.literalProbs = [UInt16](repeating: Self.initialProbability, count: 0x300 << (lc + lp))
        output.reserveCapacity(size)
    }

    // MARK: - Range decoder

    private func nextByte() throws -> UInt32 {
        guard position < stream.count else { throw LZMAError.truncated }
        defer { position += 1 }
        return UInt32(stream[position])
    }

    private func initRangeDecoder() throws {
        guard try nextByte() == 0 else { throw LZMAError.corrupt }
        code = 0
        for _ in 0..<4 { code = (code << 8) | (try nextByte()) }
        range = 0xFFFF_FFFF
        if code == range { throw LZMAError.corrupt }
    }

    private func normalize() throws {
        if range < Self.topValue {
            range <<= 8
            code = (code << 8) | (try nextByte())
        }
    }

    private func bit(_ probs: inout [UInt16], _ index: Int) throws -> Int {
        let p = UInt32(probs[index])
        let bound = (range >> Self.bitModelTotalBits) * p
        let result: Int
        if code < bound {
            probs[index] = UInt16(p + (((1 << Self.bitModelTotalBits) - p) >> Self.moveBits))
            range = bound
            result = 0
        } else {
            probs[index] = UInt16(p - (p >> Self.moveBits))
            code -= bound
            range -= bound
            result = 1
        }
        try normalize()
        return result
    }

    private func directBits(_ count: Int) throws -> UInt32 {
        var result: UInt32 = 0
        for _ in 0..<count {
            range >>= 1
            code = code &- range
            let t: UInt32 = 0 &- (code >> 31)
            code = code &+ (range & t)
            if code == range { throw LZMAError.corrupt }
            try normalize()
            result = (result << 1) &+ t &+ 1
        }
        return result
    }

    private func bitTree(_ probs: inout [UInt16], base: Int, bits: Int) throws -> Int {
        var m = 1
        for _ in 0..<bits { m = (m << 1) + (try bit(&probs, base + m)) }
        return m - (1 << bits)
    }

    private func bitTreeReverse(_ probs: inout [UInt16], base: Int, bits: Int) throws -> Int {
        var m = 1
        var symbol = 0
        for i in 0..<bits {
            let b = try bit(&probs, base + m)
            m = (m << 1) + b
            symbol |= b << i
        }
        return symbol
    }

    // MARK: - Main loop

    func run() throws {
        if size == 0 { return }
        try initRangeDecoder()

        var state = 0
        var rep0 = 0, rep1 = 0, rep2 = 0, rep3 = 0
        let pbMask = (1 << pb) - 1
        let lpMask = (1 << lp) - 1

        while output.count < size {
            let posState = output.count & pbMask

            if try bit(&isMatch, (state << 4) + posState) == 0 {
                // literal
                let prev = output.last.map(Int.init) ?? 0
                let litState = ((output.count & lpMask) << lc) + (prev >> (8 - lc))
                let base = 0x300 * litState
                var symbol = 1
                if state >= 7 {
                    var matchByte = Int(output[output.count - rep0 - 1])
                    repeat {
                        let matchBit = (matchByte >> 7) & 1
                        matchByte <<= 1
                        let b = try bit(&literalProbs, base + ((1 + matchBit) << 8) + symbol)
                        symbol = (symbol << 1) | b
                        if matchBit != b { break }
                    } while symbol < 0x100
                }
                while symbol < 0x100 {
                    symbol = (symbol << 1) | (try bit(&literalProbs, base + symbol))
                }
                output.append(UInt8(symbol - 0x100))
                state = state < 4 ? 0 : (state < 10 ? state - 3 : state - 6)
                continue
            }

            var length: Int
            if try bit(&isRep, state) != 0 {
                if output.isEmpty { throw LZMAError.corrupt }
                if try bit(&isRepG0, state) == 0 {
                    if try bit(&isRep0Long, (state << 4) + posState) == 0 {
                        // short rep: one byte from rep0
                        state = state < 7 ? 9 : 11
                        guard rep0 < output.count else { throw LZMAError.corrupt }
                        output.append(output[output.count - rep0 - 1])
                        continue
                    }
                } else {
                    let dist: Int
                    if try bit(&isRepG1, state) == 0 {
                        dist = rep1
                    } else {
                        if try bit(&isRepG2, state) == 0 {
                            dist = rep2
                        } else {
                            dist = rep3
                            rep3 = rep2
                        }
                        rep2 = rep1
                    }
                    rep1 = rep0
                    rep0 = dist
                }
                length = try decodeLen(&repLenDecoder, posState: posState)
                state = state < 7 ? 8 : 11
            } else {
                rep3 = rep2
                rep2 = rep1
                rep1 = rep0
                length = try decodeLen(&lenDecoder, posState: posState)
                state = state < 7 ? 7 : 10
                let distance = try decodeDistance(length: length)
                if distance == 0xFFFF_FFFF { break }   // end marker
                rep0 = Int(distance)
            }

            length += 2
            guard rep0 < output.count else { throw LZMAError.corrupt }
            var remaining = min(length, size - output.count)
            while remaining > 0 {
                output.append(output[output.count - rep0 - 1])
                remaining -= 1
            }
        }

        guard output.count == size else { throw LZMAError.truncated }
    }

    private func decodeLen(_ model: inout LenModel, posState: Int) throws -> Int {
        var choice = [model.choice]
        if try bit(&choice, 0) == 0 {
            model.choice = choice[0]
            return try bitTree(&model.low, base: posState * 8, bits: 3)
        }
        model.choice = choice[0]
        var choice2 = [model.choice2]
        if try bit(&choice2, 0) == 0 {
            model.choice2 = choice2[0]
            return 8 + (try bitTree(&model.mid, base: posState * 8, bits: 3))
        }
        model.choice2 = choice2[0]
        return 16 + (try bitTree(&model.high, base: 0, bits: 8))
    }

    private func decodeDistance(length: Int) throws -> UInt32 {
        let lenState = min(length, 3)
        let slot = try bitTree(&posSlot, base: lenState * 64, bits: 6)
        if slot < 4 { return UInt32(slot) }
        let numDirectBits = (slot >> 1) - 1
        var distance = UInt32((2 | (slot & 1)) << numDirectBits)
        if slot < 14 {
            distance = distance &+ UInt32(try bitTreeReverse(&posDecoders, base: Int(distance) - slot, bits: numDirectBits))
        } else {
            distance = distance &+ ((try directBits(numDirectBits - 4)) << 4)
            distance = distance &+ UInt32(try bitTreeReverse(&align, base: 0, bits: 4))
        }
        return distance
    }
}
