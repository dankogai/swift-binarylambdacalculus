//
//  BLCError.swift
//  BinaryLambdaCalculus
//

/// Everything that can go wrong while reading, encoding, or running a term.
public enum BLCError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The bits ran out in the middle of a term.
    case truncated
    /// Lambda notation that does not parse, with a description of the problem.
    case syntax(String)
    /// A variable that no enclosing lambda binds — either a name that is not in
    /// scope, or a De Bruijn index that reaches out past the whole term.
    /// Programs must be closed terms.
    case unbound(String)
    /// Reduction did not finish within the step limit it was given.
    case stepLimitExceeded(steps: Int)
    /// A term appeared where the I/O convention calls for a boolean, which is
    /// to say for a bit.
    case notABit

    public var description: String {
        switch self {
        case .truncated:
            return "the term ends in the middle of itself"
        case .syntax(let what):
            return "syntax error: \(what)"
        case .unbound(let what):
            return "unbound variable: \(what)"
        case .stepLimitExceeded(let steps):
            return "step limit exceeded after \(steps) steps"
        case .notABit:
            return "output is not a boolean, so not a bit"
        }
    }
}
