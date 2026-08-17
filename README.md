[![CI via GitHub Actions](https://github.com/dankogai/swift-binarylambdacalculus/actions/workflows/swift.yml/badge.svg)](https://github.com/dankogai/swift-binarylambdacalculus/actions/workflows/swift.yml)

# swift-binarylambdacalculus

[Binary lambda calculus] in Swift — the whole language in three encoding rules, with a lazy evaluator, a parser, and a `blc` command.

[Binary lambda calculus]: https://tromp.github.io/cl/Binary_lambda_calculus.html

## Synopsis

```swift
import BinaryLambdaCalculus

// a term is a lambda term in De Bruijn notation, and encodes to bits
Term.identity.bitString                 // "0010" — λ1, the shortest closed term
Term.K.bitString                        // "0000110" — λλ2
try Term(bitString: "0000110")          // λλ2, back again

// write terms in Swift, or in lambda notation, whichever reads better
let pair = λ(λ(λ(Term.apply(1, 3, 2))))
try Term(lambda: "\\x\\y\\z.z x y") == pair          // true
try (Term.S * .K * .K).normalForm() == .identity     // true

// a program is a closed term applied to its input as a list of booleans
try Term.identity.run([0, 1, 1, 0])     // [0, 1, 1, 0] — 0010 is cat
try Term.identity.run8("Hello")         // "Hello" — BLC8, a byte at a time

// John Tromp's 232-bit universal machine reads a program off the front of
// its input and runs it on the rest
let program = Term.identity.bits
try Term.universalMachine.run(program + [1, 0, 1, 1])    // [1, 0, 1, 1]

// output is produced lazily, so a program need not ever stop producing it
var primes = try Term(lambda: primesProgram).bitStream()
try primes.take(16).bitString           // "0011010100010100" — bit n is 1 iff n is prime
```

## Description

Binary lambda calculus, invented by [John Tromp] in 2004, is the untyped lambda calculus written in [De Bruijn index] notation and encoded as bits, three rules and no more:

| term | bits |
|------|------|
| `λ`*M* | `00` blc(*M*) |
| *M* *N* | `01` blc(*M*) blc(*N*) |
| *i* | `1`*ⁱ*`0` |

[John Tromp]: https://tromp.github.io/
[De Bruijn index]: https://en.wikipedia.org/wiki/De_Bruijn_index

That is the entire syntax.  The point of it is [descriptional complexity]: the complexity of an object is the length of the shortest program that produces it, which needs a language in which "shortest" is not an accident of syntax.  BLC is that language — the shortest closed term, `λ1`, is four bits, and every extra bit buys real work.

[descriptional complexity]: https://en.wikipedia.org/wiki/Kolmogorov_complexity

Input and output are lambda terms too.  Bit `0` is `True` = λ*x*λ*y*.*x*, bit `1` is `False` = λ*x*λ*y*.*y*, and a string of them is built by repeated pairing, ⟨*x*, *y*⟩ = λ*z*.*z* *x* *y*, ending in `Nil` — which is `False` again, and is told apart from a pair by what it does rather than by what it is.  A program is a closed term applied to that list; its result is read back the same way.  **BLC8** is the same language with bytes for bits: each element of the input is itself a list of eight booleans.

### Terms

```swift
public indirect enum Term: Hashable, Sendable {
    case index(Int)                 // a De Bruijn index, counting from 1
    case abstraction(Term)
    case application(Term, Term)
}
```

An integer literal is an index, `λ(_:)` is an abstraction over an application, and `*` is application — left-associative, like juxtaposition:

```swift
let S: Term = λ(λ(λ(Term.apply(3, 1) * Term.apply(2, 1))))    // λλλ3 1(2 1)
```

De Bruijn indices make alpha-equivalence into plain `==`, so `Term("λx.x") == Term("λy.y")`.

`bits`, `bitString`, and `packed` encode; `init(bits:)`, `init(bitString:)`, and `init(packed:)` decode.  Because the encoding is self-delimiting, decoding stops where the term does — which is exactly what lets a program and the input it runs on share one stream, and why `0010` and any of the sixteen bytes from 32 to 47 are the same program.  `Term.decode(_:)` hands back the leftovers.

### Notation

`Term(lambda:)` reads the notation Tromp's papers and `.lam` files use, and a little more:

- `λ`, `\`, or `^` starts an abstraction, whose body runs as far right as it can.
- Juxtaposition is application, associating to the left.
- A numeral is an index, read greedily: `12` is the twelfth, not `1 2`.
- A lambda may name its parameters instead — `λx y.x`, `\x\y.x` — and the two styles mix, a name being only an index in disguise.
- `let f = …; g = … in …` names terms.  A definition that mentions itself is closed with a fixed-point combinator; one that does not is left alone, so it costs no extra bits.
- `--` comments out the rest of the line.

```swift
try Term(lambda: """
    let cons = \\h\\t\\z.z h t;
        step = \\xs. xs (\\h\\t\\_. cons h (cons h (step t))) (\\a\\b.b);
    in step
    """)    // a BLC program that writes every bit of its input out twice
```

`description` prints terms back in the same notation, parenthesizing only where it must and putting a space between adjacent numerals so that the result reads back as the same term.

### Running

Reduction is normal order — leftmost outermost, so it finds a normal form whenever one exists — with call by need, so an argument is reduced at most once, and not at all if it goes unused.  That last part is what makes the I/O convention work: output can be infinite as long as you only ask for some of it, and an input ending in `Ω` can be handed to a program that knows better than to look.

```swift
try term.normalForm(limit: 1_000_000)   // reduced all the way, under lambdas included

try program.run(bits)                   // BLC: bits in, bits out
try program.run8("input")               // BLC8: bytes in, bytes out
program.bitStream(bits, limit: …)       // the same, lazily, for output that never ends
program.byteStream(bytes, terminator: .omega, arguments: […])
```

Streams are `Sequence`s; `take(_:)` and `collect()` are the throwing versions, and `limit` is a budget of reduction steps for the whole run, so that a program that never stops is an error rather than a hang.  The machine itself is iterative — one loop and an explicit stack, both for reduction and for reading terms back — so what bounds a reduction is that budget and memory, not the call stack.

### The `blc` command

```
blc <action> <program> [argument]...

run     run the program on standard input, a bit at a time     (BLC)
run8    run the program on standard input, a byte at a time    (BLC8)
print   print the program in lambda notation
nf      print the normal form of the program
blc     print the binary encoding of the program, as 0s and 1s
pack    write the binary encoding of the program, 8 bits to a byte
size    print the size of the program, in bits
```

`<program>` is a file, or `-` for standard input: `.blc` and `.blc8` are read as packed bits, a file of nothing but `0`s and `1`s as bits written out, anything else as lambda notation.  `--limit <n>` bounds the reduction, and `--omega` ends the input with `Ω` instead of `Nil`.

```sh
$ printf 'Hello, BLC!' | blc run  Examples/id.lam        # 0010 is cat
Hello, BLC!
$ printf 'Hello, BLC!' | blc run8 Examples/reverse.lam
!CLB ,olleH

$ blc pack Examples/id.lam > cat.blc8                    # compile cat to one byte
$ printf 'Hello, BLC!' | cat cat.blc8 - | blc run8 Examples/uni8.lam
Hello, BLC!                                              # ...and run it under U8

$ blc size Examples/uni.lam
232
$ blc run Examples/compress.lam < /dev/null | wc -c      # 55 bits, 65536 ones
8192
$ blc print Examples/reverse.lam                         # names were indices
(λ(λ(λλ2 1 4)((λ(λ2(1 1))(λ2(1 1)))(λλλ2(λλλ6 2(7 3 4))1)))(λλλ1 3 2))(λλ1)
```

A program that never stops producing output is a `cat`-like filter that never exits, as it should be; `--limit` is there when that is not what you want.

The [Examples](Examples) directory has the programs from Tromp's page — the universal machines, the 167-bit primes program, a 132-bit quine, 55 bits that output 65536 ones — and a couple written in the `let` notation.

### What is tested

Every published number is checked against the implementation: that `U` encodes to the same 232 bits Tromp gives; that his 167-bit primes program outputs the characteristic sequence of the primes; that `U(blc(Q) blc(Q) : Nil) = blc(Q) blc(Q)`, a 132-bit quine; that 55 bits produce exactly 65536 ones; and that his Brainfuck interpreter, itself a BLC8 program, still prints `Hello World!`.

## References

- [Binary lambda calculus](https://tromp.github.io/cl/Binary_lambda_calculus.html), John Tromp
- [Binary Lambda Calculus and Combinatory Logic](https://tromp.github.io/cl/LC.pdf), in *Randomness and Complexity, from Leibniz to Chaitin*, 2008
- [tromp/AIT](https://github.com/tromp/AIT), the reference implementation
- [Binary lambda calculus](https://esolangs.org/wiki/Binary_lambda_calculus) on Esolang
