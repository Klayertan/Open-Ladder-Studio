import XCTest
@testable import LadderCore

final class RenriMBSExportTests: XCTestCase {
    private func expanded(_ tokens: [Substring]) throws -> [UInt32] {
        var result: [UInt32] = []
        for token in tokens {
            let count = try XCTUnwrap(Int(token.prefix(1), radix: 16)) + 1
            let value = try XCTUnwrap(UInt32(token.dropFirst(), radix: 16))
            result += Array(repeating: value, count: count)
        }
        return result
    }
    func testTrafficExportUsesRealHeaderAndSixteenCellRecordStreams() throws {
        let data = try RenriMBSExporter.export(ExampleCircuits.trafficLight)
        let text = try XCTUnwrap(String(data: data, encoding: .shiftJIS))
        XCTAssertTrue(text.hasPrefix("mbs-file 3winv.1\r\nKADAI10.MBS\r\n"))
        XCTAssertFalse(text.hasPrefix("{"))
        let lines = text.components(separatedBy: "\r\n")
        let rows = lines.filter { $0.contains("DDDDDDDDD") }
        XCTAssertEqual(rows.count, 9) // Seven rungs, one holding branch, END.
        for row in rows {
            let parts = row.split(separator: " ")
            let split = try XCTUnwrap(parts.firstIndex(of: "DDDDDDDDD"))
            XCTAssertEqual(try expanded(Array(parts[1..<split])).count, 16)
            XCTAssertEqual(try expanded(Array(parts[(split + 1)...])).count, 16)
        }
        for phrase in ["スタートPB", "点滅停止PB", "青ランプ（10秒）", "黄ランプ（2秒）", "赤ランプ（5秒）"] { XCTAssertTrue(text.contains(phrase)) }
        XCTAssertFalse(RenriMBSExporter.compatibilityVerifiedInRenri)
    }
    func testHoldingBranchMatchesOfficialSampleTopologyAndDeviceTypes() throws {
        let text = try XCTUnwrap(String(data: RenriMBSExporter.export(ExampleCircuits.trafficLight), encoding: .shiftJIS))
        let lines = text.components(separatedBy: "\r\n").filter { $0.contains("DDDDDDDDD") }
        let first = lines[0].split(separator: " ")
        let boundary = try XCTUnwrap(first.firstIndex(of: "DDDDDDDDD"))
        let layout = try expanded(Array(first[1..<boundary]))
        let values = try expanded(Array(first[(boundary + 1)...]))
        XCTAssertEqual(Array(layout.prefix(2)), [0x0008805A, 0x00088068])
        XCTAssertEqual(values[0], 0) // X0
        XCTAssertEqual(values[1], 1) // X1
        XCTAssertEqual(values[11], 0x20000000) // M0
        let second = lines[1].split(separator: " ")
        let split = try XCTUnwrap(second.firstIndex(of: "DDDDDDDDD"))
        XCTAssertEqual(Array(try expanded(Array(second[1..<split])).prefix(2)), [0x0008801A, 2])
    }
    func testTimersEncodePackedDecimalHundredMillisecondPresets() throws {
        let text = try XCTUnwrap(String(data: RenriMBSExporter.export(ExampleCircuits.trafficLight), encoding: .shiftJIS))
        let lines = text.components(separatedBy: "\r\n").filter { $0.contains("DDDDDDDDD") }
        for (index, preset) in [UInt32(0x100), 0x20, 0x50].enumerated() {
            let parts = lines[index + 2].split(separator: " ")
            let split = try XCTUnwrap(parts.firstIndex(of: "DDDDDDDDD"))
            let layout = try expanded(Array(parts[1..<split]))
            let values = try expanded(Array(parts[(split + 1)...]))
            XCTAssertEqual(Array(layout[10...12]), [0x00020008, 0x0029C088, 0x35])
            XCTAssertEqual(values[11], 0x40000000 + UInt32(index))
            XCTAssertEqual(values[12], preset)
        }
    }
    func testUnsupportedTopologiesAndTimingAreRejected() throws {
        XCTAssertNoThrow(try RenriMBSExporter.export(ExampleCircuits.setReset))
        var circuit = ExampleCircuits.trafficLight
        let timer = try XCTUnwrap(circuit.elements.firstIndex { $0.kind == .timer })
        circuit.elements[timer].timerPresetMilliseconds = 1_234
        XCTAssertThrowsError(try RenriMBSExporter.export(circuit))
        circuit = ExampleCircuits.trafficLight
        let contact = try XCTUnwrap(circuit.elements.firstIndex { $0.kind == .normallyOpen })
        circuit.elements[contact].comment = "emoji 🟢"
        XCTAssertThrowsError(try RenriMBSExporter.export(circuit))
    }
}

