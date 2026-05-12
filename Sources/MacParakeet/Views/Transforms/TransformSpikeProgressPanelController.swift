import AppKit
import MacParakeetCore
import SwiftUI

/// Non-activating panel that hosts the Transforms spike progress UI. Spike
/// scope only — see `docs/research/transforms-design-2026-05.md` Phase 2 for
/// the custom-loader / pill anchored near the trigger context.
///
/// NSPanel notes:
/// - `canBecomeKey` is `false` so triggering the hotkey doesn't yank focus
///   from the user's frontmost app (which is the whole point — we paste back
///   into their text field).
/// - `.nonactivatingPanel | .borderless` is the standard floating overlay
///   style used elsewhere in MacParakeet.
private final class TransformsSpikePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Tiny state object the panel binds to. ObservableObject (not @Observable)
/// because the spike supports macOS 14 and the older binding still works
/// reliably for one-shot panels.
@MainActor
final class TransformSpikeProgressViewModel: ObservableObject {
    @Published var label: String = "Polishing…"
    @Published var isWorking: Bool = true
    @Published var errorMessage: String? = nil
    @Published var doneMessage: String? = nil
}

@MainActor
final class TransformSpikeProgressPanelController {
    private var panel: NSPanel?
    private var viewModel: TransformSpikeProgressViewModel?
    private var autoDismissTask: Task<Void, Never>?

    /// Open (or reuse) the panel showing the in-progress label. Idempotent —
    /// calling `show` while a panel is visible just updates the label.
    func show(label: String = "Polishing…") {
        autoDismissTask?.cancel()
        autoDismissTask = nil

        if let viewModel {
            viewModel.label = label
            viewModel.isWorking = true
            viewModel.errorMessage = nil
            viewModel.doneMessage = nil
            return
        }

        let vm = TransformSpikeProgressViewModel()
        vm.label = label
        self.viewModel = vm

        let host = NSHostingView(rootView: TransformSpikeProgressView(viewModel: vm))
        host.frame = NSRect(x: 0, y: 0, width: 220, height: 56)

        let panel = TransformsSpikePanel(
            contentRect: host.frame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // SwiftUI renders its own shadow.
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = host

        if let screen = Self.screenForPanel() {
            let panelSize = host.fittingSize.width > 0
                ? host.fittingSize
                : NSSize(width: 220, height: 56)
            let visible = screen.visibleFrame
            let x = visible.midX - panelSize.width / 2
            let y = visible.maxY - panelSize.height - 32
            panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: panelSize), display: true)
        }

        panel.orderFrontRegardless()
        self.panel = panel
    }

    /// Replace the spinner with a brief "Done" message, then auto-dismiss
    /// after 1.2s. Idempotent — repeated `done()` calls reset the timer.
    func done(message: String = "Done") {
        guard let viewModel else { return }
        viewModel.isWorking = false
        viewModel.errorMessage = nil
        viewModel.doneMessage = message
        scheduleAutoDismiss(after: .milliseconds(1200))
    }

    /// Replace the spinner with an error message, auto-dismiss after 4s.
    func fail(message: String) {
        guard let viewModel else {
            // Spike-grade UX: if the panel hasn't been shown yet, surface
            // the error briefly anyway.
            show(label: "Transforms")
            self.viewModel?.label = "Transforms"
            self.viewModel?.isWorking = false
            self.viewModel?.errorMessage = message
            scheduleAutoDismiss(after: .milliseconds(4000))
            return
        }
        viewModel.isWorking = false
        viewModel.doneMessage = nil
        viewModel.errorMessage = message
        scheduleAutoDismiss(after: .milliseconds(4000))
    }

    /// Tear the panel down immediately. Used when the user re-triggers the
    /// hotkey mid-run (cancel-then-restart semantics).
    func close() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        panel?.orderOut(nil)
        panel = nil
        viewModel = nil
    }

    private func scheduleAutoDismiss(after delay: Duration) {
        autoDismissTask?.cancel()
        autoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }

    private static func screenForPanel() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }
}

// MARK: - View

private struct TransformSpikeProgressView: View {
    @ObservedObject var viewModel: TransformSpikeProgressViewModel

    var body: some View {
        HStack(spacing: 12) {
            if viewModel.isWorking {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            } else if viewModel.errorMessage != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            Text(currentLabel)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.78))
                .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
        )
        .padding(8)
    }

    private var currentLabel: String {
        if let error = viewModel.errorMessage { return error }
        if let done = viewModel.doneMessage { return done }
        return viewModel.label
    }
}
