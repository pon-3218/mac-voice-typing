import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    var settings: AppSettings
    var dictationRecords: [DictationRecord]
    var microphoneGranted = false

    private let storage = StorageService.shared
    private let permissions = PermissionsService.shared

    init() {
        settings = storage.loadSettings()
        dictationRecords = storage.loadDictationRecords()
        refreshPermissions()
    }

    func refreshPermissions() {
        microphoneGranted = permissions.microphoneState() == .granted
    }

    @discardableResult
    func requestMicrophonePermission() async -> Bool {
        let granted = await permissions.requestMicrophone()
        refreshPermissions()
        return granted
    }

    func openMicrophoneSettings() {
        permissions.openMicrophoneSettings()
    }


    func addDictation(text: String, duration: TimeInterval, languageMode: LanguageMode) {
        dictationRecords.insert(DictationRecord(text: text, duration: duration, languageMode: languageMode), at: 0)
        if dictationRecords.count > 500 { dictationRecords.removeLast(dictationRecords.count - 500) }
        try? storage.saveDictationRecords(dictationRecords)
    }

    func deleteDictation(id: String) {
        dictationRecords.removeAll { $0.id == id }
        try? storage.saveDictationRecords(dictationRecords)
    }

    func updateSettings(_ settings: AppSettings) {
        var resolved = settings
        resolved.resolveKeyConflict(preferCodexKey: false)
        self.settings = resolved
        storage.saveSettings(resolved)
        LoginItem.setEnabled(resolved.autoLaunch)
    }
}
