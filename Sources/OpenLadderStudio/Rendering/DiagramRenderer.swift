import SwiftUI
import LadderCore

enum DiagramMetrics {
    static let cellWidth: CGFloat = 88
    static let cellHeight: CGFloat = 76
    static let left: CGFloat = 64
    static let top: CGFloat = 104
    static func point(_ grid: GridPoint) -> CGPoint {
        CGPoint(x: left + CGFloat(grid.column) * cellWidth, y: top + CGFloat(grid.row) * cellHeight)
    }
    static func grid(_ point: CGPoint, vertical: Bool = false) -> GridPoint {
        .init(Int(((point.x - left) / cellWidth - (vertical ? 0 : 0.5)).rounded()),
              Int(((point.y - top) / cellHeight - (vertical ? 0.5 : 0)).rounded()))
    }
    static func size(for circuit: Circuit) -> CGSize {
        CGSize(width: left * 2 + CGFloat(circuit.columns) * cellWidth,
               height: top + CGFloat(circuit.rows - 1) * cellHeight + 64)
    }
}

/// Shared by the interactive Canvas and both export formats.
enum DiagramRenderer {
    static let accent = Color(red: 0.05, green: 0.57, blue: 0.51)
    static func draw(_ circuit: Circuit, context: inout GraphicsContext, dark: Bool, grid: Bool,
                     selection: Set<UUID> = [], offset: GridPoint = .init(0, 0),
                     issues: Set<UUID> = [], energized: Set<UUID> = [], counters: [String: CounterState] = [:], visible: CGRect? = nil) {
        let ink = dark ? Color(red: 0.84, green: 0.88, blue: 0.89) : Color(red: 0.17, green: 0.23, blue: 0.26)
        let muted = dark ? Color.white.opacity(0.35) : Color.black.opacity(0.32)
        let size = DiagramMetrics.size(for: circuit)
        let title = Text(circuit.name == "Untitled" ? String(localized: "project.untitled") : circuit.name)
            .font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundColor(ink)
        context.draw(title, at: CGPoint(x: DiagramMetrics.left, y: 29), anchor: .leading)
        context.draw(Text("JIS  ·  LADDER DIAGRAM").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(muted),
                     at: CGPoint(x: DiagramMetrics.left, y: 53), anchor: .leading)
        if grid {
            let rect = visible ?? CGRect(origin: .zero, size: size)
            let firstRow = max(0, Int((rect.minY - DiagramMetrics.top) / DiagramMetrics.cellHeight) - 1)
            let lastRow = min(circuit.rows - 1, Int((rect.maxY - DiagramMetrics.top) / DiagramMetrics.cellHeight) + 1)
            if firstRow <= lastRow {
                for row in firstRow...lastRow {
                    for col in 0...circuit.columns {
                        let p = DiagramMetrics.point(.init(col, row))
                        context.fill(Path(ellipseIn: CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2)), with: .color(muted.opacity(0.45)))
                    }
                }
            }
        }
        for col in [0, circuit.columns] {
            let x = DiagramMetrics.point(.init(col, 0)).x
            var rail = Path(); rail.move(to: CGPoint(x: x, y: DiagramMetrics.top - 30))
            rail.addLine(to: CGPoint(x: x, y: size.height - 36))
            context.stroke(rail, with: .color(ink.opacity(0.65)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            context.draw(Text(col == 0 ? "L" : "N").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(muted),
                         at: CGPoint(x: x, y: DiagramMetrics.top - 43))
        }
        for row in 0..<circuit.rows {
            let y = DiagramMetrics.point(.init(0, row)).y
            if let visible, y < visible.minY - 30 || y > visible.maxY + 30 { continue }
            context.draw(Text(String(format: "%02d", row + 1)).font(.system(size: 10, design: .monospaced)).foregroundColor(muted),
                         at: CGPoint(x: 26, y: y))
        }
        for element in circuit.elements {
            var element = element
            let selected = selection.contains(element.id)
            if selected { element.position = element.position.offset(columns: offset.column, rows: offset.row) }
            let start = DiagramMetrics.point(element.position)
            let end = DiagramMetrics.point(element.end)
            let box = element.kind == .verticalWire
                ? CGRect(x: start.x - 10, y: start.y, width: 20, height: DiagramMetrics.cellHeight)
                : CGRect(x: start.x + 3, y: start.y - 32, width: DiagramMetrics.cellWidth - 6, height: 62)
            if let visible, !visible.intersects(box.insetBy(dx: -10, dy: -10)) { continue }
            if selected {
                context.fill(Path(roundedRect: box, cornerRadius: 7), with: .color(accent.opacity(0.11)))
                context.stroke(Path(roundedRect: box, cornerRadius: 7), with: .color(accent.opacity(0.8)), lineWidth: 1)
            }
            let color = energized.contains(element.id) ? Color.green : selected ? accent : ink
            drawSymbol(element.kind, from: start, to: end, context: &context, color: color,
                       presetMilliseconds: element.kind == .timer ? element.presetMilliseconds : nil, counterPreset: element.kind == .counter ? element.presetCount : nil, counterCurrent: counters[element.label]?.current)
            if !element.kind.isWire {
                context.draw(Text(element.label).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundColor(selected ? accent : ink),
                             at: CGPoint(x: (start.x + end.x) / 2, y: start.y - 28))
                let note = circuit.displayComment(for: element)
                if !note.isEmpty {
                    let comment = note.count > 13 ? String(note.prefix(12)) + "…" : note
                    context.draw(Text(comment).font(.system(size: 9)).foregroundColor(muted), at: CGPoint(x: (start.x + end.x) / 2, y: start.y + 29))
                }
            }
            if issues.contains(element.id) {
                context.fill(Path(ellipseIn: CGRect(x: end.x - 10, y: start.y - 27, width: 5, height: 5)), with: .color(.orange))
            }
        }
        // Junction dots are based on electrical degree, not the visual position of a symbol.
        var degree: [GridPoint: Int] = [:]
        for e in circuit.elements { for node in e.terminals { degree[node, default: 0] += 1 } }
        for (node, count) in degree where count > 2 {
            let p = DiagramMetrics.point(node)
            context.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(ink))
        }
    }

