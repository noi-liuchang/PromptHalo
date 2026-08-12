import Carbon
import Foundation

private enum SelfTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message):
            return message
        }
    }
}

@main
struct PromptHaloSelfTests {
    @MainActor
    static func main() throws {
        try check(
            AppLanguageSettings.resolve(
                selection: .system,
                preferredLanguages: ["zh-Hans-CN", "en-US"]
            ) == .chinese,
            "System language should resolve zh-Hans to Chinese"
        )
        try check(
            AppLanguageSettings.resolve(
                selection: .system,
                preferredLanguages: ["en-US", "zh-Hans-CN"]
            ) == .english,
            "System language should resolve en-US to English"
        )
        try check(
            AppLanguageSettings.resolve(
                selection: .english,
                preferredLanguages: ["zh-Hans-CN"]
            ) == .english,
            "Manual English should override the Mac language"
        )

        for language in [
            ResolvedInterfaceLanguage.chinese,
            ResolvedInterfaceLanguage.english
        ] {
            let prompts = PromptTemplates.defaults(for: language)
            try check(
                prompts.count == 5,
                "Each language must contain exactly five default Prompts"
            )
            try check(
                prompts.compactMap(\.slot) == [1, 2, 3, 4, 5],
                "Default Prompts must fill slots 1 through 5"
            )
            for prompt in prompts {
                try check(
                    prompt.body.count > 500,
                    "\(prompt.title) is only \(prompt.body.count) characters; every default Prompt must exceed 500"
                )
            }
            try check(
                Set(prompts.map(\.title)).count == 5,
                "Default Prompt titles must be unique"
            )
        }

        try check(
            TriggerHotKey.defaultValue.keyCode
                == UInt32(kVK_Tab),
            "The default trigger must use Tab"
        )
        try check(
            TriggerHotKey.defaultValue.modifiers
                == 0,
            "The default Tab trigger must not require modifiers"
        )
        try check(
            TriggerHotKey.defaultValue.isTabOnly
                && TriggerHotKey.defaultValue.isSingleKeyTrigger,
            "The default trigger must be Tab-only"
        )
        try check(
            TriggerHotKey.defaultValue.validationMessage == nil,
            "Tab-only must be accepted as a valid long-press trigger"
        )

        try checkLegacyShortcutMigration()
        try checkCustomShortcutPreservation()
        try checkExistingPromptPreservation()

        print("PromptHalo self-tests: all passed")
    }

    private static func check(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        if !condition() {
            throw SelfTestFailure.failed(message)
        }
    }

    private static func checkLegacyShortcutMigration() throws {
        try checkLegacyShortcutMigration(
            TriggerHotKey(
                keyCode: UInt32(kVK_Space),
                modifiers: UInt32(optionKey)
            ),
            label: "Option-Space"
        )
        try checkLegacyShortcutMigration(
            TriggerHotKey(
                keyCode: UInt32(kVK_Option),
                modifiers: UInt32(optionKey)
            ),
            label: "Left Option"
        )
    }

    private static func checkLegacyShortcutMigration(
        _ legacy: TriggerHotKey,
        label: String
    ) throws {
        let suiteName = "PromptHaloSelfTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw SelfTestFailure.failed("Could not create isolated UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(try JSONEncoder().encode(legacy), forKey: "triggerHotKey.v1")

        try check(
            TriggerHotKey.load(defaults: defaults) == .defaultValue,
            "Legacy \(label) should migrate to Tab"
        )
        try check(
            TriggerHotKey.load(defaults: defaults) == .defaultValue,
            "Migrated Tab should remain stable"
        )
    }

    private static func checkCustomShortcutPreservation() throws {
        let suiteName = "PromptHaloSelfTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw SelfTestFailure.failed("Could not create isolated UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let custom = TriggerHotKey(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(controlKey)
        )
        defaults.set(try JSONEncoder().encode(custom), forKey: "triggerHotKey.v1")

        try check(
            TriggerHotKey.load(defaults: defaults) == custom,
            "A customized trigger must not be replaced by the Tab migration"
        )
    }

    @MainActor
    private static func checkExistingPromptPreservation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PromptHaloSelfTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let fileURL = directory.appendingPathComponent("prompts.json")

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let custom = PromptItem(
            title: "My Existing Prompt",
            body: "Do not replace me.",
            slot: 3
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([custom]).write(
            to: fileURL,
            options: .atomic
        )

        let store = PromptStore(
            fileURL: fileURL,
            initialLanguage: .chinese
        )

        try check(
            store.prompts.count == 1
                && store.prompts.first?.id == custom.id
                && store.prompts.first?.title == "My Existing Prompt"
                && store.prompts.first?.body == "Do not replace me.",
            "Changing interface language must not replace existing Prompts"
        )
    }
}
