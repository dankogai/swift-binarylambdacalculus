//
//  ReadmeTests.swift
//  BinaryLambdaCalculus
//
//  Everything the README claims, claimed again where it can fail.
//
import Testing

@testable import BinaryLambdaCalculus

@Test func readmeSynopsis() async throws {
    let primesProgram = Examples.primes

    // a term is a lambda term in De Bruijn notation, and encodes to bits
    #expect(Term.identity.bitString == "0010")
    #expect(Term.K.bitString == "0000110")
    #expect(try Term(bitString: "0000110") == .K)

    // write terms in Swift, or in lambda notation, whichever reads better
    let pair = λ(λ(λ(Term.apply(1, 3, 2))))
    #expect(try Term(lambda: "\\x\\y\\z.z x y") == pair)
    #expect(try (Term.S * .K * .K).normalForm() == .identity)

    // a program is a closed term applied to its input as a list of booleans
    #expect(try Term.identity.run([0, 1, 1, 0]) == [0, 1, 1, 0])
    #expect(try Term.identity.run8("Hello") == "Hello")

    // the universal machine reads a program off the front of its input
    let program = Term.identity.bits
    #expect(try Term.universalMachine.run(program + [1, 0, 1, 1]) == [1, 0, 1, 1])

    // output is produced lazily
    var primes = try Term(lambda: primesProgram).bitStream()
    #expect(try primes.take(16).bitString == "0011010100010100")
}

@Test func readmeDescription() async throws {
    let S: Term = λ(λ(λ(Term.apply(3, 1) * Term.apply(2, 1))))
    #expect(S == .S)
    #expect("\(S)" == "λλλ3 1(2 1)")
    #expect(Term("λx.x") == Term("λy.y"))

    // the program in the notation section really does double every bit
    let double = try Term(
        lambda: """
            let cons = \\h\\t\\z.z h t;
                step = \\xs. xs (\\h\\t\\_. cons h (cons h (step t))) (\\a\\b.b);
            in step
            """)
    #expect(try double.run([0, 1, 1]) == [0, 0, 1, 1, 1, 1])

    // and the encodings quoted for the three rules are the encodings
    #expect(Term.abstraction(.identity).bitString == "00" + Term.identity.bitString)
    #expect((Term.identity * .K).bitString == "01" + Term.identity.bitString + Term.K.bitString)
    #expect(Term.index(3).bitString == "1110")
}

@Test func readmeExampleFiles() async throws {
    // the .lam files in Examples/, as the README says they are
    #expect(try Term(lambda: Examples.primes).size == 167)
    #expect(Term.universalMachine.size == 232)
    #expect(try Term(lambda: Examples.compress).run().count == 65536)

    // Examples/reverse.lam, and what `blc print` shows for it
    let reverse = try Term(
        lambda: """
            let
              nil  = \\a\\b.b;
              cons = \\h\\t\\z.z h t;
              step = \\xs\\acc. xs (\\h\\t\\_. step t (cons h acc)) acc;
            in
              \\input. step input nil
            """)
    #expect("\(reverse)" == "(λ(λ(λλ2 1 4)((λ(λ2(1 1))(λ2(1 1)))(λλλ2(λλλ6 2(7 3 4))1)))(λλλ1 3 2))(λλ1)")
    #expect(try reverse.run8("Hello, BLC!") == "!CLB ,olleH")
    #expect(try Term(lambda: "\(reverse)") == reverse)
}
