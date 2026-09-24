#if os(macOS)
import AppKit
import SwiftUI

/// Reports whether the view it sits in is in a window. A Mac `NavigationStack`
/// takes the covered page out of the window when it pushes another, but
/// SwiftUI sends that page no `onDisappear` and its scroll visibility stays
/// true — so Discover's hero kept cycling and loading trailers under the
/// title page (Mac trace, 2026-09-24). A view never added to a window
/// reports nothing, so callers start from `false`.
struct AppleMacWindowPresence: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.onChange = onChange
    }

    final class ProbeView: NSView {
        var onChange: (Bool) -> Void = { _ in }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onChange(window != nil)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
#endif
