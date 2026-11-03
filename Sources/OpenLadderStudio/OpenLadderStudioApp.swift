import SwiftUI
import LadderCore

@main
struct OpenLadderStudioApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { LadderDocument() }) { configuration in
            EditorView(document: configuration.document)
        }
        .defaultSize(width: 1440, height: 900)
        .commands { EditorCommands() }
        Settings { AppSettingsView() }
    }
}

struct EditorFocusKey: FocusedValueKey { typealias Value = EditorViewModel }
extension FocusedValues {
    var ladderEditor: EditorViewModel? {
        get { self[EditorFocusKey.self] }
        set { self[EditorFocusKey.self] = newValue }
    }
}

struct EditorCommands: Commands {
    @FocusedValue(\.ladderEditor) private var editor
    var body: some Commands {
        CommandGroup(replacing: .pasteboard) {
            Button("edit.cut") { EditorTextActions.route(#selector(NSText.cut(_:))) { editor?.cut() } }.keyboardShortcut("x")
            Button("edit.copy") { EditorTextActions.route(#selector(NSText.copy(_:))) { editor?.copy() } }.keyboardShortcut("c")
            Button("edit.paste") { EditorTextActions.route(#selector(NSText.paste(_:))) { editor?.paste() } }.keyboardShortcut("v")
            Divider()
            Button("edit.selectAll") { EditorTextActions.route(#selector(NSText.selectAll(_:))) { editor?.selectAll() } }.keyboardShortcut("a")
        }
        CommandMenu("menu.circuit") {
            Button("tool.select") { editor?.tool = .select }
            Button("tool.pan") { editor?.tool = .pan }
            Divider()
            ForEach(SymbolKind.allCases, id: \.self) { kind in
                Button(LocalizedStringKey(kind.localizationKey)) { editor?.tool = .symbol(kind) }
            }
            Button("tool.branch") { editor?.tool = .branch }
            Divider()
            Button("edit.delete") { EditorTextActions.route(#selector(NSText.deleteBackward(_:))) { editor?.deleteSelection() } }.keyboardShortcut(.delete, modifiers: [])
            Button("validation.check") { editor?.showValidation.toggle() }.keyboardShortcut("k", modifiers: [.command, .shift])
            Button("simulation.title") { editor?.showSimulation.toggle() }.keyboardShortcut("r", modifiers: [.command, .shift])
        }
        CommandGroup(after: .importExport) {
            Button("export.png") { if let editor { DiagramExporter.export(editor.circuit, format: .png, report: { editor.errorMessage = $0 }) } }
            Button("export.pdf") { if let editor { DiagramExporter.export(editor.circuit, format: .pdf, report: { editor.errorMessage = $0 }) } }
            Button("export.renri") { if let editor { DiagramExporter.exportRenri(editor.circuit, report: { editor.errorMessage = $0 }) } }
        }
        CommandGroup(after: .toolbar) {
            Button("zoom.in") { editor?.setZoom((editor?.zoom ?? 1) * 1.2) }.keyboardShortcut("+")
            Button("zoom.out") { editor?.setZoom((editor?.zoom ?? 1) / 1.2) }.keyboardShortcut("-")
            Button("zoom.actual") { editor?.setZoom(1) }.keyboardShortcut("0")
        }
    }
}

/// Native field editors (including save-panel sheets) take precedence even when
/// no document editor has a focused scene value.
@MainActor
enum EditorTextActions {
    static func route(_ selector: Selector, window: NSWindow? = nil, fallback: () -> Void) {
        let window = window ?? NSApp.keyWindow ?? NSApp.modalWindow
        let responder = window?.attachedSheet?.firstResponder ?? window?.firstResponder
        if let text = responder as? NSText, text.isEditable {
            NSApp.sendAction(selector, to: text, from: nil)
        } else if let target = NSApp.target(forAction: selector), target is NSText || target is NSTextField {
            NSApp.sendAction(selector, to: target, from: nil)
        } else { fallback() }
    }
}

struct AppSettingsView: View {
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        Form {
            Picker("settings.appearance", selection: $appearance) {
                Text("settings.system").tag("system")
                Text("settings.light").tag("light")
                Text("settings.dark").tag("dark")
            }
            Text("settings.languageHint").font(.caption).foregroundStyle(.secondary)
            Text("settings.version").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 420)
    }
}
