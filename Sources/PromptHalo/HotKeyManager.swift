import AppKit
import Carbon

private let promptHaloHotKeySignature: OSType = 0x50484C4F // "PHLO"

enum HotKeyRegistrationError: Error {
    case failed(OSStatus)
}

private enum MonitoredInputKind: Sendable, Equatable {
    case flagsChanged
    case keyDown
    case mouseDown
}

private struct MonitoredInput: Sendable {
    let kind: MonitoredInputKind
    let keyCode: UInt32
    let modifierFlags: UInt
    let leftOptionDown: Bool
    let rightOptionDown: Bool

    init?(event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            kind = .flagsChanged
            keyCode = UInt32(event.keyCode)
        case .keyDown:
            kind = .keyDown
            keyCode = UInt32(event.keyCode)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            kind = .mouseDown
            keyCode = 0
        default:
            return nil
        }

        modifierFlags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .rawValue
        leftOptionDown = CGEventSource.keyState(
            .combinedSessionState,
            key: CGKeyCode(kVK_Option)
        )
        rightOptionDown = CGEventSource.keyState(
            .combinedSessionState,
            key: CGKeyCode(kVK_RightOption)
        )
    }
}

private let promptHaloHotKeyCallback: EventHandlerUPP = {
    _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID(signature: 0, id: 0)
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let manager = Unmanaged<HotKeyManager>
        .fromOpaque(userData)
        .takeUnretainedValue()
    manager.receive(eventKind: GetEventKind(event), hotKeyID: hotKeyID.id)
    return noErr
}

@MainActor
final class HotKeyManager {
    var onMenuShown: (() -> Void)?
    var onSlotChanged: ((Int) -> Void)?
    var onMenuReleased: (() -> Void)?
    var onCancelled: (() -> Void)?
    var onError: ((String) -> Void)?

    private enum ID {
        static let triggerA: UInt32 = 1
        static let triggerB: UInt32 = 2
        static let firstSlot: UInt32 = 101
        static let cancel: UInt32 = 200
    }

    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var activeTriggerID: UInt32?
    private var activeTrigger: TriggerHotKey?
    private var globalInputMonitor: Any?
    private var localInputMonitor: Any?
    private var holdWorkItem: DispatchWorkItem?
    private var triggerIsDown = false
    private var menuIsActive = false
    private var wasCancelled = false
    private var modifierSuppressedUntilRelease = false
    private var replayUnmodifiedTriggerOnRelease = false

    init() {
        installHandler()
        installModifierMonitors()
    }

