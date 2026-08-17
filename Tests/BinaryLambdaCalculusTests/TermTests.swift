//
//  TermTests.swift
//  BinaryLambdaCalculus
//
import Testing

@testable import BinaryLambdaCalculus

@Test func termConstruction() async throws {
    // an integer literal is a De Bruijn index
    #expect(Term.identity == .abstraction(.index(1)))
    #expect(λ(1) == Term.abstraction(.index(1)))
    #expect((1 as Term) == Term.index(1))

    // λ takes the whole application as its body
    #expect(λ(1, 2) == .abstraction(.application(.index(1), .index(2))))
    #expect(λ(1, 2, 3) == .abstraction(.application(.application(.index(1), .index(2)), .index(3))))

    // * is application, and associates to the left like juxtaposition
    #expect((1 * 2 * 3 as Term) == Term.apply(1, 2, 3))
    #expect(Term.apply(1) == 1)

    // the standard terms are what they are said to be
    #expect(Term.K == Term.true)
    #expect(Term.I == Term.identity)
    #expect(Term.empty == Term.false)
    #expect(Term.true == λ(λ(2)))
    #expect(Term.false == λ(λ(1)))
    #expect(Term.S == λ(λ(λ(Term.apply(3, 1) * Term.apply(2, 1)))))
    #expect(Term.pair == λ(λ(λ(Term.apply(1, 3, 2)))))
    #expect(Term.omega == λ(1, 1) * λ(1, 1))
}

@Test func termSize() async throws {
    // size is the length of the encoding, computed without encoding
    for term in [Term.identity, .K, .S, .pair, .omega, .fix, .universalMachine, .universalMachine8] {
        #expect(term.size == term.bits.count)
    }
    #expect(Term.identity.size == 4)  // 00 10
    #expect(Term.K.size == 7)  // 00 00 110
    #expect(Term.S.size == 23)
    #expect(Term.universalMachine.size == 232)
    #expect(Term.universalMachine8.size == 355)
    // 45 bytes of BLC8, as Tromp says
    #expect(Term.universalMachine8.packed.count == 45)
}

@Test func termClosedness() async throws {
    #expect(Term.identity.isClosed)
    #expect(Term.universalMachine.isClosed)
    #expect(!Term.index(1).isClosed)
    #expect(Term.index(3).freeDepth == 3)
    #expect(λ(λ(3)).freeDepth == 1)
    #expect(λ(λ(2)).freeDepth == 0)
    // an index reaching out of one lambda is bound by the next
    #expect(!λ(2).isClosed)
    #expect(λ(λ(2)).isClosed)
}

@Test func termNormalFormPredicate() async throws {
    #expect(Term.identity.isNormalForm)
    #expect(Term.S.isNormalForm)
    #expect(!Term.omega.isNormalForm)
    #expect(!(Term.identity * .identity).isNormalForm)
    #expect((Term.index(1) * .index(2)).isNormalForm)
}

@Test func termDescription() async throws {
    #expect("\(Term.identity)" == "λ1")
    #expect("\(Term.K)" == "λλ2")
    #expect("\(Term.S)" == "λλλ3 1(2 1)")
    #expect("\(Term.pair)" == "λλλ1 3 2")
    #expect("\(Term.omega)" == "(λ1 1)(λ1 1)")
    // an abstraction as a function needs parentheses, as its body would
    // otherwise swallow the argument
    #expect("\(Term.identity * .identity)" == "(λ1)(λ1)")
    #expect("\(Term.index(1) * (Term.index(2) * Term.index(3)))" == "1(2 3)")
    // and adjacent indices need a space, or they would read as one numeral
    #expect("\(Term.index(1) * Term.index(2))" == "1 2")
    #expect("\(Term.index(12))" == "12")
}

@Test func termRoundTripsThroughItsDescription() async throws {
    let terms: [Term] = [
        .identity, .K, .S, .pair, .omega, .fix, .universalMachine, .universalMachine8,
        .list(bits: [0, 1, 1, 0]), .byte(0x42), .cons(.identity, .empty),
    ]
    for term in terms {
        #expect(Term("\(term)") == term, "\(term)")
    }
}

@Test func termConsShiftsOpenTerms() async throws {
    // a closed head goes under the new λ untouched
    #expect(Term.cons(.identity, .empty) == λ(Term.apply(1, .identity, .empty)))
    // an open one has to move out of the way of it
    #expect(Term.cons(.index(1), .index(2)) == λ(Term.apply(1, .index(2), .index(3))))
    #expect(Term.index(1).shifted(by: 2) == .index(3))
    #expect(λ(1).shifted(by: 2) == λ(1))  // bound, so unaffected
    #expect(λ(2).shifted(by: 2) == λ(4))
}
