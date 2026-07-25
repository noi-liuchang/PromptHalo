import AppKit
import ApplicationServices

@MainActor
final class PromptInjector {
    var onStatus: ((String) -> Void)?

    private struct PasteboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    func copyOnly(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        onStatus?(
            AppLanguageSettings.shared.text(
                "已复制 · \(text.count) 字",
                "Copied · \(text.count) characters"
            )
        )
    }

    func insert(_ text: String, into targetPID: pid_t?) {
        guard !text.isEmpty else {
            onStatus?(
                AppLanguageSettings.shared.text(
                    "这个 Prompt 还是空的",
                    "This Prompt is still empty"
                )
            )
            return
        }

        let pasteboard = NSPasteboard.general
        let snapshot = capture(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard AccessibilityPermission.isGranted, targetPID != nil else {
            onStatus?(
                AppLanguageSettings.shared.text(
                    "未获得辅助功能权限，已复制到剪贴板",
                    "Accessibility permission is off, so the Prompt was copied instead"
                )
            )
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.postPaste()
            self?.onStatus?(
                AppLanguageSettings.shared.text(
                    "已插入 · \(text.count) 字",
                    "Inserted · \(text.count) characters"
                )
            )

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                guard pasteboard.string(forType: .string) == text else { return }
                self?.restore(snapshot, to: pasteboard)
            }
        }
    }

    private func postPaste() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        let commandKey: CGKeyCode = 0x37
        let vKey: CGKeyCode = 0x09

        let events: [(CGKeyCode, Bool)] = [
            (commandKey, true),
            (vKey, true),
            (vKey, false),
            (commandKey, false)
        ]

        for (key, isDown) in events {
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: key,
                keyDown: isDown
            ) else { continue }
            event.flags = key == commandKey && !isDown ? [] : .maskCommand
            event.post(tap: .cghidEventTap)
        }
    }

    private func capture(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = pasteboard.pasteboardItems?.map { item in
            Dictionary(
                uniqueKeysWithValues: item.types.compactMap { type in
                    item.data(forType: type).map { (type, $0) }
                }
            )
        } ?? []
        return PasteboardSnapshot(items: items)
    }

    private func restore(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }

        let restored = snapshot.items.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
