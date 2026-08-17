//
//  main.swift
//  blc
//
//  A command line for binary lambda calculus, after the `blc` of John Tromp's
//  AIT repository.
//

import BinaryLambdaCalculus

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

import Foundation

let usage = """
    Usage: blc <action> <program> [argument]...

    Actions:
      run     run the program on standard input, a bit at a time     (BLC)
      run8    run the program on standard input, a byte at a time    (BLC8)
      print   print the program in lambda notation
      nf      print the normal form of the program
      blc     print the binary encoding of the program, as 0s and 1s
      pack    write the binary encoding of the program, 8 bits to a byte
      size    print the size of the program, in bits
      help    print this

    <program> is a file, or `-` for standard input.  A file named .blc or .blc8
    is read as packed bits, a file of nothing but 0s and 1s as bits written out,
    and anything else as lambda notation — `λx.x`, `\\x.x`, or `λ1`, as you like.

    Each [argument] is applied to the program after the input, encoded the same
    way the input is.

    Options:
      --limit <n>   give up after n reduction steps (default: no limit)
      --omega       end the input with Ω rather than nil, so that the program
                    must work out for itself where the input stops

    Examples:
      printf 'Hello' | blc run8 Examples/id.lam    -- cat, in four bits
      blc size Examples/uni.lam                    -- 232
      blc pack Examples/id.lam > cat.blc8          -- compile a program...
      printf 'Hello' | cat cat.blc8 - | blc run8 Examples/uni8.lam
                                                   -- ...and run it under U8
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("blc: \(message)\n".utf8))
    exit(1)
}

// MARK: - arguments

var arguments = Array(CommandLine.arguments.dropFirst())
var limit = Int.max
var terminator = Term.empty

var index = 0
while index < arguments.count {
    switch arguments[index] {
    case "--limit":
        guard index + 1 < arguments.count, let value = Int(arguments[index + 1]), value > 0 else {
            fail("--limit wants a positive number")
        }
        limit = value
        arguments.removeSubrange(index...(index + 1))
    case "--omega":
        terminator = .omega
        arguments.remove(at: index)
    case "-h", "--help":
        print(usage)
        exit(0)
    default:
        index += 1
    }
}

guard let action = arguments.first else {
    print(usage)
    exit(1)
}
if action == "help" {
    print(usage)
    exit(0)
}
guard arguments.count >= 2 else { fail("\(action) wants a program") }
let path = arguments[1]
let extra = Array(arguments.dropFirst(2))

// MARK: - the program

func read(_ path: String) -> Data {
    if path == "-" { return FileHandle.standardInput.readDataToEndOfFile() }
    guard let data = FileManager.default.contents(atPath: path) else {
        fail("cannot read \(path)")
    }
    return data
}

let data = read(path)
let text = String(data: data, encoding: .utf8)

let program: Term
do {
    if path.hasSuffix(".blc") || path.hasSuffix(".blc8") {
        program = try Term(packed: data)
    } else if let text, !text.isEmpty, text.allSatisfy({ "01".contains($0) || $0.isWhitespace }),
        text.contains(where: { "01".contains($0) })
    {
        program = try Term(bitString: text)
    } else if let text {
        program = try Term(lambda: text)
    } else {
        program = try Term(packed: data)
    }
} catch {
    fail("\(path): \(error)")
}

guard program.isClosed || !action.hasPrefix("run") else {
    fail("\(path): a program must be a closed term")
}

// MARK: - output

/// Writes straight to standard output, unbuffered: a program's output can
/// take a while to arrive, and holding on to a bufferful of it before showing
/// any would make a generator look like a hang.  A reader that stops reading
/// stops us with SIGPIPE, as it does any other filter.
func emit(_ bytes: [UInt8]) {
    var offset = 0
    while offset < bytes.count {
        let written = bytes.withUnsafeBytes {
            write(1, $0.baseAddress! + offset, $0.count - offset)
        }
        guard written > 0 else { fail("cannot write to standard output") }
        offset += written
    }
}

func emit(_ byte: UInt8) { emit([byte]) }

// MARK: - actions

switch action {
case "print":
    print(program)
case "blc":
    print(program.bitString)
case "pack":
    emit(program.packed)
case "size":
    print(program.size)
case "nf":
    do {
        print(try program.normalForm(limit: limit))
    } catch {
        fail("\(error)")
    }

case "run":
    // bits in, bits out, packed 8 to a byte
    let input = [Bit](packed: Array(FileHandle.standardInput.readDataToEndOfFile()))
    var stream = program.bitStream(
        input,
        terminator: terminator,
        arguments: extra.map { .list(bits: [Bit](packed: Array($0.utf8))) },
        limit: limit
    )
    var bits: [Bit] = []
    while let bit = stream.next() {
        bits.append(bit)
        if bits.count == 8 {
            emit(bits.packed[0])
            bits.removeAll(keepingCapacity: true)
        }
    }
    if !bits.isEmpty { emit(bits.packed[0]) }
    if let error = stream.error { fail("\(error)") }

case "run8":
    let input = Array(FileHandle.standardInput.readDataToEndOfFile())
    var stream = program.byteStream(
        input,
        terminator: terminator,
        arguments: extra.map { .list(string: $0) },
        limit: limit
    )
    while let byte = stream.next() { emit(byte) }
    if let error = stream.error { fail("\(error)") }

default:
    fail("no such action as \(action); try `blc help`")
}
