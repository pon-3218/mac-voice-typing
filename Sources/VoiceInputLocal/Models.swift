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
    var codexResearchEnabled: Bool
    var codexResearchKeyCode: Int

    static func makeDefault() -> AppSettings {
        AppSettings(
            languageMode: .auto,
            autoLaunch: true,
            dictationEnabled: true,
            dictationKeyCode: DictationKey.fn.rawValue,
            codexResearchEnabled: true,
            codexResearchKeyCode: DictationKey.rightCommand.rawValue
        )
    }

    init(
        languageMode: LanguageMode,
        autoLaunch: Bool,
        dictationEnabled: Bool,
        dictationKeyCode: Int,
        codexResearchEnabled: Bool,
        codexResearchKeyCode: Int
    ) {
        self.languageMode = languageMode
        self.autoLaunch = autoLaunch
        self.dictationEnabled = dictationEnabled
        self.dictationKeyCode = dictationKeyCode
        self.codexResearchEnabled = codexResearchEnabled
        self.codexResearchKeyCode = codexResearchKeyCode
    }

    init(from decoder: Decoder) throws {
        let defaults = Self.makeDefault()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        languageMode = try container.decodeIfPresent(LanguageMode.self, forKey: .languageMode) ?? defaults.languageMode
        autoLaunch = try container.decodeIfPresent(Bool.self, forKey: .autoLaunch) ?? defaults.autoLaunch
        dictationEnabled = try container.decodeIfPresent(Bool.self, forKey: .dictationEnabled) ?? defaults.dictationEnabled
        dictationKeyCode = try container.decodeIfPresent(Int.self, forKey: .dictationKeyCode) ?? defaults.dictationKeyCode
        codexResearchEnabled = try container.decodeIfPresent(Bool.self, forKey: .codexResearchEnabled) ?? defaults.codexResearchEnabled
        codexResearchKeyCode = try container.decodeIfPresent(Int.self, forKey: .codexResearchKeyCode) ?? defaults.codexResearchKeyCode

        if codexResearchKeyCode == dictationKeyCode {
            codexResearchKeyCode = Self.alternativeKey(excluding: dictationKeyCode)
        }
    }

    mutating func resolveKeyConflict(preferCodexKey: Bool) {
        guard codexResearchKeyCode == dictationKeyCode else { return }
        if preferCodexKey {
            dictationKeyCode = Self.alternativeKey(excluding: codexResearchKeyCode)
        } else {
            codexResearchKeyCode = Self.alternativeKey(excluding: dictationKeyCode)
        }
    }

    private static func alternativeKey(excluding keyCode: Int) -> Int {
        DictationKey.allCases.first { $0.rawValue != keyCode }?.rawValue ?? DictationKey.fn.rawValue
    }
}
