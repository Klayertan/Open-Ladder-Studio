import XCTest
@testable import LadderCore

final class RenriCommentTests: XCTestCase {
    private func text(_ circuit: Circuit) throws -> String {
        try XCTUnwrap(String(data:RenriMBSExporter.export(circuit),encoding:.shiftJIS))
    }
    func testDeviceCommentAndDistinctSymbolNoteAreSeparateRenriLines() throws {
        var doc = ExampleCircuits.setReset
        let index = try XCTUnwrap(doc.elements.firstIndex { $0.label == "X0" && $0.kind == .normallyOpen })
        doc.devices["X0"] = DeviceInfo(comment:"Start button")
        doc.elements[index].comment = "操作盤\n運転開始"
        let exported = try text(doc)
        XCTAssertTrue(exported.contains("0Start　button\\\\操作盤\\\\運転開始\\\\"))
        XCTAssertEqual(doc.elements[index].comment,"操作盤\n運転開始")
        XCTAssertEqual(doc.devices["X0"]?.comment,"Start button")
    }
    func testMatchingNoteAndDeviceDescriptionAreNotDuplicated() throws {
        var doc = ExampleCircuits.setReset
        doc.devices["M0"] = DeviceInfo(comment:"運転保持")
        for i in doc.elements.indices where doc.elements[i].label == "M0" { doc.elements[i].comment = "運転保持" }
        let exported = try text(doc)
        XCTAssertTrue(exported.contains("0運転保持\\\\"))
        XCTAssertFalse(exported.contains("運転保持\\\\運転保持"))
    }
    func testBranchLoweringPreservesContactAndOutputNotesAndDeviceDescriptions() throws {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var doc = try Circuit.decode(Data(contentsOf:root.appendingPathComponent("Examples/09-kai-pedestrian.ladder")))
        let contact = try XCTUnwrap(doc.elements.firstIndex { $0.label == "X001" })
        let output = try XCTUnwrap(doc.elements.firstIndex { $0.kind == .coil && $0.label == "Y004" })
        doc.elements[contact].comment = "北側ボタン"
        doc.elements[output].comment = "青点滅8回"
        let exported = try text(doc)
        for phrase in ["歩道PB1\\\\北側ボタン", "歩道青\\\\青点滅8回", "車道青", "動作中・自己保持", "点滅OFF0.5秒"] {
            XCTAssertTrue(exported.contains(phrase),phrase)
        }
        let normalized = try RenriMBSExporter.loweringBranches(doc)
        XCTAssertTrue(normalized.elements.contains { $0.label == "X001" && $0.comment == "北側ボタン" })
        XCTAssertTrue(normalized.elements.contains { $0.label == "Y004" && $0.comment == "青点滅8回" })
    }
    func testDifferentNotesOnRepeatedBranchAddressAreBothRetained() throws {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var doc = try Circuit.decode(Data(contentsOf:root.appendingPathComponent("Examples/09-kai-pedestrian.ladder")))
        let first = try XCTUnwrap(doc.elements.firstIndex { $0.label == "X001" })
        let second = try XCTUnwrap(doc.elements.firstIndex { $0.label == "X002" })
        doc.elements[first].comment = "北側入力"
        doc.elements[second].label = "X001"
        doc.elements[second].comment = "南側入力"
        let exported = try text(doc)
        XCTAssertTrue(exported.contains("北側入力"))
        XCTAssertTrue(exported.contains("南側入力"))
    }
    func testWhitespaceAndNewlinesExportWithoutBreakingRowRecords() throws {
        var doc = ExampleCircuits.setReset
        doc.devices["X0"] = DeviceInfo(comment:"Start button\r\nOperator\tpanel")
        let exported = try text(doc)
        XCTAssertTrue(exported.contains("0Start　button\\\\Operator　panel\\\\"))
        XCTAssertFalse(exported.contains("Start button"))
        let records = exported.components(separatedBy:"\r\n")
        XCTAssertFalse(records.contains { $0.hasPrefix("Operator") })
        let start = try XCTUnwrap(records.firstIndex { $0.contains("000000FF0") }) + 1
        for row in records.dropFirst(start) where !row.isEmpty && !row.contains("0F0F0F0F0") {
            var cells = 0
            for token in row.split(separator:" ").dropFirst() {
                if token.contains("\\") { cells += 1 }
                else { cells += try XCTUnwrap(Int(token,radix:16)) + 1 }
            }
            XCTAssertEqual(cells,16,"Comment row must align with sixteen instruction cells")
        }
    }
    func testUnrepresentableCharactersAndLiteralDelimiterAreRejected() throws {
        for comment in ["Start 🟢","folder\\note","bad\u{0001}text"] {
            var doc = ExampleCircuits.setReset
            doc.devices["X0"] = DeviceInfo(comment:comment)
            XCTAssertThrowsError(try RenriMBSExporter.export(doc))
        }
    }
}

