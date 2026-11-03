import SwiftUI
import LadderCore

struct InspectorView: View {
    @ObservedObject var model: EditorViewModel
    @ObservedObject var document: LadderDocument
    @State private var label = ""
    @State private var comment = ""
    @State private var projectName = ""
    @State private var timerSeconds = 1.0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("inspector.title").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary)
                }.padding(.bottom, 4)
                if let element = model.selectedElements.first, model.selection.count == 1 {
                    HStack(spacing: 10) {
                        SymbolPreview(kind: element.kind).padding(5).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(LocalizedStringKey(element.kind.localizationKey)).font(.system(size: 12, weight: .medium))
                            Text("inspector.selected").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        fieldTitle("inspector.label")
                        TextField("X0", text: $label).font(.system(size: 12, design: .monospaced)).disabled(element.kind.isWire)
                            .onSubmit(applyProperties)
                        fieldTitle("inspector.comment").padding(.top, 8)
                        TextField("inspector.commentPlaceholder", text: $comment, axis: .vertical).lineLimit(3...5).onSubmit(applyProperties)
                        if element.kind == .timer {
                            fieldTitle("inspector.timerSeconds").padding(.top, 8)
                            TextField("1.0", value: $timerSeconds, format: .number.precision(.fractionLength(0...3)))
                                .onSubmit(applyProperties)
                        }
                        Button("inspector.apply", action: applyProperties).frame(maxWidth: .infinity, alignment: .trailing)
                    }.textFieldStyle(.roundedBorder)
                    VStack(spacing: 11) {
                        infoRow("inspector.column", value: "\(element.position.column + 1)")
                        infoRow("inspector.row", value: "\(element.position.row + 1)")
                        infoRow("inspector.terminals", value: "2")
                    }
                    Button(role: .destructive) { model.deleteSelection() } label: { Label("edit.delete", systemImage: "trash") }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: model.selection.isEmpty ? "cursorarrow.click" : "square.on.square").font(.system(size: 26, weight: .light)).foregroundStyle(.tertiary)
                        Text(model.selection.isEmpty ? "inspector.noSelection" : "inspector.multiple").font(.system(size: 12, weight: .medium))
                        Text("inspector.selectionHint").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                    }.padding(.vertical, 12)
                }
                Divider()
                fieldTitle("inspector.project")
                TextField("inspector.projectName", text: $projectName).textFieldStyle(.roundedBorder).onSubmit(applyName)
                Button("inspector.rename", action: applyName).frame(maxWidth: .infinity, alignment: .trailing)
                VStack(spacing: 11) {
                    infoRow("inspector.columns", value: "\(document.circuit.columns)")
                    infoRow("inspector.rows", value: "\(document.circuit.rows)")
                }
                HStack {
                    Button { model.resize(rows: 2) } label: { Label("inspector.addRows", systemImage: "plus") }
                    Button { model.resize(columns: 1) } label: { Label("inspector.addColumn", systemImage: "plus") }
                }.font(.system(size: 10))
                Toggle("inspector.grid", isOn: $model.showGrid).font(.system(size: 11))
                if model.tool == .branch {
                    Divider()
                    fieldTitle("tool.branch")
                    Stepper(value: $model.branchWidth, in: 1...min(8, document.circuit.columns - 2)) {
                        Text("\(model.branchWidth) ") + Text("inspector.cells")
                    }.font(.system(size: 11))
                    Text("inspector.branchHint").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
                }
                Divider()
                Label("inspector.nativeFormat", systemImage: "doc.text").font(.system(size: 10)).foregroundStyle(.secondary)
                Text("inspector.futureHint").font(.system(size: 10)).foregroundStyle(.tertiary).lineSpacing(4)
            }.padding(20)
        }.background(.bar)
            .onAppear { reload() }
            .onChange(of: model.selectedElements) { _, _ in reload() }
            .onChange(of: document.circuit.name) { _, _ in projectName = document.circuit.name }
    }
    private func reload() {
        label = model.selectedElements.first?.label ?? ""
        comment = model.selectedElements.first?.comment ?? ""
        projectName = document.circuit.name
        timerSeconds = Double(model.selectedElements.first?.presetMilliseconds ?? 1_000) / 1_000
    }
    private func applyProperties() {
        guard timerSeconds.isFinite, timerSeconds >= 0.001, timerSeconds <= 86_400 else { model.errorMessage = CircuitError.invalidTimerPreset.localizedDescription; return }
        model.updateSelected(label: label, comment: comment, timerPresetMilliseconds: Int((timerSeconds * 1_000).rounded()))
    }
    private func applyName() {
        var circuit = document.circuit
        let name = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        circuit.name = name.isEmpty ? "Untitled" : String(name.prefix(100))
        model.commit(circuit, action: "action.rename")
    }
    private func fieldTitle(_ key: LocalizedStringKey) -> some View {
        Text(key).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
    }
    private func infoRow(_ key: LocalizedStringKey, value: String) -> some View {
        HStack { Text(key).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit() }.font(.system(size: 11))
    }
}

struct ValidationPanel: View {
    @ObservedObject var model: EditorViewModel
    @ObservedObject var document: LadderDocument
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("validation.title", systemImage: "checkmark.shield").font(.system(size: 11, weight: .semibold))
                Text("\(model.issues.count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Button { model.showValidation = false } label: { Image(systemName: "xmark").font(.system(size: 9)) }.buttonStyle(.plain)
            }.padding(.horizontal, 18).frame(height: 34).background(.bar)
            if model.issues.isEmpty {
                Label(document.circuit.elements.isEmpty ? "validation.empty" : "validation.valid", systemImage: "checkmark.circle")
                    .font(.system(size: 12)).foregroundStyle(DiagramRenderer.accent).padding(20)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(model.issues) { issue in
                            Button { if let id = issue.elementID { model.reveal(id) } } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: issue.severity == .error ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                                        .foregroundStyle(issue.severity == .error ? .orange : .yellow)
                                    Text(LocalizedStringKey(issue.key)).font(.system(size: 11))
                                    Spacer()
                                    if let e = document.circuit.elements.first(where: { $0.id == issue.elementID }) {
                                        Text("\(e.label.isEmpty ? "—" : e.label) · C\(e.position.column + 1) R\(e.position.row + 1)")
                                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                                    }
                                }.padding(.horizontal, 18).padding(.vertical, 7).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
