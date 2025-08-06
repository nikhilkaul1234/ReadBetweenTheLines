import SwiftUI
import AppKit

// MARK: - Helper NSView to expose the hosting NSWindow
class WindowBackedHelperView: NSView {
    var didMoveToWindowCallback: (NSWindow) -> Void

    init(didMoveToWindow: @escaping (NSWindow) -> Void) {
        self.didMoveToWindowCallback = didMoveToWindow
        super.init(frame: .zero)
        self.wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window = self.window else { return }
        didMoveToWindowCallback(window)
    }
}

struct WindowBackedView: NSViewRepresentable {
    var didMoveToWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowBackedHelperView {
        WindowBackedHelperView(didMoveToWindow: didMoveToWindow)
    }

    func updateNSView(_ nsView: WindowBackedHelperView, context: Context) {}
}

struct DidMoveToWindowModifier: ViewModifier {
    var didMoveToWindow: (NSWindow) -> Void

    func body(content: Content) -> some View {
        content.background(WindowBackedView(didMoveToWindow: didMoveToWindow))
    }
}

extension View {
    /// Executes a closure when the underlying `NSWindow` becomes available.
    func didMoveToWindow(_ callback: @escaping (NSWindow) -> Void) -> some View {
        modifier(DidMoveToWindowModifier(didMoveToWindow: callback))
    }
} 
