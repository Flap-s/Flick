import AppKit
import Combine

/// Flick speaks French or English; the user picks one in the settings or follows the system.
enum AppLanguage: String, CaseIterable {
    case system, french, english
}

@MainActor
final class Localization: ObservableObject {
    static let shared = Localization()
    nonisolated private static let key = "language"

    /// Read from any thread by `tr`; only written on the main thread. Initialized from the saved choice on first use,
    /// so text built before the settings are ever opened is already in the right language.
    nonisolated(unsafe) fileprivate static var french = resolve(storedLanguage)

    nonisolated private static var storedLanguage: AppLanguage {
        UserDefaults.standard.string(forKey: key).flatMap(AppLanguage.init) ?? .system
    }

    @Published var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            UserDefaults.standard.set(language.rawValue, forKey: Self.key)
            Self.french = Self.resolve(language)
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    static let didChange = Notification.Name("FlickLanguageDidChange")

    private init() {
        language = Self.storedLanguage
        Self.french = Self.resolve(language)
    }

    var isFrench: Bool { Self.french }

    nonisolated private static func resolve(_ language: AppLanguage) -> Bool {
        switch language {
        case .french: true
        case .english: false
        case .system: (Locale.preferredLanguages.first ?? "en").hasPrefix("fr")
        }
    }

    func label(_ language: AppLanguage) -> String {
        switch language {
        case .system: tr("Langue du système", "System language")
        case .french: "Français"
        case .english: "English"
        }
    }
}

/// The French or English text, depending on the chosen language.
func tr(_ french: String, _ english: String) -> String {
    Localization.french ? french : english
}