    deinit {
        for reference in hotKeyRefs.values {
            UnregisterEventHotKey(reference)
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
        if let globalInputMonitor {
            NSEvent.removeMonitor(globalInputMonitor)
        }
        if let localInputMonitor {
            NSEvent.removeMonitor(localInputMonitor)
        }
    }

    fileprivate nonisolated func receive(eventKind: UInt32, hotKeyID: UInt32) {
        Task { @MainActor [weak self] in
            self?.handle(eventKind: eventKind, hotKeyID: hotKeyID)
        }
    }

    func applyTrigger(
        _ candidate: TriggerHotKey
    ) -> Result<Void, HotKeyRegistrationError> {
        if activeTrigger == candidate,
           candidate.isOptionOnly || activeTriggerID != nil {
            return .success(())
        }

        if candidate.isOptionOnly {
            cancelCurrentGesture()

            if let activeTriggerID {
                unregister(id: activeTriggerID)
            }

            activeTriggerID = nil
            activeTrigger = candidate
            modifierSuppressedUntilRelease = false
            return .success(())
        }

        let nextID = activeTriggerID == ID.triggerA
            ? ID.triggerB
            : ID.triggerA

        switch makeRegistration(
            id: nextID,
            keyCode: candidate.keyCode,
            modifiers: candidate.modifiers
        ) {
        case let .success(reference):
            cancelCurrentGesture()

            if let activeTriggerID {
                unregister(id: activeTriggerID)
            }

            hotKeyRefs[nextID] = reference
            activeTriggerID = nextID
            activeTrigger = candidate
            modifierSuppressedUntilRelease = false
            return .success(())

        case let .failure(error):
            return .failure(error)
        }
    }

    func suspendTrigger() {
        cancelCurrentGesture()

        if let activeTriggerID {
            unregister(id: activeTriggerID)
        }
        activeTriggerID = nil
        activeTrigger = nil
        modifierSuppressedUntilRelease = false
    }

    func refreshModifierMonitoring() {
        installModifierMonitors()
    }

    private func handle(eventKind: UInt32, hotKeyID: UInt32) {
        if hotKeyID == activeTriggerID {
            if eventKind == UInt32(kEventHotKeyPressed) {
                triggerPressed()
            } else if eventKind == UInt32(kEventHotKeyReleased) {
                triggerReleased()
            }
            return
        }

        guard menuIsActive, eventKind == UInt32(kEventHotKeyPressed) else { return }

        if hotKeyID == ID.cancel {
            wasCancelled = true
            onCancelled?()
            return
        }

        let slot = Int(hotKeyID - ID.firstSlot + 1)
        guard (1...5).contains(slot) else { return }
        onSlotChanged?(slot)
    }

    private func triggerPressed() {
        guard !triggerIsDown else { return }
        triggerIsDown = true
        wasCancelled = false
        replayUnmodifiedTriggerOnRelease = activeTrigger?.isTabOnly == true

        let delay = activeTrigger?.isSingleKeyTrigger == true ? 0.22 : 0.15
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.triggerIsDown else { return }
            self.replayUnmodifiedTriggerOnRelease = false
            self.menuIsActive = true
            self.registerContextHotKeys()
            self.onMenuShown?()
        }
        holdWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func triggerReleased() {
        let shouldReplayUnmodifiedTrigger = replayUnmodifiedTriggerOnRelease
            && !menuIsActive
        replayUnmodifiedTriggerOnRelease = false
        triggerIsDown = false
        holdWorkItem?.cancel()
        holdWorkItem = nil

        guard menuIsActive else {
            if shouldReplayUnmodifiedTrigger {
                replayCurrentUnmodifiedTrigger()
            }
            return
        }
        menuIsActive = false
        unregisterContextHotKeys()

        if wasCancelled {
            wasCancelled = false
        } else {
            onMenuReleased?()
        }
    }

    private func registerContextHotKeys() {
        guard let modifiers = activeTrigger?.modifiers else { return }

        let keyCodes = [
            UInt32(kVK_ANSI_1),
            UInt32(kVK_ANSI_2),
            UInt32(kVK_ANSI_3),
            UInt32(kVK_ANSI_4),
            UInt32(kVK_ANSI_5)
        ]

        for (index, keyCode) in keyCodes.enumerated() {
            register(
                id: ID.firstSlot + UInt32(index),
                keyCode: keyCode,
                modifiers: modifiers
            )
        }

        register(
            id: ID.cancel,
            keyCode: UInt32(kVK_Escape),
            modifiers: modifiers
        )
    }

    private func unregisterContextHotKeys() {
        for id in ID.firstSlot..<(ID.firstSlot + 5) {
            unregister(id: id)
        }
        unregister(id: ID.cancel)
    }

    private func installHandler() {
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]

        let status = eventTypes.withUnsafeMutableBufferPointer { buffer in
            InstallEventHandler(
                GetApplicationEventTarget(),
                promptHaloHotKeyCallback,
                buffer.count,
                buffer.baseAddress,
                Unmanaged.passUnretained(self).toOpaque(),
                &handlerRef
            )
        }

        if status != noErr {
            onError?(
                AppLanguageSettings.shared.text(
                    "无法监听快捷键（错误 \(status)）",
                    "Could not monitor the shortcut (error \(status))"
                )
            )
        }
    }

    private func installModifierMonitors() {
        if let globalInputMonitor {
            NSEvent.removeMonitor(globalInputMonitor)
        }
        if let localInputMonitor {
            NSEvent.removeMonitor(localInputMonitor)
        }

        let mask: NSEvent.EventTypeMask = [
            .flagsChanged,
            .keyDown,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ]

        globalInputMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: mask
        ) { [weak self] event in
            guard let input = MonitoredInput(event: event) else { return }
            Task { @MainActor [weak self] in
                self?.handleMonitoredInput(input)
            }
        }

