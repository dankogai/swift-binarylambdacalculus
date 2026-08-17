//
//  Examples.swift
//  BinaryLambdaCalculus
//
//  Programs published by John Tromp, used here as test vectors.  Each is
//  checked against the size, and where he gives one the output, that he
//  reports for it.
//
//  The notation on his page leaves out the spaces between adjacent indices —
//  "all indices are single digit", as he puts it — so they are put back here.
//

enum Examples {
    /// The 232-bit universal machine, exactly as published.
    /// <https://tromp.github.io/cl/Binary_lambda_calculus.html>
    static let universalMachineBits = """
        0101000110100000000101011000000000011110000101111110011110
        0001011100111100000011110000101101101110011111000011111000
        0101111010011101001011001110000110110000101111100001111100
        0011100110111101111100111101110110000110010001101000011010
        """

    /// 167 bits — a prime — whose output is the characteristic sequence of the
    /// primes, proving KS(PRIMES) ≤ 167.
    static let primes =
        "λ(λ1(1((λ1 1)(λλλ1(λλ1)((λ4 4 1((λ1 1)(λ2(1 1))))(λλλλ1 3(2(6 4)))))(λλλ4(1 3)))))"
        + "(λλ1(λλ2)2)"

    /// The first 100 bits of what `primes` outputs.
    static let primesOutput =
        "0011010100010100010100010000010100000100010100010000010000010100000100010100000100010000010"
        + "000000100"

    /// Q, which concatenates two copies of its input — so `blc(Q) blc(Q)` is a
    /// 132-bit quine for the universal machine.
    static let quine = "λ1((λ1 1)(λλλλλ1 4(3(5 5)2)))1"

    /// 55 bits that output 2^2^2^2 = 65536 ones, which is shorter than gzip
    /// (344 bits) or bzip2 (352) can say the same thing.
    static let compress = "(λ1 1 1 1(λλ1(λλ1)2))(λλ2(2 1))"

    /// Tromp's unbounded-tape Brainfuck interpreter, a BLC8 program — the
    /// compiled `bf.blc8` of <https://github.com/tromp/AIT>, which is a later
    /// and slightly longer one than the 829 bits described on his page.
    ///
    /// It reads a Brainfuck program, a `]`, and then that program's input.
    static let brainfuck = """
        01000100010100011010000100000001100001000101010111010101000000101011011101110000001100000010\
        00101111111100110010111100000000000010111111111110011000010101111111010111101110000101101111\
        10010101011111110111110111101110110000001110010101010100011010000000000001011000010101011111\
        11011111101111100000010001010101011111111101111010111111101111110000101101101111000000101111\
        11010110000001111110000101101111011100111101011111110001000101001011110011000000000010111111\
        11110010111000011111101000010110111101100110000101111110100001011011111011110010111111001111\
        11111111000100111111111111100001110010100011010000100000000010101100100011010000000010111001\
        10011110111000011111111001011111111101111111010110100110101000011111111111110000111111111111\
        10000111100111010000010011010000101010110000000000000101110110110010001101000000101101110011\
        10110010100011001100110000001011000001101100000011100111010000010
        """
}
