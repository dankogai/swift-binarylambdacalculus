//
//  Term.swift
//  BinaryLambdaCalculus
//
//  The lambda term, in De Bruijn index notation.
//

/// An untyped lambda term in [De Bruijn index] notation — the sole data type of
/// binary lambda calculus.
///
/// [De Bruijn index]: https://en.wikipedia.org/wiki/De_Bruijn_index
///
/// De Bruijn indices replace variable names with the number of binders between
/// the variable and the lambda that binds it, so alpha-equivalent terms are
/// literally equal:
///
/// ```swift
/// Term("λx.x") == Term("λy.y")    // true; both are λ1
/// ```
///
/// Indices are 1-based: `1` refers to the innermost enclosing lambda, `2` to the
/// one outside it, and so on.
public indirect enum Term: Hashable, Sendable {
    /// A variable, as a 1-based De Bruijn index.  Encodes to `1`*ⁱ*`0`.
    case index(Int)
    /// An abstraction — `λ`*body*.  Encodes to `00` *body*.
    case abstraction(Term)
    /// An application — *function* *argument*.  Encodes to `01` *function* *argument*.
    case application(Term, Term)
}

extension Term: ExpressibleByIntegerLiteral {
    /// An integer literal is a De Bruijn index, so `2` means ``Term/index(_:)`` `2`.
    public init(integerLiteral value: Int) {
        self = .index(value)
    }
}

extension Term {
    /// `λ` — an abstraction whose body is the left-associated application of
    /// `body`, so `λ(1, 3, 2)` is `λ.((1 3) 2)`.
    ///
    /// The Greek letter is a perfectly good Swift identifier, which makes terms
    /// look very much like the notation they implement:
    ///
    /// ```swift
    /// let pair = λ(λ(λ(1, 3, 2)))    // λλλ.1 3 2
    /// ```
    public static func λ(_ body: Term, _ rest: Term...) -> Term {
        .abstraction(Term.apply(body, rest))
    }

    /// The left-associated application of its arguments, so
    /// `Term.apply(a, b, c)` is `(a b) c`.  Returns `a` alone when given one.
    public static func apply(_ first: Term, _ rest: Term...) -> Term {
        apply(first, rest)
    }

    static func apply(_ first: Term, _ rest: some Sequence<Term>) -> Term {
        rest.reduce(first) { .application($0, $1) }
    }

    /// Application, left-associative like juxtaposition in lambda notation and
    /// like `*` itself: `a * b * c` is `(a b) c`.
    public static func * (lhs: Term, rhs: Term) -> Term {
        .application(lhs, rhs)
    }
}

/// `λ` — an abstraction whose body is the left-associated application of `body`;
/// see ``Term/λ(_:_:)``.
public func λ(_ body: Term, _ rest: Term...) -> Term {
    .abstraction(Term.apply(body, rest))
}

extension Term {
    /// The number of bits this term takes in the binary lambda calculus
    /// encoding — computed without building the encoding.
    ///
    /// ```swift
    /// Term.identity.size            // 4, the smallest closed term there is
    /// Term.universalMachine.size    // 232
    /// ```
    public var size: Int {
        var total = 0
        var stack: [Term] = [self]
        while let term = stack.popLast() {
            switch term {
            case .index(let i):
                total += i + 1
            case .abstraction(let body):
                total += 2
                stack.append(body)
            case .application(let function, let argument):
                total += 2
                stack.append(function)
                stack.append(argument)
            }
        }
        return total
    }

    /// The greatest De Bruijn index that reaches out past the term's own
    /// binders, or `0` when the term is closed.
    public var freeDepth: Int {
        var free = 0
        var stack: [(Term, Int)] = [(self, 0)]
        while let (term, depth) = stack.popLast() {
            switch term {
            case .index(let i):
                free = max(free, i - depth)
            case .abstraction(let body):
                stack.append((body, depth + 1))
            case .application(let function, let argument):
                stack.append((function, depth))
                stack.append((argument, depth))
            }
        }
        return free
    }

    /// Whether every variable is bound by an enclosing lambda.  A binary lambda
    /// calculus program must be closed.
    public var isClosed: Bool { freeDepth == 0 }

    /// Whether the term contains no redex — no application of an abstraction —
    /// and so cannot be reduced any further.
    public var isNormalForm: Bool {
        switch self {
        case .index:
            return true
        case .abstraction(let body):
            return body.isNormalForm
        case .application(.abstraction, _):
            return false
        case .application(let function, let argument):
            return function.isNormalForm && argument.isNormalForm
        }
    }
}

extension Term: CustomStringConvertible {
    /// The term in De Bruijn notation, as on John Tromp's page: `λ` for
    /// abstraction, juxtaposition for application, decimal numerals for indices.
    ///
    /// ```swift
    /// "\(Term.S)"    // "λλλ3 1(2 1)"
    /// ```
    ///
    /// Parentheses are printed only where they are needed, and a space is
    /// inserted between two adjacent numerals so that ``init(_:)`` reads the
    /// result back as the same term.  (Tromp's pages elide those spaces and
    /// note "all indices are single digit"; this printer does not have that
    /// luxury.)
    public var description: String {
        var out = ""
        write(self, .body, into: &out)
        return out
    }

    /// Where a subterm sits, which is what decides whether it needs parentheses.
    private enum Position {
        /// The body of an abstraction or the whole term: everything is bare.
        case body
        /// The function of an application: an abstraction needs parentheses,
        /// since its body would otherwise swallow the argument.
        case function
        /// The argument of an application: an application needs them too.
        case argument
    }

    private func write(_ term: Term, _ position: Position, into out: inout String) {
        switch term {
        case .index(let i):
            if out.last?.isNumber == true { out += " " }
            out += String(i)
        case .abstraction(let body):
            let parenthesized = position != .body
            if parenthesized { out += "(" }
            out += "λ"
            write(body, .body, into: &out)
            if parenthesized { out += ")" }
        case .application(let function, let argument):
            let parenthesized = position == .argument
            if parenthesized { out += "(" }
            write(function, .function, into: &out)
            write(argument, .argument, into: &out)
            if parenthesized { out += ")" }
        }
    }
}

extension Term: LosslessStringConvertible {
    /// Parses lambda notation — De Bruijn indices, named variables, or both.
    /// Returns `nil` if `description` does not parse; use ``init(lambda:)`` to
    /// find out why.
    ///
    /// ```swift
    /// Term("λλ2")             // K, by index
    /// Term("\\x\\y.x")        // K, by name
    /// ```
    public init?(_ description: String) {
        try? self.init(lambda: description)
    }
}
