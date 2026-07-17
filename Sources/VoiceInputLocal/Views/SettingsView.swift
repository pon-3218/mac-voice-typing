import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = AppSettings.makeDefault()
    @State private var accessibilityTrusted = false

    var body: some View {
        Form {
            Section("音声入力") {
                Toggle("音声入力を有効にする", isOn: $draft.dictationEnabled)
                Picker("ホールドキー", selection: $draft.dictationKeyCode) {
                    ForEach(DictationKey.allCases, id: \.rawValue) { key in
                        Text(key.displayName).tag(key.rawValue)
                    }
                }
                .disabled(!draft.dictationEnabled)
                Picker("認識言語", selection: $draft.languageMode) {
                    ForEach(LanguageMode.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
            }

            Section("権限") {
                LabeledContent("マイク") {
                    if model.microphoneGranted {
                        Text("許可済み").foregroundStyle(.green)
                    } else {
                        Button("許可") {
                            Task {
                                if !(await model.requestMicrophonePermission()) {
                                    model.openMicrophoneSettings()
                                }
                            }
                        }
                    }
                }
                LabeledContent("ホールドキーと文字入力") {
                    if accessibilityTrusted {
                        Text("許可済み").foregroundStyle(.green)
                    } else {
                        Button("アクセシビリティを許可") { AccessibilityPermission.requestPrompt() }
                    }
                }
            }

            Section("起動") {
                Toggle("ログイン時に起動", isOn: $draft.autoLaunch)
            }

            HStack {
                Spacer()
                Button("保存") {
                    model.updateSettings(draft)
                    (NSApp.delegate as? AppDelegate)?.applyPreferences()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            draft = model.settings
            model.refreshPermissions()
            accessibilityTrusted = AccessibilityPermission.isTrusted()
        }
    }
}
