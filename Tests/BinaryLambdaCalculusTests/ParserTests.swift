//
//  ParserTests.swift
//  BinaryLambdaCalculus
//
import Testing

@testable import BinaryLambdaCalculus

@Test func parsesDeBruijnNotation() async throws {
    #expect(try Term(lambda: "λ1") == .identity)
    #expect(try Term(lambda: "λλ2") == .K)
    #expect(try Term(lambda: "λλλ3 1(2 1)") == .S)
    #expect(try Term(lambda: "λλλ1 3 2") == .pair)
    #expect(try Term(lambda: "(λ1 1)(λ1 1)") == .omega)
    // \ and ^ are λ, for keyboards that lack it
    #expect(try Term(lambda: "\\1") == .identity)
    #expect(try Term(lambda: "^1") == .identity)
    // the dot after a run of lambdas is optional
    #expect(try Term(lambda: "λλλ.1 3 2") == .pair)
    // whitespace and comments are not there
    #expect(try Term(lambda: "  λ 1  -- the identity\n") == .identity)
}

@Test func parsesApplicationToTheLeftAndAbstractionToTheRight() async throws {
    // application associates left
    #expect(try Term(lambda: "λλλ1 2 3") == λ(λ(λ(Term.apply(1, 2, 3)))))
    #expect(try Term(lambda: "λλλ1(2 3)") == λ(λ(λ(Term.index(1) * (2 * 3)))))
    // an abstraction's body runs as far right as it can
    #expect(try Term(lambda: "λ1 1") == λ(1, 1))
    #expect(try Term(lambda: "λ(λ1)1") == λ(.abstraction(.index(1)) * .index(1)))
}

@Test func parsesIndicesGreedily() async throws {
    // 12 is the twelfth index, not the first applied to the second
    #expect(try Term(lambda: String(repeating: "λ", count: 12) + "12").freeDepth == 0)
    var twelve = Term.index(12)
    for _ in 0..<12 { twelve = .abstraction(twelve) }
    #expect(try Term(lambda: "λλλλλλλλλλλλ12") == twelve)
    #expect(try Term(lambda: "λλ1 2") == λ(λ(1 * 2)))
}

@Test func parsesNames() async throws {
    #expect(try Term(lambda: "\\x.x") == .identity)
    #expect(try Term(lambda: "λx.x") == .identity)
    #expect(try Term(lambda: "\\x\\y.x") == .K)
    #expect(try Term(lambda: "λx y.x") == .K)
    #expect(try Term(lambda: "\\x\\y\\z.x z(y z)") == .S)
    #expect(try Term(lambda: "\\x\\y\\z.z x y") == .pair)
    // names and indices mix, since a name is only an index in disguise
    #expect(try Term(lambda: "λx.λ2") == .K)
    // the innermost of two same-named binders wins
    #expect(try Term(lambda: "\\x\\x.x") == .false)
    // alpha-equivalent terms are equal, De Bruijn indices being what they are
    #expect(try Term(lambda: "\\x.x") == Term(lambda: "\\y.y"))
}

@Test func parsesLet() async throws {
    // a definition is an applied abstraction, and so a redex: (λi.i)(λx.x)
    #expect(try Term(lambda: "let i = \\x.x in i") == .abstraction(.index(1)) * .identity)
    #expect(try Term(lambda: "let i = \\x.x in i").normalForm() == .identity)
    #expect(try Term(lambda: "let i = \\x.x in i i").normalForm() == .identity)
    // a later definition sees the ones before it
    #expect(try Term(lambda: "let a = \\x\\y.x; b = a in b").normalForm() == .K)
    // the `;` before `in` is optional, the ones between definitions are not:
    // without one, `let a = λ1 b = …` has the abstraction swallow the `b`
    #expect(try Term(lambda: "let a = λ1; b = λλ2 in a") == Term(lambda: "let a = λ1; b = λλ2; in a"))
    #expect(throws: BLCError.self) { try Term(lambda: "let a = λ1 b = λλ2 in a") }
}

@Test func letTiesTheRecursiveKnot() async throws {
    // a definition that mentions itself is closed with a fixed-point combinator
    let recursive = try Term(lambda: "let f = \\x.f x in f")
    #expect(recursive == .abstraction(.index(1)) * (.fix * λ(λ(2, 1))))
    // one that does not is left as it stands — no fixed point, no extra bits
    let plain = try Term(lambda: "let f = \\x.x in f")
    #expect(plain == .abstraction(.index(1)) * .identity)
    #expect(!plain.bitString.contains(Term.fix.bitString))

    // and it really does recurse: a list of as many 1 bits as you care to take
    var ones = try Term(lambda: "let ones = \\z.z (\\a\\b.b) ones in \\input.ones").bitStream()
    #expect(try ones.take(20) == [Bit](repeating: .one, count: 20))
}

@Test func parserRejectsWhatItShould() async throws {
    #expect(throws: BLCError.self) { try Term(lambda: "") }
    #expect(throws: BLCError.self) { try Term(lambda: "λ") }
    #expect(throws: BLCError.self) { try Term(lambda: "(λ1") }
    #expect(throws: BLCError.self) { try Term(lambda: "λ1)") }
    #expect(throws: BLCError.self) { try Term(lambda: "λ0") }  // indices start at 1
    #expect(throws: BLCError.self) { try Term(lambda: "λ2") }  // reaches past its lambda
    #expect(throws: BLCError.self) { try Term(lambda: "\\x.y") }  // no such name
    #expect(throws: BLCError.self) { try Term(lambda: "let x = λ1 λ1") }  // no `in`
    #expect(throws: BLCError.self) { try Term(lambda: "λ1 @") }
    // the failable initializer says nil instead
    #expect(Term("λ1 @") == nil)
    #expect(Term("λ1") == .identity)
}

@Test func parsesTheProgramsOnTrompsPage() async throws {
    // each of these is checked against the size he gives for it
    #expect(try Term(lambda: Examples.primes).size == 167)
    #expect(try Term(lambda: Examples.quine).size == 66)
    #expect(try Term(lambda: Examples.compress).size == 55)
    #expect(Term.universalMachine.size == 232)
    #expect(Term.universalMachine8.size == 355)
}
