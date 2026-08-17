//
//  Run.swift
//  BinaryLambdaCalculus
//
//  The I/O convention: a program is a closed term, applied to its input as a
//  list of booleans, whose result is read back as another such list.
//

extension Machine {
    /// Takes a list apart, one cell at a time.
    ///
    /// A cell is ⟨*head*, *tail*⟩ = `λz.z` *head* *tail*, so applying it to a
    /// variable nothing can substitute for leaves that variable holding both
    /// parts.  Anything else — `Nil`, which is `λxλy.y`, or the `λx.x` that
    /// Tromp's interpreters return on error — is the end of the list.
    func uncons(_ thunk: Thunk) throws -> (head: Thunk, tail: Thunk)? {
        let (level, probe) = self.probe()
        guard case .rigid(let found, let spine) = try apply(force(thunk), [probe]),
            found == level, spine.count >= 2
        else {
            return nil
        }
        return (spine[0], spine[1])
    }

    /// Reads a boolean: `True` — which picks its first argument — is the bit
    /// `0`, and `False` is the bit `1`.
    func bit(of thunk: Thunk) throws -> Bit {
        let (zero, zeroProbe) = probe()
        let (one, oneProbe) = probe()
        guard case .rigid(let level, let spine) = try apply(force(thunk), [zeroProbe, oneProbe]),
            spine.isEmpty
        else {
            throw BLCError.notABit
        }
        switch level {
        case zero: return .zero
        case one: return .one
        default: throw BLCError.notABit
        }
    }

    /// Reads one byte, as the list of its eight bits, most significant first.
    /// A short list is padded on the right, as `blc run8` pads its last byte.
    func byte(of thunk: Thunk) throws -> UInt8 {
        var byte: UInt8 = 0
        var filled = 0
        var rest: Thunk? = thunk
        while filled < 8, let current = rest, let cell = try uncons(current) {
            byte = byte << 1 | (try bit(of: cell.head)).rawValue
            rest = cell.tail
            filled += 1
        }
        return byte << (8 - filled)
    }
}

/// The output of a running program, read one element at a time.
///
/// The program is only reduced as far as the elements taken from it, so a
/// program whose output is infinite is perfectly fine — take what you want of
/// it and stop:
///
/// ```swift
/// // Tromp's 167-bit program whose output is the characteristic sequence
/// // of the primes — 0011010100010100…  — of which we want a glimpse
/// var primes = try Term(lambda: primesSource).bitStream()
/// try primes.take(100)
/// ```
///
/// It is a `Sequence` too, but iteration cannot throw, so it stops on error and
/// leaves it in ``error``; the throwing ``take(_:)`` and ``collect()`` are
/// usually what you want.
///
/// - Note: A stream has reference semantics — a copy of one shares its
///   position, because it shares the reduction in progress.
public struct OutputStream<Element>: Sequence, IteratorProtocol {
    private let machine: Machine
    private let read: (Machine, Thunk) throws -> Element
    private var rest: Thunk?
    /// What went wrong, if iteration stopped early.
    public private(set) var error: (any Error)?

    init(machine: Machine, list: Thunk, read: @escaping (Machine, Thunk) throws -> Element) {
        self.machine = machine
        self.rest = list
        self.read = read
    }

    /// The next element, or `nil` at the end of the output — or on the error
    /// left in ``error``.
    public mutating func next() -> Element? {
        guard let current = rest else { return nil }
        do {
            guard let cell = try machine.uncons(current) else {
                rest = nil
                return nil
            }
            let element = try read(machine, cell.head)
            rest = cell.tail
            return element
        } catch {
            self.error = error
            rest = nil
            return nil
        }
    }

    /// The next `count` elements, or fewer if the output ends first.
    ///
    /// - Throws: whatever reduction throws — most usefully
    ///   ``BLCError/stepLimitExceeded(steps:)``.
    public mutating func take(_ count: Int) throws -> [Element] {
        var elements: [Element] = []
        elements.reserveCapacity(count)
        while elements.count < count, let element = next() {
            elements.append(element)
        }
        if let error { throw error }
        return elements
    }

