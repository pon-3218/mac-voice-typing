import Foundation

final class StorageService: @unchecked Sendable {
    static let shared = StorageService()

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private var supportURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("VoiceInputLocal", isDirectory: true)
    }

    func loadSettings() -> AppSettings {
        let url = supportURL.appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: url), let settings = try? decoder.decode(AppSettings.self, from: data) else {
            return .makeDefault()
        }
        return settings
    }

    func saveSettings(_ settings: AppSettings) {
        try? fileManager.createDirectory(at: supportURL, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: supportURL.appendingPathComponent("settings.json"), options: .atomic)
    }

    func loadDictationRecords() -> [DictationRecord] {
        let url = supportURL.appendingPathComponent("history.json")
        guard let data = try? Data(contentsOf: url), let records = try? decoder.decode([DictationRecord].self, from: data) else { return [] }
        return records.sorted { $0.createdAt > $1.createdAt }
    }

    func saveDictationRecords(_ records: [DictationRecord]) throws {
        try fileManager.createDirectory(at: supportURL, withIntermediateDirectories: true)
        let data = try encoder.encode(records.sorted { $0.createdAt > $1.createdAt })
        try data.write(to: supportURL.appendingPathComponent("history.json"), options: .atomic)
    }
}
