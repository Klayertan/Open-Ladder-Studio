import Foundation

public struct TimerState: Equatable, Sendable {
    public var enabled = false
    public var elapsedMilliseconds = 0
    public var presetMilliseconds: Int
    public var done: Bool { enabled && elapsedMilliseconds >= presetMilliseconds }
}

public struct CounterState: Equatable, Sendable {
    public var current = 0
    public var preset: Int
    public var done = false
    public var lastInput = false
}

public struct PulseState: Equatable, Sendable {
    public var lastInput = false
}

public struct SimulationEvent: Equatable, Sendable {
    public let milliseconds: Int
    public let activeOutputs: [String]
}

/// A change in an observed device. Multiple changes at the same timestamp are
/// retained so momentary inputs and timer feedback pulses do not disappear.
public struct SignalTransition: Equatable, Sendable {
    public let milliseconds: Int
    public let value: Bool
    public let timing: Bool
    public let count: Int?
    public init(milliseconds: Int, value: Bool, timing: Bool = false, count: Int? = nil) {
        self.milliseconds = milliseconds; self.value = value; self.timing = timing; self.count = count
    }
}

public struct SimulationState: Equatable, Sendable {
    public init() {}
    public var milliseconds = 0
    public var bits: [String: Bool] = [:]
    public var timers: [String: TimerState] = [:]
    public var counters: [String: CounterState] = [:]
    public var pulses: [String: PulseState] = [:]
    public var energizedElements: Set<UUID> = []
    public var events: [SimulationEvent] = []
    public static let historyDurationMilliseconds = 120_000
    public static let maxTransitionsPerSignal = 4_096
    public var signalHistory: [String: [SignalTransition]] = [:]
    public var historyStartMilliseconds: Int { max(0, milliseconds - Self.historyDurationMilliseconds) }
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
        outputs = circuit.elements.filter(\.kind.isOutput).sorted {
            ($0.position.row, $0.position.column) < ($1.position.row, $1.position.column)
        }
        var writers: [String: [SymbolKind]] = [:]
        var edges: [GridPoint: [LadderElement]] = [:]
        for element in circuit.elements where !element.kind.isWire {
            let pattern = element.kind == .counter ? "^C[0-9]+$" : element.kind == .timer ? "^T[0-9]+$" : element.kind == .resetCoil ? "^[MYC][0-9]+$" : element.kind.isOutput ? "^[MY][0-9]+$" : "^[XMYTC][0-9]+$"
            guard element.label.range(of: pattern, options: .regularExpression) != nil else { throw SimulationError.invalidDevice(element.label) }
            state.bits[element.label] = false
            if element.kind.isOutput { writers[element.label, default: []].append(element.kind) }
            if element.kind.isPulse { state.pulses[element.label] = PulseState() }
            if element.kind == .counter { state.counters[element.label] = CounterState(preset: element.presetCount) }
            if element.kind == .timer { state.timers[element.label] = TimerState(presetMilliseconds: element.presetMilliseconds) }
        }
        for (label, kinds) in writers where kinds.count > 1 {
            // Allow SET/RESET pairs and one CTU plus RESET; other duplicate writers are ambiguous.
            guard kinds.count == 2 && (Set(kinds) == [.setCoil, .resetCoil] || Set(kinds) == [.counter, .resetCoil]) else { throw SimulationError.duplicateWriter(label) }
        }
        guard !CircuitValidation.issues(in: circuit).contains(where: { $0.severity == .error }) else { throw SimulationError.invalidConnections }
        for element in circuit.elements where !element.kind.isOutput {
            edges[element.position, default: []].append(element)
            if element.kind == .verticalWire { edges[element.end, default: []].append(element) }
        }
        outgoing = edges
        recordSignals()
        try settle()
        recordOutputs()
    }

    public mutating func setInput(_ address: String, pressed: Bool) throws {
        guard address.hasPrefix("X"), state.bits[address] != nil else { throw SimulationError.invalidDevice(address) }
        state.bits[address] = pressed
        recordSignals()
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
            recordSignals()
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

    public mutating func reset() throws {
        self = try LadderSimulator(circuit: circuit)
    }

    private mutating func settle() throws {
        // Relay settling is not an additional PLC scan. A counter may count at most
        // once per input/10 ms step; reset dominates for the entire step.
        // A pulse is a one-step output. Relay settling may discover an edge,
        // but cannot shorten or retrigger that output within the same step.
        for address in state.pulses.keys { state.bits[address] = false }
        recordSignals()
        var firedPulses = Set<String>()
        var counted = Set<String>()
        var resetCounters = Set<String>()
        for _ in 0..<64 {
            let oldBits = state.bits, oldTimers = state.timers, oldCounters = state.counters, oldPulses = state.pulses
            let pulseNodes = poweredNodes()
            for output in outputs where output.kind.isPulse {
                let powered = pulseNodes.contains(output.position)
                var pulse = state.pulses[output.label]!
                let edge = output.kind == .risingPulse ? powered && !pulse.lastInput : !powered && pulse.lastInput
                if edge { firedPulses.insert(output.label) }
                pulse.lastInput = powered
                state.pulses[output.label] = pulse
                state.bits[output.label] = firedPulses.contains(output.label)
            }
            let counterNodes = poweredNodes()
            for output in outputs where output.kind == .resetCoil && output.label.hasPrefix("C") && counterNodes.contains(output.position) {
                resetCounters.insert(output.label)
            }
            for output in outputs where output.kind == .counter {
                let powered = counterNodes.contains(output.position)
                var counter = state.counters[output.label]!
                if resetCounters.contains(output.label) {
                    counter.current = 0; counter.done = false; counter.lastInput = false
                } else {
                    if powered && !counter.lastInput && !counter.done && counted.insert(output.label).inserted {
                        counter.current = min(counter.preset, counter.current + 1)
                        counter.done = counter.current >= counter.preset
                    }
                    counter.lastInput = powered
                }
                state.counters[output.label] = counter
                state.bits[output.label] = counter.done
            }
            for output in outputs {
                let powered = poweredNodes().contains(output.position)
                switch output.kind {
                case .coil: state.bits[output.label] = powered
                case .setCoil: if powered { state.bits[output.label] = true }
                case .resetCoil:
                    if powered && !output.label.hasPrefix("C") { state.bits[output.label] = false }
                case .timer:
                    var timer = state.timers[output.label] ?? TimerState(presetMilliseconds: output.presetMilliseconds)
                    timer.enabled = powered
                    if !powered { timer.elapsedMilliseconds = 0 }
                    state.timers[output.label] = timer
                    state.bits[output.label] = timer.done
                default: break
                }
            }
            recordSignals()
            if oldBits == state.bits && oldTimers == state.timers && oldCounters == state.counters && oldPulses == state.pulses {
                let nodes = poweredNodes()
                state.energizedElements = Set(circuit.elements.filter { element in
                    if element.kind.isPulse { return state[element.label] }
                    if element.kind.isOutput { return nodes.contains(element.position) }
                    return conducting(element) && (nodes.contains(element.position) || (element.kind == .verticalWire && nodes.contains(element.end)))
                }.map(\.id))
                return
            }
        }
        throw SimulationError.unstableLogic
    }

    private mutating func recordSignals() {
        let cutoff = state.historyStartMilliseconds
        for (address, value) in state.bits {
            let timer = state.timers[address]
            let timing = timer.map { $0.enabled && !$0.done } ?? false
            let count = state.counters[address]?.current
            let previous = state.signalHistory[address]?.last
            if previous?.value != value || previous?.timing != timing || previous?.count != count {
                state.signalHistory[address, default: []].append(.init(milliseconds:state.milliseconds,value:value,timing:timing,count:count))
            }
            // Keep one value at/before the retained window as its starting level.
            if let history = state.signalHistory[address], history.count > 1 {
                let before = history.lastIndex { $0.milliseconds < cutoff } ?? 0
                let excess = max(0, history.count - SimulationState.maxTransitionsPerSignal)
                let remove = max(before, excess)
                if remove > 0 { state.signalHistory[address]?.removeFirst(remove) }
            }
        }
    }

    private mutating func recordOutputs() {
        let active = state.bits.keys.filter { $0.hasPrefix("Y") && state[$0] }.sorted()
        guard state.events.last?.activeOutputs != active else { return }
        state.events.append(.init(milliseconds: state.milliseconds, activeOutputs: active))
        if state.events.count > 1_000 { state.events.removeFirst() }
    }
}
