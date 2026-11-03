import Foundation

public struct TimerState: Equatable, Sendable {
    public var enabled = false
    public var elapsedMilliseconds = 0
    public var presetMilliseconds: Int
    public var done: Bool { enabled && elapsedMilliseconds >= presetMilliseconds }
}

public struct SimulationEvent: Equatable, Sendable {
    public let milliseconds: Int
    public let activeOutputs: [String]
}

public struct SimulationState: Equatable, Sendable {
    public var milliseconds = 0
    public var bits: [String: Bool] = [:]
    public var timers: [String: TimerState] = [:]
    public var energizedElements: Set<UUID> = []
    public var events: [SimulationEvent] = []
    public subscript(_ address: String) -> Bool { bits[address, default: false] }
}

public enum SimulationError: Error, LocalizedError {
    case invalidConnections, invalidDevice(String), duplicateWriter(String), unstableLogic
    public var errorDescription: String? {
        switch self {
        case .invalidConnections: String(localized: "simulation.error.connections", bundle: .main)
        case .invalidDevice(let address): String(format: String(localized: "simulation.error.device", bundle: .main), address)
        case .duplicateWriter(let address): String(format: String(localized: "simulation.error.writer", bundle: .main), address)
        case .unstableLogic: String(localized: "simulation.error.unstable", bundle: .main)
        }
    }
}

/// Deterministic educational relay simulator, independent of rendering and wall time.
/// Time advances in 10 ms steps. Each step advances already-enabled TON timers once,
/// then settles relay logic without advancing time again. A coil is a terminal load:
/// the common right rail never feeds another rung. Horizontal power flows left to
/// right; vertical branch wires conduct in either direction.
public struct LadderSimulator: Sendable {
    public let circuit: Circuit
    public private(set) var state = SimulationState()
    private var pendingMilliseconds = 0
    private let outputs: [LadderElement]
    private let outgoing: [GridPoint: [LadderElement]]

    public init(circuit: Circuit) throws {
        self.circuit = try circuit.checked()
        guard !CircuitValidation.issues(in: circuit).contains(where: { $0.severity == .error }) else { throw SimulationError.invalidConnections }
        outputs = circuit.elements.filter(\.kind.isOutput).sorted {
            ($0.position.row, $0.position.column) < ($1.position.row, $1.position.column)
        }
        var writers: [String: [SymbolKind]] = [:]
        var edges: [GridPoint: [LadderElement]] = [:]
        for element in circuit.elements where !element.kind.isWire {
            let pattern = element.kind == .timer ? "^T[0-9]+$" : element.kind.isOutput ? "^[MY][0-9]+$" : "^[XMYT][0-9]+$"
            guard element.label.range(of: pattern, options: .regularExpression) != nil else { throw SimulationError.invalidDevice(element.label) }
            state.bits[element.label] = false
            if element.kind.isOutput { writers[element.label, default: []].append(element.kind) }
            if element.kind == .timer { state.timers[element.label] = TimerState(presetMilliseconds: element.presetMilliseconds) }
        }
        for (label, kinds) in writers where kinds.count > 1 {
            // One SET and one RESET writer are allowed; ordinary/timer duplicates are ambiguous.
            guard kinds.count == 2 && Set(kinds) == [.setCoil, .resetCoil] else { throw SimulationError.duplicateWriter(label) }
        }
        for element in circuit.elements where !element.kind.isOutput {
            edges[element.position, default: []].append(element)
            if element.kind == .verticalWire { edges[element.end, default: []].append(element) }
        }
        outgoing = edges
        try settle()
        recordOutputs()
    }

    public mutating func setInput(_ address: String, pressed: Bool) throws {
        guard address.hasPrefix("X"), state.bits[address] != nil else { throw SimulationError.invalidDevice(address) }
        state.bits[address] = pressed
        try settle()
        recordOutputs()
    }

    public mutating func pulseInput(_ address: String) throws {
        try setInput(address, pressed: true)
        try setInput(address, pressed: false)
    }

    public mutating func advance(milliseconds: Int) throws {
        guard milliseconds >= 0 && milliseconds <= 86_400_000 else { throw CircuitError.invalidTimerPreset }
        pendingMilliseconds += milliseconds
        while pendingMilliseconds >= 10 {
            pendingMilliseconds -= 10
            state.milliseconds += 10
            for label in Array(state.timers.keys) {
                if var timer = state.timers[label], timer.enabled {
                    timer.elapsedMilliseconds = min(timer.presetMilliseconds, timer.elapsedMilliseconds + 10)
                    state.timers[label] = timer
                    state.bits[label] = timer.done
                }
            }
            try settle()
            recordOutputs()
        }
    }

    private func conducting(_ element: LadderElement) -> Bool {
        switch element.kind {
        case .normallyOpen: state[element.label]
        case .normallyClosed: !state[element.label]
        case .horizontalWire, .verticalWire: true
        default: false
        }
    }

    private func poweredNodes() -> Set<GridPoint> {
        var visited = Set((0..<circuit.rows).map { GridPoint(0, $0) })
        var queue = Array(visited), i = 0
        while i < queue.count {
            let node = queue[i]; i += 1
            for edge in outgoing[node, default: []] where conducting(edge) {
                let next = edge.position == node ? edge.end : edge.position
                if visited.insert(next).inserted { queue.append(next) }
            }
        }
        return visited
    }

    private mutating func settle() throws {
        for _ in 0..<64 {
            let oldBits = state.bits, oldTimers = state.timers
            for output in outputs {
                let powered = poweredNodes().contains(output.position)
                switch output.kind {
                case .coil: state.bits[output.label] = powered
                case .setCoil: if powered { state.bits[output.label] = true }
                case .resetCoil: if powered { state.bits[output.label] = false }
                case .timer:
                    var timer = state.timers[output.label] ?? TimerState(presetMilliseconds: output.presetMilliseconds)
                    timer.enabled = powered
                    if !powered { timer.elapsedMilliseconds = 0 }
                    state.timers[output.label] = timer
                    state.bits[output.label] = timer.done
                default: break
                }
            }
            if oldBits == state.bits && oldTimers == state.timers {
                let nodes = poweredNodes()
                state.energizedElements = Set(circuit.elements.filter { element in
                    if element.kind.isOutput { return nodes.contains(element.position) }
                    return conducting(element) && (nodes.contains(element.position) || (element.kind == .verticalWire && nodes.contains(element.end)))
                }.map(\.id))
                return
            }
        }
        throw SimulationError.unstableLogic
    }

    private mutating func recordOutputs() {
        let active = state.bits.keys.filter { $0.hasPrefix("Y") && state[$0] }.sorted()
        guard state.events.last?.activeOutputs != active else { return }
        state.events.append(.init(milliseconds: state.milliseconds, activeOutputs: active))
        if state.events.count > 1_000 { state.events.removeFirst() }
    }
}
