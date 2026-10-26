import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    var panel: SidePanel!
    var statusItem: NSStatusItem!
    var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = SidePanel(state: state)
        state.hide = { [weak self] in self?.panel.orderOut(nil) }

        installEditMenu()

        // Menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "SideNotes")
        let menu = NSMenu()
        add(menu, "Toggle Notes (⌥⌘N)", #selector(toggle))
        menu.addItem(.separator())
        add(menu, "Send All to Apple Notes", #selector(sendToNotes))
        add(menu, "Email All Notes…", #selector(emailNotes))
        add(menu, "Back Up Now", #selector(backup))
        add(menu, "Show Backups in Finder", #selector(showBackups))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit SideNotes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        // Global shortcut: Option + Command + N
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_N),
                        modifiers: UInt32(optionKey | cmdKey)) { [weak self] in
            self?.toggle()
        }

        state.autoBackupIfDue()
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.saveNow()
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
    }

    /// Menu-bar apps have no Edit menu, so ⌘C / ⌘V / ⌘Z wouldn't work in text fields without this.
    private func installEditMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let find = edit.addItem(withTitle: "Find", action: #selector(focusSearch), keyEquivalent: "f")
        find.target = self
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func showPanel() { if !panel.isVisible { panel.showOnRight() } }

    @objc func toggle() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.showOnRight() }
    }
    @objc func focusSearch() { NotificationCenter.default.post(name: .focusSearch, object: nil) }
    @objc func sendToNotes() { showPanel(); state.sendAllToAppleNotes() }
    @objc func emailNotes() { state.emailAllNotes() }
    @objc func backup() { showPanel(); state.backupNow() }
    @objc func showBackups() { state.showBackups() }
}
