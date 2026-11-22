import AppKit
import SwiftUI
import LadderCore

struct TimingDiagramView: View {
    @ObservedObject var model: EditorViewModel
    @ObservedObject var document: LadderDocument
    @Environment(\.colorScheme) private var colorScheme
    @State private var windowSeconds = 40
    @State private var follow = true

    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:10) {
                Label("timing.title",systemImage:"waveform.path").font(.system(size:11,weight:.semibold))
                Spacer()
                Picker("timing.window",selection:$windowSeconds) {
                    Text("10 s").tag(10)
                    Text("40 s").tag(40)
                    Text("120 s").tag(120)
                    Text("timing.all").tag(0)
                }.labelsHidden().frame(width:88).help("timing.window")
                Toggle("timing.follow",isOn:$follow).toggleStyle(.checkbox).font(.system(size:10))
            }.padding(.horizontal,12).frame(height:34).background(.bar)
            Divider()
            GeometryReader { geometry in
                let state = model.simulation ?? SimulationState()
                let elapsed = Double(state.milliseconds-state.historyStartMilliseconds)/1000
                let span = windowSeconds == 0 ? max(10,elapsed+1) : Double(windowSeconds)
                let scale = max(2,(geometry.size.width-TimingDiagramRenderer.labelWidth-12)/span)
                let width = TimingDiagramRenderer.labelWidth + max(span,elapsed+1)*scale
                let hasOverflow = width > geometry.size.width
                let count = max(1,TimingDiagramRenderer.addresses(in:document.circuit).count)
                let rowSpacing = max(30, min(TimingDiagramRenderer.rowHeight, (geometry.size.height - TimingDiagramRenderer.headerHeight) / CGFloat(count)))
                let height = TimingDiagramRenderer.headerHeight + CGFloat(count)*rowSpacing
                ScrollView(.vertical) {
                    HStack(alignment:.top,spacing:0) {
                        // Keep device labels visible while the timeline scrolls.
                        Canvas { context, _ in
                            TimingDiagramRenderer.draw(document.circuit,state:state,context:&context,size:CGSize(width:width,height:max(100,height)),pixelsPerSecond:scale,dark:colorScheme == .dark,rowSpacing:rowSpacing)
                        }.frame(width:TimingDiagramRenderer.labelWidth,height:max(100,height)).clipped()
                        ScrollViewReader { reader in
                            ScrollView(.horizontal) {
                                HStack(spacing:0) {
                                    Canvas { context, _ in
                                        context.translateBy(x:-TimingDiagramRenderer.labelWidth,y:0)
                                        TimingDiagramRenderer.draw(document.circuit,state:state,context:&context,size:CGSize(width:width,height:max(100,height)),pixelsPerSecond:scale,dark:colorScheme == .dark,rowSpacing:rowSpacing)
                                    }.frame(width:width-TimingDiagramRenderer.labelWidth,height:max(100,height)).clipped()
                                        .accessibilityElement(children:.ignore)
                                        .accessibilityLabel("timing.accessibility")
                                    Color.clear.frame(width:1,height:1).id("timing.latest")
                                }
                            }.frame(height:max(100,height))
                            .onChange(of:state.milliseconds/100) { _, _ in
                                if follow && hasOverflow { reader.scrollTo("timing.latest",anchor:.trailing) }
                            }
                            .onChange(of:follow) { _, active in
                                if active && hasOverflow { reader.scrollTo("timing.latest",anchor:.trailing) }
                            }
                        }
                    }
                }
            }
            Divider()
            Text("timing.legend").font(.system(size:9)).foregroundStyle(.secondary)
                .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,12).padding(.vertical,5)
        }
        .background(Color(nsColor:.textBackgroundColor))
    }
}

struct TimingWindowView: View {
    @ObservedObject var model: EditorViewModel
    @ObservedObject var document: LadderDocument
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                SimulationTransportControls(model: model)
            }.padding(.horizontal, 16).padding(.vertical, 8).background(.bar)
            Divider()
            HSplitView {
                LiveCircuitPreview(circuit: document.circuit, state: model.simulation)
                    .frame(minWidth: 260, idealWidth: 520)
                TimingDiagramView(model: model, document: document)
                    .frame(minWidth: 430, idealWidth: 600)
            }
            Divider()
            ScrollView(.horizontal) {
                SimulationInputControls(model: model, document: document)
                    .padding(.horizontal, 16).padding(.vertical, 10)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
        .frame(minWidth: 740, minHeight: 440)
        .tint(DiagramRenderer.accent)
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
    }

    @MainActor
    static func makeWindow(model: EditorViewModel, document: LadderDocument) -> NSWindowController {
        let defaultSize = NSSize(width: 1120, height: 680)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "timing.title")
        window.isReleasedWhenClosed = false
        let hosting = NSHostingController(rootView: TimingWindowView(model: model, document: document))
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.contentMinSize = NSSize(width: 740, height: 440)
        window.setContentSize(defaultSize)
        window.center()
        return NSWindowController(window: window)
    }
}

private struct LiveCircuitPreview: View {
    let circuit: Circuit
    let state: SimulationState?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let size = DiagramMetrics.size(for: circuit)
            let scale = min(1, max(0.35, (geometry.size.width - 12) / size.width))
            ScrollView([.horizontal, .vertical]) {
                Canvas { context, _ in
                    context.scaleBy(x: scale, y: scale)
                    DiagramRenderer.draw(circuit, context: &context, dark: colorScheme == .dark, grid: false,
                                         energized: state?.energizedElements ?? [], counters: state?.counters ?? [:])
                }
                .frame(width: size.width * scale, height: size.height * scale)
                .accessibilityLabel("timing.circuit")
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
