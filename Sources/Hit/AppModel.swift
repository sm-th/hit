import Combine
import Foundation
import HitCore

enum BreakNotice: Equatable {
    case started(UUID)
    case completed(UUID)
}

/// Shared by the menu-bar panel and history. No timer or draft depends on a visible window.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var journal: Journal?
    @Published private(set) var error: String?
    @Published private(set) var now = Date()
    @Published private(set) var breakNotice: BreakNotice?
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
            let previous = loaded.state.current
            try loaded.reconcile()
            journal = loaded
            synchronizeDraft()
            updateBreakNotice(previous: previous, restoring: true)
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
            let previous = journal.state.current
            try flushEdits()
            try action(journal)
            if journal.state.current?.id != sessionID { synchronizeDraft() }
            updateBreakNotice(previous: previous)
            now = Date()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func updateBreakNotice(previous: Session?, restoring: Bool = false) {
        if let current, current.kind == .rest {
            if restoring || current.id != previous?.id {
                breakNotice = .started(current.id)
            }
        } else if current == nil, let previous,
                  let finished = journal?.state.history.first,
                  finished.kind == .rest, finished.status == .completed,
                  finished.id == previous.id ||
                    (previous.kind == .focus && previous.deadline == finished.startedAt) {
            breakNotice = .completed(finished.id)
        } else if current?.kind == .focus || previous?.kind == .rest {
            breakNotice = nil
        }
    }

    private func synchronizeDraft() {
        synchronizing = true
        defer { synchronizing = false }
        sessionID = current?.id
        title = current?.kind == .focus ? (current?.title ?? "") : (journal?.state.draftTitle ?? "")
        notes = current?.kind == .focus ? (current?.notes ?? "") : (journal?.state.draftNotes ?? "")
        if current?.kind != .focus { detailsExpanded = false }
    }
}