extension RenriMBSExportTests {
    func testPedestrianCounterResetContactsAndFractionalTimersExport() throws {
        let doc = ExampleCircuits.pedestrianCrossing
        let text = try XCTUnwrap(String(data: RenriMBSExporter.export(doc,fileName:"PEDESTRIAN.MBS"),encoding:.shiftJIS))
        let rows = text.components(separatedBy:"\r\n").filter { $0.contains("DDDDDDDDD") }
        var layouts: [[UInt32]] = [], data: [[UInt32]] = []
        for row in rows {
            let parts = row.split(separator:" ")
            let boundary = try XCTUnwrap(parts.firstIndex(of:"DDDDDDDDD"))
            layouts.append(try expanded(Array(parts[1..<boundary])))
            data.append(try expanded(Array(parts[(boundary+1)...])))
            XCTAssertEqual(layouts.last?.count,16); XCTAssertEqual(data.last?.count,16)
        }
        // Exact instruction words from official ESP32sample/cnt.MBS rows 7/8.
        XCTAssertEqual(Array(layouts[8][10...12]),[0x00020008,0x0021C098,0x36])
        XCTAssertEqual(data[8][11],0x50000000); XCTAssertEqual(data[8][12],8)
        XCTAssertEqual(Array(layouts[10][10...12]),[0x00040C08,0x0004C408,0x1F])
        XCTAssertEqual(data[10][11],0x50000000)
        XCTAssertEqual(layouts[6][2],0x00008028) // NC C0
        XCTAssertEqual(data[6][2],0x50000000)
        XCTAssertEqual(data[9][0],0x50000000) // NO C0
        XCTAssertEqual(layouts[9][0],0x0000801A)
        for (row,preset) in [(2,UInt32(0x50)),(3,0x20),(4,0x30),(5,0x120),(6,5),(7,5),(9,0x30)] {
            XCTAssertEqual(data[row][12],preset)
        }
        XCTAssertEqual(Array(layouts[0][10...12]),[0x00040C08,0x0004C408,0x1C])
        XCTAssertEqual(rows.count,18)
    }
}

extension RenriMBSExportTests {
    func testPulseOutputsMatchOfficialPLSAndPLFOpcodes() throws {
        let elements = [SymbolKind.risingPulse,.fallingPulse].enumerated().flatMap { row, kind in
            [LadderElement(kind:.normallyOpen,position:.init(0,row),label:"X\(row)"),
             .init(kind:.horizontalWire,position:.init(1,row)),.init(kind:.horizontalWire,position:.init(2,row)),
             .init(kind:kind,position:.init(3,row),label:"M\(row)")]
        }
        let text = try XCTUnwrap(String(data:RenriMBSExporter.export(Circuit(columns:4,rows:2,elements:elements)),encoding:.shiftJIS))
        let rows = text.components(separatedBy:"\r\n").filter { $0.contains("DDDDDDDDD") }
        for index in 0..<2 {
            let parts = rows[index].split(separator:" ")
            let boundary = try XCTUnwrap(parts.firstIndex(of:"DDDDDDDDD"))
            let layout = try expanded(Array(parts[1..<boundary]))
            XCTAssertEqual(Array(layout[10...12]),[0x00040C08,0x0004C408,index == 0 ? 0x1D : 0x1E])
        }
    }
}
