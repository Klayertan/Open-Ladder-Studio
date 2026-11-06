import SwiftUI
import AppKit
import LadderCore

struct LadderCanvasView: View {
    @ObservedObject var model: EditorViewModel
    @ObservedObject var document: LadderDocument
    @Binding var viewport: CGSize
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focused: Bool
    @State private var dragStart: CGPoint?
    @State private var initialPan = CGSize.zero
    @State private var initialZoom: CGFloat?
    @State private var draggingSelection = false
    @State private var isPanning = false
    @State private var wireAnchor: GridPoint?
    @State private var wireEnd: GridPoint?
    @State private var horizontalFirst = true
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    context.translateBy(x: model.pan.width, y: model.pan.height)
                    context.scaleBy(x: model.zoom, y: model.zoom)
                    let visible = CGRect(x: -model.pan.width / model.zoom, y: -model.pan.height / model.zoom,
                                         width: size.width / model.zoom, height: size.height / model.zoom)
                    DiagramRenderer.draw(document.circuit, context: &context, dark: colorScheme == .dark,
                                         grid: model.showGrid, selection: model.selection, offset: model.dragOffset,
                                         issues: model.showValidation ? Set(model.issues.compactMap(\.elementID)) : [],
                                         energized: model.simulation?.energizedElements ?? [], counters: model.simulation?.counters ?? [:], visible: visible)
                    drawPreview(context: &context)
                }
                .background(colorScheme == .dark ? Color(red: 0.095, green: 0.11, blue: 0.12) : Color(red: 0.985, green: 0.988, blue: 0.985))
                .background(CanvasScrollZoom { delta, location in
                    model.scrollZoom(delta: delta, at: location)
                }.accessibilityHidden(true))
                .contentShape(Rectangle())
                .focusable().focused($focused).focusEffectDisabled()
                .gesture(dragGesture)
                .simultaneousGesture(MagnificationGesture().onChanged { value in
                    if initialZoom == nil { initialZoom = model.zoom }
                    model.setZoom((initialZoom ?? 1) * value, around: CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2))
                }.onEnded { _ in initialZoom = nil })
                .dropDestination(for: String.self) { items, location in
                    guard let item = items.first, item.hasPrefix("openladder.symbol:"),
                          let kind = SymbolKind(rawValue: String(item.dropFirst("openladder.symbol:".count))) else { return false }
                    let point = DiagramMetrics.grid(worldPoint(location), vertical: kind == .verticalWire)
                    model.placeSymbol(kind, at: point)
                    return true
                }
                .onChange(of: model.tool) { _, _ in wireAnchor = nil; wireEnd = nil }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        wireEnd = terminal(location)
                        horizontalFirst = !NSEvent.modifierFlags.contains(.shift)
                        let point = gridPoint(location)
                        model.cursor = (0..<document.circuit.columns).contains(point.column) && (0..<document.circuit.rows).contains(point.row) ? point : nil
                    case .ended: model.cursor = nil
                    }
                }
                .onKeyPress(.escape) { wireAnchor = nil; wireEnd = nil; model.tool = .select; model.selection = []; return .handled }
                .onKeyPress(.delete) { model.deleteSelection(); return .handled }
                .onKeyPress(characters: CharacterSet(charactersIn: "vbwpf123456789")) { press in
                    guard press.modifiers.isEmpty else { return .ignored }
                    switch press.characters {
                    case "v": model.tool = .select
                    case "b": model.tool = .branch
                    case "w": model.tool = .wire
                    case "p": model.tool = .symbol(.risingPulse)
                    case "f": model.tool = .symbol(.fallingPulse)
                    default:
                        if let index = Int(press.characters), (1...9).contains(index) { model.tool = .symbol(SymbolKind.allCases[index - 1]) }
                    }
                    return .handled
                }
                .onMoveCommand { direction in
                    switch direction {
                    case .left: model.moveSelection(columns: -1, rows: 0)
                    case .right: model.moveSelection(columns: 1, rows: 0)
                    case .up: model.moveSelection(columns: 0, rows: -1)
                    case .down: model.moveSelection(columns: 0, rows: 1)
                    @unknown default: break
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("canvas.accessibility")
                .accessibilityIdentifier("ladder.canvas")
                .contextMenu {
                    Button("edit.copy") { model.copy() }.disabled(model.selection.isEmpty)
                    Button("edit.paste") { model.paste() }
                    Button("edit.delete") { model.deleteSelection() }.disabled(model.selection.isEmpty)
                    Divider()
                    Button("zoom.fit") { model.fit(in: geometry.size) }
                }
                if document.circuit.elements.isEmpty && model.tool != .wire {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("canvas.emptyTitle").font(.system(size: 18, weight: .semibold, design: .rounded))
                        Text("canvas.emptyHint").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                    }.padding(22).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary, lineWidth: 1))
                        .padding(.leading, 115).padding(.top, 215).allowsHitTesting(false)
                }
                HStack(spacing: 6) {
                    Image(systemName: "hand.draw")
                    Text("canvas.panHint")
                }.font(.system(size: 10)).foregroundStyle(.secondary).padding(10)
                    .background(.regularMaterial, in: Capsule()).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(18)
                    .allowsHitTesting(false)
            }
            .clipped()
            .onAppear { updateViewport(geometry.size) }
            .onChange(of: geometry.size) { _, size in updateViewport(size) }
        }
    }
    private func updateViewport(_ size: CGSize) {
        viewport = size
        if size.width > 100 && size.height > 100 { model.fit(in: size) }
    }
    private func worldPoint(_ screen: CGPoint) -> CGPoint {
        CGPoint(x: (screen.x - model.pan.width) / model.zoom, y: (screen.y - model.pan.height) / model.zoom)
    }
    private func gridPoint(_ screen: CGPoint) -> GridPoint {
        DiagramMetrics.grid(worldPoint(screen), vertical: model.tool == .symbol(.verticalWire))
    }
    private func terminal(_ screen: CGPoint) -> GridPoint {
        let world = worldPoint(screen)
        return .init(min(document.circuit.columns,max(0,Int(((world.x - DiagramMetrics.left) / DiagramMetrics.cellWidth).rounded()))),
                     min(document.circuit.rows - 1,max(0,Int(((world.y - DiagramMetrics.top) / DiagramMetrics.cellHeight).rounded()))))
    }
    private func hit(_ screen: CGPoint) -> LadderElement? {
        let p = worldPoint(screen)
        // Vertical wires have a narrow hit target so contacts remain easy to select.
        return document.circuit.elements.reversed().first { e in
            let start = DiagramMetrics.point(e.position), end = DiagramMetrics.point(e.end)
            if e.kind == .verticalWire { return abs(p.x - start.x) < 9 && p.y >= start.y + 7 && p.y <= end.y - 7 }
            return p.x > start.x + 7 && p.x < end.x - 7 && abs(p.y - start.y) < 32
        }
    }
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0).onChanged { value in
            if dragStart == nil {
                focused = true; dragStart = value.startLocation; initialPan = model.pan
                draggingSelection = false
                isPanning = NSEvent.modifierFlags.contains(.option)
                if model.tool == .wire && !isPanning {
                    if wireAnchor == nil { wireAnchor = terminal(value.startLocation) }
                } else if !isPanning {
                    let element = hit(value.startLocation)
                    let symbolTool: Bool = { if case .symbol = model.tool { return true }; return false }()
                    if let element, model.tool == .select || (symbolTool && !element.kind.isWire) {
                        if NSEvent.modifierFlags.contains(.shift) {
                            if model.selection.contains(element.id) { model.selection.remove(element.id) }
                            else { model.selection.insert(element.id) }
                        } else if !model.selection.contains(element.id) { model.selection = [element.id] }
                        draggingSelection = model.selection.contains(element.id)
                    } else if model.tool == .select {
                        model.selection = []; isPanning = true
                    }
                }
            }
            if isPanning {
                model.pan = CGSize(width: initialPan.width + value.translation.width, height: initialPan.height + value.translation.height)
            } else if model.tool == .wire {
                wireEnd = terminal(value.location)
                horizontalFirst = !NSEvent.modifierFlags.contains(.shift)
            } else if draggingSelection {
                model.dragOffset = .init(Int((value.translation.width / model.zoom / DiagramMetrics.cellWidth).rounded()),
                                        Int((value.translation.height / model.zoom / DiagramMetrics.cellHeight).rounded()))
            } else {
                model.cursor = gridPoint(value.location)
            }
        }.onEnded { value in
            if !isPanning {
                if model.tool == .wire, let start = wireAnchor {
                    let end = terminal(value.location)
                    if start != end {
                        model.connect(from: start,to: end,horizontalFirst: horizontalFirst)
                        wireAnchor = nil; wireEnd = nil
                    }
                } else if draggingSelection {
                    model.moveSelection(columns: model.dragOffset.column, rows: model.dragOffset.row)
                } else if model.tool != .select {
                    model.place(at: gridPoint(value.location))
                }
            }
            model.dragOffset = .init(0, 0); dragStart = nil; draggingSelection = false; isPanning = false
        }
    }
    private func drawPreview(context: inout GraphicsContext) {
        if model.tool == .wire {
            if let start = wireAnchor {
                let origin = DiagramMetrics.point(start)
                context.fill(Path(ellipseIn: CGRect(x: origin.x - 4,y: origin.y - 4,width: 8,height: 8)),with: .color(DiagramRenderer.accent))
                if let end = wireEnd, let path = try? CircuitEditing.wirePath(from: start,to: end,horizontalFirst: horizontalFirst,in: document.circuit) {
                    context.opacity = 0.6
                    for segment in path where !document.circuit.elements.contains(where: { $0.overlaps(segment) && !$0.kind.isWire }) {
                        DiagramRenderer.drawSymbol(segment.kind,from: DiagramMetrics.point(segment.position),to: DiagramMetrics.point(segment.end),context: &context,color: DiagramRenderer.accent)
                    }
                }
            } else if let end = wireEnd {
                let point = DiagramMetrics.point(end)
                context.stroke(Path(ellipseIn: CGRect(x: point.x - 5,y: point.y - 5,width: 10,height: 10)),with: .color(DiagramRenderer.accent),lineWidth: 1.5)
            }
            return
        }
        guard let cursor = model.cursor, case .symbol(let kind) = model.tool else { return }
        let e = LadderElement(kind: kind, position: cursor)
        guard document.circuit.contains(e) else { return }
        let overlaps = document.circuit.elements.contains { $0.overlaps(e) && ($0.kind != .horizontalWire || kind.isWire) }
        context.opacity = 0.4
        DiagramRenderer.drawSymbol(kind, from: DiagramMetrics.point(e.position), to: DiagramMetrics.point(e.end),
                                   context: &context, color: overlaps ? .red : DiagramRenderer.accent)
    }
}
