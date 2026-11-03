import Foundation

public struct ValidationIssue: Identifiable, Equatable, Sendable {
    public enum Severity: String, Sendable { case error, warning }
    public var id: String { "\(elementID?.uuidString ?? "circuit")-\(key)" }
    public let elementID: UUID?
    public let severity: Severity
    public let key: String
    public init(_ key: String, elementID: UUID? = nil, severity: Severity = .error) {
        self.key = key; self.elementID = elementID; self.severity = severity
    }
}

public enum CircuitValidation {
    public static func issues(in circuit: Circuit) -> [ValidationIssue] {
        guard !circuit.elements.isEmpty else { return [] }
        var adjacency: [GridPoint: [(GridPoint, UUID)]] = [:]
        for e in circuit.elements {
            adjacency[e.position, default: []].append((e.end, e.id))
            adjacency[e.end, default: []].append((e.position, e.id))
        }
        func reachable(from seeds: [GridPoint]) -> Set<GridPoint> {
            var visited = Set(seeds), queue = seeds, index = 0
            while index < queue.count {
                let node = queue[index]; index += 1
                for (next, _) in adjacency[node, default: []] where visited.insert(next).inserted { queue.append(next) }
            }
            return visited
        }
        let left = reachable(from: (0..<circuit.rows).map { .init(0, $0) })
        let right = reachable(from: (0..<circuit.rows).map { .init(circuit.columns, $0) })
        var issues: [ValidationIssue] = []
        for e in circuit.elements {
            if !circuit.contains(e) { issues.append(.init("validation.bounds", elementID: e.id)) }
            if !left.contains(e.position) || !right.contains(e.position) {
                issues.append(.init("validation.disconnected", elementID: e.id))
            }
            if e.terminals.contains(where: { node in
                node.column != 0 && node.column != circuit.columns && adjacency[node, default: []].count < 2
            }) { issues.append(.init("validation.dangling", elementID: e.id)) }
            if e.kind.isOutput && e.end.column != circuit.columns {
                issues.append(.init("validation.outputPosition", elementID: e.id, severity: .warning))
            }
            if !e.kind.isWire && e.label.range(of: "^[A-Z][A-Z0-9_]{0,15}$", options: .regularExpression) == nil {
                issues.append(.init("validation.label", elementID: e.id))
            }
        }
        // A wire-only rail-to-rail path is a short circuit, even when other rungs are valid.
        let wires = circuit.elements.filter(\.kind.isWire)
        var wireNodes: [GridPoint: [GridPoint]] = [:]
        for e in wires { wireNodes[e.position, default: []].append(e.end); wireNodes[e.end, default: []].append(e.position) }
        var visited = Set((0..<circuit.rows).map { GridPoint(0, $0) }), queue = Array(visited), i = 0
        while i < queue.count {
            let node = queue[i]; i += 1
            for next in wireNodes[node, default: []] where visited.insert(next).inserted { queue.append(next) }
        }
        if visited.contains(where: { $0.column == circuit.columns }) { issues.append(.init("validation.shortCircuit")) }
        return issues
    }
}
