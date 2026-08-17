//
//  ProgramTests.swift
//  BinaryLambdaCalculus
//
//  Whole programs, run against the outputs John Tromp reports for them.
//
import Testing

@testable import BinaryLambdaCalculus

@Test func theIdentityIsCat() async throws {
    let input: [Bit] = [0, 1, 1, 0, 1, 0, 0, 0, 1]
    #expect(try Term.identity.run(input) == input)
    #expect(try Term.identity.run([]) == [])
    // and in BLC8, where the elements are bytes rather than bits
    #expect(try Term.identity.run8("Hello, world!") == "Hello, world!")
    #expect(try Term.identity.run8([0x00, 0xff, 0x80]) == [0x00, 0xff, 0x80])
    // every byte from 32 to 47 is that same four-bit program
    for byte in UInt8(32)...47 {
        #expect(try Term(packed: [byte]).run8("cat") == "cat")
    }
}

@Test func theUniversalMachineRunsWhatItIsGiven() async throws {
    // U reads a program off the front of its input and runs it on the rest
    let input: [Bit] = [1, 0, 1, 1, 0]
    #expect(try Term.universalMachine.run(Term.identity.bits + input) == input)

    // a program that ignores its input and outputs three bits of its own
    let constant = λ(Term.list(bits: [0, 1, 0] as [Bit]))
    #expect(try Term.universalMachine.run(constant.bits + input) == [0, 1, 0])

    // U interpreting U interpreting the identity, which is where the constant
    // in "any description method costs at most a constant more" comes from
    let doubled = Term.universalMachine.bits + Term.identity.bits + input
    #expect(try Term.universalMachine.run(doubled, limit: 10_000_000) == input)
}

@Test func theByteOrientedUniversalMachineDoesTheSame() async throws {
    #expect(try Term.universalMachine8.run8(Term.identity.packed + Array("Hello".utf8))
        == Array("Hello".utf8))
    // its own encoding is 45 bytes, as Tromp says
    #expect(Term.universalMachine8.packed.count == 45)
}

@Test func primes() async throws {
    // 167 bits whose output is the characteristic sequence of the primes:
    // bit n, counting from 0, is 1 exactly when n is prime
    let primes = try Term(lambda: Examples.primes)
    #expect(primes.size == 167)
    var output = primes.bitStream()
    let hundred = try output.take(100)
    #expect(hundred.bitString == Examples.primesOutput)
    // which is to say
    let isPrime = { (n: Int) in n > 1 && !(2..<n).contains { n % $0 == 0 } }
    for (n, bit) in hundred.enumerated() {
        #expect((bit == .one) == isPrime(n), "bit \(n)")
    }
}

@Test func aQuineForTheUniversalMachine() async throws {
    // Q concatenates two copies of its input, so U, given blc(Q) twice, writes
    // out just what it was given
    let Q = try Term(lambda: Examples.quine)
    #expect(Q.size == 66)
    let quine = Q.bits + Q.bits
    #expect(quine.count == 132)
    #expect(try Term.universalMachine.run(quine, limit: 10_000_000) == quine)
}

@Test func fiftyFiveBitsOfCompression() async throws {
    // 2^2^2^2 = 65536 ones, from a program that gzip cannot come close to
    let compress = try Term(lambda: Examples.compress)
    #expect(compress.size == 55)
    let output = try compress.run()
    #expect(output.count == 65536)
    #expect(output.allSatisfy { $0 == .one })
}

@Test func brainfuck() async throws {
    // Tromp's Brainfuck interpreter, a BLC8 program, running the traditional
    // first program.  Its input is a Brainfuck program, a `]`, and then that
    // program's own input.
    let brainfuck = try Term(bitString: Examples.brainfuck)
    let hello = """
        ++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]\
        >>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++.
        """
    #expect(try brainfuck.run8(hello + "]") == "Hello World!\n")

    // and one that reads: `,[.,]` is cat
    #expect(try brainfuck.run8(",[.,]" + "]" + "echo") == "echo")
}

@Test func outputIsProducedLazily() async throws {
    // a program whose output never ends is only reduced as far as it is read
    let ones = try Term(lambda: "let ones = \\z.z (\\a\\b.b) ones in \\input.ones")
    var stream = ones.bitStream()
    #expect(try stream.take(5) == [1, 1, 1, 1, 1])
    #expect(try stream.take(5) == [1, 1, 1, 1, 1])  // picks up where it left off
    // taking all of it, on the other hand, would never return — the step limit
    // is what stands between a program and forever
    var bounded = ones.bitStream(limit: 100_000)
    #expect(throws: BLCError.stepLimitExceeded(steps: 100_000)) { try bounded.collect() }
}

@Test func inputMayBeSelfDelimiting() async throws {
    // Ω in place of the end of the input is a program's cue to work out for
    // itself where its input stops, since looking at Ω never returns.  U
    // parses a program off the front without ever looking that far — which is
    // what makes prefix complexity, and so the halting probability, work
    let constant = λ(Term.list(bits: [0, 1, 0] as [Bit]))
    #expect(try Term.universalMachine.run(
        constant.bits, terminator: .omega, limit: 1_000_000) == [0, 1, 0])

    // cat, on the other hand, copies its input — Ω and all
    var greedy = Term.identity.bitStream([0, 1, 0], terminator: .omega, limit: 1_000_000)
    #expect(try greedy.take(3) == [0, 1, 0])
    #expect(throws: BLCError.stepLimitExceeded(steps: 1_000_000)) { try greedy.take(1) }
    // and given Nil it knows where to stop
    #expect(try Term.identity.run([0, 1, 0], terminator: .empty) == [0, 1, 0])
}

@Test func argumentsAreAppliedAfterTheInput() async throws {
    // `blc run prog.lam foo` applies the program to its input and then to foo,
    // which is how a description is made conditional on something
    let second = λ(λ(1))  // ignore the input, output the argument
    #expect(try second.run([0, 0], arguments: [.list(bits: [1, 1] as [Bit])]) == [1, 1])
}

@Test func outputThatIsNotAListEndsIt() async throws {
    // Tromp's interpreters signal failure by returning λx.x, which is neither
    // a pair nor nil; anything that is not a pair is the end of the output.
    // Here Brainfuck's `,` asks for input that is not there.
    let brainfuck = try Term(bitString: Examples.brainfuck)
    #expect(try brainfuck.run8(",]") == "")
    // and something that is a list of the wrong thing is an error
    var stream = λ(Term.cons(.identity, .empty)).bitStream()
    #expect(throws: BLCError.notABit) { try stream.collect() }
}
