import SwiftUI
import LadderCore

struct SimulationPanel: View {
    @ObservedObject var model: EditorViewModel
    @ObservedObject var document: LadderDocument

    private var inputs: [String] { Array(Set(document.circuit.elements.map(\.label).filter { $0.hasPrefix("X") })).sorted() }
    private var outputs: [String] { Array(Set(document.circuit.elements.filter { $0.kind.isOutput && $0.label.hasPrefix("Y") }.map(\.label))).sorted() }
    private var timers: [String] { (model.simulation?.timers.keys.map { $0 } ?? []).sorted() }
    private func comment(_ address: String) -> String { document.circuit.device(address).comment }
    private func lampColor(_ address: String) -> Color { document.circuit.device(address).lampColor?.color ?? DiagramRenderer.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                Label("simulation.title", systemImage: "waveform.path.ecg").font(.system(size: 12, weight: .semibold))
                Circle().fill(model.isSimulationRunning ? Color.green : .secondary).frame(width: 6, height: 6)
                Text(model.isSimulationRunning ? "simulation.running" : "simulation.paused").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "t = %.2f s", Double(model.simulation?.milliseconds ?? 0) / 1_000))
                    .font(.system(size: 11, design: .monospaced)).monospacedDigit()
                Button(model.isSimulationRunning ? "simulation.pause" : "simulation.run") {
                    if model.isSimulationRunning { model.pauseSimulation() } else { model.startSimulation() }
                }.buttonStyle(.borderedProminent)
                Button("simulation.step") { model.advanceSimulation(milliseconds: 100) }.disabled(model.isSimulationRunning)
                Button("simulation.reset") { model.resetSimulation() }
            }
            ScrollView(.horizontal) {
              HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("simulation.inputs").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(inputs, id: \.self) { address in
                            VStack(spacing: 4) {
                                Button { model.pressInput(address) } label: {
                                    Text("\(address) \(comment(address))").font(.system(size: 11, weight: .medium))
                                }.help("simulation.momentary")
                                Toggle("simulation.hold", isOn: Binding(get: { model.simulation?[address] ?? false }, set: { model.setInput(address, pressed: $0) }))
                                    .font(.system(size: 9)).toggleStyle(.checkbox)
                            }
                        }
                    }
                }
                Divider().frame(height: 55)
                HStack(spacing: 15) {
                    ForEach(outputs, id: \.self) { address in
                        let active = model.simulation?[address] ?? false
                        VStack(spacing: 5) {
                            Circle().fill(active ? lampColor(address) : lampColor(address).opacity(0.08))
                                .frame(width: 29, height: 29)
                                .overlay(Circle().stroke(lampColor(address).opacity(active ? 1 : 0.3), lineWidth: 1.5))
                                .shadow(color: active ? lampColor(address).opacity(0.4) : .clear, radius: 8)
                            Text("\(address) \(comment(address))").font(.system(size: 10))
                            Text(active ? "simulation.on" : "simulation.off").font(.system(size: 9, design: .monospaced)).foregroundStyle(active ? lampColor(address) : .secondary)
                        }.accessibilityElement(children: .combine)
                    }
                }
              }
            }.scrollIndicators(.hidden).frame(height: 72)
            HStack(spacing: 18) {
                ForEach(timers, id: \.self) { address in
                    if let timer = model.simulation?.timers[address] {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(format: "%@  %.2f / %.2f s", address, Double(timer.elapsedMilliseconds) / 1_000, Double(timer.presetMilliseconds) / 1_000))
                                .font(.system(size: 10, design: .monospaced)).monospacedDigit()
                            ProgressView(value: Double(timer.elapsedMilliseconds), total: Double(timer.presetMilliseconds)).tint(timer.done ? .green : DiagramRenderer.accent)
                        }
                    }
                }
                if timers.isEmpty { Text("simulation.hint").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            Text("simulation.educational").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18).padding(.vertical, 12).background(.bar)
        .onAppear { _ = model.prepareSimulation() }
    }
}

extension LampColor {
    var color: Color {
        switch self {
        case .green: .green
        case .yellow: .yellow
        case .red: .red
        case .blue: .blue
        case .white: Color(white: 0.85)
        }
    }
}
