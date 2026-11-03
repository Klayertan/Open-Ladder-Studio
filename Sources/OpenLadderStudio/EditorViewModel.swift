import SwiftUI
import AppKit
import LadderCore

enum EditorTool: Equatable {
    case select, pan, symbol(SymbolKind), branch
    var key: String {
        switch self {
        case .select: "tool.select"
        case .pan: "tool.pan"
        case .symbol(let kind): kind.localizationKey
        case .branch: "tool.branch"
        }
    }
}

@MainActor
final class EditorViewModel: ObservableObject {
    let document: LadderDocument
    weak var undoManager: UndoManager?
    @Published var tool: EditorTool = .select
    @Published var selection: Set<UUID> = []
    @Published var zoom: CGFloat = 1
    @Published var pan = CGSize(width: 20, height: 24)
    @Published var showGrid = true
    @Published var showValidation = false
    @Published var errorMessage: String?
    @Published var cursor: GridPoint?
    @Published var branchWidth = 1
    @Published var dragOffset = GridPoint(0, 0)
    @Published var statusKey = "status.ready"
    @Published var showSimulation = false
    @Published private(set) var simulation: SimulationState?
    @Published private(set) var isSimulationRunning = false
    private var simulator: LadderSimulator?
    private var simulationTask: Task<Void, Never>?
    static let clipboardType = NSPasteboard.PasteboardType("studio.openladder.elements")

    init(document: LadderDocument) { self.document = document }
    var circuit: Circuit { document.circuit }
    var selectedElements: [LadderElement] { circuit.elements.filter { selection.contains($0.id) } }
    var issues: [ValidationIssue] { CircuitValidation.issues(in: circuit) }

