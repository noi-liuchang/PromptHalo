import AppKit
import Carbon
import Foundation

struct TriggerHotKey: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let defaultValue = TriggerHotKey(
        keyCode: UInt32(kVK_Option),
        modifiers: UInt32(optionKey)
    )

    private static let legacyDefaultValue = TriggerHotKey(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey)
    )
    private static let defaultsKey = "triggerHotKey.v1"
    private static let defaultMigrationKey = "triggerHotKey.leftOptionDefault.v2"

    static func load(defaults: UserDefaults = .standard) -> TriggerHotKey {
        guard
            let data = defaults.data(forKey: defaultsKey),
            let value = try? JSONDecoder().decode(TriggerHotKey.self, from: data),
            value.validationMessage == nil
        else {
            defaults.set(true, forKey: defaultMigrationKey)
            return .defaultValue
        }

        if
            value == legacyDefaultValue,
            !defaults.bool(forKey: defaultMigrationKey)
        {
            defaults.set(true, forKey: defaultMigrationKey)
            defaultValue.save(defaults: defaults)
            return .defaultValue
        }

        defaults.set(true, forKey: defaultMigrationKey)
        return value
    }

    func save(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var result: UInt32 = 0

        if flags.contains(.control) {
            result |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            result |= UInt32(optionKey)
        }
        if flags.contains(.shift) {
            result |= UInt32(shiftKey)
        }
        if flags.contains(.command) {
            result |= UInt32(cmdKey)
        }

        return result
    }

    var isOptionOnly: Bool {
        modifiers == UInt32(optionKey)
            && (
                keyCode == UInt32(kVK_Option)
                    || keyCode == UInt32(kVK_RightOption)
            )
    }

    var isRightOptionOnly: Bool {
        isOptionOnly && keyCode == UInt32(kVK_RightOption)
    }

    var displayString: String {
        if isOptionOnly {
            return isRightOptionOnly
                ? AppLanguageSettings.shared.text("右 ⌥", "Right ⌥")
                : AppLanguageSettings.shared.text("左 ⌥", "Left ⌥")
        }

        var result = ""

        if modifiers & UInt32(controlKey) != 0 {
            result += "⌃"
        }
        if modifiers & UInt32(optionKey) != 0 {
            result += "⌥"
        }
        if modifiers & UInt32(shiftKey) != 0 {
            result += "⇧"
        }
        if modifiers & UInt32(cmdKey) != 0 {
            result += "⌘"
        }

        let key = Self.keyLabel(for: keyCode) ?? "Key \(keyCode)"
        return result + (key.count > 1 ? " \(key)" : key)
    }

    var validationMessage: String? {
        if isOptionOnly {
            return nil
        }

        let modifierOnlyKeyCodes: Set<UInt32> = [
            UInt32(kVK_Option),
            UInt32(kVK_RightOption),
            UInt32(kVK_Control),
            UInt32(kVK_RightControl),
            UInt32(kVK_Shift),
            UInt32(kVK_RightShift),
            UInt32(kVK_Command),
            UInt32(kVK_RightCommand),
            UInt32(kVK_CapsLock),
            UInt32(kVK_Function)
        ]
        guard !modifierOnlyKeyCodes.contains(keyCode) else {
            return AppLanguageSettings.shared.text(
                "单键长按目前只支持左/右 Option；其他修饰键请再搭配一个普通键。",
                "Only Left or Right Option can be used alone. Pair other modifier keys with a regular key."
            )
        }

        let nonShiftModifiers = UInt32(controlKey | optionKey | cmdKey)
        guard modifiers & nonShiftModifiers != 0 else {
            return AppLanguageSettings.shared.text(
                "至少按住 ⌃、⌥ 或 ⌘ 中的一个；⇧ 可以一起使用。",
                "Hold at least one of ⌃, ⌥, or ⌘. You may also include ⇧."
            )
        }

        guard Self.keyLabel(for: keyCode) != nil else {
            return AppLanguageSettings.shared.text(
                "这个按键暂不支持，请换一个字母、数字、空格、方向键或功能键。",
                "That key is not supported. Try a letter, number, Space, arrow key, or function key."
            )
        }

        let reservedSelectionKeys: Set<UInt32> = [
            UInt32(kVK_ANSI_1),
            UInt32(kVK_ANSI_2),
            UInt32(kVK_ANSI_3),
            UInt32(kVK_ANSI_4),
            UInt32(kVK_ANSI_5),
            UInt32(kVK_Escape)
        ]
        guard !reservedSelectionKeys.contains(keyCode) else {
            return AppLanguageSettings.shared.text(
                "1–5 和 Esc 已用于轮盘选择，请换一个呼出主键。",
                "1–5 and Esc are reserved for wheel selection. Choose another trigger key."
            )
        }

        if modifiers == UInt32(cmdKey),
           Self.commonCommandShortcuts.contains(keyCode) {
            return AppLanguageSettings.shared.text(
                "这个组合是常用 Mac 快捷键，PromptHalo 不会抢占它。",
                "That is a common Mac shortcut, so PromptHalo will not take it over."
            )
        }

        return nil
    }

    private static let commonCommandShortcuts: Set<UInt32> = [
        UInt32(kVK_ANSI_A),
        UInt32(kVK_ANSI_C),
        UInt32(kVK_ANSI_F),
        UInt32(kVK_ANSI_N),
        UInt32(kVK_ANSI_P),
        UInt32(kVK_ANSI_Q),
        UInt32(kVK_ANSI_S),
        UInt32(kVK_ANSI_T),
        UInt32(kVK_ANSI_V),
        UInt32(kVK_ANSI_W),
        UInt32(kVK_ANSI_X),
        UInt32(kVK_ANSI_Z)
    ]

    private static func keyLabel(for keyCode: UInt32) -> String? {
        let labels: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A",
            UInt32(kVK_ANSI_B): "B",
            UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D",
            UInt32(kVK_ANSI_E): "E",
            UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G",
            UInt32(kVK_ANSI_H): "H",
            UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J",
            UInt32(kVK_ANSI_K): "K",
            UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M",
            UInt32(kVK_ANSI_N): "N",
            UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P",
            UInt32(kVK_ANSI_Q): "Q",
            UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S",
            UInt32(kVK_ANSI_T): "T",
            UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V",
            UInt32(kVK_ANSI_W): "W",
            UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y",
            UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0",
            UInt32(kVK_ANSI_1): "1",
            UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3",
            UInt32(kVK_ANSI_4): "4",
            UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6",
            UInt32(kVK_ANSI_7): "7",
            UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_Space): "Space",
            UInt32(kVK_Return): "↩",
            UInt32(kVK_Tab): "⇥",
            UInt32(kVK_Delete): "⌫",
            UInt32(kVK_ForwardDelete): "⌦",
            UInt32(kVK_LeftArrow): "←",
            UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑",
            UInt32(kVK_DownArrow): "↓",
            UInt32(kVK_Home): "Home",
            UInt32(kVK_End): "End",
            UInt32(kVK_PageUp): "Page Up",
            UInt32(kVK_PageDown): "Page Down",
            UInt32(kVK_ANSI_Grave): "`",
            UInt32(kVK_ANSI_Minus): "–",
            UInt32(kVK_ANSI_Equal): "=",
            UInt32(kVK_ANSI_LeftBracket): "[",
            UInt32(kVK_ANSI_RightBracket): "]",
            UInt32(kVK_ANSI_Backslash): "\\",
            UInt32(kVK_ANSI_Semicolon): ";",
            UInt32(kVK_ANSI_Quote): "'",
            UInt32(kVK_ANSI_Comma): ",",
            UInt32(kVK_ANSI_Period): ".",
            UInt32(kVK_ANSI_Slash): "/",
            UInt32(kVK_F1): "F1",
            UInt32(kVK_F2): "F2",
            UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4",
            UInt32(kVK_F5): "F5",
            UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7",
            UInt32(kVK_F8): "F8",
            UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10",
            UInt32(kVK_F11): "F11",
            UInt32(kVK_F12): "F12"
        ]

        return labels[keyCode]
    }
}
