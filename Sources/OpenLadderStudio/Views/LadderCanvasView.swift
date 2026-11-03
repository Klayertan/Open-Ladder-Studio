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
                                         energized: model.simulation?.energizedElements ?? [], visible: visible)
                    drawPreview(context: &context)
                }
                .background(colorScheme == .dark ? Color(red: 0.095, green: 0.11, blue: 0.12) : Color(red: 0.985, green: 0.988, blue: 0.985))
                .contentShape(Rectangle())
                .focusable().focused($focused).focusEffectDisabled()
                .gesture(dragGesture)
                .simultaneousGesture(MagnificationGesture().onChanged { value in
                    if initialZoom == nil { initialZoom = model.zoom }
                    model.setZoom((initialZoom ?? 1) * value, around: CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2))
                }.onEnded { _ in initialZoom = nil })
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let point = gridPoint(location)
                        model.cursor = (0..<document.circuit.columns).contains(point.column) && (0..<document.circuit.rows).contains(point.row) ? point : nil
                    case .ended: model.cursor = nil
                    }
                }
                .onKeyPress(.escape) { model.tool = .select; model.selection = []; return .handled }
                .onKeyPress(.delete) { model.deleteSelection(); return .handled }
                .onKeyPress(characters: CharacterSet(charactersIn: "vhb12345678")) { press in
                    guard press.modifiers.isEmpty else { return .ignored }
                    switch press.characters {
                    case "v": model.tool = .select
                    case "h": model.tool = .pan
                    case "b": model.tool = .branch
                    default:
                        if let index = Int(press.characters), (1...8).contains(index) { model.tool = .symbol(SymbolKind.allCases[index - 1]) }
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
                .accessibilityLabel("canvas.accessibility")
                .contextMenu {
                    Button("edit.copy") { model.copy() }.disabled(model.selection.isEmpty)
                    Button("edit.paste") { model.paste() }
                    Button("edit.delete") { model.deleteSelection() }.disabled(model.selection.isEmpty)
                    Divider()
                    Button("zoom.fit") { model.fit(in: geometry.size) }
                }
                if document.circuit.elements.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("canvas.emptyTitle").font(.system(size: 18, weight: .semibold, design: .rounded))
                        Text("canvas.emptyHint").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                        Button("example.sealIn") { model.replace(with: ExampleCircuits.sealIn); model.fit(in: geometry.size) }
                            .buttonStyle(.bordered).padding(.top, 4)
                    }.padding(22).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary, lineWidth: 1))
                        .padding(.leading, 115).padding(.top, 215)
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
                if model.tool == .select {
                    if let e = hit(value.startLocation) {
                        if NSEvent.modifierFlags.contains(.shift) {
                            if model.selection.contains(e.id) { model.selection.remove(e.id) } else { model.selection.insert(e.id) }
                        } else if !model.selection.contains(e.id) { model.selection = [e.id] }
                        draggingSelection = model.selection.contains(e.id)
                    } else { model.selection = []; draggingSelection = false }
                }
            }
            if model.tool == .pan {
                model.pan = CGSize(width: initialPan.width + value.translation.width, height: initialPan.height + value.translation.height)
            } else if model.tool == .select && draggingSelection {
                model.dragOffset = .init(Int((value.translation.width / model.zoom / DiagramMetrics.cellWidth).rounded()),
                                         Int((value.translation.height / model.zoom / DiagramMetrics.cellHeight).rounded()))
            }
        }.onEnded { value in
            if model.tool == .select && draggingSelection {
                model.moveSelection(columns: model.dragOffset.column, rows: model.dragOffset.row)
            } else if model.tool != .pan && model.tool != .select {
                model.place(at: gridPoint(value.location))
            }
            model.dragOffset = .init(0, 0); dragStart = nil; draggingSelection = false
        }
    }
    private func drawPreview(context: inout GraphicsContext) {
        guard let cursor = model.cursor, case .symbol(let kind) = model.tool else { return }
        let e = LadderElement(kind: kind, position: cursor)
        guard document.circuit.contains(e) else { return }
        let overlaps = document.circuit.elements.contains { $0.overlaps(e) }
        context.opacity = 0.4
        DiagramRenderer.drawSymbol(kind, from: DiagramMetrics.point(e.position), to: DiagramMetrics.point(e.end),
                                   context: &context, color: overlaps ? .red : DiagramRenderer.accent)
    }
}
