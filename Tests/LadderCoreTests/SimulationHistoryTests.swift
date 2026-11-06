import XCTest
@testable import LadderCore

final class SimulationHistoryTests: XCTestCase {
    private func worksheet() throws -> Circuit {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Circuit.decode(Data(contentsOf:root.appendingPathComponent("Examples/09-kai-pedestrian.ladder")))
    }
    func testAllDevicesAndSameTimestampMomentaryInputAreRecorded() throws {
        let doc = try worksheet()
        var sim = try LadderSimulator(circuit:doc)
        XCTAssertEqual(Set(sim.state.signalHistory.keys),Set(doc.addresses))
        try sim.pulseInput("X001")
        let input = try XCTUnwrap(sim.state.signalHistory["X001"])
        XCTAssertEqual(input.map(\.value),[false,true,false])
        XCTAssertEqual(input.map(\.milliseconds),[0,0,0])
        XCTAssertTrue(sim.state.signalHistory["M0"]?.last?.value ?? false)
        XCTAssertTrue(sim.state.signalHistory["T0"]?.last?.timing ?? false)
    }
    func testFullCycleRecordsEightFlashesCountEventsAndTimerFeedbackPulses() throws {
        var sim = try LadderSimulator(circuit:worksheet())
        try sim.pulseInput("X001")
        try sim.advance(milliseconds:33000)
        let green = try XCTUnwrap(sim.state.signalHistory["Y004"])
        XCTAssertEqual(green.filter { $0.value }.map(\.milliseconds),[10000,22500,23500,24500,25500,26500,27500,28500,29500])
        let timer = try XCTUnwrap(sim.state.signalHistory["T5"])
        XCTAssertEqual(timer.filter(\.value).map(\.milliseconds),[23000,24000,25000,26000,27000,28000,29000,30000])
        XCTAssertTrue(timer.contains { $0.timing })
        let counter = try XCTUnwrap(sim.state.signalHistory["C0"])
        XCTAssertEqual(counter.compactMap(\.count),[0,1,2,3,4,5,6,7,8,0])
        XCTAssertEqual(counter.filter(\.value).map(\.milliseconds),[30000])
        XCTAssertEqual(counter.last?.milliseconds,33000)
        XCTAssertEqual(sim.state.signalHistory["T6"]?.filter(\.value).map(\.milliseconds),[33000])
    }
    func testHistoryResetsAndDoesNotEnterSavedDocument() throws {
        let doc = try worksheet()
        var sim = try LadderSimulator(circuit:doc)
        try sim.pulseInput("X001"); try sim.advance(milliseconds:24000)
        try sim.reset()
        XCTAssertEqual(sim.state.milliseconds,0)
        XCTAssertFalse(sim.state.signalHistory["X001"]?.contains { $0.value } ?? true)
        XCTAssertEqual(sim.state.signalHistory["C0"]?.last?.count,0)
        let encoded = try doc.encoded()
        XCTAssertFalse(String(decoding:encoded,as:UTF8.self).contains("signalHistory"))
        XCTAssertEqual(try Circuit.decode(encoded),doc)
    }
    func testRetentionKeepsStartingLevelAndBoundsHighFrequencyInputs() throws {
        let elements = [LadderElement(kind:.normallyOpen,position:.init(0,0),label:"X0"),
                        .init(kind:.horizontalWire,position:.init(1,0)),.init(kind:.horizontalWire,position:.init(2,0)),
                        .init(kind:.coil,position:.init(3,0),label:"Y0")]
        var sim = try LadderSimulator(circuit:Circuit(columns:4,rows:2,elements:elements))
        for _ in 0..<2200 { try sim.pulseInput("X0") }
        XCTAssertLessThanOrEqual(sim.state.signalHistory["X0"]?.count ?? .max,SimulationState.maxTransitionsPerSignal)
        try sim.setInput("X0",pressed:true)
        try sim.advance(milliseconds:121000)
        XCTAssertEqual(sim.state.historyStartMilliseconds,1000)
        XCTAssertTrue(sim.state.signalHistory["X0"]?.last?.value ?? false)
        XCTAssertLessThanOrEqual(sim.state.signalHistory["X0"]?.count ?? .max,2)
    }
}
