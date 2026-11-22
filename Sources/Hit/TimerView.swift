import AppKit
import HitCore
import SwiftUI

@MainActor
struct TimerView: View {
    @ObservedObject var model: AppModel
    let showHistory: () -> Void
    let resize: (CGSize) -> Void

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("Hit").font(.headline)
                Spacer()
                if model.current?.status == .paused {
                    Text("Paused").font(.caption).foregroundStyle(.secondary)
                }
            }
            if model.journal != nil {
                timer
                if let error = model.error { saveError(error) }
                if model.kind == .focus {
                    DisclosureGroup("Task & notes", isExpanded: $model.detailsExpanded) {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Task name (optional)", text: $model.title)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("taskTitle")
                            TextEditor(text: $model.notes)
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .frame(height: 104)
                                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                                .accessibilityLabel("Task notes")
                            Text(model.error == nil ? "Saved on this Mac." : "Unsaved changes. Keep Hit open.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.top, 10)
                    }
                    .font(.callout)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Workspace unavailable", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text(model.error ?? "Could not open the workspace.")
                        .font(.caption).textSelection(.enabled)
                    Text("Your data has not been overwritten.").font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { model.load() }
                }
            }
            Divider()
            HStack {
                Button(action: showHistory) { Label("History", systemImage: "clock.arrow.circlepath") }
                    .disabled(model.journal == nil)
                Spacer()
                Button { revealWorkspace(model.fileURL) } label: { Image(systemName: "folder") }
                    .help("Show local workspace file")
                    .accessibilityLabel("Show local workspace file")
                Button("Quit") { NSApp.terminate(nil) }
            }
            .font(.caption).buttonStyle(.borderless)
        }
        .padding(20)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .tint(.teal)
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { resize(geometry.size) }
                    .onChange(of: geometry.size) { resize($0) }
            }
        }
    }

    private var timer: some View {
        VStack(spacing: 12) {
            Text(model.kind.label).font(.callout).foregroundStyle(.secondary)
            Text(model.timeLabel)
                .font(.system(size: 68, weight: .light, design: .rounded))
                .monospacedDigit()
                .accessibilityLabel("Time remaining, \(model.timeLabel)")
            PrimaryTimerButton(
                title: model.primaryTitle, symbol: model.primarySymbol,
                enabled: model.journal != nil, action: model.toggleTimer
            )
            .frame(width: 150, height: 36)
            if model.current != nil {
                Button("Finish Early") { model.finishEarly() }
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
            } else if model.kind == .rest {
                Button("Skip Break") { model.skipBreak() }
                    .buttonStyle(.borderless).font(.caption)
            }
        }
    }

    private func saveError(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Could not save", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.bold()).foregroundStyle(.red)
            Text(message).font(.caption).textSelection(.enabled)
            Button("Retry Saving") { model.retrySaving() }.font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A native, keyboard-focusable control, also exercised directly by the packaged-app smoke test.
@MainActor
struct PrimaryTimerButton: NSViewRepresentable {
    let title: String
    let symbol: String
    let enabled: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.press))
        button.identifier = NSUserInterfaceItemIdentifier("primaryTimerAction")
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.bezelColor = .systemTeal
        button.contentTintColor = .white
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.title = title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.isEnabled = enabled
        button.setAccessibilityLabel(title)
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func press() { action() }
    }
}

@MainActor
struct HistoryView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if let sessions = model.journal?.state.history, !sessions.isEmpty {
                List(sessions) { session in
                    DisclosureGroup {
                        Text(session.notes.isEmpty ? "No notes." : session.notes)
                            .font(.callout).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.title.isEmpty ? session.kind.label : session.title).font(.headline)
                            Text(session.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                            Text(session.status == .completed ? "Completed" : "Stopped early")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath").font(.largeTitle).foregroundStyle(.secondary)
                    Text("No sessions yet").font(.headline)
                    Text("Your sessions and notes will be saved here.").foregroundStyle(.secondary)
                }
                .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 340, minHeight: 300)
        .tint(.teal)
    }
}
