import AppKit
import Combine
import HitCore
import SwiftUI

@main
@MainActor
final class HitApp: NSObject, NSApplicationDelegate {
    let model: AppModel
    let popover = NSPopover()
    private(set) var statusItem: NSStatusItem?
    private var historyWindow: NSWindow?
    private var subscription: AnyCancellable?
    private var ticker: Timer?

    static func main() {
        let application = NSApplication.shared
        let delegate = HitApp()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }

    override init() {
        let fileURL = CommandLine.arguments.contains("--smoke-test")
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("Hit-Smoke-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent("workspace.json")
            : Journal.defaultFileURL
        model = AppModel(fileURL: fileURL)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "HitTimer"
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        item.button?.imagePosition = .imageLeading
        statusItem = item

        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(
            rootView: TimerView(
                model: model,
                showHistory: { [weak self] in self?.showHistory() },
                resize: { [weak self] size in self?.popover.contentSize = size }
            )
        )
        subscription = model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateStatus() }
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.model.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        updateStatus()
        showPanel()

        if CommandLine.arguments.contains("--smoke-test") {
            Task { await SmokeTest.run(app: self) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        do {
            try model.saveBeforeQuit()
            return .terminateNow
        } catch {
            let alert = NSAlert()
            alert.messageText = "Some changes have not been saved"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "Keep Hit Open")
            alert.addButton(withTitle: "Quit Without Saving")
            return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
        }
    }

    @objc func togglePanel() {
        if popover.isShown { popover.performClose(nil) } else { showPanel() }
    }

    func showPanel() {
        guard let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func updateStatus() {
        guard let button = statusItem?.button else { return }
        let symbol = model.error != nil ? "exclamationmark.triangle" :
            (model.current?.status == .paused ? "pause.circle" : "timer")
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Hit")
        button.title = " " + model.timeLabel
        button.toolTip = model.error ?? "Hit · \(model.kind.label) · \(model.primaryTitle)"
        button.setAccessibilityLabel("Hit, \(model.kind.label), \(model.timeLabel), \(model.primaryTitle)")
    }

    @objc func showHistory() {
        popover.performClose(nil)
        if historyWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            window.title = "History — Hit"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: HistoryView(model: model))
            window.center()
            historyWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        historyWindow?.makeKeyAndOrderFront(nil)
    }

    private func installMainMenu() {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Show Timer", action: #selector(showTimerFromMenu), keyEquivalent: "1").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Hit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        // Preserve standard text editing for task titles and notes in an accessory app.
        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [
            ("Undo", "undo:", "z"), ("Redo", "redo:", "Z"),
            ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
            ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")
        ] {
            edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @objc private func showTimerFromMenu() { showPanel() }
}

func revealWorkspace(_ fileURL: URL) {
    if FileManager.default.fileExists(atPath: fileURL.path) {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    } else {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path)
    }
}
