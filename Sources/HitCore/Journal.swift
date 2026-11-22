import Combine
import Foundation

public enum SessionKind: String, Codable {
    case focus
    case rest

    public var duration: TimeInterval { self == .focus ? 25 * 60 : 5 * 60 }
    public var label: String { self == .focus ? "Focus" : "Short break" }
}

public enum SessionStatus: String, Codable {
    case running
    case paused
    case completed
    case stopped
}

public struct Session: Codable, Identifiable {
    public let id: UUID
    public let kind: SessionKind
    public internal(set) var title: String
    public internal(set) var notes: String
    public let startedAt: Date
    public internal(set) var endedAt: Date?
    public internal(set) var status: SessionStatus
    public let duration: TimeInterval
    public internal(set) var remaining: TimeInterval
    public internal(set) var deadline: Date?

    public func secondsRemaining(at now: Date) -> Int {
        let seconds = deadline.map { $0.timeIntervalSince(now) } ?? remaining
        return Int(ceil(max(0, min(duration, seconds))))
    }
}

public struct Workspace: Codable {
    public let schemaVersion: Int
    public internal(set) var draftTitle: String
    public internal(set) var draftNotes: String
    public internal(set) var current: Session?
    public internal(set) var history: [Session]
    public internal(set) var nextKind: SessionKind

    fileprivate static var empty: Workspace {
        Workspace(schemaVersion: 1, draftTitle: "", draftNotes: "", current: nil,
                  history: [], nextKind: .focus)
    }
}

public enum JournalError: LocalizedError {
    case invalidTransition
    case unsupportedData

    public var errorDescription: String? {
        switch self {
        case .invalidTransition: return "This action is not available for the current timer state."
        case .unsupportedData:
            return "The saved workspace is invalid or uses an unsupported version. Your file has not been changed."
        }
    }
}

/// A durable workspace. Mutations publish only after the complete new state is saved atomically.
/// Running timers use a persisted deadline; quitting or sleeping never pauses them.
@MainActor
public final class Journal: ObservableObject {
    @Published public private(set) var state: Workspace
    public let fileURL: URL

