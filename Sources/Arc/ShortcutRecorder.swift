import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    let record: (NSEvent) -> Void
    let cancel: () -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.record = record
        view.cancel = cancel
        return view
    }

    func updateNSView(_ view: CaptureView, context: Context) {
        view.record = record
        view.cancel = cancel
    }

    final class CaptureView: NSView {
        var record: ((NSEvent) -> Void)?
        var cancel: (() -> Void)?
        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.window?.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { cancel?() }
            else { record?(event) }
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self else { return false }
            keyDown(with: event)
            return true
        }
    }
}
