//
//  Encoding.swift
//  BinaryLambdaCalculus
//
//  blc(λM)  = 00 blc(M)
//  blc(M N) = 01 blc(M) blc(N)
//  blc(i)   = 1ⁱ0
//

extension Term {
    /// The binary lambda calculus encoding of this term:
    ///
    /// | term | bits |
    /// |------|------|
    /// | `λ`*M* | `00` blc(*M*) |
    /// | *M* *N* | `01` blc(*M*) blc(*N*) |
    /// | *i* | `1`*ⁱ*`0` |
    ///
    /// ```swift
    /// Term.identity.bitString    // "0010"
    /// ```
    public var bits: [Bit] {
        var bits: [Bit] = []
        bits.reserveCapacity(size)
        // an explicit stack of terms still to encode, rightmost on top
        var stack: [Term] = [self]
        while let term = stack.popLast() {
            switch term {
            case .index(let i):
                bits.append(contentsOf: repeatElement(.one, count: i))
                bits.append(.zero)
            case .abstraction(let body):
                bits += [.zero, .zero]
                stack.append(body)
            case .application(let function, let argument):
                bits += [.zero, .one]
                stack.append(argument)
                stack.append(function)
            }
        }
        return bits
    }

    /// The encoding as a string of `0`s and `1`s.
    public var bitString: String { bits.bitString }

    /// The encoding packed 8 bits to a byte, most significant bit first, the
    /// last byte padded with `0`s.
    ///
    /// The padding is why the identity function — a four-bit program — can be
    /// written as any byte from 32 (`00100000`) through 47 (`00101111`): the
    /// decoder stops as soon as it has a term and never looks at the rest.
    public var packed: [UInt8] { bits.packed }

    /// Decodes the term encoded at the front of `bits`.
    ///
    /// Trailing bits are ignored, as the BLC encoding is self-delimiting — that
    /// is what lets a program and the input it runs on share a single stream.
    /// Use ``decode(_:)`` when the leftovers are the point.
    ///
    /// - Throws: ``BLCError/truncated`` if the bits run out mid-term.
    public init(bits: some Sequence<Bit>) throws {
        self = try Term.decode(bits).term
    }

    /// Decodes the term encoded at the front of `bitString`, ignoring every
    /// character that is not a `0` or a `1`.
    ///
    /// - Throws: ``BLCError/truncated`` if the bits run out mid-term.
    public init(bitString: String) throws {
        try self.init(bits: [Bit](bitString: bitString))
    }

    /// Decodes the term encoded at the front of `bytes`, most significant bit
    /// of each byte first.
    ///
    /// - Throws: ``BLCError/truncated`` if the bits run out mid-term.
    public init(packed bytes: some Sequence<UInt8>) throws {
        try self.init(bits: [Bit](packed: bytes))
    }

    /// Decodes one term from the front of `bits` and returns it together with
    /// the bits left over.
    ///
    /// - Throws: ``BLCError/truncated`` if the bits run out mid-term.
    public static func decode(_ bits: some Sequence<Bit>) throws -> (term: Term, rest: ArraySlice<Bit>) {
        let all = [Bit](bits)
        var position = 0
        let term = try decode(all, at: &position)
        return (term, all[position...])
    }

    /// The decoder proper: an explicit stack, so that no input, however deeply
    /// nested, can overflow the call stack.
    static func decode(_ bits: [Bit], at position: inout Int) throws -> Term {
        /// What remains to be done once the subterm being read is complete.
        enum Frame {
            /// Wrap the finished subterm in an abstraction.
            case abstraction
            /// The finished subterm is a function; its argument comes next.
            case function
            /// The finished subterm is the argument of this function.
            case argument(Term)
        }
        var stack: [Frame] = []
        var finished: Term?
        while true {
            // hand a finished subterm to whatever is waiting for it
            if let term = finished {
                guard let frame = stack.popLast() else { return term }
                switch frame {
                case .abstraction:
                    finished = .abstraction(term)
                case .function:
                    stack.append(.argument(term))
                    finished = nil
                case .argument(let function):
                    finished = .application(function, term)
                }
                continue
            }
            // otherwise start reading the next one
            guard position < bits.count else { throw BLCError.truncated }
            let first = bits[position]
            position += 1
            if first == .one {
                // 1ⁱ0 — the leading 1 counts, then count 1s up to the 0
                var index = 1
                while true {
                    guard position < bits.count else { throw BLCError.truncated }
                    let bit = bits[position]
                    position += 1
                    if bit == .zero { break }
                    index += 1
                }
                finished = .index(index)
            } else {
                guard position < bits.count else { throw BLCError.truncated }
                let second = bits[position]
                position += 1
                stack.append(second == .zero ? .abstraction : .function)
            }
        }
    }
}
