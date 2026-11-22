import Combine
import Foundation
import HitCore

/// Shared by the menu-bar panel and history. No timer or draft depends on a visible window.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var journal: Journal?
    @Published private(set) var error: String?
    @Published private(set) var now = Date()
    @Published var detailsExpanded = false
    @Published var title = "" { didSet { persistEdits() } }
    @Published var notes = "" { didSet { persistEdits() } }
    let fileURL: URL
    private var synchronizing = false
    private var sessionID: UUID?

    var current: Session? { journal?.state.current }
    var kind: SessionKind { current?.kind ?? journal?.state.nextKind ?? .focus }
    var secondsRemaining: Int { current?.secondsRemaining(at: now) ?? Int(kind.duration) }
    var timeLabel: String {
        let seconds = secondsRemaining
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    var primaryTitle: String {
        if current?.status == .running { return "Pause" }
        if current?.status == .paused { return "Resume" }
        return kind == .focus ? "Start Focus" : "Start Break"
    }
    var primarySymbol: String { current?.status == .running ? "pause.fill" : "play.fill" }

    init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    func load() {
        do {
            let loaded = try Journal(fileURL: fileURL)
            try loaded.reconcile()
            journal = loaded
            synchronizeDraft()
            now = Date()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func toggleTimer() {
        perform { journal in
            switch journal.state.current?.status {
            case .running: try journal.pause()
            case .paused: try journal.resume()
            default: try journal.start()
            }
        }
    }

    func finishEarly() { perform { try $0.stop() } }
    func skipBreak() { perform { try $0.skipBreak() } }
    func retrySaving() { persistEdits() }

    func tick() {
        now = Date()
        guard journal != nil else { return }
        perform { try $0.reconcile(at: now) }
    }

    func saveBeforeQuit() throws {
        guard journal != nil else { return }
        try flushEdits()
    }

    private func persistEdits() {
        guard !synchronizing else { return }
        do {
            try flushEdits()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func flushEdits() throws {
        guard let journal else { throw JournalError.invalidTransition }
        guard kind == .focus else { return }
        try journal.setTitle(title)
        try journal.setNotes(notes)
    }

    private func perform(_ action: (Journal) throws -> Void) {
        do {
            guard let journal else { throw JournalError.invalidTransition }
            try flushEdits()
            try action(journal)
            if journal.state.current?.id != sessionID { synchronizeDraft() }
            now = Date()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func synchronizeDraft() {
        synchronizing = true
        defer { synchronizing = false }
        sessionID = current?.id
        title = current?.kind == .focus ? (current?.title ?? "") : (journal?.state.draftTitle ?? "")
        notes = current?.kind == .focus ? (current?.notes ?? "") : (journal?.state.draftNotes ?? "")
        if current == nil { detailsExpanded = false }
    }
}
