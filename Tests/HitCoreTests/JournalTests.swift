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
    func testExpiredTimerRecordsOneCompletionAtDeadlineAndWaitsForManualBreak() async throws {
        try withJournal { journal, url in
            try journal.setTitle("Sketch a solution")
            try journal.start(at: start)
            try journal.setNotes("Keep the simple version.")
            let reopened = try Journal(fileURL: url)
            try reopened.reconcile(at: start.addingTimeInterval(86_400))
            try reopened.reconcile(at: start.addingTimeInterval(90_000))
            XCTAssertNil(reopened.state.current)
            XCTAssertEqual(reopened.state.history.count, 1)
            XCTAssertEqual(reopened.state.history.first?.endedAt, start.addingTimeInterval(1500))
            XCTAssertEqual(reopened.state.history.first?.status, .completed)
            XCTAssertEqual(reopened.state.history.first?.notes, "Keep the simple version.")
            XCTAssertEqual(reopened.state.nextKind, .rest)
            let restoredHistory = try Journal(fileURL: url)
            XCTAssertEqual(restoredHistory.state.history.first?.title, "Sketch a solution")
            try restoredHistory.start(at: start.addingTimeInterval(90_000))
            XCTAssertEqual(restoredHistory.state.current?.secondsRemaining(at: start.addingTimeInterval(90_000)), 300)
            try restoredHistory.reconcile(at: start.addingTimeInterval(90_300))
            XCTAssertEqual(restoredHistory.state.nextKind, .focus)
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
    func testPausingAnExpiredTimerRecordsCompletionInsteadOfZeroLengthPause() async throws {
        try withJournal { journal, _ in
            try journal.setTitle("Finish a draft")
            try journal.start(at: start)
            try journal.pause(at: start.addingTimeInterval(1500))
            XCTAssertNil(journal.state.current)
            XCTAssertEqual(journal.state.history.first?.status, .completed)
        }
    }

    @MainActor
    func testSkippingBreakDoesNotInventACompletedSession() async throws {
        try withJournal { journal, url in
            try journal.setTitle("One task")
            try journal.start(at: start)
            try journal.reconcile(at: start.addingTimeInterval(1500))
            try journal.skipBreak()
            let reopened = try Journal(fileURL: url)
            XCTAssertEqual(reopened.state.nextKind, .focus)
            XCTAssertEqual(reopened.state.history.count, 1)
            XCTAssertEqual(reopened.state.history.first?.kind, .focus)
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
