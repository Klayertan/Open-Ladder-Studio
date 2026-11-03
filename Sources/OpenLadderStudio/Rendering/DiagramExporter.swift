import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LadderCore

@MainActor
enum DiagramExporter {
    enum Format { case png, pdf }
    static func exportRenri(_ circuit: Circuit, report: @escaping (String) -> Void) {
        // Validate before presenting the save panel; no JSON-renaming fallback.
        do { _ = try RenriMBSExporter.export(circuit) }
        catch { report(error.localizedDescription); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "mbs", conformingTo: .data) ?? .data]
        panel.nameFieldStringValue = "KADAI10.MBS"
        panel.message = NSLocalizedString("export.renriWarning", comment: "Unverified format export")
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try RenriMBSExporter.export(circuit, fileName: url.lastPathComponent).write(to: url, options: .atomic) }
            catch { report(error.localizedDescription) }
        }
    }
    static func export(_ circuit: Circuit, format: Format, report: @escaping (String) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format == .png ? .png : .pdf]
        panel.nameFieldStringValue = (circuit.name == "Untitled" ? "Circuit" : circuit.name) + (format == .png ? ".png" : ".pdf")
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try write(circuit, format: format, to: url) }
            catch { report(error.localizedDescription) }
        }
    }
    static func write(_ circuit: Circuit, format: Format, to url: URL) throws {
        let size = DiagramMetrics.size(for: circuit)
        let content = Canvas { context, _ in
            DiagramRenderer.draw(circuit, context: &context, dark: false, grid: false)
        }.frame(width: size.width, height: size.height).background(.white).environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(size)
        if format == .png {
            renderer.scale = min(2, 8192 / max(size.width, size.height))
            guard let cgImage = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: .atomic)
        } else {
            var box = CGRect(origin: .zero, size: size)
            guard let data = CFDataCreateMutable(nil, 0), let consumer = CGDataConsumer(data: data),
                  let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
            renderer.render { _, render in
                context.beginPDFPage(nil); render(context); context.endPDFPage()
            }
            context.closePDF()
            guard CFDataGetLength(data) > 0 else { throw CocoaError(.fileWriteUnknown) }
            try (data as Data).write(to: url, options: .atomic)
        }
    }
}
