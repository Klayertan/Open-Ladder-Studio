import SwiftUI
import LadderCore

struct TimingDiagramView: View {
    @ObservedObject var model: EditorViewModel
    @ObservedObject var document: LadderDocument
    var expanded = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var showExpanded = false
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
                Button {
                    if expanded { dismiss() } else { showExpanded = true }
                } label: { Image(systemName:expanded ? "xmark" : "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(.plain).help(expanded ? "timing.close" : "timing.expand")
            }.padding(.horizontal,12).frame(height:34).background(.bar)
            Divider()
            GeometryReader { geometry in
                let state = model.simulation ?? SimulationState()
                let elapsed = Double(state.milliseconds-state.historyStartMilliseconds)/1000
                let span = windowSeconds == 0 ? max(10,elapsed+1) : Double(windowSeconds)
                let scale = max(2,(geometry.size.width-TimingDiagramRenderer.labelWidth-12)/span)
                let width = TimingDiagramRenderer.labelWidth + max(span,elapsed+1)*scale
                let count = max(1,TimingDiagramRenderer.addresses(in:document.circuit).count)
                let rowSpacing = expanded ? max(30,min(TimingDiagramRenderer.rowHeight,(geometry.size.height-TimingDiagramRenderer.headerHeight)/CGFloat(count))) : TimingDiagramRenderer.rowHeight
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
                                if follow { reader.scrollTo("timing.latest",anchor:.trailing) }
                            }
                            .onChange(of:follow) { _, active in
                                if active { reader.scrollTo("timing.latest",anchor:.trailing) }
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
        .sheet(isPresented:$showExpanded) {
            TimingDiagramView(model:model,document:document,expanded:true).frame(minWidth:900,minHeight:650)
        }
    }
}
