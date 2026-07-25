import AppKit
import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let store: PromptStore

    @Published var lastStatus: String
    @Published var accessibilityGranted = AccessibilityPermission.isGranted
    @Published private(set) var triggerHotKey = TriggerHotKey.load()
    @Published private(set) var isRecordingTriggerHotKey = false
    @Published var triggerHotKeyError: String?

    private let overlay = RadialMenuPanelController()
    private let injector = PromptInjector()
    private let toast = ToastController()
    private var hotKeys: HotKeyManager!
    private var targetPID: pid_t?
    private var explicitSlot: Int?
    private var permissionTimer: Timer?
    private var languageCancellable: AnyCancellable?

    private init() {
        store = PromptStore(
            initialLanguage: AppLanguageSettings.shared.resolvedLanguage
        )
        lastStatus = AppLanguageSettings.shared.text("准备就绪", "Ready")

        injector.onStatus = { [weak self] message in
            self?.report(message)
        }

        hotKeys = HotKeyManager()
        hotKeys.onMenuShown = { [weak self] in
            self?.beginSelection()
        }
        hotKeys.onSlotChanged = { [weak self] slot in
            self?.explicitSlot = slot
            self?.overlay.select(slot: slot)
        }
        hotKeys.onMenuReleased = { [weak self] in
            self?.finishSelection()
        }
        hotKeys.onCancelled = { [weak self] in
            self?.cancelSelection()
        }
        hotKeys.onError = { [weak self] message in
            self?.report(message)
        }

        activateInitialTrigger()

        permissionTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let isGranted = AccessibilityPermission.isGranted
                if self.accessibilityGranted != isGranted {
                    self.accessibilityGranted = isGranted
                    self.hotKeys.refreshModifierMonitoring()
                }
            }
        }

        languageCancellable = AppLanguageSettings.shared.$selection
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.lastStatus = AppLanguageSettings.shared.text(
                    "准备就绪",
                    "Ready"
                )
            }
    }

    deinit {
        permissionTimer?.invalidate()
    }

    func requestAccessibility() {
        AccessibilityPermission.request()
        AccessibilityPermission.openSystemSettings()
    }

    func beginTriggerHotKeyRecording() {
        guard !isRecordingTriggerHotKey else { return }
        triggerHotKeyError = nil
        hotKeys.suspendTrigger()
        isRecordingTriggerHotKey = true
    }

    @discardableResult
    func completeTriggerHotKeyRecording(
        with candidate: TriggerHotKey
    ) -> Bool {
        guard isRecordingTriggerHotKey else { return false }

        if let validationMessage = candidate.validationMessage {
            triggerHotKeyError = validationMessage
            restoreCurrentTrigger()
            isRecordingTriggerHotKey = false
            return false
        }

        switch hotKeys.applyTrigger(candidate) {
        case .success:
            triggerHotKey = candidate
            triggerHotKey.save()
            triggerHotKeyError = nil
            isRecordingTriggerHotKey = false
            report(
                AppLanguageSettings.shared.text(
                    "呼出键已改为 \(candidate.displayString)",
                    "Trigger changed to \(candidate.displayString)"
                )
            )
            return true

        case .failure:
            triggerHotKeyError = AppLanguageSettings.shared.text(
                "这个组合键已被系统或其他应用占用，原呼出键仍可使用。",
                "That shortcut is already used by macOS or another app. Your previous trigger still works."
            )
            restoreCurrentTrigger()
            isRecordingTriggerHotKey = false
            return false
        }
    }

    func cancelTriggerHotKeyRecording() {
        guard isRecordingTriggerHotKey else { return }
        restoreCurrentTrigger()
        isRecordingTriggerHotKey = false
    }

    func resetTriggerHotKey() {
        if isRecordingTriggerHotKey {
            isRecordingTriggerHotKey = false
        }

        switch hotKeys.applyTrigger(.defaultValue) {
        case .success:
            triggerHotKey = .defaultValue
            triggerHotKey.save()
            triggerHotKeyError = nil
            report(
                AppLanguageSettings.shared.text(
                    "已恢复默认呼出键 \(triggerHotKey.displayString)",
                    "Default trigger restored: \(triggerHotKey.displayString)"
                )
            )

        case .failure:
            triggerHotKeyError = AppLanguageSettings.shared.text(
                "默认快捷键目前被其他应用占用。",
                "The default trigger is currently unavailable."
            )
            restoreCurrentTrigger()
        }
    }

    func previewWheel() {
        overlay.show(prompts: store.slottedPrompts())
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            self?.overlay.hide()
        }
    }

    func copyPrompt(id: UUID) {
        guard let item = store.prompt(id: id) else { return }
        injector.copyOnly(item.body)
    }

    func createPrompt(in slot: Int? = nil) -> PromptItem {
        store.addPrompt(slot: slot)
    }

    func notify(_ message: String) {
        report(message)
    }

    private func activateInitialTrigger() {
        switch hotKeys.applyTrigger(triggerHotKey) {
        case .success:
            return

        case .failure:
            let fallback = TriggerHotKey.defaultValue
            if hotKeys.applyTrigger(fallback).isSuccess {
                triggerHotKey = fallback
                triggerHotKey.save()
                lastStatus = AppLanguageSettings.shared.text(
                    "原呼出键不可用，已恢复默认",
                    "The previous trigger was unavailable, so the default was restored"
                )
            } else {
                lastStatus = AppLanguageSettings.shared.text(
                    "呼出键被其他应用占用",
                    "The trigger is being used by another app"
                )
            }
        }
    }

    private func restoreCurrentTrigger() {
        if case .failure = hotKeys.applyTrigger(triggerHotKey) {
            lastStatus = AppLanguageSettings.shared.text(
                "原呼出键暂时无法恢复，请重新选择",
                "The previous trigger could not be restored. Please choose another one."
            )
        }
    }

    private func beginSelection() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        targetPID = frontmost?.processIdentifier
        explicitSlot = nil
        overlay.show(prompts: store.slottedPrompts())
    }

    private func finishSelection() {
        let chosenSlot = explicitSlot ?? overlay.selectedSlot
        overlay.hide()

        guard let chosenSlot else {
            targetPID = nil
            return
        }
        guard let item = store.prompt(in: chosenSlot) else {
            report(
                AppLanguageSettings.shared.text(
                    "位置 \(chosenSlot) 还没有 Prompt",
                    "Slot \(chosenSlot) does not have a Prompt yet"
                )
            )
            targetPID = nil
            return
        }

        let pid = targetPID
        targetPID = nil
        explicitSlot = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.injector.insert(item.body, into: pid)
        }
    }

    private func cancelSelection() {
        explicitSlot = nil
        targetPID = nil
        overlay.hide()
        report(AppLanguageSettings.shared.text("已取消", "Cancelled"))
    }

    private func report(_ message: String) {
        lastStatus = message
        toast.show(message)
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
}
