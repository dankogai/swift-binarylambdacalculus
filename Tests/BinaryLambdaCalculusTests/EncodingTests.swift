//
//  EncodingTests.swift
//  BinaryLambdaCalculus
//
import Testing

@testable import BinaryLambdaCalculus

@Test func encodesTheExamplesFromTheSpecification() async throws {
    // https://esolangs.org/wiki/Binary_lambda_calculus
    #expect(Term.identity.bitString == "0010")  // 00 10
    #expect(Term.K.bitString == "0000110")  // 00 00 110
    #expect(Term.true.bitString == "0000110")
    #expect(Term.false.bitString == "000010")  // 00 00 10
    #expect(Term.empty.bitString == "000010")
    // λxλyλz.((xz)(yz)) = 00 00 00 01 01 1110 10 01 110 10
    #expect(Term.S.bitString == "00000001011110100111010")
    // λxλyλz.zxy = 00 00 00 01 01 10 1110 110
    #expect(Term.pair.bitString == "0000000101101110110")
    // "take in one input and output it twice" = 00 01 10 10
    #expect(λ(1, 1).bitString == "00011010")
    // "take in two inputs and output the first one three times"
    #expect(λ(λ(2, 2, 2)).bitString == "00000101110110110")
    // a cons cell is 00 01 01 10 x y
    #expect(Term.cons(.identity, .empty).bitString == "00010110" + "0010" + "000010")
}

@Test func decodesWhatItEncodes() async throws {
    let terms: [Term] = [
        .identity, .K, .S, .pair, .omega, .fix, .universalMachine, .universalMachine8,
        .index(1), .index(17), λ(λ(λ(λ(4, 3, 2, 1)))), .list(bits: [0, 1, 1, 0, 1]),
        .list(bytes: [0x00, 0x7f, 0xff]),
    ]
    for term in terms {
        #expect(try Term(bits: term.bits) == term, "\(term)")
        #expect(try Term(bitString: term.bitString) == term, "\(term)")
        #expect(try Term(packed: term.packed) == term, "\(term)")
    }
}

@Test func decodingStopsWhereTheTermDoes() async throws {
    // the encoding is self-delimiting, which is what lets a program and the
    // input it runs on share one stream
    let (term, rest) = try Term.decode([Bit](bitString: "0010" + "110101"))
    #expect(term == .identity)
    #expect(Array(rest).bitString == "110101")

    // so any byte from 32 to 47 is the identity, padding and all
    for byte in UInt8(32)...47 {
        #expect(try Term(packed: [byte]) == .identity)
    }
    // 48 is 00 110000, an abstraction over the second index — a different
    // term, and not a closed one; 31 is 00 01 1111, which never finishes
    #expect(try Term(packed: [48]) == λ(2))
    #expect(throws: BLCError.truncated) { try Term(packed: [31]) }
}

@Test func decodingFailsOnTruncation() async throws {
    #expect(throws: BLCError.truncated) { try Term(bitString: "") }
    #expect(throws: BLCError.truncated) { try Term(bitString: "0") }
    #expect(throws: BLCError.truncated) { try Term(bitString: "00") }  // λ with no body
    #expect(throws: BLCError.truncated) { try Term(bitString: "0110") }  // application, one argument short
    #expect(throws: BLCError.truncated) { try Term(bitString: "111") }  // index with no terminating 0
}

@Test func packsBitsIntoBytes() async throws {
    #expect([Bit]().packed == [])
    #expect(([0, 0, 1, 0] as [Bit]).packed == [0b0010_0000])
    #expect(([1, 1, 1, 1, 1, 1, 1, 1, 1] as [Bit]).packed == [0xff, 0b1000_0000])
    #expect([Bit](packed: [0b1010_0000]) == [1, 0, 1, 0, 0, 0, 0, 0])
    #expect([Bit](packed: [0x00, 0xff]).bitString == "0000000011111111")
    // unpacking and repacking whole bytes is the identity
    let bytes: [UInt8] = [0, 1, 42, 127, 128, 255]
    #expect([Bit](packed: bytes).packed == bytes)
}

@Test func readsBitsOutOfAnythingWritten() async throws {
    // whitespace and ASCII art are free — the self-interpreter on the esolangs
    // wiki is written as a triangle
    #expect([Bit](bitString: " 0 0 1 0 ").bitString == "0010")
    #expect(try Term(bitString: "00\n10") == .identity)
    #expect([Bit](bitString: "no bits here").isEmpty)
}

@Test func bitIsABit() async throws {
    #expect(Bit(0) == .zero)
    #expect(Bit(1) == .one)
    #expect(Bit(42) == .one)
    #expect(Bit("0") == .zero)
    #expect(Bit("x") == nil)
    #expect("\(Bit.one)" == "1")
    // bit 0 is True, bit 1 is False — which is why the empty list, being
    // False, needs telling apart from a pair by what it does, not what it is
    #expect(Term.bit(.zero) == .true)
    #expect(Term.bit(.one) == .false)
}
