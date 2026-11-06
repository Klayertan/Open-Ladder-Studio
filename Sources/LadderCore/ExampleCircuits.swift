import Foundation

public enum ExampleCircuits {
    /// Exercise 10: green 10 s → yellow 2 s → red 5 s, repeat.
    /// X1 is a logical, momentary stop input. Stop clears M0 and resets all TONs.
    public static var trafficLight: Circuit {
        var elements: [LadderElement] = []
        func rung(_ row: Int, contacts: [Int: (SymbolKind, String, String)], output: String,
                  kind: SymbolKind = .coil, comment: String, milliseconds: Int? = nil) {
            for column in 0..<10 {
                if let (contactKind, label, note) = contacts[column] {
                    elements.append(.init(kind: contactKind, position: .init(column, row), label: label, comment: note))
                } else if column == 9 {
                    elements.append(.init(kind: kind, position: .init(column, row), label: output, comment: comment, timerPresetMilliseconds: milliseconds))
                } else { elements.append(.init(kind: .horizontalWire, position: .init(column, row))) }
            }
        }
        rung(0, contacts: [1: (.normallyClosed, "X1", "点滅停止PB"), 3: (.normallyOpen, "X0", "スタートPB")], output: "M0", comment: "運転自己保持")
        elements += [.init(kind: .verticalWire, position: .init(3, 0)),
                     .init(kind: .normallyOpen, position: .init(3, 1), label: "M0", comment: "自己保持接点"),
                     .init(kind: .verticalWire, position: .init(4, 0))]
        rung(2, contacts: [1: (.normallyOpen, "M0", "運転中"), 3: (.normallyClosed, "T2", "一周期リセット")], output: "T0", kind: .timer, comment: "青10秒", milliseconds: 10_000)
        rung(3, contacts: [1: (.normallyOpen, "T0", "青時間完了")], output: "T1", kind: .timer, comment: "黄2秒", milliseconds: 2_000)
        rung(4, contacts: [1: (.normallyOpen, "T1", "黄時間完了")], output: "T2", kind: .timer, comment: "赤5秒", milliseconds: 5_000)
        rung(5, contacts: [1: (.normallyOpen, "M0", "運転中"), 3: (.normallyClosed, "T0", "青時間内")], output: "Y0", comment: "青ランプ（10秒）")
        rung(6, contacts: [1: (.normallyOpen, "M0", "運転中"), 3: (.normallyOpen, "T0", "青完了"), 5: (.normallyClosed, "T1", "黄時間内")], output: "Y1", comment: "黄ランプ（2秒）")
        rung(7, contacts: [1: (.normallyOpen, "M0", "運転中"), 3: (.normallyOpen, "T1", "黄完了")], output: "Y2", comment: "赤ランプ（5秒）")
        return Circuit(name: "練習問題10 信号機", rows: 8, elements: elements).adoptingCommentsAsDevices()
    }
    public static var sealIn: Circuit {
        var elements: [LadderElement] = []
        for c in 0..<10 {
            let kind: SymbolKind = c == 1 ? .normallyOpen : c == 4 ? .normallyClosed : c == 9 ? .coil : .horizontalWire
            let label = c == 1 ? "X0" : c == 4 ? "X1" : c == 9 ? "Y0" : ""
            elements.append(.init(kind: kind, position: .init(c, 0), label: label))
        }
        elements += [.init(kind: .verticalWire, position: .init(1, 0)),
                     .init(kind: .normallyOpen, position: .init(1, 1), label: "Y0", comment: "Seal-in contact"),
                     .init(kind: .verticalWire, position: .init(2, 0))]
        return Circuit(name: "Motor seal-in", elements: elements).adoptingCommentsAsDevices()
    }
    public static var setReset: Circuit {
        var elements: [LadderElement] = []
        for row in 0..<2 {
            for column in 0..<10 {
                let kind: SymbolKind = column == 1 ? .normallyOpen : column == 9 ? (row == 0 ? .setCoil : .resetCoil) : .horizontalWire
                elements.append(.init(kind: kind, position: .init(column, row * 2), label: column == 1 ? "X\(row)" : column == 9 ? "M0" : ""))
            }
        }
        return Circuit(name: "Set and reset memory", elements: elements)
    }
}

extension ExampleCircuits {
    /// Complete single-run pedestrian sequence: 5 s / 2 s / 3 s / 12 s,
    /// eight half-second on/off flashes, then a 3 s clearance timer.
    /// X0 starts, X1 stops; stop clears C0 and all non-retentive timers.
    public static var pedestrianCrossing: Circuit {
        var elements: [LadderElement] = []
        func rung(_ contacts: [(SymbolKind, String)], _ kind: SymbolKind, _ label: String, _ preset: Int = 0) {
            let row = elements.count / 10
            for column in 0..<10 {
                if column == 9 {
                    elements.append(.init(kind: kind, position: .init(column, row), label: label,
                                          timerPresetMilliseconds: kind == .timer ? preset : nil,
                                          counterPreset: kind == .counter ? preset : nil))
                } else if column < contacts.count {
                    elements.append(.init(kind: contacts[column].0, position: .init(column, row), label: contacts[column].1))
                } else { elements.append(.init(kind: .horizontalWire, position: .init(column, row))) }
            }
        }
        rung([(.normallyOpen,"X0")], .setCoil,"M0")
        rung([(.normallyOpen,"X1")], .resetCoil,"M0")
        rung([(.normallyOpen,"M0")], .timer,"T0",5000)
        rung([(.normallyOpen,"T0")], .timer,"T1",2000)
        rung([(.normallyOpen,"T1")], .timer,"T2",3000)
        rung([(.normallyOpen,"T2")], .timer,"T3",12000)
        rung([(.normallyOpen,"T3"),(.normallyClosed,"T5"),(.normallyClosed,"C0")], .timer,"T4",500)
        rung([(.normallyOpen,"T4"),(.normallyClosed,"C0")], .timer,"T5",500)
        rung([(.normallyOpen,"T5")], .counter,"C0",8)
        rung([(.normallyOpen,"C0")], .timer,"T6",3000)
        rung([(.normallyClosed,"M0")], .resetCoil,"C0")
        rung([(.normallyOpen,"M0"),(.normallyClosed,"T0")], .coil,"Y0")
        rung([(.normallyOpen,"T0"),(.normallyClosed,"T1")], .coil,"Y1")
        rung([(.normallyOpen,"T1"),(.normallyClosed,"T2")], .coil,"Y2")
        rung([(.normallyOpen,"T2"),(.normallyClosed,"T3")], .coil,"Y3")
        rung([(.normallyOpen,"T3"),(.normallyClosed,"T4"),(.normallyClosed,"C0")], .coil,"Y4")
        rung([(.normallyOpen,"T6")], .coil,"Y5")
        return Circuit(name: "Eight-flash pedestrian crossing", columns: 10, rows: 18, elements: elements)
    }
}
