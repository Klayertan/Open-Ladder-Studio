import Foundation

public struct GridPoint: Codable, Hashable, Sendable {
    public var column: Int
    public var row: Int
    public init(_ column: Int, _ row: Int) { self.column = column; self.row = row }
    public func offset(columns: Int, rows: Int) -> Self { .init(column + columns, row + rows) }
}

public enum SymbolKind: String, Codable, CaseIterable, Sendable {
    case normallyOpen, normallyClosed, coil, setCoil, resetCoil, horizontalWire, verticalWire, timer

    public var isWire: Bool { self == .horizontalWire || self == .verticalWire }
    public var isOutput: Bool { self == .coil || self == .setCoil || self == .resetCoil || self == .timer }
    public var defaultLabel: String {
        switch self {
        case .normallyOpen, .normallyClosed: "X0"
        case .coil: "Y0"
        case .setCoil, .resetCoil: "M0"
        case .timer: "T0"
        case .horizontalWire, .verticalWire: ""
        }
    }
    public var localizationKey: String { "symbol.\(rawValue)" }
}

/// A symbol is an electrical edge between two integer grid nodes.
/// Horizontal elements occupy one cell; vertical wires occupy its left boundary.
public struct LadderElement: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var kind: SymbolKind
    public var position: GridPoint
    public var label: String
    public var comment: String
    public var timerPresetMilliseconds: Int?
    public var presetMilliseconds: Int { timerPresetMilliseconds ?? 1_000 }
    public init(id: UUID = UUID(), kind: SymbolKind, position: GridPoint, label: String? = nil, comment: String = "", timerPresetMilliseconds: Int? = nil) {
        self.id = id; self.kind = kind; self.position = position
        self.label = label ?? kind.defaultLabel; self.comment = comment
        self.timerPresetMilliseconds = timerPresetMilliseconds
    }
    public var end: GridPoint {
        position.offset(columns: kind == .verticalWire ? 0 : 1, rows: kind == .verticalWire ? 1 : 0)
    }
    public var terminals: [GridPoint] { [position, end] }
    public func overlaps(_ other: Self) -> Bool {
        position == other.position && (kind == .verticalWire) == (other.kind == .verticalWire)
    }
}

public struct Circuit: Codable, Equatable, Sendable {
    public static let formatVersion = 2
    public var version: Int
    public var name: String
    public var columns: Int
    public var rows: Int
    public var elements: [LadderElement]
    public init(name: String = "Untitled", columns: Int = 10, rows: Int = 10, elements: [LadderElement] = []) {
        version = Self.formatVersion; self.name = name; self.columns = columns; self.rows = rows; self.elements = elements
    }
    public func contains(_ element: LadderElement) -> Bool {
        if element.kind == .verticalWire {
            return element.position.column > 0 && element.position.column < columns && element.position.row >= 0 && element.position.row < rows - 1
        }
        return element.position.column >= 0 && element.position.column < columns && element.position.row >= 0 && element.position.row < rows
    }
    public func checked() throws -> Circuit {
        guard version == Self.formatVersion else { throw CircuitError.unsupportedVersion(version) }
        guard (4...128).contains(columns), (2...512).contains(rows), elements.count <= 65_536 else { throw CircuitError.invalidDimensions }
        guard Set(elements.map(\.id)).count == elements.count else { throw CircuitError.duplicateIdentifier }
        guard elements.allSatisfy(contains) else { throw CircuitError.outOfBounds }
        // Occupancy is independent of symbol type, so a contact and a wire cannot share a cell.
        var occupied = Set<String>()
        for e in elements {
            if e.kind == .timer && !(1...86_400_000).contains(e.presetMilliseconds) { throw CircuitError.invalidTimerPreset }
            let key = "\(e.position.column),\(e.position.row),\(e.kind == .verticalWire)"
            guard occupied.insert(key).inserted else { throw CircuitError.overlap }
        }
        return self
    }
    public static func decode(_ data: Data) throws -> Circuit {
        var circuit = try JSONDecoder().decode(Circuit.self, from: data)
        if circuit.version == 1 { circuit.version = formatVersion }
        return try circuit.checked()
    }
    public func encoded() throws -> Data {
        _ = try checked()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

public enum CircuitError: Error, LocalizedError, Equatable {
    case overlap, outOfBounds, invalidDimensions, duplicateIdentifier, unsupportedVersion(Int), invalidLabel, noRoomForPaste, unsupportedImporter, invalidTimerPreset
    public var errorDescription: String? {
        switch self {
        case .overlap: String(localized: "error.overlap", bundle: .main)
        case .outOfBounds: String(localized: "error.bounds", bundle: .main)
        case .invalidDimensions: String(localized: "error.dimensions", bundle: .main)
        case .duplicateIdentifier: String(localized: "error.identifiers", bundle: .main)
        case .unsupportedVersion(let version): String(format: String(localized: "error.version", bundle: .main), version)
        case .invalidLabel: String(localized: "error.label", bundle: .main)
        case .noRoomForPaste: String(localized: "error.paste", bundle: .main)
        case .unsupportedImporter: String(localized: "error.importer", bundle: .main)
        case .invalidTimerPreset: String(localized: "error.timerPreset", bundle: .main)
        }
    }
}
