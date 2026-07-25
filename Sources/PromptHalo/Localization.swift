import Foundation

enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case system
    case chinese
    case english

    var id: String { rawValue }
}

enum ResolvedInterfaceLanguage: Equatable {
    case chinese
    case english
}

final class AppLanguageSettings: ObservableObject {
    static let shared = AppLanguageSettings()

    @Published var selection: InterfaceLanguage {
        didSet {
            defaults.set(selection.rawValue, forKey: Self.defaultsKey)
        }
    }

    private static let defaultsKey = "interfaceLanguage.v1"

    private let defaults: UserDefaults
    private let preferredLanguages: () -> [String]

    init(
        defaults: UserDefaults = .standard,
        preferredLanguages: @escaping () -> [String] = {
            Locale.preferredLanguages
        }
    ) {
        self.defaults = defaults
        self.preferredLanguages = preferredLanguages

        if
            let rawValue = defaults.string(forKey: Self.defaultsKey),
            let saved = InterfaceLanguage(rawValue: rawValue)
        {
            selection = saved
        } else {
            selection = .system
        }
    }

    var resolvedLanguage: ResolvedInterfaceLanguage {
        Self.resolve(
            selection: selection,
            preferredLanguages: preferredLanguages()
        )
    }

    var locale: Locale {
        switch resolvedLanguage {
        case .chinese:
            return Locale(identifier: "zh-Hans")
        case .english:
            return Locale(identifier: "en")
        }
    }

    func text(_ chinese: String, _ english: String) -> String {
        resolvedLanguage == .chinese ? chinese : english
    }

    static func resolve(
        selection: InterfaceLanguage,
        preferredLanguages: [String]
    ) -> ResolvedInterfaceLanguage {
        switch selection {
        case .chinese:
            return .chinese
        case .english:
            return .english
        case .system:
            let primary = preferredLanguages.first?.lowercased() ?? "en"
            return primary.hasPrefix("zh") ? .chinese : .english
        }
    }
}