    /// Everything the program outputs, which for some programs is never.
    ///
    /// - Throws: whatever reduction throws.
    public mutating func collect() throws -> [Element] {
        var elements: [Element] = []
        while let element = next() { elements.append(element) }
        if let error { throw error }
        return elements
    }
}

/// A program's output, bit by bit — BLC's own I/O.
public typealias BitStream = OutputStream<Bit>
/// A program's output, byte by byte — the BLC8 variation.
public typealias ByteStream = OutputStream<UInt8>

extension Term {
    /// Applies this program to `input` and to `arguments`, and returns its
    /// output as a lazily reduced stream of bits.
    ///
    /// This is BLC's I/O convention: bit `0` is `λxλy.x` and bit `1` is
    /// `λxλy.y`, a string of them is built by repeated pairing, and the program
    /// is a closed term applied to that.
    ///
    /// - Parameters:
    ///   - input: the bits of standard input.
    ///   - terminator: what follows the input — ``Term/empty`` (`Nil`) if the
    ///     program may see where the input ends, or ``Term/omega`` to make it
    ///     work self-delimitingly, since looking at `Ω` never returns.
    ///   - arguments: further terms to apply the program to, after the input.
    ///   - limit: the most reduction steps to take, across the whole stream.
    public func bitStream(
        _ input: some Sequence<Bit> = [Bit](),
        terminator: Term = .empty,
        arguments: [Term] = [],
        limit: Int = .max
    ) -> BitStream {
        stream(applied: .list(bits: input, terminator: terminator), arguments, limit) {
            try $0.bit(of: $1)
        }
    }

    /// Applies this program to `input` and to `arguments`, and returns its
    /// output as a lazily reduced stream of bytes — the BLC8 convention, in
    /// which each byte is a list of its eight bits, most significant first.
    public func byteStream(
        _ input: some Sequence<UInt8> = [UInt8](),
        terminator: Term = .empty,
        arguments: [Term] = [],
        limit: Int = .max
    ) -> ByteStream {
        stream(applied: .list(bytes: input, terminator: terminator), arguments, limit) {
            try $0.byte(of: $1)
        }
    }

    private func stream<Element>(
        applied input: Term,
        _ arguments: [Term],
        _ limit: Int,
        _ read: @escaping (Machine, Thunk) throws -> Element
    ) -> OutputStream<Element> {
        let machine = Machine(limit: limit)
        let applied = Term.apply(.application(self, input), arguments)
        return OutputStream(machine: machine, list: Thunk(applied, nil), read: read)
    }

    /// Runs this program on `input` and collects all of its output — BLC, one
    /// bit at a time.
    ///
    /// ```swift
    /// try Term.identity.run([0, 1, 1, 0])    // [0, 1, 1, 0]
    /// ```
    ///
    /// - Throws: whatever reduction throws.  A program whose output never ends
    ///   never returns; give a `limit`, or use ``bitStream(_:terminator:arguments:limit:)``
    ///   and take what you need.
    public func run(
        _ input: some Sequence<Bit> = [Bit](),
        terminator: Term = .empty,
        arguments: [Term] = [],
        limit: Int = .max
    ) throws -> [Bit] {
        var stream = bitStream(input, terminator: terminator, arguments: arguments, limit: limit)
        return try stream.collect()
    }

    /// Runs this program on `input` and collects all of its output — BLC8, one
    /// byte at a time.
    ///
    /// - Throws: whatever reduction throws.
    public func run8(
        _ input: some Sequence<UInt8> = [UInt8](),
        terminator: Term = .empty,
        arguments: [Term] = [],
        limit: Int = .max
    ) throws -> [UInt8] {
        var stream = byteStream(input, terminator: terminator, arguments: arguments, limit: limit)
        return try stream.collect()
    }

    /// Runs this program on the UTF-8 of `input` and reads its output back the
    /// same way — BLC8 for people who would rather think in text.
    ///
    /// - Throws: whatever reduction throws.
    public func run8(
        _ input: String,
        terminator: Term = .empty,
        arguments: [Term] = [],
        limit: Int = .max
    ) throws -> String {
        let output = try run8(
            Array(input.utf8), terminator: terminator, arguments: arguments, limit: limit)
        return String(decoding: output, as: UTF8.self)
    }
}
