import AppKit
import Carbon
import SwiftUI

struct TriggerHotKeySettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var language = AppLanguageSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "keyboard")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 42, height: 42)
                    .background(
                        Color.accentColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        language.text(
                            "设置呼出键",
                            "Set Trigger"
                        )
                    )
                        .font(.title2.weight(.semibold))
                    Text(
                        language.text(
                            "长按约 0.2 秒，Prompt 轮盘会出现在鼠标旁。",
                            "Hold for about 0.2 seconds to open the Prompt wheel beside your pointer."
                        )
                    )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                if state.isRecordingTriggerHotKey {
                    state.cancelTriggerHotKeyRecording()
                } else {
                    state.beginTriggerHotKeyRecording()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            state.isRecordingTriggerHotKey
                                ? language.text(
                                    "按下 Option 后松开，或按一个组合键…",
                                    "Press and release Option, or enter a shortcut…"
                                )
                                : language.text(
                                    "当前呼出键",
                                    "Current Trigger"
                                )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Text(
                            state.isRecordingTriggerHotKey
                                ? language.text(
                                    "等待输入",
                                    "Waiting for input"
                                )
                                : state.triggerHotKey.displayString
                        )
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    }

                    Spacer()

                    Image(
                        systemName: state.isRecordingTriggerHotKey
                            ? "record.circle.fill"
                            : "pencil"
                    )
                    .font(.title3)
                    .foregroundStyle(
                        state.isRecordingTriggerHotKey
                            ? Color.accentColor
                            : Color.secondary
                    )
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(
                    state.isRecordingTriggerHotKey
                        ? Color.accentColor.opacity(0.1)
                        : Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            state.isRecordingTriggerHotKey
                                ? Color.accentColor
                                : Color.primary.opacity(0.1),
                            lineWidth: state.isRecordingTriggerHotKey ? 1.6 : 0.8
                        )
                }
            }
            .buttonStyle(.plain)

            Text(
                language.text(
                    "支持单独长按左/右 Option，也支持组合键；Esc 取消，1–5 保留给 Prompt 选择。",
                    "Use Left or Right Option alone, or a key combination. Esc cancels; 1–5 are reserved for Prompt selection."
                )
            )
                .font(.caption)
                .foregroundStyle(.secondary)

            if let error = state.triggerHotKeyError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button(
                    language.text(
                        "恢复默认左 ⌥",
                        "Restore Default Left ⌥"
                    )
                ) {
                    state.resetTriggerHotKey()
                }
                .buttonStyle(.borderless)

                Spacer()

                Button(
                    language.text(
                        "完成",
                        "Done"
                    )
                ) {
                    state.cancelTriggerHotKeyRecording()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 470)
        .background {
            ShortcutEventCaptureView(
                isActive: state.isRecordingTriggerHotKey,
                onCapture: { candidate in
                    _ = state.completeTriggerHotKeyRecording(with: candidate)
                },
                onCancel: {
                    state.cancelTriggerHotKeyRecording()
                }
            )
            .frame(width: 1, height: 1)
            .opacity(0.001)
        }
        .onAppear {
            state.beginTriggerHotKeyRecording()
        }
        .onDisappear {
            state.cancelTriggerHotKeyRecording()
        }
        .environment(\.locale, language.locale)
    }
}

private struct ShortcutEventCaptureView: NSViewRepresentable {
    let isActive: Bool
    let onCapture: (TriggerHotKey) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ view: ShortcutCaptureNSView, context: Context) {
        view.onCapture = onCapture
        view.onCancel = onCancel
        view.isCapturing = isActive

        if isActive {
            DispatchQueue.main.async { [weak view] in
                guard let view, view.isCapturing else { return }
                view.window?.makeFirstResponder(view)
            }
        }
    }
}

private final class ShortcutCaptureNSView: NSView {
    var isCapturing = false {
        didSet {
            if !isCapturing {
                pendingOptionKeyCode = nil
            }
        }
    }
    var onCapture: ((TriggerHotKey) -> Void)?
    var onCancel: (() -> Void)?
    private var pendingOptionKeyCode: UInt16?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard isCapturing else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCapturing else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }
        handle(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isCapturing else {
            return super.performKeyEquivalent(with: event)
        }
        handle(event)
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        guard isCapturing else {
            super.flagsChanged(with: event)
            return
        }

        let optionKeyCodes: Set<UInt16> = [
            UInt16(kVK_Option),
            UInt16(kVK_RightOption)
        ]
        guard optionKeyCodes.contains(event.keyCode) else { return }

        let sourceReportsOptionDown = CGEventSource.keyState(
            .combinedSessionState,
            key: CGKeyCode(event.keyCode)
        )
        let optionFlagIsDown = event.modifierFlags.contains(.option)
        let optionIsDown = sourceReportsOptionDown
            || (pendingOptionKeyCode == nil && optionFlagIsDown)

        if optionIsDown {
            let flags = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
            let hasExtraModifier = flags.contains(.command)
                || flags.contains(.control)
                || flags.contains(.shift)
            if !hasExtraModifier {
                pendingOptionKeyCode = event.keyCode
            }
            return
        }

        guard pendingOptionKeyCode == event.keyCode else { return }
        pendingOptionKeyCode = nil
        isCapturing = false
        onCapture?(
            TriggerHotKey(
                keyCode: UInt32(event.keyCode),
                modifiers: UInt32(optionKey)
            )
        )
    }

    private func handle(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        isCapturing = false

        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
        } else {
            onCapture?(
                TriggerHotKey(
                    keyCode: UInt32(event.keyCode),
                    modifiers: TriggerHotKey.carbonModifiers(
                        from: event.modifierFlags
                    )
                )
            )
        }
    }
}
