import Foundation

public enum RenriExportError: Error, LocalizedError {
    case unsupportedLayout, unsupportedDevice, unsupportedTimer, unencodableComment
    public var errorDescription: String? {
        switch self {
        case .unsupportedLayout: String(localized: "renri.error.layout", bundle: .main)
        case .unsupportedDevice: String(localized: "renri.error.device", bundle: .main)
        case .unsupportedTimer: String(localized: "renri.error.timer", bundle: .main)
        case .unencodableComment: String(localized: "renri.error.encoding", bundle: .main)
        }
    }
}

/// Experimental writer for the `mbs-file 3winv.1` text format observed in the
/// developer's official srenri884 distribution. This is NOT an assertion of
/// runtime compatibility. A file must still be opened/compiled in Renri.
///
/// Supported: complete series rungs (NO/NC, OUT, 100 ms TIM) and the single-cell
/// NO self-holding branch used by Exercise 10. Other topologies fail explicitly.
/// The holding rung is normalized to (Start OR Hold) AND Stop because the known
/// official branch template places the stop contact after the join. This is
/// electrically equivalent for the supported pure contacts.
public enum RenriMBSExporter {
    public static let compatibilityVerifiedInRenri = false
    private static let width = 16
    private struct Row {
        var layout: [UInt32]
        var data: [UInt32]
        var comments: [String]
    }

    public static func export(_ circuit: Circuit, fileName: String = "KADAI10.MBS") throws -> Data {
        _ = try circuit.checked()
        guard !circuit.elements.isEmpty, !CircuitValidation.issues(in: circuit).contains(where: { $0.severity == .error }),
              !fileName.contains("\n"), !fileName.contains("\r") else { throw RenriExportError.unsupportedLayout }
        var rows: [Row] = [], consumed = Set<UUID>()
        let outputs = circuit.elements.filter(\.kind.isOutput).sorted { $0.position.row < $1.position.row }
        guard Set(outputs.map { $0.position.row }).count == outputs.count else { throw RenriExportError.unsupportedLayout }
        for output in outputs {
            guard output.position.column == circuit.columns - 1, output.kind == .coil || output.kind == .timer else { throw RenriExportError.unsupportedLayout }
            let line = circuit.elements.filter { $0.position.row == output.position.row && $0.kind != .verticalWire }.sorted { $0.position.column < $1.position.column }
            guard line.count == circuit.columns, line.enumerated().allSatisfy({ $0.offset == $0.element.position.column }) else { throw RenriExportError.unsupportedLayout }
            let contacts = line.filter { !$0.kind.isWire && !$0.kind.isOutput }
            guard (1...9).contains(contacts.count), contacts.allSatisfy({ $0.kind == .normallyOpen || $0.kind == .normallyClosed }) else { throw RenriExportError.unsupportedLayout }
            let verticals = circuit.elements.filter { $0.kind == .verticalWire && $0.position.row == output.position.row }
            if verticals.isEmpty {
                rows.append(try series(contacts: contacts, output: output, in: circuit))
            } else {
                guard output.kind == .coil, output.label.hasPrefix("M"), contacts.count == 2, verticals.count == 2 else { throw RenriExportError.unsupportedLayout }
                let nodes = verticals.map { $0.position.column }.sorted()
                guard nodes[1] == nodes[0] + 1,
                      let top = contacts.first(where: { $0.position.column == nodes[0] }), top.kind == .normallyOpen,
                      let stop = contacts.first(where: { $0.id != top.id }), stop.kind == .normallyClosed else { throw RenriExportError.unsupportedLayout }
                let lower = circuit.elements.filter { $0.position.row == output.position.row + 1 && $0.kind != .verticalWire }
                guard lower.count == 1, let hold = lower.first, hold.kind == .normallyOpen,
                      hold.position.column == top.position.column, hold.label == output.label else { throw RenriExportError.unsupportedLayout }
                var main = try series(contacts: [top, stop], output: output, in: circuit)
                // Exact two-contact branch topology from official sample/sample1.mbs.
                main.layout[0] = 0x0008805A
                main.layout[1] = 0x00088068
                rows.append(main)
                var branch = emptyRow()
                branch.layout[0] = 0x0000801A; branch.layout[1] = 0x00000002
                branch.data[0] = try device(hold.label); branch.comments[0] = circuit.displayComment(for: hold)
                rows.append(branch)
                consumed.formUnion(lower.map(\.id))
                consumed.formUnion(verticals.map(\.id))
            }
            consumed.formUnion(line.map(\.id))
        }
        guard consumed.count == circuit.elements.count else { throw RenriExportError.unsupportedLayout }
        var end = emptyRow()
        end.layout[0] = 0x000000BB
        for i in 1...10 { end.layout[i] = 0x000000B9 }
        end.layout[11] = 0x00006408; end.layout[12] = 0x00000010
        rows.append(end)

        var lines = ["mbs-file 3winv.1", fileName]
        for (i, row) in rows.enumerated() {
            lines.append(String(format: "%05d  ", i + 1) + rle(row.layout) + " DDDDDDDDD " + rle(row.data) + " ")
        }
        let sentinelIndex = rows.count + 1
        lines.append(String(format: "%05d  ", sentinelIndex) + Array(repeating: "000000FF0", count: width).joined(separator: " ") + " ")
        for (i, row) in rows.enumerated() { lines.append(String(format: "%05d  ", i + 1) + (try commentRLE(row.comments)) + " ") }
        lines.append(String(format: "%05d  ", sentinelIndex) + Array(repeating: "0F0F0F0F0", count: width).joined(separator: " ") + " ")
        guard let data = (lines.joined(separator: "\r\n") + "\r\n").data(using: .shiftJIS, allowLossyConversion: false) else { throw RenriExportError.unencodableComment }
        return data
    }

