//
//  MachineTests.swift
//  BinaryLambdaCalculus
//
import Testing

@testable import BinaryLambdaCalculus

@Test func reducesCombinators() async throws {
    #expect(try (Term.identity * .K).normalForm() == .K)
    #expect(try (Term.S * .K * .K).normalForm() == .identity)
    #expect(try (Term.S * .K * .S * .pair).normalForm() == .pair)
    #expect(try (Term.K * .S * .omega).normalForm() == .S)  // the argument is never looked at
    // SKK x = x, whatever x is
    for x in [Term.identity, .K, .S, .pair] {
        #expect(try (Term.S * .K * .K * x).normalForm() == x)
    }
}

@Test func reducesUnderLambdas() async throws {
    // normal order finds the normal form wherever it is, inside λ included
    #expect(try λ(Term.identity * 1).normalForm() == .identity)
    #expect(try λ(λ(Term.identity * 2)).normalForm() == .K)
    // a term already in normal form comes back unchanged
    for term in [Term.identity, .K, .S, .pair, .true, .false, .empty] {
        #expect(try term.normalForm() == term, "\(term)")
    }
    // Y has none: reducing under its λ unfolds f(f(f(…))) forever
    #expect(throws: BLCError.stepLimitExceeded(steps: 10_000)) {
        try Term.fix.normalForm(limit: 10_000)
    }
}

@Test func reducesChurchNumerals() async throws {
    // n = λfλx.fⁿx
    func church(_ n: Int) -> Term {
        var body = Term.index(1)
        for _ in 0..<n { body = .application(.index(2), body) }
        return λ(λ(body))
    }
    let successor = try Term(lambda: "λλλ2(3 2 1)")
    let add = try Term(lambda: "λλλλ4 2(3 2 1)")
    let multiply = try Term(lambda: "λλλ3(2 1)")
    let power = try Term(lambda: "λλ1 2")

    #expect(try (successor * church(0)).normalForm() == church(1))
    #expect(try (add * church(2) * church(3)).normalForm() == church(5))
    #expect(try (multiply * church(3) * church(4)).normalForm() == church(12))
    #expect(try (power * church(2) * church(8)).normalForm() == church(256))
}

@Test func laziness() async throws {
    // an argument that is never used is never reduced, so Ω is harmless here
    #expect(try (Term.K * .identity * .omega).normalForm(limit: 1000) == .identity)
    // but not here
    #expect(throws: BLCError.stepLimitExceeded(steps: 1000)) {
        try Term.omega.normalForm(limit: 1000)
    }
    #expect(throws: BLCError.stepLimitExceeded(steps: 1000)) {
        try (Term.identity * .omega).normalForm(limit: 1000)
    }
}

@Test func sharesTheWorkOfAnArgument() async throws {
    // call by need: an argument used twice is still only reduced once, so
    // (λx.x x) M costs about what M does, not twice what M does
    let slow = try Term(lambda: "λλ2(2(2(2(2(2(2(2 1)))))))") * Term.identity * Term.identity
    let once = Machine(limit: .max)
    _ = try once.normalForm(of: slow)
    let twice = Machine(limit: .max)
    _ = try twice.normalForm(of: λ(1, 1) * slow)
    #expect(twice.steps < 2 * once.steps)
}

@Test func stepLimitCatchesRecursionThatNeverStops() async throws {
    let forever = try Term(lambda: "let f = \\x.f x in \\y.f y")
    #expect(throws: BLCError.stepLimitExceeded(steps: 10_000)) {
        try forever.normalForm(limit: 10_000)
    }
}

@Test func rejectsOpenTerms() async throws {
    #expect(throws: BLCError.unbound("index 1")) { try Term.index(1).normalForm() }
    #expect(throws: BLCError.unbound("index 2")) { try λ(Term.index(2)).normalForm() }
}

@Test func theUniversalMachineHasNoNormalForm() async throws {
    // U begins (λ1 1)(λ… (3 3) …), which unfolds itself forever; that it has
    // no normal form does not stop it from having a perfectly good output
    #expect(throws: BLCError.stepLimitExceeded(steps: 100_000)) {
        try Term.universalMachine.normalForm(limit: 100_000)
    }
    #expect(!Term.universalMachine.isNormalForm)
}
