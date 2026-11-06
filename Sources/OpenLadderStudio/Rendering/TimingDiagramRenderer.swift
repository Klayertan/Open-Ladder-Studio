import SwiftUI
import LadderCore

/// Shared native timing-chart renderer. Values come from simulation transitions,
/// including same-timestamp pulses, rather than periodically sampling the UI.
enum TimingDiagramRenderer {
    static let labelWidth: CGFloat = 154
    static let headerHeight: CGFloat = 32
    static let rowHeight: CGFloat = 44

    static func addresses(in circuit: Circuit) -> [String] {
        let order = ["X":0,"M":1,"T":2,"C":3,"Y":4]
        return circuit.addresses.sorted {
            (order[String($0.prefix(1)),default:5],Int($0.dropFirst()) ?? .max,$0) <
            (order[String($1.prefix(1)),default:5],Int($1.dropFirst()) ?? .max,$1)
        }
    }
    static func color(for address: String, in circuit: Circuit) -> Color {
        if let lamp = circuit.device(address).lampColor { return lamp.color }
        switch address.prefix(1) {
        case "X": return .blue
        case "T": return .orange
        case "C": return .purple
        default: return DiagramRenderer.accent
        }
    }
    static func draw(_ circuit: Circuit, state: SimulationState, context: inout GraphicsContext,
                     size: CGSize, pixelsPerSecond: CGFloat, dark: Bool, rowSpacing: CGFloat = rowHeight) {
        let addresses = addresses(in:circuit)
        let ink: Color = dark ? .white.opacity(0.88) : .black.opacity(0.78)
        let muted: Color = dark ? .white.opacity(0.43) : .black.opacity(0.42)
        let origin = state.historyStartMilliseconds
        let now = state.milliseconds
        func x(_ milliseconds: Int) -> CGFloat { labelWidth + CGFloat(milliseconds-origin) / 1000 * pixelsPerSecond }
        let rangeSeconds = Double(size.width-labelWidth) / Double(pixelsPerSecond)
        let tick = [0.1,0.2,0.5,1,2,5,10,20,30,60].first { $0 >= rangeSeconds / 12 } ?? 60
        let first = ceil(Double(origin) / 1000 / tick) * tick
        var second = first
        while x(Int((second * 1000).rounded())) <= size.width {
            let px = x(Int((second * 1000).rounded()))
            var grid = Path(); grid.move(to:.init(x:px,y:headerHeight)); grid.addLine(to:.init(x:px,y:size.height))
            context.stroke(grid,with:.color(muted.opacity(0.25)),style:.init(lineWidth:0.5,dash:[2,4]))
            context.draw(Text(String(format:"%g s",second)).font(.system(size:9,design:.monospaced)).foregroundColor(muted),at:.init(x:px+3,y:12),anchor:.leading)
            second += tick
        }
        for (row,address) in addresses.enumerated() {
            let top = headerHeight + CGFloat(row) * rowSpacing
            let high = top+rowSpacing*0.23, low = top+rowSpacing*0.66
            let color = color(for:address,in:circuit)
            if row.isMultiple(of:2) {
                context.fill(Path(CGRect(x:0,y:top,width:size.width,height:rowSpacing)),with:.color(muted.opacity(0.035)))
            }
            let current = state[address]
            let counter = state.counters[address]
            let timer = state.timers[address]
            let suffix = counter.map { "  \($0.current)/\($0.preset)" } ?? timer.map { String(format:"  %g s",Double($0.presetMilliseconds)/1000) } ?? ""
            context.draw(Text(address+suffix).font(.system(size:11,weight:.medium,design:.monospaced)).foregroundColor(current ? color : ink),at:.init(x:10,y:top+rowSpacing*0.27),anchor:.leading)
            let comment = circuit.device(address).comment
            if !comment.isEmpty {
                context.draw(Text(String(comment.prefix(17))).font(.system(size:9)).foregroundColor(muted),at:.init(x:10,y:top+rowSpacing*0.66),anchor:.leading)
            }
            context.fill(Path(ellipseIn:CGRect(x:labelWidth-15,y:top+rowSpacing*0.20,width:5,height:5)),with:.color(current ? color : muted.opacity(0.3)))
            var baseline = Path(); baseline.move(to:.init(x:labelWidth,y:low)); baseline.addLine(to:.init(x:size.width,y:low))
            context.stroke(baseline,with:.color(muted.opacity(0.3)),lineWidth:0.6)
            let history = state.signalHistory[address,default:[]]
            var lastCountX: CGFloat = -.infinity
            for index in history.indices {
                let sample = history[index]
                let end = index+1 < history.count ? history[index+1].milliseconds : now
                guard end >= origin, sample.milliseconds <= now else { continue }
                let left = x(max(origin,sample.milliseconds)), right = x(min(now,end))
                let y = sample.value ? high : low
                if sample.timing && right > left {
                    let box = CGRect(x:left,y:high,width:right-left,height:low-high)
                    context.fill(Path(box),with:.color(color.opacity(0.08)))
                    var hatch = Path()
                    for px in stride(from:left,through:right,by:7) {
                        hatch.move(to:.init(x:px,y:low)); hatch.addLine(to:.init(x:min(px+6,right),y:high))
                    }
                    context.stroke(hatch,with:.color(color.opacity(0.3)),lineWidth:0.6)
                }
                if sample.value && right > left {
                    context.fill(Path(CGRect(x:left,y:high,width:right-left,height:low-high)),with:.color(color.opacity(0.13)))
                }
                var line = Path(); line.move(to:.init(x:left,y:y)); line.addLine(to:.init(x:max(left,right),y:y))
                if index > 0, sample.milliseconds >= origin, history[index-1].value != sample.value {
                    line.move(to:.init(x:left,y:history[index-1].value ? high : low)); line.addLine(to:.init(x:left,y:y))
                }
                context.stroke(line,with:.color(color),style:.init(lineWidth:1.5,lineJoin:.miter))
                // Zero-width pulses are real transitions, drawn as a vertical marker.
                if sample.value && end == sample.milliseconds {
                    context.fill(Path(ellipseIn:CGRect(x:left-2,y:high-2,width:4,height:4)),with:.color(color))
                }
                if let count = sample.count, count > 0, index == 0 || history[index-1].count != count,
                   sample.milliseconds >= origin, left-lastCountX >= 14 {
                    context.draw(Text("\(count)").font(.system(size:8,design:.monospaced)).foregroundColor(color),at:.init(x:left+2,y:top+rowSpacing*0.86),anchor:.leading)
                    lastCountX = left
                }
            }
        }
        // Mask the label gutter so pulses at a clipped window boundary stay in the plot.
        var divider = Path(); divider.move(to:.init(x:labelWidth,y:0)); divider.addLine(to:.init(x:labelWidth,y:size.height))
        context.stroke(divider,with:.color(muted.opacity(0.35)),lineWidth:0.6)
        var cursor = Path(); cursor.move(to:.init(x:x(now),y:headerHeight)); cursor.addLine(to:.init(x:x(now),y:size.height))
        context.stroke(cursor,with:.color(ink.opacity(0.6)),style:.init(lineWidth:1,dash:[3,3]))
    }
}
