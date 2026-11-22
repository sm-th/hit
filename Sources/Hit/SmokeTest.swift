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
                  let primary = findButton(in: content), primary.isEnabled else {
                throw Failure("The menu-bar panel has no enabled Start button")
            }
            guard !app.model.detailsExpanded else { throw Failure("Notes should remain collapsed") }
            try await enterTitle("Before starting", in: app)
            let draft = try Journal(fileURL: app.model.fileURL)
            guard draft.state.draftTitle == "Before starting" else {
                throw Failure("The inline title did not save before starting")
            }
            try await enterTitle("", in: app)
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

            try await enterTitle("Write the first draft", in: app)
            let renamed = try Journal(fileURL: app.model.fileURL)
            guard !app.model.detailsExpanded, renamed.state.current?.title == "Write the first draft" else {
                throw Failure("Inline naming required opening Notes or failed to save")
            }
            try await enterTitle("", in: app)
            guard app.model.current?.title == "", app.model.current?.status == .running else {
                throw Failure("Clearing the optional title interrupted the timer")
            }
            try await enterTitle("Write the first draft", in: app)
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
            try await verifyBreakTransitions(app: app)
            print("SMOKE_TEST_PASSED: inline editing, automatic full-screen break, Escape/minimize, background countdown, break completion, Skip Break with saved timing, manual next focus")
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

    private static func verifyBreakTransitions(app: HitApp) async throws {
        app.popover.performClose(nil)
        app.model.finishEarly()
        let fixture = try Journal(fileURL: app.model.fileURL)
        try fixture.setTitle("Take a real break")
        try fixture.start(at: Date().addingTimeInterval(-1496))
        try fixture.setNotes("Completion must bring the break to the foreground.")
        app.model.load()
        try await waitFor("Focus completion did not show the full-screen break") {
            app.model.current?.kind == .rest && app.breakPresenter.isVisible
        }
        try verifyScreenCoverage(app: app)
        guard app.model.current?.status == .running, app.model.secondsRemaining > 290,
              app.model.journal?.state.history.first?.notes == "Completion must bring the break to the foreground." else {
            throw Failure("The break did not start automatically or focus notes were lost")
        }
        let saved = try Journal(fileURL: app.model.fileURL)
        guard saved.state.current?.kind == .rest, saved.state.current?.status == .running else {
            throw Failure("The automatically started break was not saved")
        }
        try captureBreak(suffix: "-break")
        let remaining = app.model.secondsRemaining
        guard let window = app.breakPresenter.windows.first(where: { $0.isVisible }),
              let escape = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false, keyCode: 53
              ) else { throw Failure("Could not send Escape to the break window") }
        NSApp.sendEvent(escape)
        try await waitFor("Escape did not minimize the break") { !app.breakPresenter.isVisible }
        try await Task.sleep(nanoseconds: 2_200_000_000)
        guard !app.breakPresenter.isVisible, app.model.current?.kind == .rest,
              app.model.current?.status == .running, app.model.secondsRemaining < remaining else {
            throw Failure("Minimizing paused the break or ordinary ticks reopened its window")
        }

        // Restore a real persisted break near its deadline; the app's ordinary ticker completes it.
        let ending = try Journal(fileURL: app.model.fileURL)
        try ending.stop()
        try ending.start(at: Date().addingTimeInterval(-1796))
        try ending.reconcile()
        app.model.load()
        try await waitFor("Restoring an ongoing break did not show its window") { app.breakPresenter.isVisible }
        app.breakPresenter.windows.first?.miniaturize(nil)
        try await waitFor("Native minimize did not hide the break") { !app.breakPresenter.isVisible }
        try await waitFor("Break completion did not notify while minimized") {
            app.model.current == nil && app.breakPresenter.isVisible
        }
        guard let notice = app.model.breakNotice, case .completed = notice,
              app.model.journal?.state.history.first?.status == .completed else {
            throw Failure("Break completion did not wait for manual focus start")
        }
        try verifyScreenCoverage(app: app)
        try captureBreak(suffix: "-ready")
        guard let content = app.breakPresenter.windows.first?.contentView,
              let start = findButton(in: content) else {
            throw Failure("The break-complete window has no Start Focus control")
        }
        start.performClick(nil)
        try await waitFor("Starting focus did not dismiss the break window") {
            app.model.current?.kind == .focus && app.model.current?.status == .running &&
                !app.breakPresenter.isVisible
        }

        app.model.finishEarly()
        let skipping = try Journal(fileURL: app.model.fileURL)
        try skipping.start(at: Date().addingTimeInterval(-1496))
        app.model.load()
        try await waitFor("A new focus did not produce a skippable break") {
            app.model.current?.kind == .rest && app.breakPresenter.isVisible
        }
        guard let skipContent = app.breakPresenter.windows.first?.contentView,
              let skip = findButton(in: skipContent, identifier: "skipBreakAction") else {
            throw Failure("The full-screen break has no Skip Break button")
        }
        skip.performClick(nil)
        try await waitFor("Skip Break did not immediately start focus and dismiss the overlay") {
            app.model.current?.kind == .focus && !app.breakPresenter.isVisible
        }
        let afterSkip = try Journal(fileURL: app.model.fileURL)
        guard let record = afterSkip.state.history.first,
              record.kind == .rest, record.status == .stopped,
              record.duration == 300, record.remaining > 290,
              let ended = record.endedAt, ended >= record.startedAt,
              afterSkip.state.current?.kind == .focus,
              afterSkip.state.current?.status == .running else {
            throw Failure("Skip Break did not save its outcome and actual timing with the new focus")
        }
    }

    private static func verifyScreenCoverage(app: HitApp) throws {
        guard !NSScreen.screens.isEmpty else { throw Failure("No display is available") }
        for screen in NSScreen.screens {
            guard app.breakPresenter.windows.contains(where: {
                $0.isVisible && $0.frame == screen.frame && $0.level == .statusBar
            }) else { throw Failure("The break does not cover an entire display, including menu bar and Dock") }
        }
    }

    private static func captureBreak(suffix: String) throws {
        if let path = ProcessInfo.processInfo.environment["HIT_SMOKE_SCREENSHOT"] {
            try screenshot(URL(fileURLWithPath: path).deletingPathExtension().path + suffix + ".png")
        }
    }

    private static func waitFor(_ message: String, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw Failure(message)
    }

    private static func enterTitle(_ value: String, in app: HitApp) async throws {
        guard let content = app.popover.contentViewController?.view,
              let field = findTitleField(in: content),
              let window = field.window, window.makeFirstResponder(field),
              let editor = field.currentEditor() as? NSTextView else {
            throw Failure("The title above the timer is not directly editable")
        }
        editor.selectAll(nil)
        if value.isEmpty {
            editor.deleteBackward(nil)
        } else {
            editor.insertText(value, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        let saved = try Journal(fileURL: app.model.fileURL)
        guard (saved.state.current?.title ?? saved.state.draftTitle) == value else {
            throw Failure("The inline title was not saved while typing")
        }
        // Enter ends editing; persistence is asserted independently of committing the field.
        editor.insertNewline(nil)
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    private static func findTitleField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        for child in view.subviews {
            if let found = findTitleField(in: child) { return found }
        }
        return nil
    }

    private static func findButton(in view: NSView, identifier: String = "primaryTimerAction") -> NSButton? {
        if let button = view as? NSButton, button.identifier?.rawValue == identifier { return button }
        for child in view.subviews {
            if let found = findButton(in: child, identifier: identifier) { return found }
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
            throw Failure("Could not capture the actual application interface")
        }
    }

    private struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
