import SwiftUI
import LadderCore

struct ComponentSidebar: View {
    @ObservedObject var model: EditorViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                    .font(.system(size: 18)).foregroundStyle(DiagramRenderer.accent)
                    .frame(width: 36, height: 36).background(DiagramRenderer.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text("OPEN LADDER").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1)
                    Text("sidebar.subtitle").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 18).padding(.vertical, 22)
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    sectionTitle("sidebar.tools")
                    toolRow(.select, icon: "cursorarrow", shortcut: "V")
                    sectionTitle("sidebar.contacts").padding(.top, 20)
                    symbolRow(.normallyOpen, shortcut: "1")
                    symbolRow(.normallyClosed, shortcut: "2")
                    sectionTitle("sidebar.outputs").padding(.top, 20)
                    symbolRow(.coil, shortcut: "3")
                    symbolRow(.setCoil, shortcut: "4")
                    symbolRow(.resetCoil, shortcut: "5")
                    symbolRow(.timer, shortcut: "8")
                    symbolRow(.counter, shortcut: "9")
                    symbolRow(.risingPulse, shortcut: "P")
                    symbolRow(.fallingPulse, shortcut: "F")
                    sectionTitle("sidebar.connections").padding(.top, 20)
                    toolRow(.wire, icon: "pencil.tip", shortcut: "W")
                    toolRow(.branch, icon: "point.topleft.down.to.point.bottomright.curvepath", shortcut: "B")
                }.padding(.horizontal, 12).padding(.bottom, 20)
            }
            Divider()
            VStack(alignment: .leading, spacing: 9) {
                Label("sidebar.hintTitle", systemImage: "lightbulb").font(.system(size: 11, weight: .medium))
                Text("sidebar.hint").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }.padding(18)
        }.background(.background.opacity(0.35))
    }
    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key).font(.system(size: 9, weight: .semibold)).tracking(1.1).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.bottom, 6)
    }
    private func toolRow(_ tool: EditorTool, icon: String, shortcut: String) -> some View {
        row(tool, shortcut: shortcut) { Image(systemName: icon).font(.system(size: 15)).frame(width: 44, height: 28) }
    }
    private func symbolRow(_ kind: SymbolKind, shortcut: String) -> some View {
        row(.symbol(kind), shortcut: shortcut) { SymbolPreview(kind: kind) }
            .draggable("openladder.symbol:\(kind.rawValue)")
    }
    private func row<Icon: View>(_ tool: EditorTool, shortcut: String, @ViewBuilder icon: () -> Icon) -> some View {
        Button { model.tool = tool } label: {
            HStack(spacing: 5) {
                icon()
                Text(LocalizedStringKey(tool.key)).font(.system(size: 11, weight: model.tool == tool ? .semibold : .regular))
                Spacer(minLength: 2)
                Text(shortcut).font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 7).padding(.vertical, 5).contentShape(Rectangle())
                .foregroundStyle(model.tool == tool ? DiagramRenderer.accent : .primary)
                .background(model.tool == tool ? DiagramRenderer.accent.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).accessibilityLabel(Text(LocalizedStringKey(tool.key))).help(Text(LocalizedStringKey(tool.key)) + Text(" (\(shortcut))"))
    }
}
