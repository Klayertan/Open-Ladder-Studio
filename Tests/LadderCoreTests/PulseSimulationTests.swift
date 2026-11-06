import XCTest
@testable import LadderCore

final class PulseSimulationTests: XCTestCase {
    private func circuit(reversed: Bool = false) -> Circuit {
        var rungs: [(String,SymbolKind,String)] = [("X0",.risingPulse,"M0"),("X0",.fallingPulse,"M1"),("M0",.counter,"C0"),("M1",.counter,"C1")]
        if reversed { rungs.reverse() }
        let elements = rungs.enumerated().flatMap { row, rung in
            [LadderElement(kind:.normallyOpen,position:.init(0,row),label:rung.0),
             .init(kind:.horizontalWire,position:.init(1,row)),
             .init(kind:.horizontalWire,position:.init(2,row)),
             .init(kind:rung.1,position:.init(3,row),label:rung.2,counterPreset:rung.1 == .counter ? 8 : nil)]
        }
        return Circuit(columns:4,rows:4,elements:elements)
    }
    func testPulseIsOneStepAndHeldInputsDoNotRetrigger() throws {
        for reversed in [false,true] {
            var sim = try LadderSimulator(circuit:circuit(reversed:reversed))
            XCTAssertFalse(sim.state["M0"]); XCTAssertFalse(sim.state["M1"])
            for count in 1...8 {
                try sim.setInput("X0",pressed:true)
                XCTAssertTrue(sim.state["M0"]); XCTAssertFalse(sim.state["M1"])
                XCTAssertEqual(sim.state.counters["C0"]?.current,count)
                try sim.advance(milliseconds:10)
                XCTAssertFalse(sim.state["M0"])
                try sim.advance(milliseconds:100)
                XCTAssertEqual(sim.state.counters["C0"]?.current,count)
                try sim.setInput("X0",pressed:false)
                XCTAssertFalse(sim.state["M0"]); XCTAssertTrue(sim.state["M1"])
                XCTAssertEqual(sim.state.counters["C1"]?.current,count)
                try sim.advance(milliseconds:10)
                XCTAssertFalse(sim.state["M1"])
            }
            XCTAssertTrue(sim.state["C0"]); XCTAssertTrue(sim.state["C1"])
        }
    }
    func testPulseRuntimeResetsAndConfigurationSerializes() throws {
        let doc = circuit()
        XCTAssertEqual(try Circuit.decode(doc.encoded()),doc)
        var sim = try LadderSimulator(circuit:doc)
        try sim.setInput("X0",pressed:true)
        try sim.reset()
        XCTAssertFalse(sim.state["M0"]); XCTAssertFalse(sim.state["M1"])
        XCTAssertFalse(sim.state.pulses["M0"]?.lastInput ?? true)
        try sim.setInput("X0",pressed:true)
        XCTAssertTrue(sim.state["M0"])
        XCTAssertEqual(sim.state.counters["C0"]?.current,1)
    }
    func testPulseChunkSizesAreDeterministic() throws {
        var a = try LadderSimulator(circuit:circuit()), b = a
        try a.setInput("X0",pressed:true); try b.setInput("X0",pressed:true)
        try a.advance(milliseconds:100)
        for _ in 0..<100 { try b.advance(milliseconds:1) }
        XCTAssertEqual(a.state,b.state)
    }
}