    nonisolated public static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hit", isDirectory: true)
            .appendingPathComponent("workspace.json")
    }

    public init(fileURL: URL = Journal.defaultFileURL) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let loaded = try JSONDecoder().decode(Workspace.self, from: Data(contentsOf: fileURL))
            guard loaded.schemaVersion == 1,
                  loaded.current.map(Self.isValidActive) ?? true,
                  loaded.history.allSatisfy(Self.isValidHistory) else {
                throw JournalError.unsupportedData
            }
            state = loaded
        } else {
            state = .empty
        }
    }

    public func setTitle(_ value: String) throws {
        let existing = state.current?.kind == .focus ? state.current?.title : state.draftTitle
        guard value != existing else { return }
        try update { workspace in
            if workspace.current?.kind == .focus {
                workspace.current?.title = value
            } else {
                workspace.draftTitle = value
            }
        }
    }

    public func setNotes(_ value: String) throws {
        let existing = state.current?.kind == .focus ? state.current?.notes : state.draftNotes
        guard value != existing else { return }
        try update { workspace in
            if workspace.current?.kind == .focus {
                workspace.current?.notes = value
            } else {
                workspace.draftNotes = value
            }
        }
    }

    public func start(at now: Date = Date()) throws {
        guard state.current == nil else { throw JournalError.invalidTransition }
        let kind = state.nextKind
        try update { workspace in
            Self.startSession(in: &workspace, kind: kind, at: now)
        }
    }

    public func pause(at now: Date = Date()) throws {
        guard let session = state.current, session.status == .running,
              let deadline = session.deadline else { throw JournalError.invalidTransition }
        if deadline <= now {
            try reconcile(at: now)
            return
        }
        try update { workspace in
            workspace.current?.remaining = min(session.duration, deadline.timeIntervalSince(now))
            workspace.current?.deadline = nil
            workspace.current?.status = .paused
        }
    }

    public func resume(at now: Date = Date()) throws {
        guard let session = state.current, session.status == .paused else {
            throw JournalError.invalidTransition
        }
        try update { workspace in
            workspace.current?.deadline = now.addingTimeInterval(session.remaining)
            workspace.current?.status = .running
        }
    }

    public func stop(at now: Date = Date()) throws {
        guard state.current != nil else { throw JournalError.invalidTransition }
        if let deadline = state.current?.deadline, deadline <= now {
            try reconcile(at: now)
            return
        }
        try update { workspace in
            guard let session = workspace.current else { return }
            workspace.history.insert(Self.endedSession(session, at: now), at: 0)
            workspace.current = nil
            workspace.nextKind = .focus
        }
    }

    /// Only breaks start automatically. Catch-up is bounded to one focus and its break.
    /// Completion and the next interval are committed in one atomic save.
    public func reconcile(at now: Date = Date()) throws {
        guard let deadline = state.current?.deadline, deadline <= now else { return }
        try update { workspace in
            while let session = workspace.current, let deadline = session.deadline, deadline <= now {
                let completed = Self.endedSession(session, at: deadline)
                workspace.history.insert(completed, at: 0)
                workspace.current = nil
                workspace.nextKind = .focus
                if completed.kind == .focus {
                    Self.startSession(in: &workspace, kind: .rest, at: deadline)
                }
            }
        }
    }

    public func skipBreak(at now: Date = Date()) throws {
        guard state.current?.kind == .rest || (state.current == nil && state.nextKind == .rest) else {
            throw JournalError.invalidTransition
        }
        try update { workspace in
            let ended: Session
            if let session = workspace.current {
                ended = Self.endedSession(session, at: now)
            } else {
                // A pending break saved by an earlier release was skipped without being started.
                let kind = SessionKind.rest
                ended = Session(
                    id: UUID(), kind: kind, title: kind.label, notes: "",
                    startedAt: now, endedAt: now, status: .stopped,
                    duration: kind.duration, remaining: kind.duration, deadline: nil
                )
            }
            workspace.history.insert(ended, at: 0)
            Self.startSession(in: &workspace, kind: .focus, at: now)
        }
    }

    private static func startSession(in workspace: inout Workspace, kind: SessionKind, at now: Date) {
        workspace.current = Session(
            id: UUID(), kind: kind,
            title: kind == .focus ? workspace.draftTitle.trimmingCharacters(in: .whitespacesAndNewlines) : kind.label,
            notes: kind == .focus ? workspace.draftNotes : "", startedAt: now,
            endedAt: nil, status: .running, duration: kind.duration,
            remaining: kind.duration, deadline: now.addingTimeInterval(kind.duration)
        )
        workspace.nextKind = kind
        if kind == .focus {
            workspace.draftTitle = ""
            workspace.draftNotes = ""
        }
    }

    private static func endedSession(_ session: Session, at now: Date) -> Session {
        var ended = session
        let expired = session.deadline.map { $0 <= now } ?? false
        ended.status = expired ? .completed : .stopped
        ended.endedAt = expired ? session.deadline : now
        if let deadline = session.deadline {
            ended.remaining = min(session.duration, max(0, deadline.timeIntervalSince(now)))
        }
        ended.deadline = nil
        return ended
    }

    private func update(_ change: (inout Workspace) -> Void) throws {
        var updated = state
        change(&updated)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(updated)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        state = updated
    }

    private static func isValidActive(_ session: Session) -> Bool {
        guard session.duration == session.kind.duration,
              session.remaining.isFinite, session.remaining > 0,
              session.remaining <= session.duration, session.endedAt == nil else { return false }
        switch session.status {
        case .running: return session.deadline != nil
        case .paused: return session.deadline == nil
        default: return false
        }
    }

    private static func isValidHistory(_ session: Session) -> Bool {
        session.duration == session.kind.duration && session.remaining.isFinite &&
        session.remaining >= 0 && session.remaining <= session.duration &&
        session.deadline == nil && session.endedAt != nil &&
        (session.status == .completed || session.status == .stopped)
    }
}
