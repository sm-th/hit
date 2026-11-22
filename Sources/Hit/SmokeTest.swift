import AppKit
import Darwin
import HitCore

/// Runs only with an isolated workspace supplied by --smoke-test.
@MainActor
enum SmokeTest {
    static func run(app: HitApp) async {
        do {
            try await Task.sleep(nanoseconds: 500_000_000)
            guard let statusButton = app.statusItem?.button, app.statusItem?.isVisible == true else {
                throw Failure("Hit is missing from the menu bar")
            }
            // Reopen through the actual status button, not a separate test-only action.
            app.popover.performClose(nil)
            statusButton.performClick(nil)
            try await Task.sleep(nanoseconds: 300_000_000)
            guard app.popover.isShown,
                  let content = app.popover.contentViewController?.view,
                  let primary = findPrimaryButton(in: content), primary.isEnabled else {
                throw Failure("The menu-bar panel has no enabled Start button")
            }
            guard app.model.title.isEmpty, app.model.notes.isEmpty else {
                throw Failure("The fresh workspace unexpectedly requires task input")
            }
            primary.performClick(nil)
            guard app.model.current?.status == .running,
                  app.model.current?.title == "", app.model.secondsRemaining >= 1498 else {
                throw Failure("One click did not start an unnamed 25-minute focus interval")
            }
            try await Task.sleep(nanoseconds: 200_000_000)
            primary.performClick(nil)
            guard app.model.current?.status == .paused else { throw Failure("Pause did not work") }
            try await Task.sleep(nanoseconds: 200_000_000)
            primary.performClick(nil)
            guard app.model.current?.status == .running else { throw Failure("Resume did not work") }

            app.model.title = "Write the first draft"
            app.model.notes = "Started first. Added a thought along the way."
            let beforeClosing = app.model.secondsRemaining
            app.popover.performClose(nil)
            try await Task.sleep(nanoseconds: 2_200_000_000)
            guard !app.popover.isShown, app.model.secondsRemaining < beforeClosing,
                  app.applicationShouldTerminateAfterLastWindowClosed(NSApp) == false else {
                throw Failure("The timer did not keep running with the panel closed")
            }
            let restored = try Journal(fileURL: app.model.fileURL)
            guard restored.state.current?.title == "Write the first draft",
                  restored.state.current?.notes == "Started first. Added a thought along the way.",
                  restored.state.current?.status == .running else {
                throw Failure("Optional task edits did not survive reopening")
            }
            statusButton.performClick(nil)
            try await Task.sleep(nanoseconds: 300_000_000)
            guard app.popover.isShown, statusButton.title.contains(app.model.timeLabel) else {
                throw Failure("The status button did not reopen the timer or display its countdown")
            }
            if let path = ProcessInfo.processInfo.environment["HIT_SMOKE_SCREENSHOT"] {
                try screenshot(path)
                app.model.detailsExpanded = true
                try await Task.sleep(nanoseconds: 500_000_000)
                let details = URL(fileURLWithPath: path).deletingPathExtension().path + "-notes.png"
                try screenshot(details)
            }
            print("SMOKE_TEST_PASSED: menu-bar Start/Pause/Resume, title-free start, hidden-panel countdown, durable optional notes")
            fflush(stdout)
            app.popover.performClose(nil)
            // Exit directly after cleanup, without invoking regular quit-time saving.
            try FileManager.default.removeItem(at: app.model.fileURL.deletingLastPathComponent())
            exit(0)
        } catch {
            fputs("SMOKE_TEST_FAILED: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func findPrimaryButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.identifier?.rawValue == "primaryTimerAction" { return button }
        for child in view.subviews {
            if let found = findPrimaryButton(in: child) { return found }
        }
        return nil
    }

    private static func screenshot(_ path: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: path) else {
            throw Failure("Could not capture the actual menu-bar panel")
        }
    }

    private struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
