//
//  Prelude.swift
//  BinaryLambdaCalculus
//
//  The handful of terms the language is defined in terms of.
//

extension Term {
    /// `λ1` — the identity, and the shortest closed term there is at four bits.
    /// As a program it copies its input to its output, which makes `0010` the
    /// BLC equivalent of `cat`.
    public static let identity = λ(1)

    /// `λλ2` — the boolean that picks its first argument, and so also the
    /// combinator `K` and the encoding of the bit `0`.
    public static let `true` = λ(λ(2))

    /// `λλ1` — the boolean that picks its second argument, and so also the
    /// encoding of the bit `1` and of the empty list.
    public static let `false` = λ(λ(1))

    /// `λλ1` — the end of a list.  The same term as ``false``, which is exactly
    /// what makes it easy to tell apart from a pair.
    public static let empty = Term.false

    /// `(λ11)(λ11)` — the term that reduces to itself forever.
    ///
    /// As the tail of an input it means "there is no end of input to find": a
    /// program given `s:Ω` must decide for itself where its input stops, and
    /// this is the difference between plain and prefix complexity.
    public static let omega = λ(1, 1) * λ(1, 1)

    /// `λλλ3 1(2 1)` — the `S` combinator, λ*x*λ*y*λ*z*.((*x* *z*)(*y* *z*)).
    public static let S = λ(λ(λ(Term.apply(3, 1) * Term.apply(2, 1))))

    /// `λλ2` — the `K` combinator, λ*x*λ*y*.*x*.  The same term as ``true``.
    public static let K = Term.true

    /// `λ1` — the `I` combinator.  The same term as ``identity``.
    public static let I = Term.identity

    /// `λλλ1 3 2` — the pairing function λ*x*λ*y*λ*z*.*z* *x* *y*, which is how
    /// BLC builds every list.
    public static let pair = λ(λ(λ(Term.apply(1, 3, 2))))

    /// `λ(λ2(1 1))(λ2(1 1))` — Curry's fixed-point combinator `Y`, which is how
    /// a term written in ``init(lambda:)``'s `let` notation refers to itself.
    public static let fix = λ(λ(2, 1 * 1) * λ(2, 1 * 1))

    /// The bit as the boolean that stands for it: `0` is ``true``, `1` is
    /// ``false``.
    public static func bit(_ bit: Bit) -> Term {
        bit == .zero ? .true : .false
    }

    /// ⟨*head*, *tail*⟩ = `λz.z` *head* *tail* — one cell of a list.
    public static func cons(_ head: Term, _ tail: Term) -> Term {
        .abstraction(.application(.application(.index(1), head.shifted(by: 1)), tail.shifted(by: 1)))
    }

    /// The terms as a list, built by repeated pairing and ended with
    /// `terminator`.
    ///
    /// - Precondition: every element, and the terminator, is closed — as
    ///   everything the I/O convention builds lists out of is.
    public static func list(
        _ elements: some Sequence<Term>, terminator: Term = .empty
    ) -> Term {
        precondition(terminator.isClosed, "a list terminator must be a closed term")
        var term = terminator
        for element in Array(elements).reversed() {
            precondition(element.isClosed, "a list element must be a closed term")
            // both parts are closed, so nothing needs shifting under the new λ
            term = .abstraction(.application(.application(.index(1), element), term))
        }
        return term
    }

    /// The bits as a list of booleans — the input of a BLC program, and the
    /// shape its output is expected to have.
    public static func list(bits: some Sequence<Bit>, terminator: Term = .empty) -> Term {
        list(bits.map(Term.bit), terminator: terminator)
    }

    /// One byte as a list of eight booleans, most significant bit first — the
    /// element type of BLC8's input and output.
    public static func byte(_ byte: UInt8) -> Term {
        list(bits: (0..<8).map { Bit(byte >> (7 - $0) & 1) })
    }

    /// The bytes as a list of lists of booleans — the input of a BLC8 program.
    public static func list(bytes: some Sequence<UInt8>, terminator: Term = .empty) -> Term {
        list(bytes.map(Term.byte), terminator: terminator)
    }

    /// The UTF-8 of `string` as a BLC8 input list.
    public static func list(string: String, terminator: Term = .empty) -> Term {
        list(bytes: Array(string.utf8), terminator: terminator)
    }

    /// Increases every free index by `amount`, so that the term means the same
    /// thing under `amount` more lambdas than it was written under.
    public func shifted(by amount: Int, from depth: Int = 0) -> Term {
        switch self {
        case .index(let index):
            return .index(index > depth ? index + amount : index)
        case .abstraction(let body):
            return .abstraction(body.shifted(by: amount, from: depth + 1))
        case .application(let function, let argument):
            return .application(
                function.shifted(by: amount, from: depth),
                argument.shifted(by: amount, from: depth)
            )
        }
    }
}

extension Term {
    /// John Tromp's universal machine `U`: 232 bits that read a BLC program off
    /// the front of their input and run it on the rest.
    ///
    /// ```swift
    /// // run the identity program under U, and it behaves like `cat`
    /// let program = Term.identity.bits
    /// try Term.universalMachine.run(program + [1, 0, 1, 1])    // [1, 0, 1, 1]
    /// ```
    ///
    /// It is what makes the length of a BLC program a concrete measure of
    /// descriptional complexity: any other way of describing an object costs at
    /// most a constant — the size of its interpreter written in BLC — more.
    public static let universalMachine = try! Term(
        lambda:
            // from https://tromp.github.io/cl/Binary_lambda_calculus.html,
            // with the spaces his single-digit convention leaves out put back
            "(λ1 1)(λλλ1(λλλλ3(λ5(3(λ2(3(λλ3(λ1 2 3)))(4(λ4(λ3 1(2 1))))))"
            + "(1(2(λ1 2))(λ4(λ4(λ2(1 4)))5))))(3 3)2)(λ1((λ1 1)(λ1 1)))")

    /// John Tromp's byte-oriented universal machine `U8`: the same idea as
    /// ``universalMachine``, reading and writing lists of eight-bit lists
    /// instead of bare bits.  355 bits, which is 45 bytes.
    public static let universalMachine8 = try! Term(
        lambda:
            // likewise; `10` and `11` really are the tenth and eleventh indices
            "λ1((λ1 1)(λ(λλλ1(λλλ2(λλλ(λ7(10(λ5(2(λλ3(λ1 2 3)))(11(λ3(λ3 1(2 1)))))3)"
            + "(4(1(λ1 5)3)(10(λ2(λ2(1 6)))6)))8)(λ1(λ8 7(λ1 6 2))))(λ1(4 3)))(1 1))"
            + "(λλ2((λ1 1)(λ1 1))))")
}
