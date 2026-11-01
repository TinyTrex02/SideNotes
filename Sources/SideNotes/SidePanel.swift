import AppKit
import SwiftUI
import Combine
import QuartzCore

final class SidePanel: NSPanel {
    private let state: AppState
    private var bag = Set<AnyCancellable>()
    private var pinned = true
    private var expandedFrame: NSRect?
    private let dotSize = NSSize(width: 52, height: 52)

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
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
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
        state.$isCollapsed
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] collapsed in self?.setCollapsed(collapsed) }
            .store(in: &bag)
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
        if state.isCollapsed {
            makeKeyAndOrderFront(nil)
            return
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let f = screen?.visibleFrame else { return }
        let width: CGFloat = max(frame.width, 380)
        setFrame(NSRect(x: f.maxX - width, y: f.minY, width: width, height: f.height), display: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(state.editor.textView)
    }

    private func setCollapsed(_ collapsed: Bool) {
        if collapsed {
            expandedFrame = frame
            let target = NSRect(x: frame.maxX - dotSize.width - 8,
                                y: frame.maxY - dotSize.height - 8,
                                width: dotSize.width,
                                height: dotSize.height)
            minSize = dotSize
            styleMask = [.nonactivatingPanel, .borderless]
            isMovableByWindowBackground = true
            animate(to: target)
        } else {
            let target = expandedFrame ?? expandedFrameOnCurrentScreen()
            styleMask = [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable]
            titleVisibility = .hidden
            titlebarAppearsTransparent = true
            standardWindowButton(.closeButton)?.isHidden = true
            standardWindowButton(.miniaturizeButton)?.isHidden = true
            standardWindowButton(.zoomButton)?.isHidden = true
            minSize = NSSize(width: 280, height: 300)
            isMovableByWindowBackground = true
            animate(to: target)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.makeFirstResponder(self.state.editor.textView)
                self.state.editor.resizeDividers()
            }
        }
    }

    private func expandedFrameOnCurrentScreen() -> NSRect {
        let screen = self.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return NSRect(x: 0, y: 0, width: 380, height: 700) }
        return NSRect(x: visible.maxX - 380, y: visible.minY, width: 380, height: visible.height)
    }

    private func animate(to target: NSRect) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(target, display: true)
        }
    }
}
