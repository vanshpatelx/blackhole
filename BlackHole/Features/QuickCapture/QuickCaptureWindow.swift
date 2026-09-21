import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A panel that can take keys, unlike the notch panel it hangs under.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }
}

/// One line, anywhere, without leaving what you're doing.
///
/// Option-Space drops an input out of the notch. Type, press Return, and it's a task — with the day
/// and time lifted out of the sentence. Escape or clicking away puts it back.
@MainActor
final class QuickCaptureController {
    private let services: AppServices
    private var panel: NSPanel?
    private var hotKey: HotKey?
    private var dismissMonitor: Any?

    init(services: AppServices) {
        self.services = services
        hotKey = HotKey(keyCode: kVK_Space, modifiers: optionKey) { [weak self] in
            MainActor.assumeIsolated { self?.toggle() }
        }
    }

    func toggle() {
        if panel == nil {
            show()
        } else {
            hide()
        }
    }

    private func show() {
        let geometry = services.notch.geometry
        let size = CGSize(width: 520, height: 56)
        let frame = NSRect(
            x: geometry.screenFrame.midX - size.width / 2,
            // Just under the notch, so it reads as having come out of it.
            y: geometry.topY - size.height - 10,
            width: size.width,
            height: size.height
        )

        let panel = KeyPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .mainMenu + 3
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false

        let view = QuickCaptureView(
            onSubmit: { [weak self] text in self?.commit(text) ?? nil },
            onCancel: { [weak self] in self?.hide() },
            onFinished: { [weak self] in self?.hide() }
        )
        .blackHoleEnvironment(services)

        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setFrame(frame, display: true)

        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        // A capture bar people can't type into is worse than none, so take focus properly.
        NSApp.activate(ignoringOtherApps: true)

        dismissMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func hide() {
        if let dismissMonitor {
            NSEvent.removeMonitor(dismissMonitor)
        }
        dismissMonitor = nil
        panel?.orderOut(nil)
        panel = nil
    }

    /// - Returns: A confirmation for the bar to show, or nil when it should just close.
    private func commit(_ text: String) -> String? {
        guard let command = Command.parse(text) else {
            hide()
            return nil
        }
        let answer = CommandRunner(services: services).run(command)
        if answer == nil {
            hide()
        }
        return answer
    }
}

private struct QuickCaptureView: View {
    /// Returns what to show back, or nil when the bar has already closed.
    let onSubmit: (String) -> String?
    let onCancel: () -> Void
    let onFinished: () -> Void

    @State private var text = ""
    @State private var answer: String?
    @FocusState private var focused: Bool

    /// What the sentence will turn into, shown while typing so the parsing isn't a surprise.
    private var preview: QuickParse.Result? {
        text.isEmpty ? nil : QuickParse.parse(text)
    }

    var body: some View {
        HStack(spacing: 10) {
            AppMark(size: 22)

            if let answer {
                Text(answer)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            } else {
                TextField("Add to your day, or type a command…", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .focused($focused)
                    .disabled(answer != nil)
                    .onSubmit {
                        guard let reply = onSubmit(text) else { return }
                        // Confirmations are worth a beat on screen; the bar closes itself after.
                        answer = reply
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { onFinished() }
                    }
            }

            if answer == nil, let preview, preview.dayKey != DayKey.today || preview.reminder != nil || preview.recurrence != nil {
                Text(summary(preview))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.white.opacity(0.1)))
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.panel)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.08)))
        }
        .onAppear { focused = true }
        .onExitCommand { onCancel() }
        .preferredColorScheme(.dark)
    }

    private func summary(_ result: QuickParse.Result) -> String {
        guard let day = DayKey.date(result.dayKey) else { return "" }
        let dayText = result.dayKey == DayKey.today
            ? "Today"
            : (result.dayKey == DayKey.adding(days: 1, to: DayKey.today)
                ? "Tomorrow"
                : day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
        var parts = [dayText]
        if let reminder = result.reminder {
            parts.append(reminder.formatted(date: .omitted, time: .shortened))
        }
        if let rule = result.recurrence {
            parts = [rule.badge]
        }
        return parts.joined(separator: " · ")
    }
}
