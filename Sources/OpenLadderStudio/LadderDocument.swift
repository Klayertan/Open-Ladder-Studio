import SwiftUI
import Combine
import UniformTypeIdentifiers
import LadderCore

extension UTType {
    static let ladderProject = UTType(exportedAs: "studio.openladder.project", conformingTo: .json)
}

// AppKit may request snapshots off the main thread. The lock protects the value
// snapshot; UI mutation and Combine notification remain on the main actor.
final class LadderDocument: ReferenceFileDocument, @unchecked Sendable {
    typealias Snapshot = Circuit
    static var readableContentTypes: [UTType] { [.ladderProject] }
    let objectWillChange = ObservableObjectPublisher()
    private let lock = NSLock()
    private var storedCircuit: Circuit
    @MainActor var circuit: Circuit {
        get { lock.withLock { storedCircuit } }
        set {
            objectWillChange.send()
            lock.withLock { storedCircuit = newValue }
        }
    }

    init(circuit: Circuit = Circuit()) { storedCircuit = circuit }
    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        storedCircuit = try Circuit.decode(data)
    }
    func snapshot(contentType: UTType) throws -> Circuit { lock.withLock { storedCircuit } }
    func fileWrapper(snapshot: Circuit, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try snapshot.encoded())
    }
}