        localInputMonitor = NSEvent.addLocalMonitorForEvents(
            matching: mask
        ) { [weak self] event in
            if let input = MonitoredInput(event: event) {
                Task { @MainActor [weak self] in
                    self?.handleMonitoredInput(input)
                }
            }
            return event
        }
    }

    private func handleMonitoredInput(_ input: MonitoredInput) {
        guard let activeTrigger else { return }
        if activeTrigger.isTabOnly {
            handleTabOnlyInput(input, trigger: activeTrigger)
            return
        }
        guard activeTrigger.isOptionOnly else { return }

        var watchedOptionDown = activeTrigger.isRightOptionOnly
            ? input.rightOptionDown
            : input.leftOptionDown
        let otherOptionDown = activeTrigger.isRightOptionOnly
            ? input.leftOptionDown
            : input.rightOptionDown
        let flags = NSEvent.ModifierFlags(rawValue: input.modifierFlags)

        if input.kind == .flagsChanged,
           input.keyCode == activeTrigger.keyCode,
           !triggerIsDown,
           flags.contains(.option) {
            // Synthetic events used by QA do not always update keyState,
            // while a real hardware event does. The event flags are a safe
            // fallback only for the initial press of the watched key.
            watchedOptionDown = true
        }

        switch input.kind {
        case .flagsChanged:
            let hasExtraModifier = flags.contains(.command)
                || flags.contains(.control)
                || flags.contains(.shift)

            if watchedOptionDown {
                if hasExtraModifier || otherOptionDown {
                    suppressModifierGesture()
                    return
                }

                guard !modifierSuppressedUntilRelease else { return }
                triggerPressed()
            } else {
                if triggerIsDown {
                    triggerReleased()
                }
                if !input.leftOptionDown && !input.rightOptionDown {
                    modifierSuppressedUntilRelease = false
                }
            }

        case .keyDown:
            guard triggerIsDown else { return }

            let contextKeyCodes: Set<UInt32> = [
                UInt32(kVK_ANSI_1),
                UInt32(kVK_ANSI_2),
                UInt32(kVK_ANSI_3),
                UInt32(kVK_ANSI_4),
                UInt32(kVK_ANSI_5),
                UInt32(kVK_Escape)
            ]
            if menuIsActive && contextKeyCodes.contains(input.keyCode) {
                return
            }

            suppressModifierGesture()

        case .mouseDown:
            guard triggerIsDown else { return }
            suppressModifierGesture()
        }
    }

    private func handleTabOnlyInput(
        _ input: MonitoredInput,
        trigger: TriggerHotKey
    ) {
        switch input.kind {
        case .flagsChanged:
            return

        case .keyDown:
            guard triggerIsDown else { return }
            if input.keyCode == trigger.keyCode {
                return
            }

            let contextKeyCodes: Set<UInt32> = [
                UInt32(kVK_ANSI_1),
                UInt32(kVK_ANSI_2),
                UInt32(kVK_ANSI_3),
                UInt32(kVK_ANSI_4),
                UInt32(kVK_ANSI_5),
                UInt32(kVK_Escape)
            ]
            if menuIsActive && contextKeyCodes.contains(input.keyCode) {
                return
            }

            replayUnmodifiedTriggerOnRelease = false
            cancelCurrentGesture()

        case .mouseDown:
            guard triggerIsDown else { return }
            replayUnmodifiedTriggerOnRelease = false
            cancelCurrentGesture()
        }
    }

    private func suppressModifierGesture() {
        modifierSuppressedUntilRelease = true
        cancelCurrentGesture()
    }

    @discardableResult
    private func register(
        id: UInt32,
        keyCode: UInt32,
        modifiers: UInt32
    ) -> Bool {
        switch makeRegistration(
            id: id,
            keyCode: keyCode,
            modifiers: modifiers
        ) {
        case let .success(reference):
            hotKeyRefs[id] = reference
            return true
        case let .failure(.failed(status)):
            onError?(
                AppLanguageSettings.shared.text(
                    "快捷键被其他应用占用（错误 \(status)）",
                    "The shortcut is already in use (error \(status))"
                )
            )
            return false
        }
    }

    private func makeRegistration(
        id: UInt32,
        keyCode: UInt32,
        modifiers: UInt32
    ) -> Result<EventHotKeyRef, HotKeyRegistrationError> {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(
            signature: promptHaloHotKeySignature,
            id: id
        )

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        if status == noErr, let reference {
            return .success(reference)
        } else {
            return .failure(.failed(status))
        }
    }

    private func unregister(id: UInt32) {
        guard let reference = hotKeyRefs.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(reference)
    }

    private func replayCurrentUnmodifiedTrigger() {
        guard
            let trigger = activeTrigger,
            trigger.isTabOnly,
            let registrationID = activeTriggerID
        else { return }

        unregister(id: registrationID)
        activeTriggerID = nil

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = CGKeyCode(trigger.keyCode)
        let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: true
        )
        let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: false
        )
        keyDown?.flags = []
        keyUp?.flags = []
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self,
                  self.activeTrigger == trigger,
                  self.activeTriggerID == nil else { return }

            switch self.makeRegistration(
                id: registrationID,
                keyCode: trigger.keyCode,
                modifiers: trigger.modifiers
            ) {
            case let .success(reference):
                self.hotKeyRefs[registrationID] = reference
                self.activeTriggerID = registrationID
            case let .failure(.failed(status)):
                self.onError?(
                    AppLanguageSettings.shared.text(
                        "Tab 呼出键暂时无法恢复（错误 \(status)）",
                        "The Tab trigger could not be restored (error \(status))"
                    )
                )
            }
        }
    }

    private func cancelCurrentGesture() {
        triggerIsDown = false
        replayUnmodifiedTriggerOnRelease = false
        holdWorkItem?.cancel()
        holdWorkItem = nil

        if menuIsActive {
            menuIsActive = false
            unregisterContextHotKeys()
            onCancelled?()
        }

        wasCancelled = false
    }
}
