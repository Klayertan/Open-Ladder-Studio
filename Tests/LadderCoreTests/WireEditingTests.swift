import XCTest
@testable import LadderCore

final class WireEditingTests: XCTestCase {
    func testOrthogonalRoutingBothBendsAndReverseDirection() throws {
        let doc = Circuit(columns:6,rows:6)
        let start = GridPoint(1,1), end = GridPoint(4,4)
        let horizontal = try CircuitEditing.wirePath(from:start,to:end,in:doc)
        XCTAssertEqual(horizontal.count,6)
        XCTAssertEqual(horizontal.filter { $0.kind == .horizontalWire }.map(\.position),[.init(1,1),.init(2,1),.init(3,1)])
        XCTAssertEqual(horizontal.filter { $0.kind == .verticalWire }.map(\.position),[.init(4,1),.init(4,2),.init(4,3)])
        let vertical = try CircuitEditing.wirePath(from:start,to:end,horizontalFirst:false,in:doc)
        XCTAssertEqual(vertical.filter { $0.kind == .verticalWire }.map(\.position),[.init(1,1),.init(1,2),.init(1,3)])
        XCTAssertEqual(vertical.filter { $0.kind == .horizontalWire }.map(\.position),[.init(1,4),.init(2,4),.init(3,4)])
        let reversed = try CircuitEditing.wirePath(from:end,to:start,horizontalFirst:false,in:doc)
        XCTAssertEqual(Set(horizontal.map(\.position)),Set(reversed.map(\.position)))
    }
    func testDrawingReusesWiresAndPreservesContacts() throws {
        let contact = LadderElement(kind:.normallyOpen,position:.init(2,1),label:"X0")
        var doc = Circuit(columns:6,rows:6,elements:[contact])
        doc = try CircuitEditing.connect(from:.init(0,1),to:.init(6,1),in:doc)
        XCTAssertEqual(doc.elements.count,6)
        XCTAssertEqual(doc.elements.first { $0.id == contact.id },contact)
        let again = try CircuitEditing.connect(from:.init(6,1),to:.init(0,1),in:doc)
        XCTAssertEqual(again,doc)
        XCTAssertEqual(try Circuit.decode(doc.encoded()),doc)
        XCTAssertEqual(try CircuitEditing.connect(from:.init(0,1),to:.init(0,5),in:doc),doc)
        XCTAssertThrowsError(try CircuitEditing.connect(from:.init(-1,0),to:.init(2,1),in:doc))
        XCTAssertThrowsError(try CircuitEditing.connect(from:.init(1,0),to:.init(2,6),in:doc))
    }
    func testDropReplacesWireButRejectsOccupiedSymbolAtomically() throws {
        let wire = LadderElement(kind:.horizontalWire,position:.init(2,1))
        let doc = Circuit(elements:[wire])
        let contact = LadderElement(kind:.normallyClosed,position:.init(2,1),label:"C0")
        let placed = try CircuitEditing.place(contact,in:doc)
        XCTAssertEqual(placed.elements,[contact])
        XCTAssertEqual(doc.elements,[wire])
        XCTAssertThrowsError(try CircuitEditing.place(.init(kind:.coil,position:.init(2,1)),in:placed))
        XCTAssertEqual(placed.elements,[contact])
    }
    func testPenDrawnBranchConductsAndSurvivesSerialization() throws {
        var doc = Circuit(columns:4,rows:3)
        doc = try CircuitEditing.connect(from:.init(0,0),to:.init(4,0),in:doc)
        doc = try CircuitEditing.place(.init(kind:.normallyOpen,position:.init(1,0),label:"X0"),in:doc)
        doc = try CircuitEditing.place(.init(kind:.coil,position:.init(3,0),label:"Y0"),in:doc)
        doc = try CircuitEditing.connect(from:.init(1,0),to:.init(1,1),in:doc)
        doc = try CircuitEditing.connect(from:.init(1,1),to:.init(2,1),in:doc)
        doc = try CircuitEditing.connect(from:.init(2,1),to:.init(2,0),in:doc)
        doc = try CircuitEditing.place(.init(kind:.normallyOpen,position:.init(1,1),label:"X1"),in:doc)
        XCTAssertTrue(CircuitValidation.issues(in:doc).isEmpty)
        var sim = try LadderSimulator(circuit:Circuit.decode(doc.encoded()))
        try sim.setInput("X1",pressed:true); XCTAssertTrue(sim.state["Y0"])
        try sim.setInput("X1",pressed:false); XCTAssertFalse(sim.state["Y0"])
    }
}
