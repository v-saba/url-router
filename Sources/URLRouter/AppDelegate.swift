import AppKit
import SwiftUI
import Combine

enum UnsavedDecision { case save, discard, cancel }

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var handledURL = false
    private var window: NSWindow?
    private var model: ConfigModel?
    private var cancellables = Set<AnyCancellable>()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Register for the GetURL Apple Event that macOS sends to the default browser.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        // A GetURL event (if any) arrives right around launch. Wait a beat; if no URL
        // was handled, the app was opened directly by the user → show the editor.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !self.handledURL else { return }
            self.showEditor()
        }
    }

    // MARK: URL routing

    /// Modern URL delivery (newer SDKs / `open --args`). macOS may use this instead of
    /// the GetURL Apple Event, so we must handle both to reliably route without a window.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { route(url) }
    }

    /// Legacy GetURL Apple Event delivery.
    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor,
                                 withReplyEvent reply: NSAppleEventDescriptor) {
        guard
            let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
            let url = URL(string: urlString)
        else { return }
        route(url)
    }

    /// Routes a URL to the right browser/profile. When the app was launched purely to
    /// handle a URL (no editor window), it quits immediately — never showing a window.
    private func route(_ url: URL) {
        handledURL = true
        let config = ConfigStore.shared.load()
        Launcher.launch(url: url, decision: RuleEngine.decide(url: url, config: config))
        if window == nil {            // headless launch → route and exit
            NSApp.terminate(nil)
        }
    }

    // MARK: Editor window

    /// Re-open (clicking the dock/Finder icon while running) also shows the editor.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showEditor() }
        return true
    }

    func showEditor() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        NSApp.setActivationPolicy(.regular)

        let model = ConfigModel()
        self.model = model
        // Reflect unsaved state in the window's close button (the standard "edited" dot).
        model.objectWillChange
            .sink { [weak self] in
                DispatchQueue.main.async { self?.window?.isDocumentEdited = model.isDirty }
            }
            .store(in: &cancellables)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "URL Router"
        window.center()
        window.contentView = NSHostingView(rootView: RootView(model: model))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Quit / close behavior

    /// Closing the editor window quits the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Closing the window (red button / ⌘W) prompts if there are unsaved changes.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let model, model.isDirty else { return true }
        confirmUnsaved(on: sender) { decision in
            switch decision {
            case .save: model.save(); sender.close()
            case .discard: model.discardChanges(); sender.close()
            case .cancel: break
            }
        }
        return false   // we close manually after the user answers
    }

    /// ⌘Q (or Quit menu) — same unsaved-changes prompt, then quit.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let window, let model, model.isDirty else { return .terminateNow }
        confirmUnsaved(on: window) { decision in
            switch decision {
            case .save: model.save(); NSApp.reply(toApplicationShouldTerminate: true)
            case .discard: NSApp.reply(toApplicationShouldTerminate: true)
            case .cancel: NSApp.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }

    private func confirmUnsaved(on window: NSWindow,
                                completion: @escaping (UnsavedDecision) -> Void) {
        let alert = NSAlert()
        alert.messageText = "You have unsaved changes."
        alert.informativeText = "Do you want to save your changes before closing?"
        alert.addButton(withTitle: "Save")        // .alertFirstButtonReturn (default)
        alert.addButton(withTitle: "Cancel")      // .alertSecondButtonReturn
        alert.addButton(withTitle: "Don't Save")  // .alertThirdButtonReturn (left-aligned)
        alert.beginSheetModal(for: window) { response in
            switch response {
            case .alertFirstButtonReturn: completion(.save)
            case .alertThirdButtonReturn: completion(.discard)
            default: completion(.cancel)
            }
        }
    }

    // MARK: Menu

    private func buildMainMenu() {
        let appName = "URL Router"
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About \(appName)",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // Edit menu (gives text fields Undo/Cut/Copy/Paste/Select All shortcuts)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All",
                         action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        // Window menu
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close",
                           action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }
}
