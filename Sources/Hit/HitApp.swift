import AppKit
import Darwin
import HitCore
import SwiftUI

@main
@MainActor
struct HitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var startup = Startup()

    var body: some Scene {
        WindowGroup("Hit") {
            RootView(startup: startup)
                .frame(minWidth: 760, minHeight: 540)
        }
        .defaultSize(width: 900, height: 650)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor
final class Startup: ObservableObject {
    @Published var journal: Journal?
    @Published var error: String?
    let isSmokeTest = CommandLine.arguments.contains("--smoke-test")
    let fileURL: URL
    private var didRunSmoke = false

    init() {
        fileURL = CommandLine.arguments.contains("--smoke-test")
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("Hit-Smoke-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent("workspace.json")
            : Journal.defaultFileURL
        load()
    }

    func load() {
        do {
            let loaded = try Journal(fileURL: fileURL)
            try loaded.reconcile()
            journal = loaded
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func runSmokeIfNeeded() async {
        guard isSmokeTest, !didRunSmoke else { return }
        didRunSmoke = true
        do {
            guard let journal else { throw SmokeError.failed("Workspace did not load") }
            try journal.setTitle("Write a thoughtful first draft")
            try journal.setNotes("Outline the idea, then focus on one small step.\nNotes are saved on this Mac.")
            try journal.start()
            try journal.pause()
            try journal.resume()
            let restored = try Journal(fileURL: fileURL)
            guard restored.state.current?.title == "Write a thoughtful first draft",
                  restored.state.current?.notes.contains("one small step") == true,
                  restored.state.current?.status == .running else {
                throw SmokeError.failed("Workspace did not survive reopening")
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                  window.frame.width >= 760 else {
                throw SmokeError.failed("The application window is not visible")
            }
            if let path = ProcessInfo.processInfo.environment["HIT_SMOKE_SCREENSHOT"] {
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", path]
                try capture.run()
                capture.waitUntilExit()
                guard capture.terminationStatus == 0,
                      FileManager.default.fileExists(atPath: path) else {
                    throw SmokeError.failed("Could not capture the application window")
                }
            }
            try FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
            print("SMOKE_TEST_PASSED: visible Hit window and durable task notes")
            fflush(stdout)
            NSApp.terminate(nil)
        } catch {
            fputs("SMOKE_TEST_FAILED: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

private enum SmokeError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        switch self { case .failed(let message): return message }
    }
}

@MainActor
struct RootView: View {
    @ObservedObject var startup: Startup

    var body: some View {
        Group {
            if let journal = startup.journal {
                ContentView(journal: journal)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.largeTitle).foregroundStyle(.orange)
                    Text("Your workspace could not be opened").font(.title2.bold())
                    Text(startup.error ?? "Unknown storage error.").textSelection(.enabled)
                    Text("Hit has not overwritten your data. Back up the file before repairing it or moving it aside.")
                        .foregroundStyle(.secondary)
                    Text(startup.fileURL.path).font(.caption).textSelection(.enabled)
                    HStack {
                        Button("Show Data Folder") { reveal(startup.fileURL) }
                        Button("Retry") { startup.load() }
                    }
                }
                .padding(40)
            }
        }
        .tint(.teal)
        .task { await startup.runSmokeIfNeeded() }
    }
}

@MainActor
struct ContentView: View {
    @ObservedObject var journal: Journal
    @State private var storageError: String?
    @State private var selectedSession: UUID?
    @State private var confirmStop = false
    @State private var title = ""
    @State private var notes = ""
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var current: Session? { journal.state.current }
    private var kind: SessionKind { current?.kind ?? journal.state.nextKind }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Hit").font(.largeTitle.weight(.bold))
                    Spacer()
                    Label("On this Mac", systemImage: "internaldrive")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let storageError {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Changes could not be saved", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline).foregroundStyle(.red)
                        Text(storageError).font(.caption).textSelection(.enabled)
                        Button("Retry Saving") { perform { try saveDraft() } }
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                VStack(spacing: 8) {
                    Text(kind.label.uppercased()).font(.caption.weight(.semibold))
                        .tracking(3).foregroundStyle(.secondary)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = current?.secondsRemaining(at: context.date) ?? Int(kind.duration)
                        Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                            .font(.system(size: 76, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .accessibilityLabel("Time remaining")
                            .accessibilityValue("\(seconds / 60) minutes, \(seconds % 60) seconds")
                    }
                    Text(timerHint).font(.callout).foregroundStyle(.secondary)
                    controls.padding(.top, 10)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)

                if kind == .focus {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TASK").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextField("What will you focus on?", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("taskTitle")
                        Text("NOTES").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.top, 8)
                        TextEditor(text: $notes)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                        .frame(minHeight: 100)
                        .accessibilityLabel("Task notes")
                        .accessibilityIdentifier("taskNotes")
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "cup.and.saucer").font(.system(size: 32)).foregroundStyle(.teal)
                        Text("A little room to recharge.").font(.title3)
                        Text("Your task and notes are in History.").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                HStack {
                    Text(storageError == nil ? "Changes are saved automatically." : "Last change was not saved.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { reveal(journal.fileURL) } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Show local workspace file")
                    .accessibilityLabel("Show local workspace file")
                }
            }
            .padding(28).frame(minWidth: 450, maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("History").font(.headline)
                    Spacer()
                    Text("\(journal.state.history.count)").foregroundStyle(.secondary)
                }
                if journal.state.history.isEmpty {
                    Spacer()
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath").font(.title).foregroundStyle(.secondary)
                        Text("One session at a time").font(.headline)
                        Text("Finished sessions and their notes will appear here.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    List(selection: $selectedSession) {
                        ForEach(journal.state.history) { session in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(session.title.isEmpty ? "Untitled task" : session.title)
                                    .font(.headline).lineLimit(2)
                                Text(session.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(session.status == .completed ? "Completed · \(session.kind.label)" : "Stopped early")
                                    .font(.caption).foregroundStyle(session.status == .completed ? Color.teal : Color.secondary)
                            }
                            .padding(.vertical, 6).tag(session.id)
                        }
                    }
                    .listStyle(.plain)
                    if let session = journal.state.history.first(where: { $0.id == selectedSession }) {
                        Divider()
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(session.title).font(.headline)
                                Text(session.notes.isEmpty ? "No notes for this session." : session.notes)
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 180)
                    }
                }
            }
            .padding(20).frame(minWidth: 250, idealWidth: 280, maxWidth: 340, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        }
        .onAppear { synchronizeDraft() }
        .onChange(of: journal.state.current?.id) { _ in synchronizeDraft() }
        .onChange(of: title) { _ in perform { try saveDraft() } }
        .onChange(of: notes) { _ in perform { try saveDraft() } }
        .onReceive(clock) { date in
            // A failed completion remains retryable; the saved deadline is never discarded.
            do {
                try saveDraft()
                try journal.reconcile(at: date)
                storageError = nil
            }
            catch { storageError = error.localizedDescription }
        }
        .confirmationDialog("Finish this session early?", isPresented: $confirmStop) {
            Button("Finish Early", role: .destructive) {
                perform { try saveDraft(); try journal.stop() }
            }
            Button("Keep Working", role: .cancel) {}
        } message: {
            Text("The session and its notes will remain in History.")
        }
    }

    private var timerHint: String {
        if current?.status == .paused { return "Paused. Take your time." }
        if current != nil { return kind == .focus ? "One task. A little progress." : "Step away for a moment." }
        return kind == .focus ? "Make space for your next task." : "Focus complete. Ready for a break?"
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 12) {
            if let current {
                if current.status == .paused {
                    Button { perform { try saveDraft(); try journal.resume() } } label: {
                        Label("Resume", systemImage: "play.fill")
                    }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button { perform { try saveDraft(); try journal.pause() } } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }
                        .buttonStyle(.borderedProminent)
                }
                Button("Finish Early") { confirmStop = true }.buttonStyle(.bordered)
            } else {
                Button(kind == .focus ? "Start Focus" : "Start Break") {
                    perform { try saveDraft(); try journal.start() }
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(kind == .focus && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if kind == .rest {
                    Button("Skip Break") { perform { try journal.skipBreak() } }.buttonStyle(.bordered)
                }
            }
        }
        .controlSize(.large)
    }

    private func synchronizeDraft() {
        title = current?.kind == .focus ? (current?.title ?? "") : journal.state.draftTitle
        notes = current?.kind == .focus ? (current?.notes ?? "") : journal.state.draftNotes
    }

    private func saveDraft() throws {
        guard kind == .focus else { return }
        try journal.setTitle(title)
        try journal.setNotes(notes)
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            storageError = nil
        } catch {
            storageError = error.localizedDescription
        }
    }
}

private func reveal(_ fileURL: URL) {
    if FileManager.default.fileExists(atPath: fileURL.path) {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    } else {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path)
    }
}
