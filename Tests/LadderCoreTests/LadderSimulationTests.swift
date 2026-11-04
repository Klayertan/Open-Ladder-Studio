import XCTest
@testable import LadderCore

final class LadderSimulationTests: XCTestCase {
    func testTrafficLightExactBoundariesAndRepeat() throws {
        var engine = try LadderSimulator(circuit: ExampleCircuits.trafficLight)
        XCTAssertFalse(engine.state["Y0"])
        try engine.pulseInput("X0")
        XCTAssertTrue(engine.state["Y0"])
        try engine.advance(milliseconds: 9_990)
        XCTAssertTrue(engine.state["Y0"])
        try engine.advance(milliseconds: 10)
        XCTAssertFalse(engine.state["Y0"]); XCTAssertTrue(engine.state["Y1"])
        try engine.advance(milliseconds: 2_000)
        XCTAssertFalse(engine.state["Y1"]); XCTAssertTrue(engine.state["Y2"])
        try engine.advance(milliseconds: 5_000)
        XCTAssertTrue(engine.state["Y0"]); XCTAssertFalse(engine.state["Y2"])
        try engine.advance(milliseconds: 17_000)
        XCTAssertEqual(engine.state.events.filter { !$0.activeOutputs.isEmpty }.map(\.milliseconds), [0, 10_000, 12_000, 17_000, 27_000, 29_000, 34_000])
        XCTAssertTrue(engine.state.events.allSatisfy { $0.activeOutputs.count <= 1 })
    }
    func testStopInEveryPhaseAndRestartFromGreen() throws {
        for time in [500, 10_500, 13_000] {
            var engine = try LadderSimulator(circuit: ExampleCircuits.trafficLight)
            try engine.pulseInput("X0"); try engine.advance(milliseconds: time)
            try engine.pulseInput("X1")
            for output in ["M0", "Y0", "Y1", "Y2"] { XCTAssertFalse(engine.state[output]) }
            XCTAssertTrue(engine.state.timers.values.allSatisfy { !$0.enabled && $0.elapsedMilliseconds == 0 })
            try engine.advance(milliseconds: 20_000)
            XCTAssertFalse(engine.state["Y0"])
            try engine.pulseInput("X0")
            XCTAssertTrue(engine.state["Y0"])
            try engine.advance(milliseconds: 9_990)
            XCTAssertTrue(engine.state["Y0"])
            try engine.advance(milliseconds: 10)
            XCTAssertTrue(engine.state["Y1"])
        }
    }
    func testStopDominatesSimultaneousStartAndStartDoesNotRestartAnActiveCycle() throws {
        var engine = try LadderSimulator(circuit: ExampleCircuits.trafficLight)
        try engine.setInput("X1", pressed: true)
        try engine.setInput("X0", pressed: true)
        XCTAssertFalse(engine.state["M0"])
        try engine.setInput("X0", pressed: false); try engine.setInput("X1", pressed: false)
        try engine.pulseInput("X0"); try engine.advance(milliseconds: 5_000)
        try engine.pulseInput("X0"); try engine.advance(milliseconds: 5_000)
        XCTAssertTrue(engine.state["Y1"])
    }
    func testChunkSizesDoNotChangeTimerBehavior() throws {
        var a = try LadderSimulator(circuit: ExampleCircuits.trafficLight), b = a
        try a.pulseInput("X0"); try b.pulseInput("X0")
        try a.advance(milliseconds: 12_340)
        for _ in 0..<1_234 { try b.advance(milliseconds: 10) }
        XCTAssertEqual(a.state, b.state)
    }
    func testSealInAndSetResetExamplesStillSimulate() throws {
        var seal = try LadderSimulator(circuit: ExampleCircuits.sealIn)
        try seal.pulseInput("X0"); XCTAssertTrue(seal.state["Y0"])
        try seal.pulseInput("X1"); XCTAssertFalse(seal.state["Y0"])
        var latch = try LadderSimulator(circuit: ExampleCircuits.setReset)
        try latch.pulseInput("X0"); XCTAssertTrue(latch.state["M0"])
        try latch.pulseInput("X1"); XCTAssertFalse(latch.state["M0"])
    }
    func testTimerPresetAndJapaneseCommentsSerialize() throws {
        let circuit = ExampleCircuits.trafficLight
        XCTAssertEqual(try Circuit.decode(circuit.encoded()), circuit)
        XCTAssertEqual(circuit.elements.filter { $0.kind == .timer }.map(\.presetMilliseconds), [10_000, 2_000, 5_000])
        XCTAssertTrue(circuit.elements.filter { $0.label.hasPrefix("X") || $0.label.hasPrefix("Y") }.allSatisfy { !circuit.displayComment(for: $0).isEmpty })
        XCTAssertTrue(CircuitValidation.issues(in: circuit).isEmpty)
    }
    func testLegacyVersionOneProjectsMigrate() throws {
        var circuit = ExampleCircuits.sealIn; circuit.version = 1
        let loaded = try Circuit.decode(JSONEncoder().encode(circuit))
        XCTAssertEqual(loaded.version, Circuit.formatVersion)
        XCTAssertEqual(loaded.elements, circuit.elements)
        XCTAssertEqual(loaded.devices, circuit.devices)
    }
    func testDisconnectedAndUnstableProgramsFailExplicitly() throws {
        XCTAssertThrowsError(try LadderSimulator(circuit: Circuit(elements: [.init(kind: .coil, position: .init(2, 0))])))
        var circuit = ExampleCircuits.setReset
        circuit.elements.removeAll { $0.position.row == 2 }
        for i in circuit.elements.indices {
            if circuit.elements[i].kind == .normallyOpen { circuit.elements[i].kind = .normallyClosed; circuit.elements[i].label = "M0" }
            if circuit.elements[i].kind == .setCoil { circuit.elements[i].kind = .coil }
        }
        XCTAssertThrowsError(try LadderSimulator(circuit: circuit))
    }
}
