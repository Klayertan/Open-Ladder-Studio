import Foundation

/// Pure, atomic editing operations. UI, storage, and a future simulator do not own topology.
public enum CircuitEditing {
    public static func insert(_ elements: [LadderElement], into circuit: Circuit) throws -> Circuit {
        var result = circuit; result.elements += elements
        return try result.checked()
    }
    /// Place a symbol directly onto a wire without disturbing neighbouring connections.
    public static func place(_ element: LadderElement, in circuit: Circuit) throws -> Circuit {
        var result = circuit
        if !element.kind.isWire {
            result.elements.removeAll { $0.kind == .horizontalWire && $0.position == element.position }
        }
        return try insert([element], into: result)
    }

    /// Orthogonal terminal-to-terminal route. Existing symbols/wires and rails are reused.
    public static func wirePath(from start: GridPoint, to end: GridPoint, horizontalFirst: Bool = true, in circuit: Circuit) throws -> [LadderElement] {
        func valid(_ p: GridPoint) -> Bool {
            (0...circuit.columns).contains(p.column) && (0..<circuit.rows).contains(p.row)
        }
        guard valid(start), valid(end) else { throw CircuitError.outOfBounds }
        var path: [LadderElement] = []
        func horizontal(_ a: GridPoint, _ b: GridPoint) {
            for column in min(a.column,b.column)..<max(a.column,b.column) {
                path.append(.init(kind: .horizontalWire, position: .init(column,a.row)))
            }
        }
        func vertical(_ a: GridPoint, _ b: GridPoint) {
            // The power rails already connect all their row terminals.
            guard a.column > 0 && a.column < circuit.columns else { return }
            for row in min(a.row,b.row)..<max(a.row,b.row) {
                path.append(.init(kind: .verticalWire, position: .init(a.column,row)))
            }
        }
        let bend = horizontalFirst ? GridPoint(end.column,start.row) : GridPoint(start.column,end.row)
        if horizontalFirst { horizontal(start,bend); vertical(bend,end) }
        else { vertical(start,bend); horizontal(bend,end) }
        return path
    }

    public static func connect(from start: GridPoint, to end: GridPoint, horizontalFirst: Bool = true, in circuit: Circuit) throws -> Circuit {
        let path = try wirePath(from: start,to: end,horizontalFirst: horizontalFirst,in: circuit)
        let additions = path.filter { segment in !circuit.elements.contains { $0.overlaps(segment) } }
        return try insert(additions,into: circuit)
    }

    public static func remove(_ ids: Set<UUID>, from circuit: Circuit) -> Circuit {
        var result = circuit; result.elements.removeAll { ids.contains($0.id) }; return result
    }
    public static func move(_ ids: Set<UUID>, columns: Int, rows: Int, in circuit: Circuit) throws -> Circuit {
        _ = try circuit.checked()
        guard (-128...128).contains(columns), (-512...512).contains(rows) else { throw CircuitError.outOfBounds }
        var result = circuit
        for i in result.elements.indices where ids.contains(result.elements[i].id) {
            result.elements[i].position = result.elements[i].position.offset(columns: columns, rows: rows)
        }
        return try result.checked()
    }
    public static func update(_ id: UUID, label: String, comment: String, timerPresetMilliseconds: Int? = nil, counterPreset: Int? = nil, in circuit: Circuit) throws -> Circuit {
        var result = circuit
        guard let i = result.elements.firstIndex(where: { $0.id == id }) else { return result }
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !result.elements[i].kind.isWire {
            guard normalized.range(of: Circuit.addressPattern, options: .regularExpression) != nil else { throw CircuitError.invalidLabel }
        }
        result.elements[i].label = result.elements[i].kind.isWire ? "" : normalized
        result.elements[i].comment = String(comment.prefix(240))
        if result.elements[i].kind == .timer, let timerPresetMilliseconds { result.elements[i].timerPresetMilliseconds = timerPresetMilliseconds }
        if result.elements[i].kind == .counter, let counterPreset { result.elements[i].counterPreset = counterPreset }
        return try result.checked()
    }
    /// Edits the shared definition of an address; every symbol with that label follows it.
    public static func setDevice(_ address: String, comment: String, lampColor: LampColor?, in circuit: Circuit) throws -> Circuit {
        var result = circuit
        let info = DeviceInfo(comment: String(comment.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240)), lampColor: lampColor)
        result.devices[address] = info.isEmpty ? nil : info
        return try result.checked()
    }
    /// Adds an explicit rectangular bypass below a span. Existing matching wires are reused.
    /// Any collision with a symbol rejects the entire operation.
    public static func branch(from start: GridPoint, width: Int, in circuit: Circuit) throws -> Circuit {
        guard start.column > 0, start.column < circuit.columns, start.row >= 0, start.row < circuit.rows - 1,
              width >= 1, width < circuit.columns - start.column else { throw CircuitError.outOfBounds }
        var additions = [LadderElement(kind: .verticalWire, position: start),
                         LadderElement(kind: .verticalWire, position: start.offset(columns: width, rows: 0))]
        additions += (0..<width).map { LadderElement(kind: .horizontalWire, position: start.offset(columns: $0, rows: 1)) }
        additions.removeAll { e in circuit.elements.contains { $0.kind == e.kind && $0.position == e.position } }
        return try insert(additions, into: circuit)
    }
    public static func paste(_ elements: [LadderElement], at anchor: GridPoint, into circuit: Circuit) throws -> (Circuit, Set<UUID>) {
        guard let minColumn = elements.map(\.position.column).min(), let minRow = elements.map(\.position.row).min(), elements.count <= 65_536 else {
            throw CircuitError.noRoomForPaste
        }
        guard elements.allSatisfy({ (0..<128).contains($0.position.column) && (0..<512).contains($0.position.row) }),
              (0..<128).contains(anchor.column), (0..<512).contains(anchor.row) else { throw CircuitError.outOfBounds }
        let copies = elements.map { e in
            var copy = e; copy.id = UUID()
            copy.position = e.position.offset(columns: anchor.column - minColumn, rows: anchor.row - minRow)
            return copy
        }
        return (try insert(copies, into: circuit), Set(copies.map(\.id)))
    }
}

/// Reserved extension point. A format adapter must produce a validated native circuit.
public protocol CircuitImporter: Sendable {
    var fileExtensions: [String] { get }
    func importCircuit(from data: Data) throws -> Circuit
}

public struct NativeJSONImporter: CircuitImporter {
    public init() {}
    public var fileExtensions: [String] { ["ladder"] }
    public func importCircuit(from data: Data) throws -> Circuit { try Circuit.decode(data) }
}

/// Deliberately disabled until real Renri files and format semantics are verified.
public struct RenriImporter: CircuitImporter {
    public init() {}
    public var fileExtensions: [String] { ["mbs"] }
    public func importCircuit(from data: Data) throws -> Circuit { throw CircuitError.unsupportedImporter }
}
