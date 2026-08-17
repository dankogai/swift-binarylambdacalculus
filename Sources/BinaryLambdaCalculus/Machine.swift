//
//  Machine.swift
//  BinaryLambdaCalculus
//
//  A call-by-need abstract machine: normal-order reduction with sharing.
//

/// A suspended term — evaluated at most once, then overwritten with its value.
final class Thunk {
    enum State {
        /// Not evaluated yet.
        case delayed(Term, Env?)
        /// Evaluated.
        case value(Value)
    }

    var state: State

    init(_ term: Term, _ environment: Env?) {
        state = .delayed(term, environment)
    }

    init(_ value: Value) {
        state = .value(value)
    }

    deinit {
        guard state.hasChildren else { return }
        var thunks: [Thunk] = []
        var environments: [Env] = []
        state.children(&thunks, &environments)
        state = .nothing
        drain(&thunks, &environments)
    }
}

extension Thunk.State {
    /// A state that refers to nothing, for a thunk on its way out.
    static var nothing: Self { .value(.rigid(0, [])) }

    var hasChildren: Bool {
        switch self {
        case .delayed(_, let environment): return environment != nil
        case .value(.closure(_, let environment)): return environment != nil
        case .value(.rigid(_, let spine)): return !spine.isEmpty
        }
    }

    /// Adds whatever this state holds on to, so that a caller can take it over.
    func children(_ thunks: inout [Thunk], _ environments: inout [Env]) {
        switch self {
        case .delayed(_, let environment), .value(.closure(_, let environment)):
            if let environment { environments.append(environment) }
        case .value(.rigid(_, let spine)):
            thunks.append(contentsOf: spine)
        }
    }
}

/// Takes a graph of thunks and environments apart without recursing.
///
/// A reduction that ran for a while leaves a chain — thunk to environment to
/// thunk, over and over — as long as it ran.  Releasing the first link of such
/// a chain would release the second, and so on, one stack frame per link, and
/// a program that loops until the step limit stops it would take the stack
/// with it.  So each link hands its children to a work list, and takes an
/// extra reference to each before letting go of it, which leaves nothing for
/// the runtime to free recursively.
private func drain(_ thunks: inout [Thunk], _ environments: inout [Env]) {
    while true {
        // `popLast` hands over the array's reference, so a link that nothing
        // else holds on to is uniquely referenced here and about to die anyway
        if var thunk = thunks.popLast() {
            if isKnownUniquelyReferenced(&thunk) {
                thunk.state.children(&thunks, &environments)
                thunk.state = .nothing
            }
        } else if var environment = environments.popLast() {
            if isKnownUniquelyReferenced(&environment) {
                thunks.append(environment.head)
                if let tail = environment.tail { environments.append(tail) }
                environment.tail = nil
            }
        } else {
            return
        }
    }
}

/// What a term reduces to, in weak head normal form.
enum Value {
    /// An abstraction, together with the environment its body refers to.
    case closure(Term, Env?)
    /// A variable that nothing will ever substitute for — a parameter held
    /// abstract during read-back, or a probe applied to a term to see what it
    /// does with it — applied to zero or more arguments.
    ///
    /// The `Int` is a De Bruijn *level*, which unlike an index means the same
    /// thing at every depth.
    case rigid(Int, [Thunk])
}

/// The bindings a term's free indices refer to, innermost first.
final class Env {
    let head: Thunk
    /// Mutable only so that ``deinit`` can unlink it; see `drain`.
    fileprivate(set) var tail: Env?

    init(_ head: Thunk, _ tail: Env?) {
        self.head = head
        self.tail = tail
    }

    deinit {
        var thunks: [Thunk] = [head]
        var environments: [Env] = []
        if let tail {
            environments.append(tail)
            self.tail = nil
        }
        drain(&thunks, &environments)
    }

    /// The binding for a 1-based De Bruijn index, or `nil` if it reaches past
    /// the whole environment.
    static func lookup(_ environment: Env?, _ index: Int) -> Thunk? {
        guard index >= 1 else { return nil }
        var environment = environment
        var index = index
        while index > 1 {
            environment = environment?.tail
            index -= 1
        }
        return environment?.head
    }
}

/// The reducer.
///
/// Reduction is normal order — the leftmost, outermost redex first, which is
/// the strategy that finds a normal form whenever one exists — with call by
/// need, so an argument is reduced at most once no matter how often it is used,
/// and never at all if it is not.  That is what makes it possible to run a
/// program whose output is infinite, and to hand a program an input it must not
/// look at, such as `Ω`.
///
/// The machine keeps a running step count across everything it is asked to do,
/// so one ``limit`` covers a whole program run rather than each list cell of it.
final class Machine {
    /// The most reduction steps to take before giving up.
    let limit: Int
    /// Steps taken so far.
    private(set) var steps = 0
    /// Levels for probe variables, kept negative so that they cannot be
    /// mistaken for the levels read-back assigns, which start at 1.
    private var lastProbe = 0

    init(limit: Int = .max) {
        self.limit = limit
    }

    /// What is left to do once the term in hand reaches weak head normal form.
    private enum Frame {
        /// Apply the result to this argument.
        case argument(Thunk)
        /// Store the result in this thunk, which is where it came from.
        case update(Thunk)
    }

    /// Reduces `term` to weak head normal form.
    func whnf(_ term: Term, _ environment: Env? = nil) throws -> Value {
        try run(term, environment, [])
    }

    /// Reduces a thunk to weak head normal form, remembering the result.
    func force(_ thunk: Thunk) throws -> Value {
        switch thunk.state {
        case .value(let value):
            return value
        case .delayed(let term, let environment):
            return try run(term, environment, [.update(thunk)])
        }
    }

