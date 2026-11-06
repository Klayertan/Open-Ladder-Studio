import SwiftUI
import LadderCore

struct EditorView: View {
    @ObservedObject var document: LadderDocument
    @StateObject private var model: EditorViewModel
    @Environment(\.undoManager) private var undoManager
    @AppStorage("appearance") private var appearance = "system"
    @State private var showInspector = true
    @State private var pendingExample: Int?
    @State private var viewport = CGSize(width: 800, height: 700)
    init(document: LadderDocument) {
        self.document = document
        _model = StateObject(wrappedValue: EditorViewModel(document: document))
    }
    var body: some View {
        GeometryReader { window in
            HSplitView {
                ComponentSidebar(model: model)
                    .frame(minWidth: 210, idealWidth: 224, maxWidth: 270)
                    .frame(height: window.size.height)
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        editorHeader
                        Divider()
                        VSplitView {
                            LadderCanvasView(model: model, document: document, viewport: $viewport).frame(minHeight:120)
                            if model.showSimulation && model.showTimingDiagram {
                                TimingDiagramView(model:model,document:document)
                                    .frame(minHeight:150,idealHeight:260)
                            }
                        }
                        if model.showSimulation {
                            Divider()
                            SimulationPanel(model: model, document: document).frame(height: 208)
                        }
                        if model.showValidation {
                            Divider()
                            ValidationPanel(model: model, document: document).frame(height: 170)
                        }
                        Divider()
                        statusBar
                    }
                    if showInspector {
                        Divider()
                        InspectorView(model: model, document: document).frame(width: 252)
                    }
                }.frame(height: window.size.height)
            }
            .frame(width: window.size.width, height: window.size.height)
        }
        .navigationTitle("Open Ladder Studio")
        .toolbar { toolbar }
        .frame(minWidth: 1040, minHeight: 640)
        .tint(DiagramRenderer.accent)
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        .focusedSceneValue(\.ladderEditor, model)
        .onAppear { model.undoManager = undoManager }
        .onDisappear { model.pauseSimulation() }
        .onChange(of: model.showSimulation) { _, visible in
            if visible { model.showValidation = false } else { model.pauseSimulation() }
        }
        .onChange(of: model.showValidation) { _, visible in if visible { model.showSimulation = false } }
        .alert("error.title", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("common.ok") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .confirmationDialog("example.replace", isPresented: Binding(get: { pendingExample != nil }, set: { if !$0 { pendingExample = nil } }), titleVisibility: .visible) {
            Button("example.load") { if let choice = pendingExample { loadExample(choice) }; pendingExample = nil }
            Button("common.cancel", role: .cancel) { pendingExample = nil }
        } message: { Text("example.undoHint") }
    }
    private var editorHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted").foregroundStyle(DiagramRenderer.accent)
            Text("editor.title").font(.system(size: 12, weight: .semibold))
            Text("v0.2").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            Spacer()
            Text(LocalizedStringKey(model.tool.key)).font(.system(size: 11)).foregroundStyle(.secondary)
            Rectangle().fill(.quaternary).frame(width: 1, height: 13)
            Text("JIS").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(DiagramRenderer.accent)
                .padding(.horizontal, 7).padding(.vertical, 3).background(DiagramRenderer.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 4))
        }.padding(.horizontal, 20).frame(height: 44).background(.bar)
    }
    private var statusBar: some View {
        HStack(spacing: 9) {
            Circle().fill(model.issues.isEmpty ? DiagramRenderer.accent : .orange).frame(width: 5, height: 5)
            Text(model.issues.isEmpty ? "status.ready" : "status.issues").font(.system(size: 10))
            Text("\(document.circuit.elements.count)").font(.system(size: 10, design: .monospaced))
            Text("status.elements").font(.system(size: 10))
            Spacer()
            if let p = model.cursor {
                Text("C\(p.column + 1) : R\(p.row + 1)").font(.system(size: 10, design: .monospaced))
            }
            Image(systemName: "dot.squareshape.split.2x2").font(.system(size: 10))
            Text("status.snap").font(.system(size: 10))
        }.foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 30).background(.bar)
    }
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { model.undoManager?.undo() } label: { Image(systemName: "arrow.uturn.backward") }.help("edit.undo")
            Button { model.undoManager?.redo() } label: { Image(systemName: "arrow.uturn.forward") }.help("edit.redo")
        }
        ToolbarItemGroup(placement: .principal) {
            Button { model.setZoom(model.zoom / 1.2, around: CGPoint(x: viewport.width / 2, y: viewport.height / 2)) } label: { Image(systemName: "minus.magnifyingglass") }.help("zoom.out")
            Text("\(Int(model.zoom * 100))% ").font(.system(size: 11, design: .monospaced)).monospacedDigit().frame(width: 52)
            Button { model.setZoom(model.zoom * 1.2, around: CGPoint(x: viewport.width / 2, y: viewport.height / 2)) } label: { Image(systemName: "plus.magnifyingglass") }.help("zoom.in")
            Button { model.fit(in: viewport) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("zoom.fit")
        }
        ToolbarItemGroup(placement: .automatic) {
            Menu {
                Button("example.sealIn") { requestExample(0) }
                Button("example.setReset") { requestExample(1) }
                Button("example.trafficLight") { requestExample(3) }
                Button("example.pedestrian") { requestExample(4) }
                Divider()
                Button("example.blank") { requestExample(2) }
            } label: { Label("example.menu", systemImage: "square.stack") }.help("example.menu")
            Toggle(isOn: $model.showValidation) { Label("validation.check", systemImage: "checkmark.shield") }.help("validation.check")
            Toggle(isOn: $model.showSimulation) { Label("simulation.title", systemImage: "waveform.path.ecg") }.help("simulation.title")
            Menu {
                Button("export.png") { DiagramExporter.export(model.circuit, format: .png) { model.errorMessage = $0 } }
                Button("export.pdf") { DiagramExporter.export(model.circuit, format: .pdf) { model.errorMessage = $0 } }
                Divider()
                Button("export.renri") { DiagramExporter.exportRenri(model.circuit) { model.errorMessage = $0 } }
            } label: { Label("export.title", systemImage: "square.and.arrow.up") }
            Button { showInspector.toggle() } label: { Image(systemName: "sidebar.right") }.help("inspector.toggle")
        }
    }
    private func requestExample(_ choice: Int) {
        if document.circuit.elements.isEmpty { loadExample(choice) } else { pendingExample = choice }
    }
    private func loadExample(_ choice: Int) {
        model.replace(with: choice == 0 ? ExampleCircuits.sealIn : choice == 1 ? ExampleCircuits.setReset : choice == 3 ? ExampleCircuits.trafficLight : choice == 4 ? ExampleCircuits.pedestrianCrossing : Circuit())
        model.showSimulation = choice == 3
        model.fit(in: viewport)
    }
}