    func commit(_ newCircuit: Circuit, action: String) {
        guard newCircuit != circuit else { return }
        pauseSimulation()
        simulator = nil; simulation = nil
        let previous = circuit
        undoManager?.registerUndo(withTarget: self) { target in target.commit(previous, action: action) }
        undoManager?.setActionName(NSLocalizedString(action, comment: "Undo action"))
        document.circuit = newCircuit
        selection.formIntersection(Set(newCircuit.elements.map(\.id)))
        statusKey = "status.ready"
    }
    func perform(_ action: String, _ operation: () throws -> Circuit) {
        do { commit(try operation(), action: action) }
        catch { errorMessage = error.localizedDescription }
    }
    func place(at point: GridPoint) {
        switch tool {
        case .symbol(let kind):
            let e = LadderElement(kind: kind, position: point, label: nextLabel(for: kind))
            perform("action.place") { try CircuitEditing.insert([e], into: circuit) }
            if circuit.elements.contains(where: { $0.id == e.id }) { selection = [e.id] }
        case .branch:
            perform("action.branch") { try CircuitEditing.branch(from: point, width: branchWidth, in: circuit) }
        case .select, .pan: break
        }
    }
    func nextLabel(for kind: SymbolKind) -> String {
        guard !kind.isWire else { return "" }
        let prefix = kind.defaultLabel.prefix(1), existing = Set(circuit.elements.map(\.label))
        return (0...9999).lazy.map { "\(prefix)\($0)" }.first { !existing.contains($0) } ?? kind.defaultLabel
    }
    func deleteSelection() {
        perform("action.delete") { CircuitEditing.remove(selection, from: circuit) }
        selection = []
    }
    func moveSelection(columns: Int, rows: Int) {
        guard !selection.isEmpty, columns != 0 || rows != 0 else { return }
        perform("action.move") { try CircuitEditing.move(selection, columns: columns, rows: rows, in: circuit) }
    }
    func updateSelected(label: String, comment: String, timerPresetMilliseconds: Int? = nil) {
        guard selection.count == 1, let id = selection.first else { return }
        perform("action.properties") { try CircuitEditing.update(id, label: label, comment: comment, timerPresetMilliseconds: timerPresetMilliseconds, in: circuit) }
    }
    func copy() {
        guard !selectedElements.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(selectedElements)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(data, forType: Self.clipboardType)
        } catch { errorMessage = error.localizedDescription }
    }
    func cut() { copy(); deleteSelection() }
    func paste() {
        guard let data = NSPasteboard.general.data(forType: Self.clipboardType), data.count < 8_000_000 else { return }
        do {
            let elements = try JSONDecoder().decode([LadderElement].self, from: data)
            let preferred = cursor ?? GridPoint(1, 1)
            // Search nearby free cells, preserving the copied topology and issuing fresh IDs.
            for offset in 0..<circuit.rows {
                let anchor = GridPoint(preferred.column, (preferred.row + offset) % circuit.rows)
                if let (result, ids) = try? CircuitEditing.paste(elements, at: anchor, into: circuit) {
                    commit(result, action: "action.paste"); selection = ids; tool = .select; return
                }
            }
            throw CircuitError.noRoomForPaste
        } catch { errorMessage = error.localizedDescription }
    }
    func selectAll() { selection = Set(circuit.elements.map(\.id)); tool = .select }
    func resize(columns: Int = 0, rows: Int = 0) {
        var result = circuit; result.columns += columns; result.rows += rows
        perform("action.resize") { try result.checked() }
    }
    func setZoom(_ value: CGFloat, around anchor: CGPoint? = nil) {
        let value = min(max(value, 0.25), 2.5)
        if let anchor {
            let ratio = value / zoom
            pan = CGSize(width: anchor.x - (anchor.x - pan.width) * ratio,
                         height: anchor.y - (anchor.y - pan.height) * ratio)
        }
        zoom = value
    }
    func fit(in size: CGSize) {
        let diagram = DiagramMetrics.size(for: circuit)
        zoom = min(1.25, max(0.25, min((size.width - 48) / diagram.width, (size.height - 48) / diagram.height)))
        pan = CGSize(width: (size.width - diagram.width * zoom) / 2, height: (size.height - diagram.height * zoom) / 2)
    }
    func reveal(_ id: UUID) {
        guard let e = circuit.elements.first(where: { $0.id == id }) else { return }
        selection = [id]; tool = .select
        let p = DiagramMetrics.point(e.position)
        pan = CGSize(width: 100 - p.x * zoom, height: 160 - p.y * zoom)
    }
    func replace(with circuit: Circuit) {
        commit(circuit, action: "action.example"); selection = []; pan = .init(width: 20, height: 24)
    }

    func prepareSimulation() -> Bool {
        guard simulator == nil else { return true }
        do {
            simulator = try LadderSimulator(circuit: circuit)
            simulation = simulator?.state
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func startSimulation() {
        guard !isSimulationRunning, prepareSimulation() else { return }
        showSimulation = true; isSimulationRunning = true
        simulationTask = Task { [weak self] in
            var last = ContinuousClock.now
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(20)) } catch { break }
                let now = ContinuousClock.now
                let duration = last.duration(to: now).components
                let milliseconds = Int(duration.seconds * 1_000 + duration.attoseconds / 1_000_000_000_000_000)
                // Retain sub-millisecond time by moving the reference only by consumed time.
                last = last.advanced(by: .milliseconds(milliseconds))
                guard let self else { return }
                self.advanceSimulation(milliseconds: milliseconds)
            }
        }
    }

    func pauseSimulation() {
        simulationTask?.cancel(); simulationTask = nil; isSimulationRunning = false
    }

    func resetSimulation() {
        pauseSimulation(); simulator = nil; simulation = nil
        _ = prepareSimulation()
    }

    func advanceSimulation(milliseconds: Int) {
        guard prepareSimulation() else { return }
        do {
            try simulator?.advance(milliseconds: milliseconds)
            simulation = simulator?.state
        } catch { pauseSimulation(); errorMessage = error.localizedDescription }
    }

    func pressInput(_ address: String) {
        guard prepareSimulation() else { return }
        do {
            try simulator?.pulseInput(address)
            simulation = simulator?.state
        } catch { pauseSimulation(); errorMessage = error.localizedDescription }
    }

    func setInput(_ address: String, pressed: Bool) {
        guard prepareSimulation() else { return }
        do {
            try simulator?.setInput(address, pressed: pressed)
            simulation = simulator?.state
        } catch { pauseSimulation(); errorMessage = error.localizedDescription }
    }
}
