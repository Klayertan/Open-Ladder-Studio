import XCTest
import AppKit
import PDFKit
import LadderCore
@testable import OpenLadderStudio

final class EditorIntegrationTests: XCTestCase {
    @MainActor func testNativeTextActionsKeepTextSelectionInsideFieldEditor() {
        _ = NSApplication.shared
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        text.string = "X0 and X1"
        let window = NSWindow(contentRect: text.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = text
        window.makeFirstResponder(text)
        defer { window.close() }
        var usedCircuitAction = false
        EditorTextActions.route(#selector(NSText.selectAll(_:)), window: window) { usedCircuitAction = true }
        XCTAssertFalse(usedCircuitAction)
        XCTAssertEqual(text.selectedRange(), NSRange(location: 0, length: text.string.utf16.count))
    }
    @MainActor func testDocumentEditingUndoAndRedo() throws {
        let document = LadderDocument()
        let model = EditorViewModel(document: document)
        let undo = UndoManager(); model.undoManager = undo
        undo.beginUndoGrouping()
        model.tool = .symbol(.normallyOpen); model.place(at: .init(1, 0))
        undo.endUndoGrouping()
        XCTAssertEqual(document.circuit.elements.count, 1)
        XCTAssertTrue(undo.canUndo)
        undo.undo()
        XCTAssertTrue(document.circuit.elements.isEmpty)
        undo.redo()
        XCTAssertEqual(document.circuit.elements.count, 1)
        XCTAssertEqual(try document.snapshot(contentType: .ladderProject), document.circuit)
    }
    @MainActor func testFailedMoveDoesNotAddUndoOrMutateDocument() {
        let document = LadderDocument(circuit: ExampleCircuits.sealIn)
        let model = EditorViewModel(document: document), undo = UndoManager()
        model.undoManager = undo
        model.selection = [document.circuit.elements[0].id]
        let original = document.circuit
        model.moveSelection(columns: 1, rows: 0)
        XCTAssertEqual(document.circuit, original)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(undo.canUndo)
    }
    @MainActor func testPNGAndPDFExportProduceReadableFiles() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let circuit = ExampleCircuits.sealIn
        let png = directory.appendingPathComponent("circuit.png"), pdf = directory.appendingPathComponent("circuit.pdf")
        try DiagramExporter.write(circuit, format: .png, to: png)
        let data = try Data(contentsOf: png)
        XCTAssertEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(bitmap.pixelsWide, Int(DiagramMetrics.size(for: circuit).width * 2))
        try DiagramExporter.write(circuit, format: .pdf, to: pdf)
        let pdfDocument = try XCTUnwrap(PDFDocument(url: pdf))
        XCTAssertEqual(pdfDocument.pageCount, 1)
        XCTAssertEqual(pdfDocument.page(at: 0)?.bounds(for: .mediaBox).size, DiagramMetrics.size(for: circuit))
    }
    @MainActor func testGeometrySnapsHorizontalAndVerticalEdges() {
        let p = GridPoint(2, 3), start = DiagramMetrics.point(p)
        XCTAssertEqual(DiagramMetrics.grid(.init(x: start.x + DiagramMetrics.cellWidth / 2, y: start.y + 5)), p)
        XCTAssertEqual(DiagramMetrics.grid(.init(x: start.x + 3, y: start.y + DiagramMetrics.cellHeight / 2), vertical: true), p)
    }
    @MainActor func testClipboardPasteIsUndoableAndUsesNewIdentifiers() {
        let document = LadderDocument(circuit: ExampleCircuits.sealIn)
        let model = EditorViewModel(document: document), undo = UndoManager()
        model.undoManager = undo
        model.selection = [document.circuit.elements[1].id]
        let saved = NSPasteboard.general.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        } ?? []
        defer { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(saved) }
        model.copy(); model.cursor = .init(1, 3)
        let previous = document.circuit
        undo.beginUndoGrouping(); model.paste(); undo.endUndoGrouping()
        XCTAssertEqual(document.circuit.elements.count, previous.elements.count + 1)
        XCTAssertTrue(model.selection.isDisjoint(with: Set(previous.elements.map(\.id))))
        undo.undo(); XCTAssertEqual(document.circuit, previous)
    }
}
