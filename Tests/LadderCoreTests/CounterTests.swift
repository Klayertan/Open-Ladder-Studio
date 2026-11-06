import XCTest
@testable import LadderCore

final class CounterTests: XCTestCase {
    private func circuit(_ rungs: [([(SymbolKind, String)], SymbolKind, String, Int)]) -> Circuit {
        var elements: [LadderElement] = []
        for (row, rung) in rungs.enumerated() {
            for col in 0..<6 {
                if col == 5 {
                    elements.append(.init(kind: rung.1, position: .init(col, row), label: rung.2,
                                          timerPresetMilliseconds: rung.1 == .timer ? rung.3 : nil,
                                          counterPreset: rung.1 == .counter ? rung.3 : nil))
                } else if col < rung.0.count {
                    elements.append(.init(kind: rung.0[col].0, position: .init(col, row), label: rung.0[col].1))
                } else { elements.append(.init(kind: .horizontalWire, position: .init(col, row))) }
            }
        }
        return Circuit(columns: 6, rows: max(2, rungs.count), elements: elements)
    }
    private var basic: Circuit {
        circuit([([(.normallyOpen,"X0")], .counter,"C0",8),
                 ([(.normallyOpen,"C0")], .coil,"Y0",0),
                 ([(.normallyClosed,"C0")], .coil,"Y1",0),
                 ([(.normallyOpen,"X1")], .resetCoil,"C0",0)])
    }
    func testEdgesHoldingEightPulsesCompletionAndContacts() throws {
        var sim = try LadderSimulator(circuit: basic)
        XCTAssertTrue(sim.state["Y1"])
        for count in 1...8 {
            try sim.setInput("X0", pressed: true)
            XCTAssertEqual(sim.state.counters["C0"]?.current, count)
            try sim.advance(milliseconds: 100)
            XCTAssertEqual(sim.state.counters["C0"]?.current, count)
            try sim.setInput("X0", pressed: false)
        }
        XCTAssertTrue(sim.state["C0"]); XCTAssertTrue(sim.state["Y0"]); XCTAssertFalse(sim.state["Y1"])
        try sim.pulseInput("X0"); try sim.advance(milliseconds: 100)
        XCTAssertEqual(sim.state.counters["C0"]?.current,8)
        XCTAssertTrue(sim.state["C0"])
    }
    func testResetDominatesAndRearmsHeldInput() throws {
        var sim = try LadderSimulator(circuit: basic)
        try sim.setInput("X0", pressed: true)
        try sim.setInput("X1", pressed: true)
        try sim.advance(milliseconds: 100)
        XCTAssertEqual(sim.state.counters["C0"]?.current,0)
        XCTAssertFalse(sim.state["C0"])
        XCTAssertFalse(try XCTUnwrap(sim.state.counters["C0"]).lastInput)
        try sim.setInput("X1", pressed: false)
        XCTAssertEqual(sim.state.counters["C0"]?.current,1)
        try sim.reset()
        XCTAssertEqual(sim.state.counters["C0"]?.current,0)
        XCTAssertEqual(sim.state.milliseconds,0)
        XCTAssertFalse(sim.state["X0"])
    }
    func testMultipleIndependentCountersAndSerialization() throws {
        let doc = circuit([([(.normallyOpen,"X0")], .counter,"C0",8), ([(.normallyOpen,"X1")], .counter,"C1",2)])
        XCTAssertEqual(try Circuit.decode(doc.encoded()),doc)
        var sim = try LadderSimulator(circuit: Circuit.decode(doc.encoded()))
        try sim.pulseInput("X0"); try sim.pulseInput("X1"); try sim.pulseInput("X1")
        XCTAssertEqual(sim.state.counters["C0"]?.current,1)
        XCTAssertFalse(sim.state["C0"]); XCTAssertTrue(sim.state["C1"])
        let fresh = try LadderSimulator(circuit: doc)
        XCTAssertEqual(fresh.state.counters["C1"]?.current,0)
    }
    func testInvalidAddressesPresetsAndDuplicateWriters() throws {
        for address in ["C", "C-1", "X0"] {
            var doc = basic; doc.elements[5].label = address
            XCTAssertThrowsError(try LadderSimulator(circuit: doc)) { error in
                guard case SimulationError.invalidDevice(let rejected) = error else { return XCTFail("Expected invalid device: \(error)") }
                XCTAssertEqual(rejected,address)
            }
        }
        var doc = basic; doc.elements[5].counterPreset = 0
        XCTAssertThrowsError(try doc.encoded())
        doc = circuit([([(.normallyOpen,"X0")], .counter,"C0",8), ([(.normallyOpen,"X1")], .counter,"C0",2)])
        XCTAssertThrowsError(try LadderSimulator(circuit: doc))
    }
    private func blinking(reversed: Bool = false) -> Circuit {
        // M0 and T3 are driven by X0 here to isolate the supplied five-rung circuit.
        var rungs: [([(SymbolKind,String)],SymbolKind,String,Int)] = [
            ([(.normallyOpen,"X0")], .coil,"M0",0),
            ([(.normallyOpen,"M0")], .timer,"T3",12000),
            ([(.normallyOpen,"T3"),(.normallyClosed,"T5"),(.normallyClosed,"C0")], .timer,"T4",500),
            ([(.normallyOpen,"T4"),(.normallyClosed,"C0")], .timer,"T5",500),
            ([(.normallyOpen,"T5")], .counter,"C0",8),
            ([(.normallyOpen,"C0")], .timer,"T6",3000),
            ([(.normallyClosed,"M0")], .resetCoil,"C0",0)]
        if reversed { rungs.reverse() }
        return circuit(rungs)
    }
    func testEightFlashTimerFeedbackAndRungOrder() throws {
        for reversed in [false,true] {
            var sim = try LadderSimulator(circuit: blinking(reversed: reversed))
            try sim.setInput("X0", pressed:true)
            try sim.advance(milliseconds:12000)
            var events: [Int] = []
            var previous = 0
            for _ in 0..<1100 {
                try sim.advance(milliseconds:10)
                let current = try XCTUnwrap(sim.state.counters["C0"]).current
                if current != previous { events.append(sim.state.milliseconds); XCTAssertEqual(current,previous+1) }
                previous = current
            }
            XCTAssertEqual(events,[13000,14000,15000,16000,17000,18000,19000,20000])
            XCTAssertTrue(sim.state["C0"]); XCTAssertTrue(sim.state["T6"])
            XCTAssertEqual(sim.state.timers["T6"]?.elapsedMilliseconds,3000)
            try sim.setInput("X0", pressed:false)
            XCTAssertEqual(sim.state.counters["C0"]?.current,0)
            XCTAssertFalse(sim.state["T6"])
            try sim.setInput("X0", pressed:true)
            try sim.advance(milliseconds:13000)
            XCTAssertEqual(sim.state.counters["C0"]?.current,1)
        }
    }
    func testFractionalTimerPresetsAndChunkSizes() throws {
        let doc = blinking()
        XCTAssertEqual(try Circuit.decode(doc.encoded()),doc)
        var a = try LadderSimulator(circuit: doc), b = a
        try a.setInput("X0",pressed:true); try b.setInput("X0",pressed:true)
        try a.advance(milliseconds:23000)
        for _ in 0..<4600 { try b.advance(milliseconds:5) }
        XCTAssertEqual(a.state,b.state)
        for preset in [500,2000,3000,5000,12000] {
            let timer = circuit([([(.normallyOpen,"X0")],.timer,"T0",preset)])
            var sim = try LadderSimulator(circuit: Circuit.decode(timer.encoded()))
            try sim.setInput("X0",pressed:true)
            try sim.advance(milliseconds:preset-10); XCTAssertFalse(sim.state["T0"])
            try sim.advance(milliseconds:10); XCTAssertTrue(sim.state["T0"])
        }
    }
}

