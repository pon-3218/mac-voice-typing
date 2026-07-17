import Foundation

enum LanguageMode: String, Codable, CaseIterable, Sendable {
    case auto
    case japanese
    case english

    var displayName: String {
        switch self {
        case .auto: return "自動（日本語優先）"
        case .japanese: return "日本語"
        case .english: return "English"
        }
    }

    var preferredLocaleIdentifier: String {
        switch self {
        case .auto, .japanese: return "ja-JP"
        case .english: return "en-US"
        }
    }
}

enum DictationKey: Int, CaseIterable, Sendable {
    case rightOption = 61
    case fn = 63
    case rightCommand = 54
    case rightControl = 62

    var displayName: String {
        switch self {
        case .rightOption: return "右 Option"
        case .fn: return "Fn"
        case .rightCommand: return "右 Command"
        case .rightControl: return "右 Control"
        }
    }
}

struct DictationRecord: Codable, Identifiable, Sendable, Equatable {
    var id: String = UUID().uuidString
    var createdAt: Date = Date()
    var text: String
    var duration: TimeInterval
    var languageMode: LanguageMode
}

struct AppSettings: Codable, Sendable, Equatable {
    var languageMode: LanguageMode
    var autoLaunch: Bool
    var dictationEnabled: Bool
    var dictationKeyCode: Int

    static func makeDefault() -> AppSettings {
        AppSettings(
            languageMode: .auto,
            autoLaunch: true,
            dictationEnabled: true,
            dictationKeyCode: DictationKey.fn.rawValue
        )
    }
}
