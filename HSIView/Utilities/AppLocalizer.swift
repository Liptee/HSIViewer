import Foundation

enum AppLocalizer {
    static let preferredLanguageDefaultsKey = "preferred_app_language"

    static var preferredLanguage: AppLanguage {
        let stored = UserDefaults.standard.string(forKey: preferredLanguageDefaultsKey)
        return AppLanguage(rawValue: stored ?? "") ?? .english
    }

    static var locale: Locale {
        preferredLanguage.locale
    }

    static func localized(_ key: String) -> String {
        guard let code = preferredLanguage.localizationCode else {
            return NSLocalizedString(key, comment: "")
        }
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return NSLocalizedString(key, comment: "")
        }
        return NSLocalizedString(key, tableName: nil, bundle: bundle, value: key, comment: "")
    }

    static func localizedFormat(_ key: String, args: [CVarArg]) -> String {
        let format = localized(key)
        return String(format: format, locale: locale, arguments: args)
    }
}

func L(_ key: String) -> String {
    AppLocalizer.localized(key)
}

func LF(_ key: String, _ args: CVarArg...) -> String {
    AppLocalizer.localizedFormat(key, args: args)
}
