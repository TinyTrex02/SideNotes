import AppKit
import SwiftUI
import Combine

final class SidePanel: NSPanel {
    private let state: AppState
    private var bag = Set<AnyCancellable>()
    private var pinned = true

    init(state: AppState) {
        self.state = state
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 700),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        level = .floating
        // Appear on every Space and over full-screen apps
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isFloatingPanel = true
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        isMovableByWindowBackground = true
        minSize = NSSize(width: 280, height: 300)
        contentView = NSHostingView(rootView: ContentView().environmentObject(state))

        state.$pinned.sink { [weak self] p in
            self?.pinned = p
            self?.level = p ? .floating : .normal
        }.store(in: &bag)
        state.$opacity.sink { [weak self] o in self?.alphaValue = CGFloat(o) }.store(in: &bag)
    }

    override var canBecomeKey: Bool { true }

    // Esc hides the panel
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }

    // When not pinned, hide as soon as you click elsewhere
    override func resignKey() {
        super.resignKey()
        if !pinned && attachedSheet == nil { orderOut(nil) }
    }

    func showOnRight() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let f = screen?.visibleFrame else { return }
        let width: CGFloat = max(frame.width, 380)
        setFrame(NSRect(x: f.maxX - width, y: f.minY, width: width, height: f.height), display: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(state.editor.textView)
    }
}
