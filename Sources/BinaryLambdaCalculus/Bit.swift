//
//  Bit.swift
//  BinaryLambdaCalculus
//

/// One bit — of a program, or of the I/O stream it runs on.
public enum Bit: UInt8, Hashable, Sendable, CaseIterable {
    case zero = 0
    case one = 1

    /// `.zero` for `0`, `.one` for anything else.
    public init(_ value: some BinaryInteger) {
        self = value == 0 ? .zero : .one
    }

    /// `.zero` for `"0"`, `.one` for `"1"`, `nil` for anything else.
    public init?(_ character: Character) {
        switch character {
        case "0": self = .zero
        case "1": self = .one
        default: return nil
        }
    }
}

extension Bit: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: UInt8) {
        self.init(value)
    }
}

extension Bit: CustomStringConvertible {
    public var description: String { self == .zero ? "0" : "1" }
}

extension Sequence<Bit> {
    /// The bits as a string of `0`s and `1`s.
    public var bitString: String {
        String(map { $0 == .zero ? "0" : "1" })
    }

    /// The bits packed 8 to a byte, most significant bit first, the last byte
    /// padded with `0`s — the on-disk and on-the-wire form of a BLC program.
    public var packed: [UInt8] {
        var bytes: [UInt8] = []
        var byte: UInt8 = 0
        var filled = 0
        for bit in self {
            byte = byte << 1 | bit.rawValue
            filled += 1
            if filled == 8 {
                bytes.append(byte)
                byte = 0
                filled = 0
            }
        }
        if filled > 0 { bytes.append(byte << (8 - filled)) }
        return bytes
    }
}

extension Array where Element == Bit {
    /// The `0`s and `1`s of `bitString`, ignoring every other character — so
    /// whitespace, and the layout of the ASCII-art programs people like to
    /// write BLC in, are free.
    public init(bitString: String) {
        self = bitString.compactMap(Bit.init)
    }

    /// The bits of `bytes`, most significant bit of each byte first.
    public init(packed bytes: some Sequence<UInt8>) {
        self = bytes.flatMap { byte in
            (0..<8).map { Bit(byte >> (7 - $0) & 1) }
        }
    }
}
