import Foundation
import HitCore
import XCTest

final class JournalTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor
    private func withJournal(_ body: (Journal, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HitTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("workspace.json")
        try body(Journal(fileURL: url), url)
    }

    @MainActor
    func testDraftTaskAndMultilineNotesSurviveReopening() async throws {
        try withJournal { journal, url in
            try journal.setTitle("Prepare a proposal")
            try journal.setNotes("First idea\nA second thought — café")
            let reopened = try Journal(fileURL: url)
            XCTAssertEqual(reopened.state.draftTitle, "Prepare a proposal")
            XCTAssertEqual(reopened.state.draftNotes, "First idea\nA second thought — café")
        }
    }

    @MainActor
    func testRunningTimerAndEditedNotesSurviveReopening() async throws {
        try withJournal { journal, url in
            try journal.setTitle("Write the introduction")
            try journal.start(at: start)
            try journal.setTitle("Write a better introduction")
            try journal.setNotes("Explain the problem first.")
            let reopened = try Journal(fileURL: url)
            XCTAssertEqual(reopened.state.current?.secondsRemaining(at: start.addingTimeInterval(90)), 1410)
            XCTAssertEqual(reopened.state.current?.title, "Write a better introduction")
            XCTAssertEqual(reopened.state.current?.notes, "Explain the problem first.")
            XCTAssertEqual(reopened.state.draftTitle, "")
        }
    }

    @MainActor
    func testPauseSurvivesRelaunchAndResumeUsesOnlyRemainingTime() async throws {
        try withJournal { journal, url in
            try journal.setTitle("Read a chapter")
            try journal.start(at: start)
            try journal.pause(at: start.addingTimeInterval(100.25))
            let reopened = try Journal(fileURL: url)
            XCTAssertEqual(reopened.state.current?.secondsRemaining(at: start.addingTimeInterval(10_000)), 1400)
            try reopened.resume(at: start.addingTimeInterval(10_000))
            XCTAssertEqual(reopened.state.current?.secondsRemaining(at: start.addingTimeInterval(10_030)), 1370)
        }
    }

    @MainActor
    func testFocusCompletionStartsAndPersistsBreakAtTheOriginalDeadline() async throws {
        try withJournal { journal, url in
            try journal.setTitle("Sketch a solution")
            try journal.start(at: start)
            try journal.setNotes("Keep the simple version.")
            try journal.reconcile(at: start.addingTimeInterval(1501))
            let reopened = try Journal(fileURL: url)
            XCTAssertEqual(reopened.state.current?.kind, .rest)
            XCTAssertEqual(reopened.state.current?.status, .running)
            XCTAssertEqual(reopened.state.current?.startedAt, start.addingTimeInterval(1500))
            XCTAssertEqual(reopened.state.current?.deadline, start.addingTimeInterval(1800))
            XCTAssertEqual(reopened.state.current?.secondsRemaining(at: start.addingTimeInterval(1501)), 299)
            XCTAssertEqual(reopened.state.history.first?.notes, "Keep the simple version.")
            XCTAssertEqual(reopened.state.history.first?.endedAt, start.addingTimeInterval(1500))
            let breakID = reopened.state.current?.id
            try reopened.reconcile(at: start.addingTimeInterval(1502))
            XCTAssertEqual(reopened.state.current?.id, breakID)
            XCTAssertEqual(reopened.state.history.count, 1)
        }
    }

    @MainActor
    func testLongAbsenceCompletesOnlyOneFocusAndOneBreakAtTheirDeadlines() async throws {
        try withJournal { journal, url in
            try journal.start(at: start)
            try journal.reconcile(at: start.addingTimeInterval(86_400))
            try journal.reconcile(at: start.addingTimeInterval(90_000))
            let reopened = try Journal(fileURL: url)
            XCTAssertNil(reopened.state.current)
            XCTAssertEqual(reopened.state.nextKind, .focus)
            XCTAssertEqual(reopened.state.history.count, 2)
            XCTAssertEqual(reopened.state.history.first?.kind, .rest)
            XCTAssertEqual(reopened.state.history.first?.status, .completed)
            XCTAssertEqual(reopened.state.history.first?.endedAt, start.addingTimeInterval(1800))
            XCTAssertEqual(reopened.state.history.first?.startedAt, start.addingTimeInterval(1500))
            XCTAssertEqual(reopened.state.history.first?.duration, 300)
            XCTAssertEqual(reopened.state.history.first?.remaining, 0)
            XCTAssertEqual(reopened.state.history.last?.endedAt, start.addingTimeInterval(1500))
        }
    }

    @MainActor
    func testPausedAutomaticBreakSurvivesReopeningWithoutRunningInTheBackground() async throws {
        try withJournal { journal, url in
            try journal.start(at: start)
            try journal.reconcile(at: start.addingTimeInterval(1500))
            try journal.pause(at: start.addingTimeInterval(1550))
            let reopened = try Journal(fileURL: url)
            try reopened.reconcile(at: start.addingTimeInterval(10_000))
            XCTAssertEqual(reopened.state.current?.kind, .rest)
            XCTAssertEqual(reopened.state.current?.status, .paused)
            XCTAssertEqual(reopened.state.current?.secondsRemaining(at: start.addingTimeInterval(10_000)), 250)
            try reopened.resume(at: start.addingTimeInterval(10_000))
            try reopened.reconcile(at: start.addingTimeInterval(10_250))
            XCTAssertNil(reopened.state.current)
            XCTAssertEqual(reopened.state.nextKind, .focus)
            XCTAssertEqual(reopened.state.history.count, 2)
        }
    }

    @MainActor
    func testStoppingEarlyPreservesTaskAndNotesInHistory() async throws {
        try withJournal { journal, url in
            try journal.setTitle("Investigate an idea")
            try journal.start(at: start)
            try journal.setNotes("Continue with the smaller approach tomorrow.")
            try journal.stop(at: start.addingTimeInterval(45))
            let reopened = try Journal(fileURL: url)
            XCTAssertNil(reopened.state.current)
            XCTAssertEqual(reopened.state.history.first?.status, .stopped)
            XCTAssertEqual(reopened.state.history.first?.remaining, 1455)
            XCTAssertEqual(reopened.state.history.first?.notes, "Continue with the smaller approach tomorrow.")
            XCTAssertEqual(reopened.state.nextKind, .focus)
        }
    }

    @MainActor
    func testPausingAnExpiredFocusStartsBreakInsteadOfCreatingAZeroLengthPause() async throws {
        try withJournal { journal, _ in
            try journal.setTitle("Finish a draft")
            try journal.start(at: start)
            try journal.pause(at: start.addingTimeInterval(1500))
            XCTAssertEqual(journal.state.current?.kind, .rest)
            XCTAssertEqual(journal.state.current?.status, .running)
            XCTAssertEqual(journal.state.history.first?.status, .completed)
        }
    }

    @MainActor
    func testSkippingAnAutomaticBreakRecordsItsTimingAndImmediatelyStartsFocus() async throws {
        try withJournal { journal, url in
            try journal.setTitle("One task")
            try journal.start(at: start)
            try journal.reconcile(at: start.addingTimeInterval(1500))
            try journal.skipBreak(at: start.addingTimeInterval(1550))
            let reopened = try Journal(fileURL: url)
            XCTAssertEqual(reopened.state.nextKind, .focus)
            XCTAssertEqual(reopened.state.current?.kind, .focus)
            XCTAssertEqual(reopened.state.current?.status, .running)
            XCTAssertEqual(reopened.state.current?.startedAt, start.addingTimeInterval(1550))
            XCTAssertEqual(reopened.state.history.count, 2)
            XCTAssertEqual(reopened.state.history.first?.kind, .rest)
            XCTAssertEqual(reopened.state.history.first?.status, .stopped)
            XCTAssertEqual(reopened.state.history.first?.remaining, 250)
            XCTAssertEqual(reopened.state.history.first?.duration, 300)
            XCTAssertEqual(reopened.state.history.first?.startedAt, start.addingTimeInterval(1500))
            XCTAssertEqual(reopened.state.history.first?.endedAt, start.addingTimeInterval(1550))
            XCTAssertEqual(reopened.state.history.last?.kind, .focus)
        }
    }

    @MainActor
    func testSkippingAPausedBreakPreservesActiveTimeSeparatelyFromWallTime() async throws {
        try withJournal { journal, url in
            try journal.start(at: start)
            try journal.reconcile(at: start.addingTimeInterval(1500))
            try journal.pause(at: start.addingTimeInterval(1550))
            try journal.skipBreak(at: start.addingTimeInterval(1600))
            let reopened = try Journal(fileURL: url)
            XCTAssertEqual(reopened.state.current?.kind, .focus)
            XCTAssertEqual(reopened.state.history.first?.kind, .rest)
            XCTAssertEqual(reopened.state.history.first?.remaining, 250)
            XCTAssertEqual(reopened.state.history.first?.endedAt, start.addingTimeInterval(1600))
            XCTAssertEqual(reopened.state.history.first?.status, .stopped)
        }
    }

    @MainActor
    func testSkippingAnAlreadyElapsedBreakRecordsCompletionRatherThanLostTime() async throws {
        try withJournal { journal, url in
            try journal.start(at: start)
            try journal.reconcile(at: start.addingTimeInterval(1500))
            try journal.skipBreak(at: start.addingTimeInterval(1801))
            let reopened = try Journal(fileURL: url)
            XCTAssertEqual(reopened.state.history.first?.kind, .rest)
            XCTAssertEqual(reopened.state.history.first?.status, .completed)
            XCTAssertEqual(reopened.state.history.first?.remaining, 0)
            XCTAssertEqual(reopened.state.history.first?.endedAt, start.addingTimeInterval(1800))
            XCTAssertEqual(reopened.state.current?.startedAt, start.addingTimeInterval(1801))
        }
    }

    @MainActor
    func testSkippingAPreviouslySavedPendingBreakRecordsZeroTimeAndKeepsTheNextTask() async throws {
        try withJournal { _, url in
            let data = Data("""
            {"schemaVersion":1,"draftTitle":"Next task","draftNotes":"Keep this note","history":[],"nextKind":"rest"}
            """.utf8)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            let pending = try Journal(fileURL: url)
            try pending.skipBreak(at: start)
            let reopened = try Journal(fileURL: url)
            XCTAssertEqual(reopened.state.current?.kind, .focus)
            XCTAssertEqual(reopened.state.current?.title, "Next task")
            XCTAssertEqual(reopened.state.current?.notes, "Keep this note")
            XCTAssertEqual(reopened.state.history.first?.kind, .rest)
            XCTAssertEqual(reopened.state.history.first?.status, .stopped)
            XCTAssertEqual(reopened.state.history.first?.startedAt, start)
            XCTAssertEqual(reopened.state.history.first?.endedAt, start)
            XCTAssertEqual(reopened.state.history.first?.remaining, 300)
        }
    }

    @MainActor
    func testUntitledFocusStartsImmediatelyAndCanBeNamedWhileRunning() async throws {
        try withJournal { journal, url in
            try journal.start(at: start)
            XCTAssertEqual(journal.state.current?.status, .running)
            XCTAssertEqual(journal.state.current?.secondsRemaining(at: start), 1500)
            XCTAssertEqual(journal.state.current?.title, "")
            try journal.setTitle("A name added later")
            try journal.setNotes("A thought captured after starting.")
            let reopened = try Journal(fileURL: url)
            XCTAssertEqual(reopened.state.current?.title, "A name added later")
            XCTAssertEqual(reopened.state.current?.notes, "A thought captured after starting.")
            XCTAssertEqual(reopened.state.current?.startedAt, start)
        }
    }

    @MainActor
    func testWhitespaceTitleIsOptionalAndAnActiveSessionCannotBeReplaced() async throws {
        try withJournal { journal, _ in
            try journal.setTitle(" \n ")
            try journal.start(at: start)
            let originalID = journal.state.current?.id
            XCTAssertEqual(journal.state.current?.title, "")
            XCTAssertThrowsError(try journal.start(at: start.addingTimeInterval(5)))
            XCTAssertEqual(journal.state.current?.id, originalID)
            XCTAssertEqual(journal.state.current?.startedAt, start)
        }
    }

    @MainActor
    func testFailedSaveDoesNotClaimTheEditWasPersisted() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HitBlocked-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not a directory".utf8).write(to: directory)
        let journal = try Journal(fileURL: directory.appendingPathComponent("workspace.json"))
        XCTAssertThrowsError(try journal.setTitle("An unsaved edit"))
        XCTAssertEqual(journal.state.draftTitle, "")
    }

    @MainActor
    func testFailedCompletionRetainsFocusAndRetriesTheWholeTransition() async throws {
        try withJournal { journal, url in
            try journal.setTitle("A task that must not disappear")
            try journal.start(at: start)
            let focusID = journal.state.current?.id
            try FileManager.default.removeItem(at: url)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            XCTAssertThrowsError(try journal.reconcile(at: start.addingTimeInterval(1500)))
            XCTAssertEqual(journal.state.current?.id, focusID)
            XCTAssertEqual(journal.state.current?.kind, .focus)
            XCTAssertTrue(journal.state.history.isEmpty)
            try FileManager.default.removeItem(at: url)
            try journal.reconcile(at: start.addingTimeInterval(1501))
            let reopened = try Journal(fileURL: url)
            XCTAssertEqual(reopened.state.current?.kind, .rest)
            XCTAssertEqual(reopened.state.current?.startedAt, start.addingTimeInterval(1500))
            XCTAssertEqual(reopened.state.history.first?.title, "A task that must not disappear")
            XCTAssertEqual(reopened.state.history.count, 1)
        }
    }

    @MainActor
    func testCorruptOrNewerDataIsNotSilentlyOverwritten() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HitInvalid-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        for content in ["broken JSON", "{\"schemaVersion\":2,\"draftTitle\":\"Future task\",\"draftNotes\":\"\",\"history\":[],\"nextKind\":\"focus\"}"] {
            let original = Data(content.utf8)
            try original.write(to: url)
            XCTAssertThrowsError(try Journal(fileURL: url))
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }
}