extension RenriCommentTests {
    private func layouts(_ circuit: Circuit) throws -> [[UInt32]] {
        try text(circuit).components(separatedBy:"\r\n").filter { $0.contains("DDDDDDDDD") }.map { line in
            let parts = line.split(separator:" ")
            let boundary = try XCTUnwrap(parts.firstIndex(of:"DDDDDDDDD"))
            return try parts[1..<boundary].flatMap { token -> [UInt32] in
                let count = try XCTUnwrap(Int(token.prefix(1),radix:16)) + 1
                let word = try XCTUnwrap(UInt32(token.dropFirst(),radix:16))
                return Array(repeating:word,count:count)
            }
        }
    }
    func testCommentedContactAndCoilUseOfficialDisplayWords() throws {
        let elements = [LadderElement(kind:.normallyOpen,position:.init(0,0),label:"X0"),
                        .init(kind:.horizontalWire,position:.init(1,0)),.init(kind:.horizontalWire,position:.init(2,0)),
                        .init(kind:.coil,position:.init(3,0),label:"Y0")]
        let bare = Circuit(columns:4,rows:2,elements:elements)
        var annotated = bare
        annotated.devices["X0"] = DeviceInfo(comment:"始動")
        annotated.devices["Y0"] = DeviceInfo(comment:"出力")
        let plain = try layouts(bare), visible = try layouts(annotated)
        // Actual native words in official sample1.mbs / M5Sample/setrst.MBS.
        XCTAssertEqual(plain[0][0],0x0000801A)
        XCTAssertEqual(visible[0][0],0x0008801A)
        XCTAssertEqual(plain[0][11],0x0000C078)
        XCTAssertEqual(visible[0][11],0x0008C078)
        for index in plain[0].indices {
            XCTAssertEqual(visible[0][index] & ~RenriMBSExporter.commentDisplayFlag,plain[0][index])
        }
    }
    func testDisplayFlagIsAppliedToAllBranchedDevicesAndInstructionKinds() throws {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let circuit = try Circuit.decode(Data(contentsOf:root.appendingPathComponent("Examples/09-kai-pedestrian.ladder")))
        let normalized = try RenriMBSExporter.loweringBranches(circuit)
        let records = try layouts(normalized)
        let outputs = normalized.elements.filter(\.kind.isOutput).sorted { $0.position.row < $1.position.row }
        for (row,output) in outputs.enumerated() {
            let contacts = normalized.elements.filter { $0.position.row == output.position.row && !$0.kind.isOutput && !$0.kind.isWire }.sorted { $0.position.column < $1.position.column }
            for (column,contact) in contacts.enumerated() where !normalized.displayComment(for:contact).isEmpty {
                XCTAssertNotEqual(records[row][column] & RenriMBSExporter.commentDisplayFlag,0,contact.label)
            }
            if !normalized.displayComment(for:output).isEmpty {
                XCTAssertNotEqual(records[row][11] & RenriMBSExporter.commentDisplayFlag,0,output.label)
            }
        }
    }
}