    /// Applies a value to arguments, reducing the result to weak head normal
    /// form.
    func apply(_ value: Value, _ arguments: [Thunk]) throws -> Value {
        guard !arguments.isEmpty else { return value }
        switch value {
        case .rigid(let level, let spine):
            // nothing to reduce: a rigid variable just collects arguments
            return .rigid(level, spine + arguments)
        case .closure(let body, let environment):
            // the first argument goes on top of the stack
            return try run(.abstraction(body), environment, arguments.reversed().map(Frame.argument))
        }
    }

    /// The machine proper.  One loop, one explicit stack, no recursion — so
    /// that the depth of a reduction is limited by memory rather than by the
    /// call stack.
    private func run(_ start: Term, _ startEnvironment: Env?, _ startStack: [Frame]) throws -> Value {
        var term = start
        var environment = startEnvironment
        var stack = startStack
        while true {
            steps += 1
            if steps > limit { throw BLCError.stepLimitExceeded(steps: limit) }

            var value: Value
            switch term {
            case .application(let function, let argument):
                // remember the argument, unevaluated, and keep going left
                stack.append(.argument(Thunk(argument, environment)))
                term = function
                continue
            case .abstraction(let body):
                value = .closure(body, environment)
            case .index(let index):
                guard let thunk = Env.lookup(environment, index) else {
                    throw BLCError.unbound("index \(index)")
                }
                switch thunk.state {
                case .delayed(let delayed, let delayedEnvironment):
                    // evaluate it in place, and write the result back when done
                    stack.append(.update(thunk))
                    term = delayed
                    environment = delayedEnvironment
                    continue
                case .value(let forced):
                    value = forced
                }
            }

            // a value in hand; hand it to the frames waiting for it
            dispatch: while true {
                switch value {
                case .closure(let body, let closed):
                    guard let frame = stack.popLast() else { return value }
                    switch frame {
                    case .update(let thunk):
                        thunk.state = .value(value)
                        continue dispatch
                    case .argument(let argument):
                        // β: bind the argument and carry on with the body
                        term = body
                        environment = Env(argument, closed)
                        break dispatch
                    }
                case .rigid(let level, let spine):
                    // nothing more will reduce: everything still on the stack
                    // is an argument to this variable, and every thunk waiting
                    // for an update gets what it asked for along the way
                    var spine = spine
                    while let frame = stack.popLast() {
                        switch frame {
                        case .update(let thunk):
                            thunk.state = .value(.rigid(level, spine))
                        case .argument(let argument):
                            spine.append(argument)
                        }
                    }
                    return .rigid(level, spine)
                }
            }
        }
    }

    /// A fresh variable that no term can contain, for probing what a term does
    /// with its arguments.
    func probe() -> (level: Int, thunk: Thunk) {
        lastProbe -= 1
        return (lastProbe, Thunk(.rigid(lastProbe, [])))
    }

    // MARK: - normal form

    /// Reduces `term` all the way, under lambdas included.
    func normalForm(of term: Term) throws -> Term {
        try readBack(whnf(term), depth: 0)
    }

    /// Turns a value back into a term, reducing whatever it still contains.
    ///
    /// `depth` is how many lambdas the term being built sits under, which is
    /// what turns the absolute levels of rigid variables back into indices.
    ///
    /// Iterative, like ``run(_:_:_:)`` and for the same reason: a term whose
    /// normal form is deeper than the call stack should run out of patience,
    /// not out of stack.
    private func readBack(_ value: Value, depth: Int) throws -> Term {
        /// A step of the read-back still to take.
        enum Job {
            /// Read this value back, `Int` lambdas deep.
            case value(Value, Int)
            /// Reduce this thunk, then read it back.
            case thunk(Thunk, Int)
            /// Wrap the finished term in an abstraction.
            case abstract
            /// Apply the term before last to the last.
            case combine
        }
        var jobs: [Job] = [.value(value, depth)]
        var finished: [Term] = []
        while let job = jobs.popLast() {
            switch job {
            case .thunk(let thunk, let depth):
                jobs.append(.value(try force(thunk), depth))
            case .abstract:
                finished.append(.abstraction(finished.removeLast()))
            case .combine:
                let argument = finished.removeLast()
                finished.append(.application(finished.removeLast(), argument))
            case .value(.closure(let body, let environment), let depth):
                // go under the lambda: its parameter becomes a rigid variable
                let parameter = Thunk(.rigid(depth + 1, []))
                jobs.append(.abstract)
                jobs.append(.value(try whnf(body, Env(parameter, environment)), depth + 1))
            case .value(.rigid(let level, let spine), let depth):
                finished.append(.index(depth - level + 1))
                // …applied to its arguments, leftmost first once unstacked
                for argument in spine.reversed() {
                    jobs.append(.combine)
                    jobs.append(.thunk(argument, depth))
                }
            }
        }
        return finished[0]
    }
}

extension Term {
    /// The normal form of this term: the term reduced as far as it goes,
    /// under lambdas included.
    ///
    /// ```swift
    /// try (Term.S * .K * .K).normalForm()    // λ1, the identity
    /// ```
    ///
    /// Not every term has one — `Ω` reduces to itself forever — so give a
    /// `limit` to anything you are not sure of.
    ///
    /// - Parameter limit: the most reduction steps to take.
    /// - Throws: ``BLCError/stepLimitExceeded(steps:)`` if it runs out of them,
    ///   ``BLCError/unbound(_:)`` if the term is not closed.
    public func normalForm(limit: Int = .max) throws -> Term {
        try Machine(limit: limit).normalForm(of: self)
    }
}
