import XCTest
@testable import LadderCore

final class CircuitEditingTests: XCTestCase {
    func testInsertAndDelete() throws {
        let element = LadderElement(kind: .normallyOpen, position: .init(1, 0), label: "X0")
        let circuit = try CircuitEditing.insert([element], into: Circuit())
        XCTAssertEqual(circuit.elements, [element])
        XCTAssertTrue(CircuitEditing.remove([element.id], from: circuit).elements.isEmpty)
    }
    func testAllSymbolKindsRoundTrip() throws {
        let elements = SymbolKind.allCases.enumerated().map { index, kind in
            LadderElement(kind: kind, position: .init(1, index))
        }
        let circuit = Circuit(rows: max(10, SymbolKind.allCases.count + 1), elements: elements)
        XCTAssertEqual(try Circuit.decode(circuit.encoded()), circuit)
    }
    func testOverlapRejectedAcrossDifferentHorizontalKinds() throws {
        let contact = LadderElement(kind: .normallyOpen, position: .init(1, 0))
        let original = try CircuitEditing.insert([contact], into: Circuit())
        XCTAssertThrowsError(try CircuitEditing.insert([.init(kind: .horizontalWire, position: .init(1, 0))], into: original)) {
            XCTAssertEqual($0 as? CircuitError, .overlap)
        }
        XCTAssertEqual(original.elements, [contact])
    }
    func testVerticalAndHorizontalCanMeetAtJunction() throws {
        let elements = [LadderElement(kind: .normallyOpen, position: .init(1, 0)),
                        LadderElement(kind: .verticalWire, position: .init(1, 0))]
        XCTAssertEqual(try CircuitEditing.insert(elements, into: Circuit()).elements.count, 2)
    }
    func testGroupMovePreservesRelativePositions() throws {
        let a = LadderElement(kind: .normallyOpen, position: .init(1, 0))
        let b = LadderElement(kind: .normallyClosed, position: .init(2, 0))
        let circuit = Circuit(elements: [a, b])
        let moved = try CircuitEditing.move([a.id, b.id], columns: 2, rows: 3, in: circuit)
        XCTAssertEqual(moved.elements.map(\.position), [.init(3, 3), .init(4, 3)])
        XCTAssertEqual(moved.elements.map(\.id), [a.id, b.id])
    }
    func testMoveCollisionIsAtomic() throws {
        let a = LadderElement(kind: .normallyOpen, position: .init(1, 0))
        let b = LadderElement(kind: .coil, position: .init(2, 0))
        let original = Circuit(elements: [a, b])
        XCTAssertThrowsError(try CircuitEditing.move([a.id], columns: 1, rows: 0, in: original))
        XCTAssertEqual(original.elements.map(\.position), [.init(1, 0), .init(2, 0)])
    }
    func testOutOfBoundsAndRailWiresRejected() throws {
        for e in [LadderElement(kind: .coil, position: .init(-1, 0)),
                  LadderElement(kind: .coil, position: .init(10, 0)),
                  LadderElement(kind: .verticalWire, position: .init(0, 0)),
                  LadderElement(kind: .verticalWire, position: .init(10, 0)),
                  LadderElement(kind: .verticalWire, position: .init(1, 9))] {
            XCTAssertThrowsError(try CircuitEditing.insert([e], into: Circuit()))
        }
    }
    func testBranchAddsExplicitTopologyAndReusesWires() throws {
        let circuit = try CircuitEditing.branch(from: .init(1, 0), width: 2, in: Circuit())
        XCTAssertEqual(circuit.elements.count, 4)
        XCTAssertEqual(circuit.elements.filter { $0.kind == .verticalWire }.count, 2)
        let repeated = try CircuitEditing.branch(from: .init(1, 0), width: 2, in: circuit)
        XCTAssertEqual(repeated, circuit)
    }
    func testBranchCollisionRejectsWholeBranch() throws {
        let contact = LadderElement(kind: .normallyOpen, position: .init(2, 1))
        let circuit = Circuit(elements: [contact])
        XCTAssertThrowsError(try CircuitEditing.branch(from: .init(1, 0), width: 2, in: circuit))
        XCTAssertEqual(circuit.elements, [contact])
    }
    func testPasteRegeneratesIDsAndPreservesTopology() throws {
        let source = ExampleCircuits.sealIn.elements.filter { $0.position.column == 1 }
        let (pasted, ids) = try CircuitEditing.paste(source, at: .init(3, 4), into: Circuit())
        XCTAssertTrue(ids.isDisjoint(with: Set(source.map(\.id))))
        XCTAssertEqual(pasted.elements.map(\.position), source.map { $0.position.offset(columns: 2, rows: 4) })
        XCTAssertEqual(pasted.elements.map(\.label), source.map(\.label))
    }
    func testPasteCollisionAndEmptyPayloadRejected() throws {
        let e = LadderElement(kind: .normallyOpen, position: .init(1, 0))
        XCTAssertThrowsError(try CircuitEditing.paste([e], at: .init(1, 0), into: Circuit(elements: [e])))
        XCTAssertThrowsError(try CircuitEditing.paste([], at: .init(1, 0), into: Circuit()))
    }
    func testLabelsNormalizeAndCommentsRoundTrip() throws {
        let e = LadderElement(kind: .normallyOpen, position: .init(1, 0))
        let updated = try CircuitEditing.update(e.id, label: "  m10 ", comment: "起動ボタン", in: Circuit(elements: [e]))
        XCTAssertEqual(updated.elements[0].label, "M10")
        XCTAssertEqual(try Circuit.decode(updated.encoded()).elements[0].comment, "起動ボタン")
        XCTAssertThrowsError(try CircuitEditing.update(e.id, label: "1 bad", comment: "", in: updated))
    }
    func testDecoderRejectsUnsupportedVersionAndDuplicateIDs() throws {
        var circuit = Circuit(); circuit.version = 99
        XCTAssertThrowsError(try Circuit.decode(JSONEncoder().encode(circuit)))
        let e = LadderElement(kind: .normallyOpen, position: .init(1, 0))
        var copy = e; copy.position = .init(2, 0)
        circuit = Circuit(elements: [e, copy])
        XCTAssertThrowsError(try Circuit.decode(JSONEncoder().encode(circuit)))
    }
    func testDecoderRejectsInvalidDimensionsAndOverlap() throws {
        XCTAssertThrowsError(try Circuit.decode(JSONEncoder().encode(Circuit(columns: 0))))
        let e = LadderElement(kind: .normallyOpen, position: .init(1, 0))
        let duplicate = LadderElement(kind: .normallyClosed, position: .init(1, 0))
        XCTAssertThrowsError(try Circuit.decode(JSONEncoder().encode(Circuit(elements: [e, duplicate]))))
    }
    func testExampleCircuitsPassValidation() throws {
        for circuit in [ExampleCircuits.sealIn, ExampleCircuits.setReset] {
            XCTAssertNoThrow(try circuit.checked())
            XCTAssertTrue(CircuitValidation.issues(in: circuit).isEmpty)
        }
    }
    func testDisconnectedAndDanglingTerminalsDetected() {
        let e = LadderElement(kind: .normallyOpen, position: .init(2, 2))
        let keys = Set(CircuitValidation.issues(in: Circuit(elements: [e])).map(\.key))
        XCTAssertTrue(keys.contains("validation.disconnected"))
        XCTAssertTrue(keys.contains("validation.dangling"))
    }
    func testRailShortCircuitDetected() {
        let wires = (0..<10).map { LadderElement(kind: .horizontalWire, position: .init($0, 0)) }
        XCTAssertTrue(CircuitValidation.issues(in: Circuit(elements: wires)).contains { $0.key == "validation.shortCircuit" })
    }
    func testBrokenBranchDetectedEvenWithCompleteMainRung() {
        var circuit = ExampleCircuits.sealIn
        circuit.elements.removeAll { $0.kind == .verticalWire && $0.position.column == 2 }
        XCTAssertTrue(CircuitValidation.issues(in: circuit).contains { $0.key == "validation.dangling" })
    }
    func testOutputPlacementWarning() {
        let e = LadderElement(kind: .coil, position: .init(1, 0))
        XCTAssertTrue(CircuitValidation.issues(in: Circuit(elements: [e])).contains { $0.key == "validation.outputPosition" && $0.severity == .warning })
    }
    func testNativeImporter() throws {
        let native = NativeJSONImporter()
        let example = ExampleCircuits.sealIn
        XCTAssertEqual(try native.importCircuit(from: example.encoded()), example)
    }
    func testRenriImportFailsExplicitly() {
        XCTAssertThrowsError(try RenriImporter().importCircuit(from: Data())) {
            XCTAssertEqual($0 as? CircuitError, .unsupportedImporter)
        }
    }
    func testMalformedClipboardCoordinatesDoNotOverflow() {
        let e = LadderElement(kind: .normallyOpen, position: .init(Int.min, Int.max))
        XCTAssertThrowsError(try CircuitEditing.paste([e], at: .init(1, 0), into: Circuit()))
        XCTAssertThrowsError(try CircuitEditing.branch(from: .init(Int.max, 0), width: Int.max, in: Circuit()))
    }
}
