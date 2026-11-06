import Foundation

extension RenriMBSExporter {
    private struct Literal: Hashable {
        let label: String
        let closed: Bool
        let comment: String
        init(label: String, closed: Bool, comment: String = "") {
            self.label = label; self.closed = closed; self.comment = comment
        }
        var key: String { label + (closed ? ":NC:" : ":NO:") + comment }
    }

    /// Lower a monotone left-to-right electrical graph into series instructions.
    /// OR networks use private ordinary relays and De Morgan's law. Helpers precede
    /// their output so a sequential Renri scan evaluates the whole expression first.
    /// No guessed branch graphics/opcodes are written to the MBS stream.
    static func loweringBranches(_ circuit: Circuit) throws -> Circuit {
        _ = try circuit.checked()
        guard !CircuitValidation.issues(in:circuit).contains(where: { $0.severity == .error }) else { throw RenriExportError.unsupportedLayout }
        let outputs = circuit.elements.filter(\.kind.isOutput).sorted {
            ($0.position.row,$0.position.column) < ($1.position.row,$1.position.column)
        }
        guard !outputs.isEmpty else { throw RenriExportError.unsupportedLayout }
        var parents: [GridPoint:GridPoint] = [:]
        func root(_ point: GridPoint) -> GridPoint {
            if let parent = parents[point], parent != point {
                let result = root(parent); parents[point] = result; return result
            }
            return point
        }
        for wire in circuit.elements where wire.kind == .verticalWire {
            let a = root(wire.position), b = root(wire.end)
            if a != b { parents[b] = a }
        }
        var incoming: [GridPoint:[LadderElement]] = [:]
        for element in circuit.elements where !element.kind.isOutput && element.kind != .verticalWire {
            guard element.kind == .horizontalWire || element.kind == .normallyOpen || element.kind == .normallyClosed else { throw RenriExportError.unsupportedLayout }
            incoming[root(element.end),default:[]].append(element)
        }
        typealias Term = Set<Literal>
        var memo: [GridPoint:Set<Term>] = [:]
        func expression(_ point: GridPoint) throws -> Set<Term> {
            let point = root(point)
            if point.column == 0 { return [Term()] }
            if let cached = memo[point] { return cached }
            var terms = Set<Term>()
            for edge in incoming[point,default:[]] {
                for var term in try expression(edge.position) {
                    if !edge.kind.isWire {
                        let literal = Literal(label:edge.label,closed:edge.kind == .normallyClosed,comment:edge.comment)
                        if term.contains(where: { $0.label == literal.label && $0.closed != literal.closed }) { continue }
                        term.insert(literal)
                    }
                    // Absorption keeps duplicated/shared branch paths compact.
                    if terms.contains(where: { $0.isSubset(of:term) }) { continue }
                    terms = Set(terms.filter { !term.isSubset(of:$0) })
                    terms.insert(term)
                    guard terms.count <= 256 else { throw RenriExportError.unsupportedLayout }
                }
            }
            memo[point] = terms
            return terms
        }
        var reserved = Set(circuit.addresses.filter { $0.hasPrefix("M") }.compactMap { Int($0.dropFirst()) })
        var nextRelay = 0
        func relay() throws -> String {
            while reserved.contains(nextRelay) { nextRelay += 1 }
            // Stay below the conventional special-relay region.
            guard nextRelay < 8000 else { throw RenriExportError.unsupportedLayout }
            reserved.insert(nextRelay)
            return "M\(nextRelay)"
        }
        var elements: [LadderElement] = []
        var row = 0
        func append(_ literals: [Literal], output: LadderElement) throws {
            guard literals.count <= 9, row < 512 else { throw RenriExportError.unsupportedLayout }
            for column in 0..<12 {
                if column == 11 {
                    var copy = output; copy.id = UUID(); copy.position = .init(column,row)
                    elements.append(copy)
                } else if column < literals.count {
                    let literal = literals[column]
                    elements.append(.init(kind:literal.closed ? .normallyClosed : .normallyOpen,position:.init(column,row),label:literal.label,comment:literal.comment))
                } else { elements.append(.init(kind:.horizontalWire,position:.init(column,row))) }
            }
            row += 1
        }
        func conjunction(_ literals: [Literal], output: LadderElement) throws {
            var remaining = literals
            while remaining.count > 9 {
                let address = try relay()
                try append(Array(remaining.prefix(9)),output:.init(kind:.coil,position:.init(0,0),label:address))
                remaining = [Literal(label:address,closed:false)] + Array(remaining.dropFirst(9))
            }
            try append(remaining,output:output)
        }
        for output in outputs {
            let terms = try expression(output.position).map { $0.sorted { $0.key < $1.key } }.sorted {
                $0.map(\.key).joined(separator:",") < $1.map(\.key).joined(separator:",")
            }
            guard !terms.isEmpty else { throw RenriExportError.unsupportedLayout }
            if terms.count == 1 { try conjunction(terms[0],output:output); continue }
            var negatives: [Literal] = []
            for term in terms {
                let address = try relay()
                try conjunction(term,output:.init(kind:.coil,position:.init(0,0),label:address))
                negatives.append(.init(label:address,closed:true))
            }
            let nor = try relay()
            try conjunction(negatives,output:.init(kind:.coil,position:.init(0,0),label:nor))
            try append([.init(label:nor,closed:true)],output:output)
        }
        return Circuit(name:circuit.name,columns:12,rows:max(2,row),elements:elements,devices:circuit.devices)
    }
}
