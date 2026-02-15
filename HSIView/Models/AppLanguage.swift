import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english
    case russian
    case system

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .english:
            return Locale(identifier: "en")
        case .russian:
            return Locale(identifier: "ru")
        case .system:
            return .autoupdatingCurrent
        }
    }

    var localizationCode: String? {
        switch self {
        case .english:
            return "en"
        case .russian:
            return "ru"
        case .system:
            return nil
        }
    }
}