extension CounterTests {
    func testFullPedestrianSequenceEightVisibleFlashesStopAndRestart() throws {
        var sim = try LadderSimulator(circuit: ExampleCircuits.pedestrianCrossing)
        try sim.pulseInput("X0")
        try sim.advance(milliseconds:22000)
        XCTAssertTrue(sim.state["T3"])
        XCTAssertTrue(sim.state["Y4"])
        for count in 0..<8 {
            XCTAssertTrue(sim.state["Y4"])
            try sim.advance(milliseconds:500)
            XCTAssertFalse(sim.state["Y4"])
            try sim.advance(milliseconds:500)
            XCTAssertEqual(sim.state.counters["C0"]?.current,count+1)
        }
        XCTAssertTrue(sim.state["C0"]); XCTAssertFalse(sim.state["Y4"])
        try sim.advance(milliseconds:2990); XCTAssertFalse(sim.state["Y5"])
        try sim.advance(milliseconds:10); XCTAssertTrue(sim.state["Y5"])
        try sim.pulseInput("X1")
        XCTAssertEqual(sim.state.counters["C0"]?.current,0)
        XCTAssertTrue(sim.state.timers.values.allSatisfy { !$0.enabled && $0.elapsedMilliseconds == 0 })
        try sim.pulseInput("X0"); try sim.advance(milliseconds:23000)
        XCTAssertEqual(sim.state.counters["C0"]?.current,1)
    }
    func testCounterPoweredByParallelBranch() throws {
        var doc = circuit([([(.normallyOpen,"X0")],.counter,"C0",8)])
        // Bypass X0 at column 1 so a branch can attach away from the rail.
        doc.elements[0] = .init(kind:.horizontalWire,position:.init(0,0))
        doc.elements[1] = .init(kind:.normallyOpen,position:.init(1,0),label:"X0")
        doc = try CircuitEditing.branch(from:.init(1,0),width:1,in:doc)
        let lower = try XCTUnwrap(doc.elements.firstIndex { $0.position == .init(1,1) && $0.kind == .horizontalWire })
        doc.elements[lower].kind = .normallyOpen; doc.elements[lower].label = "X1"
        var sim = try LadderSimulator(circuit:doc)
        try sim.setInput("X1",pressed:true)
        try sim.setInput("X0",pressed:true)
        XCTAssertEqual(sim.state.counters["C0"]?.current,1)
        try sim.setInput("X1",pressed:false); try sim.setInput("X0",pressed:false)
        try sim.pulseInput("X0")
        XCTAssertEqual(sim.state.counters["C0"]?.current,2)
    }
}
