//
//  Parser.swift
//  BinaryLambdaCalculus
//
//  Lambda notation in, `Term` out.
//

extension Term {
    /// Parses lambda notation.
    ///
    /// The notation is the one John Tromp's papers and `.lam` files are written
    /// in:
    ///
    /// - `λ`, `\`, or `^` starts an abstraction.  Its body runs as far to the
    ///   right as it can, so `λ1 2` is `λ(1 2)`, not `(λ1) 2`.
    /// - Juxtaposition is application, and associates to the left: `a b c` is
    ///   `(a b) c`.
    /// - A numeral is a De Bruijn index, counting from 1, and greedily: `12` is
    ///   the twelfth index, not `1 2`.  Write the space if you mean two.
    /// - A lambda may instead name its parameters — `λx y.x`, `\x\y.x` — and
    ///   the two styles mix freely, since a name is just an index in disguise.
    /// - `let f = …; g = …  in …` binds terms to names.  A definition may refer
    ///   to itself, in which case it is closed with a fixed-point combinator,
    ///   and to the definitions before it.  The `;` between definitions is
    ///   required — without it an abstraction would swallow the next name —
    ///   and the one before `in` is not.
    /// - `--` starts a comment that runs to the end of the line.
    ///
    /// ```swift
    /// try Term(lambda: "λλ2")           // K by index
    /// try Term(lambda: "\\x\\y.x")      // K by name
    /// try Term(lambda: "let K = \\x\\y.x in K K")
    /// ```
    ///
    /// - Throws: ``BLCError/syntax(_:)`` or ``BLCError/unbound(_:)``.
    public init(lambda source: String) throws {
        var parser = LambdaParser(source)
        self = try parser.parse()
    }
}

/// A recursive-descent parser for lambda notation.
struct LambdaParser {
    private enum Token: Equatable {
        case lambda
        case dot
        case open
        case close
        case equals
        case semicolon
        case index(Int)
        case name(String)
        case `let`
        case `in`
        case end
    }

    private let source: String
    private var tokens: [Token] = []
    private var position = 0
    /// The binders in scope, outermost first; `nil` for an unnamed lambda,
    /// which nothing can refer to by name but which still counts for indices.
    private var scope: [String?] = []

    init(_ source: String) {
        self.source = source
    }

    // MARK: - the whole of it

    mutating func parse() throws -> Term {
        try tokenize()
        let term = try parseTerm()
        guard peek() == .end else {
            throw BLCError.syntax("unexpected \(describe(peek())) after a complete term")
        }
        return term
    }

    // MARK: - tokens

    private mutating func tokenize() throws {
        var rest = Substring(source)
        while let character = rest.first {
            switch character {
            case " ", "\t", "\n", "\r":
                rest.removeFirst()
            case "-" where rest.hasPrefix("--"):
                rest = rest.drop { $0 != "\n" }
            case "λ", "\\", "^":
                rest.removeFirst()
                tokens.append(.lambda)
            case ".":
                rest.removeFirst()
                tokens.append(.dot)
            case "(":
                rest.removeFirst()
                tokens.append(.open)
            case ")":
                rest.removeFirst()
                tokens.append(.close)
            case "=":
                rest.removeFirst()
                tokens.append(.equals)
            case ";":
                rest.removeFirst()
                tokens.append(.semicolon)
            case _ where character.isNumber:
                // greedily, so that `12` is one index and not two
                let digits = rest.prefix { $0.isNumber }
                rest = rest.dropFirst(digits.count)
                guard let index = Int(digits), index > 0 else {
                    throw BLCError.syntax("\(digits) is not a De Bruijn index; they start at 1")
                }
                tokens.append(.index(index))
            case _ where isNameHead(character):
                let name = rest.prefix(while: isNameBody)
                rest = rest.dropFirst(name.count)
                switch name {
                case "let": tokens.append(.let)
                case "in": tokens.append(.in)
                default: tokens.append(.name(String(name)))
                }
            default:
                throw BLCError.syntax("stray ‘\(character)’")
            }
        }
        tokens.append(.end)
    }

    private func isNameHead(_ character: Character) -> Bool {
        character.isLetter || character == "_"
    }

    private func isNameBody(_ character: Character) -> Bool {
        isNameHead(character) || character.isNumber || character == "'"
    }

    private func peek(_ ahead: Int = 0) -> Token {
        position + ahead < tokens.count ? tokens[position + ahead] : .end
    }

    private mutating func take() -> Token {
        defer { position += 1 }
        return peek()
    }

    private mutating func match(_ token: Token) -> Bool {
        guard peek() == token else { return false }
        position += 1
        return true
    }