    private static func emptyRow() -> Row {
        Row(layout: Array(repeating: 0, count: width), data: Array(repeating: 0, count: width), comments: Array(repeating: "", count: width))
    }
    private static func device(_ label: String) throws -> UInt32 {
        guard let first = label.first, let number = UInt32(label.dropFirst()), number <= 0xFFFF else { throw RenriExportError.unsupportedDevice }
        let prefix: UInt32
        switch first {
        case "X": prefix = 0
        case "Y": prefix = 0x10000000
        case "M": prefix = 0x20000000
        case "T": prefix = 0x40000000
        default: throw RenriExportError.unsupportedDevice
        }
        // Renri X/Y addresses are hexadecimal; T/M addresses are decimal.
        if first == "X" || first == "Y" {
            guard let address = UInt32(label.dropFirst(), radix: 16), address <= 0xFFFF else { throw RenriExportError.unsupportedDevice }
            return prefix | address
        }
        return prefix | number
    }
    private static func series(contacts: [LadderElement], output: LadderElement, in circuit: Circuit) throws -> Row {
        var row = emptyRow()
        for (column, contact) in contacts.enumerated() {
            row.layout[column] = (contact.kind == .normallyOpen ? 0x00008010 : 0x00008020) | (column == 0 ? 0xA : 0x8)
            row.data[column] = try device(contact.label); row.comments[column] = circuit.displayComment(for: contact)
        }
        let wireEnd = output.kind == .timer ? 10 : 11
        for i in contacts.count..<wireEnd { row.layout[i] = 0x000000B9 }
        row.data[11] = try device(output.label); row.comments[11] = circuit.displayComment(for: output)
        if output.kind == .timer {
            guard output.label.hasPrefix("T"), output.presetMilliseconds % 100 == 0,
                  (1...9_999).contains(output.presetMilliseconds / 100) else { throw RenriExportError.unsupportedTimer }
            row.layout[10] = 0x00020008; row.layout[11] = 0x0021C088; row.layout[12] = 0x00000035
            // K constants are packed decimal digits. Verified against timer.MBS
            // (K10 serialized as 000000010) and its generated timer.ino (10 * 100000 us).
            row.data[12] = UInt32(String(output.presetMilliseconds / 100), radix: 16)!
        } else {
            guard output.label.hasPrefix("M") || output.label.hasPrefix("Y") else { throw RenriExportError.unsupportedDevice }
            row.layout[11] = 0x0000C078; row.layout[12] = 0x0000000F
        }
        return row
    }
    private static func rle(_ values: [UInt32]) -> String {
        var tokens: [String] = [], i = 0
        while i < values.count {
            var count = 1
            while i + count < values.count && values[i + count] == values[i] && count < 16 { count += 1 }
            tokens.append(String(format: "%1X%08X", count - 1, values[i])); i += count
        }
        return tokens.joined(separator: " ")
    }
    private static func commentRLE(_ comments: [String]) throws -> String {
        var tokens: [String] = [], i = 0
        while i < comments.count {
            if comments[i].isEmpty {
                var count = 1
                while i + count < comments.count && comments[i + count].isEmpty && count < 16 { count += 1 }
                tokens.append(String(format: "%X", count - 1)); i += count
            } else {
                // A literal space/backslash is a format delimiter; reject rather
                // than silently corrupt an exported comment.
                guard !comments[i].contains(where: { $0.isWhitespace || $0 == "\\" }) else { throw RenriExportError.unencodableComment }
                tokens.append("0" + comments[i] + "\\\\"); i += 1
            }
        }
        return tokens.joined(separator: " ")
    }
}
