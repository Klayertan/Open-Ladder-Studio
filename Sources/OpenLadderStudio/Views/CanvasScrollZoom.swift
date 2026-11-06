import SwiftUI
import AppKit

/// Observe wheel events only inside this canvas; sidebar/Inspector scrolling is untouched.
struct CanvasScrollZoom: NSViewRepresentable {
    let onScroll: (CGFloat, CGPoint) -> Void
    func makeNSView(context: Context) -> ScrollView {
        let view = ScrollView()
        view.onScroll = onScroll
        return view
    }
    func updateNSView(_ view: ScrollView, context: Context) { view.onScroll = onScroll }
    static func dismantleNSView(_ view: ScrollView, coordinator: ()) { view.stopMonitoring() }

    final class ScrollView: NSView {
        var onScroll: ((CGFloat, CGPoint) -> Void)?
        private var monitor: Any?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      window.isKeyWindow, !self.isHiddenOrHasHiddenAncestor else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.visibleRect.contains(point) else { return event }
                // Momentum belongs to the same gesture and remains canvas-local.
                self.onScroll?(event.scrollingDeltaY, point)
                return nil
            }
        }
        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
