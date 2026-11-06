import XCTest
@testable import LadderCore

final class DeviceTableTests: XCTestCase {
    /// A version 2 file: comments live on symbols and there is no `devices` key.
    private func legacyJSON() throws -> Data {
        let elements: [LadderElement] = [
            .init(kind: .normallyOpen, position: .init(1, 0), label: "X0", comment: "スタートPB"),
            .init(kind: .coil, position: .init(9, 0), label: "Y0", comment: "青ランプ"),
            .init(kind: .normallyOpen, position: .init(1, 1), label: "Y0", comment: "自己保持接点"),
            .init(kind: .normallyOpen, position: .init(1, 2), label: "Y0", comment: "青ランプ"),
            .init(kind: .coil, position: .init(9, 2), label: "Y1", comment: "黄ランプ")
        ]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(Circuit(elements: elements))) as? [String: Any])
        object["version"] = 2; object.removeValue(forKey: "devices")
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testVersionTwoMigratesCommentsIntoDeviceTable() throws {
        let circuit = try Circuit.decode(legacyJSON())
        XCTAssertEqual(circuit.version, 3)
        XCTAssertEqual(circuit.device("X0").comment, "スタートPB")
        // The coil's comment wins over contacts; colour is inferred once and stored.
        XCTAssertEqual(circuit.device("Y0"), DeviceInfo(comment: "青ランプ", lampColor: .green))
        XCTAssertEqual(circuit.device("Y1").lampColor, .yellow)
        XCTAssertNil(circuit.device("X0").lampColor)
        // A differing contact note survives as an override; duplicates of the device comment are cleared.
        let y0 = circuit.elements.filter { $0.label == "Y0" }.map(\.comment)
        XCTAssertEqual(y0, ["", "自己保持接点", ""])
        XCTAssertEqual(circuit.elements.map { circuit.displayComment(for: $0) }, ["スタートPB", "青ランプ", "自己保持接点", "青ランプ", "黄ランプ"])
    }

    func testDeviceEditAppliesToEverySymbolWithThatAddress() throws {
        var circuit = try Circuit.decode(legacyJSON())
        circuit = try CircuitEditing.setDevice("Y0", comment: " 運転表示灯 ", lampColor: .red, in: circuit)
        XCTAssertEqual(circuit.device("Y0"), DeviceInfo(comment: "運転表示灯", lampColor: .red))
        let shown = circuit.elements.filter { $0.label == "Y0" }.map { circuit.displayComment(for: $0) }
        XCTAssertEqual(shown, ["運転表示灯", "自己保持接点", "運転表示灯"])
        XCTAssertEqual(try Circuit.decode(circuit.encoded()), circuit)
        // Clearing a device removes its entry rather than storing an empty one.
        circuit = try CircuitEditing.setDevice("Y0", comment: "", lampColor: nil, in: circuit)
        XCTAssertNil(circuit.devices["Y0"])
    }

    func testInvalidDeviceEntriesAreRejected() {
        var circuit = Circuit(); circuit.devices["bad key"] = DeviceInfo(comment: "x")
        XCTAssertThrowsError(try circuit.checked())
        circuit = Circuit(); circuit.devices["X0"] = DeviceInfo(comment: String(repeating: "あ", count: 241))
        XCTAssertThrowsError(try circuit.checked())
    }

    func testAddressesSortNumerically() {
        let circuit = Circuit(elements: ["X10", "X2", "Y0", "M1"].enumerated().map {
            .init(kind: .normallyOpen, position: .init(1, $0.offset), label: $0.element)
        })
        XCTAssertEqual(circuit.addresses, ["M1", "X2", "X10", "Y0"])
    }

    /// Ignore only the documented comment-display bit; instructions and operands must match.
    func testTrafficInstructionRecordsMatchPreviouslyVerifiedFile() throws {
        let saved = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("output/exercise10/KADAI10.MBS")
        let expected = try Data(contentsOf: saved)
        func instructionRecords(_ data: Data) throws -> [String] {
            let text = try XCTUnwrap(String(data:data,encoding:.shiftJIS))
            let lines = text.components(separatedBy:"\r\n")
            let end = try XCTUnwrap(lines.firstIndex { $0.contains("000000FF0") })
            return try lines.prefix(end+1).map { line in
                let parts = line.split(separator:" ")
                guard let boundary = parts.firstIndex(of:"DDDDDDDDD") else { return line }
                var layout: [UInt32] = []
                for token in parts[1..<boundary] {
                    let repeats = try XCTUnwrap(Int(token.prefix(1),radix:16)) + 1
                    let word = try XCTUnwrap(UInt32(token.dropFirst(),radix:16)) & ~RenriMBSExporter.commentDisplayFlag
                    layout += Array(repeating:word,count:repeats)
                }
                return String(parts[0]) + " " + layout.map { String(format:"%08X",$0) }.joined(separator:" ") + " DDDDDDDDD " + parts[(boundary+1)...].joined(separator:" ")
            }
        }
        XCTAssertEqual(try instructionRecords(RenriMBSExporter.export(ExampleCircuits.trafficLight)),try instructionRecords(expected))
    }
}
