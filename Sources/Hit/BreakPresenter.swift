import AppKit
import HitCore
import SwiftUI

/// One dismissible, edge-to-edge window per display. This is not a notification banner
/// and does not depend on notification permission or creating a separate full-screen Space.
@MainActor
final class BreakPresenter {
    private let model: AppModel
    private let willPresent: () -> Void
    private var lastNotice: BreakNotice?
    private(set) var windows: [BreakWindow] = []

    var isVisible: Bool { windows.contains { $0.isVisible } }

    init(model: AppModel, willPresent: @escaping () -> Void) {
        self.model = model
        self.willPresent = willPresent
    }

    func synchronize() {
        guard let notice = model.breakNotice else {
            if lastNotice != nil {
                lastNotice = nil
                minimize()
            }
            return
        }
        guard notice != lastNotice else { return }
        lastNotice = notice
        present()
    }

    func present() {
        guard model.breakNotice != nil else { return }
        willPresent()
        for window in windows { window.close() }
        windows.removeAll(keepingCapacity: true)
        for screen in NSScreen.screens {
            let window = BreakWindow(
                contentRect: screen.frame, styleMask: [.borderless],
                backing: .buffered, defer: false, screen: screen
            )
            window.title = "Break — Hit"
            window.isReleasedWhenClosed = false
            window.isExcludedFromWindowsMenu = true
            window.hasShadow = false
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.onMinimize = { [weak self] in self?.minimize() }
            window.contentViewController = NSHostingController(
                rootView: BreakView(model: model, minimize: { [weak self] in self?.minimize() })
            )
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKeyAndOrderFront(nil)
    }

    func minimize() {
        for window in windows { window.orderOut(nil) }
        // Keep lastNotice: ordinary timer ticks must not bring a minimized break back.
    }
}

@MainActor
final class BreakWindow: NSWindow {
    var onMinimize: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onMinimize?() }
    override func miniaturize(_ sender: Any?) { onMinimize?() }
}

@MainActor
private struct BreakView: View {
    @ObservedObject var model: AppModel
    let minimize: () -> Void
    private var isBreak: Bool { model.current?.kind == .rest }

    var body: some View {
        VStack(spacing: 24) {
            Text(isBreak ? "Break" : "Break complete")
                .font(.system(size: 64, weight: .light, design: .rounded))
            if isBreak {
                Text(model.timeLabel)
                    .font(.system(size: 112, weight: .ultraLight, design: .rounded))
                    .monospacedDigit()
                    .accessibilityLabel("Break time remaining, \(model.timeLabel)")
                Text(model.current?.status == .paused ? "Paused" : "Breathe. Stretch. Look away from the screen.")
                    .font(.title3).foregroundStyle(.secondary)
                if let started = model.current?.startedAt {
                    HStack(spacing: 4) {
                        Text("Started at")
                        Text(started, style: .time)
                    }
                    .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "checkmark.circle").font(.system(size: 96, weight: .ultraLight))
                    .foregroundStyle(.teal)
                Text("Start your next focus session when you're ready.")
                    .font(.title3).foregroundStyle(.secondary)
                if let ended = model.journal?.state.history.first?.endedAt {
                    HStack(spacing: 4) {
                        Text("Finished at")
                        Text(ended, format: .dateTime.month(.abbreviated).day().hour().minute())
                    }
                    .font(.callout).foregroundStyle(.secondary)
                }
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red).frame(maxWidth: 500)
            }
            HStack(spacing: 16) {
                TimerActionButton(
                    title: model.primaryTitle, symbol: model.primarySymbol,
                    enabled: model.journal != nil, action: model.toggleTimer
                )
                .frame(width: 150, height: 36)
                Button("Minimize", action: minimize)
                    .buttonStyle(.bordered).controlSize(.large)
                    .keyboardShortcut(.cancelAction)
            }
            if isBreak {
                TimerActionButton(
                    title: "Skip Break", symbol: "forward.end.fill",
                    enabled: model.journal != nil, action: model.skipBreak,
                    prominent: false, identifier: "skipBreakAction"
                )
                .frame(width: 150, height: 32)
            }
            Text(isBreak ? "Esc to minimize. The break keeps running." : "Esc to dismiss.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.teal)
    }
}