    static func drawSymbol(_ kind: SymbolKind, from start: CGPoint, to end: CGPoint, context: inout GraphicsContext, color: Color, presetMilliseconds: Int? = nil, counterPreset: Int? = nil, counterCurrent: Int? = nil) {
        var path = Path()
        func line(_ a: CGPoint, _ b: CGPoint) { path.move(to: a); path.addLine(to: b) }
        let cx = (start.x + end.x) / 2, y = start.y
        if kind == .timer || kind == .counter {
            line(start, CGPoint(x: cx - 25, y: y)); line(CGPoint(x: cx + 25, y: y), end)
            path.addRoundedRect(in: CGRect(x: cx - 25, y: y - 17, width: 50, height: 34), cornerSize: CGSize(width: 3, height: 3))
            context.draw(Text(kind == .counter ? "CTU" : "TON").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundColor(color), at: CGPoint(x: cx, y: presetMilliseconds == nil && counterPreset == nil ? y : y - 6))
            if let counterPreset {
                context.draw(Text(counterCurrent.map { "\($0)/K\(counterPreset)" } ?? "K\(counterPreset)").font(.system(size: 9, design: .monospaced)).foregroundColor(color), at: CGPoint(x: cx, y: y + 8))
            }
            if let presetMilliseconds {
                context.draw(Text(String(format: "%g s", Double(presetMilliseconds) / 1_000)).font(.system(size: 9, design: .monospaced)).foregroundColor(color), at: CGPoint(x: cx, y: y + 8))
            }
        }
        else if kind.isWire { line(start, end) }
        else if !kind.isOutput {
            line(start, CGPoint(x: cx - 10, y: y)); line(CGPoint(x: cx + 10, y: y), end)
            for x in [cx - 10, cx + 10] { line(CGPoint(x: x, y: y - 16), CGPoint(x: x, y: y + 16)) }
            if kind == .normallyClosed { line(CGPoint(x: cx - 17, y: y + 21), CGPoint(x: cx + 17, y: y - 21)) }
        } else {
            line(start, CGPoint(x: cx - 17, y: y)); line(CGPoint(x: cx + 17, y: y), end)
            path.move(to: CGPoint(x: cx - 10, y: y - 17))
            path.addQuadCurve(to: CGPoint(x: cx - 10, y: y + 17), control: CGPoint(x: cx - 24, y: y))
            path.move(to: CGPoint(x: cx + 10, y: y - 17))
            path.addQuadCurve(to: CGPoint(x: cx + 10, y: y + 17), control: CGPoint(x: cx + 24, y: y))
            if kind != .coil {
                context.draw(Text(kind == .risingPulse ? "↑" : kind == .fallingPulse ? "↓" : kind == .setCoil ? "S" : "R").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundColor(color), at: CGPoint(x: cx, y: y))
            }
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
    }
}

struct SymbolPreview: View {
    let kind: SymbolKind
    var body: some View {
        Canvas { context, size in
            let start = CGPoint(x: kind == .verticalWire ? size.width / 2 : 2, y: kind == .verticalWire ? 4 : size.height / 2)
            let end = CGPoint(x: kind == .verticalWire ? size.width / 2 : size.width - 2, y: kind == .verticalWire ? size.height - 4 : size.height / 2)
            var scaled = context
            if kind.isWire { DiagramRenderer.drawSymbol(kind, from: start, to: end, context: &scaled, color: .primary) }
            else {
                scaled.scaleBy(x: 0.65, y: 0.65)
                DiagramRenderer.drawSymbol(kind, from: .init(x: 0, y: size.height / 1.3), to: .init(x: size.width / 0.65, y: size.height / 1.3), context: &scaled, color: .primary)
            }
        }.frame(width: 44, height: 28).accessibilityHidden(true)
    }
}