    private func describe(_ token: Token) -> String {
        switch token {
        case .lambda: return "‘λ’"
        case .dot: return "‘.’"
        case .open: return "‘(’"
        case .close: return "‘)’"
        case .equals: return "‘=’"
        case .semicolon: return "‘;’"
        case .index(let i): return "index \(i)"
        case .name(let n): return "‘\(n)’"
        case .let: return "‘let’"
        case .in: return "‘in’"
        case .end: return "end of input"
        }
    }

    // MARK: - terms

    private mutating func parseTerm() throws -> Term {
        if peek() == .let { return try parseLet() }
        if peek() == .lambda { return try parseAbstraction() }
        return try parseApplication()
    }

    /// `λ`, then any number of named parameters, then an optional `.`, then the
    /// body — which reaches as far to the right as it can.
    private mutating func parseAbstraction() throws -> Term {
        _ = take()  // λ
        var binders: [String?] = []
        while case .name(let name) = peek() {
            position += 1
            binders.append(name)
        }
        if binders.isEmpty { binders.append(nil) }
        _ = match(.dot)
        let depth = scope.count
        scope += binders
        defer { scope.removeLast(scope.count - depth) }
        var body = try parseTerm()
        for _ in binders { body = .abstraction(body) }
        return body
    }

    /// One or more atoms, applied left to right.
    private mutating func parseApplication() throws -> Term {
        guard var term = try parseAtom() else {
            throw BLCError.syntax("expected a term, found \(describe(peek()))")
        }
        while let argument = try parseAtom() {
            term = .application(term, argument)
        }
        return term
    }

    /// An index, a name, or a parenthesized term — `nil` when the next token
    /// starts none of those, which is how ``parseApplication()`` knows to stop.
    private mutating func parseAtom() throws -> Term? {
        switch peek() {
        case .index(let index):
            position += 1
            guard index <= scope.count else {
                throw BLCError.unbound("index \(index), with only \(scope.count) lambda(s) around it")
            }
            return .index(index)
        case .name(let name):
            position += 1
            guard let found = scope.lastIndex(of: name) else {
                throw BLCError.unbound(name)
            }
            return .index(scope.count - found)
        case .open:
            position += 1
            let term = try parseTerm()
            guard match(.close) else {
                throw BLCError.syntax("expected ‘)’, found \(describe(peek()))")
            }
            return term
        case .lambda:
            // an abstraction is an atom only in parentheses; bare, it swallows
            // the rest of the application, which `parseTerm` handles
            return try parseAbstraction()
        case .let:
            return try parseLet()
        default:
            return nil
        }
    }

    /// `let name = term; … in term`, desugared to applied abstractions.
    private mutating func parseLet() throws -> Term {
        _ = take()  // let
        let depth = scope.count
        defer { scope.removeLast(scope.count - depth) }
        var definitions: [Term] = []
        while case .name(let name) = peek() {
            position += 1
            guard match(.equals) else {
                throw BLCError.syntax("expected ‘=’ after ‘\(name)’, found \(describe(peek()))")
            }
            // the name is in scope inside its own definition, so that it may
            // recurse; if it does not, the binder comes back off again
            scope.append(name)
            let body = try parseTerm()
            definitions.append(
                Term.binderIsUsed(body)
                    ? .application(.fix, .abstraction(body))
                    : Term.dropBinder(body)
            )
            _ = match(.semicolon)
        }
        guard !definitions.isEmpty else {
            throw BLCError.syntax("‘let’ with no definitions")
        }
        guard match(.in) else {
            throw BLCError.syntax("expected ‘in’, found \(describe(peek()))")
        }
        var term = try parseTerm()
        // (λn₁.(λn₂. body) t₂) t₁, built from the inside out
        for definition in definitions.reversed() {
            term = .application(.abstraction(term), definition)
            scope.removeLast()
        }
        return term
    }
}

extension Term {
    /// Whether `body`, taken as the body of an abstraction, refers to the
    /// parameter of that abstraction.
    static func binderIsUsed(_ body: Term) -> Bool {
        func walk(_ term: Term, _ depth: Int) -> Bool {
            switch term {
            case .index(let index):
                return index == depth + 1
            case .abstraction(let inner):
                return walk(inner, depth + 1)
            case .application(let function, let argument):
                return walk(function, depth) || walk(argument, depth)
            }
        }
        return walk(body, 0)
    }

    /// Rewrites `body` as though the abstraction around it had never been —
    /// every index reaching past `body` moves in by one.  Only sound when
    /// ``binderIsUsed(_:)`` is `false`.
    static func dropBinder(_ body: Term) -> Term {
        func walk(_ term: Term, _ depth: Int) -> Term {
            switch term {
            case .index(let index):
                return .index(index > depth ? index - 1 : index)
            case .abstraction(let inner):
                return .abstraction(walk(inner, depth + 1))
            case .application(let function, let argument):
                return .application(walk(function, depth), walk(argument, depth))
            }
        }
        return walk(body, 0)
    }
}
