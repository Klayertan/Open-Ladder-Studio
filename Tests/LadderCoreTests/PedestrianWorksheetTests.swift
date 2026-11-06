import XCTest
@testable import LadderCore

final class PedestrianWorksheetTests: XCTestCase {
    private func fixture() throws -> Circuit {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Circuit.decode(Data(contentsOf:root.appendingPathComponent("Examples/09-kai-pedestrian.ladder")))
    }
    func testWorksheetTimelineEightFlashesAndAutomaticReturnForEitherButton() throws {
        let doc = try fixture()
        XCTAssertTrue(CircuitValidation.issues(in:doc).isEmpty)
        XCTAssertEqual(doc.elements.filter { $0.kind == .timer }.map(\.presetMilliseconds),[5000,2000,3000,12000,500,500,3000])
        for button in ["X001","X002"] {
            var sim = try LadderSimulator(circuit:doc)
            XCTAssertTrue(sim.state["Y000"]); XCTAssertTrue(sim.state["Y003"])
            try sim.pulseInput(button)
            var previousCount = 0, previousGreen = false
            var counts: [Int] = [], flashStarts: [Int] = []
            for _ in 0..<3300 {
                try sim.advance(milliseconds:10)
                let time = sim.state.milliseconds
                let count = try XCTUnwrap(sim.state.counters["C0"]).current
                if count > previousCount { counts.append(time) }
                if sim.state["Y004"] && !previousGreen && time > 22000 { flashStarts.append(time) }
                previousCount = count; previousGreen = sim.state["Y004"]
                XCTAssertFalse(sim.state["Y000"] && sim.state["Y002"])
                XCTAssertFalse(sim.state["Y003"] && sim.state["Y004"])
                if time == 5000 { XCTAssertTrue(sim.state["Y001"]); XCTAssertFalse(sim.state["Y000"]) }
                if time == 7000 { XCTAssertTrue(sim.state["Y002"]); XCTAssertFalse(sim.state["Y001"]) }
                if time == 10000 { XCTAssertTrue(sim.state["Y004"]); XCTAssertFalse(sim.state["Y003"]) }
                if time == 30000 { XCTAssertTrue(sim.state["Y003"]); XCTAssertFalse(sim.state["Y004"]); XCTAssertTrue(sim.state["C0"]) }
            }
            XCTAssertEqual(counts,[23000,24000,25000,26000,27000,28000,29000,30000])
            XCTAssertEqual(flashStarts,[22500,23500,24500,25500,26500,27500,28500,29500])
            XCTAssertFalse(sim.state["M0"])
            XCTAssertTrue(sim.state["Y000"]); XCTAssertTrue(sim.state["Y003"])
            XCTAssertFalse(sim.state["Y001"]); XCTAssertFalse(sim.state["Y002"]); XCTAssertFalse(sim.state["Y004"])
            XCTAssertEqual(sim.state.counters["C0"]?.current,0)
            try sim.advance(milliseconds:40000)
            XCTAssertTrue(sim.state["Y000"]); XCTAssertFalse(sim.state["M0"])
        }
    }
    func testBranchLoweringMatchesOriginalCircuitAtEveryStep() throws {
        let doc = try fixture(), normalized = try RenriMBSExporter.loweringBranches(doc)
        XCTAssertTrue(normalized.elements.allSatisfy { $0.kind != .verticalWire })
        XCTAssertEqual(try Circuit.decode(normalized.encoded()),normalized)
        XCTAssertNoThrow(try RenriMBSExporter.export(doc,fileName:"09KAI.MBS"))
        var original = try LadderSimulator(circuit:doc), lowered = try LadderSimulator(circuit:normalized)
        try original.pulseInput("X001"); try lowered.pulseInput("X001")
        for _ in 0..<3300 {
            try original.advance(milliseconds:10); try lowered.advance(milliseconds:10)
            for address in doc.addresses {
                XCTAssertEqual(original.state[address],lowered.state[address],"\(address) at \(original.state.milliseconds)")
            }
            XCTAssertEqual(original.state.counters,lowered.state.counters)
        }
    }
    func testLongSeriesExpressionLowersWithoutChangingItsMeaning() throws {
        var elements: [LadderElement] = []
        for column in 0..<12 {
            elements.append(.init(kind:column == 11 ? .coil : .normallyOpen,position:.init(column,0),label:column == 11 ? "Y0" : "X\(column)"))
        }
        let doc = Circuit(columns:12,elements:elements)
        XCTAssertNoThrow(try RenriMBSExporter.export(doc))
        var sim = try LadderSimulator(circuit:RenriMBSExporter.loweringBranches(doc))
        for index in 0..<11 { try sim.setInput("X\(index)",pressed:true) }
        XCTAssertTrue(sim.state["Y0"])
        try sim.setInput("X5",pressed:false); XCTAssertFalse(sim.state["Y0"])
    }
}
