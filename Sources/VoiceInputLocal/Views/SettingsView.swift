import SwiftUI
import AppKit

struct SettingsView: View {
    private enum RecordingTarget { case dictation, codexResearch }

    @Environment(AppModel.self) private var model
    @State private var draft = AppSettings.makeDefault()
    @State private var accessibilityTrusted = false
    @State private var recordingTarget: RecordingTarget?
    @State private var recorder: ModifierKeyRecorder?
    @State private var recordingError: String?

    var body: some View {
        Form {
            Section("音声入力") {
                Toggle("音声入力を有効にする", isOn: $draft.dictationEnabled)
                keyRecorderRow(
                    title: "ホールドキー",
                    keyCode: draft.dictationKeyCode,
                    target: .dictation,
                    enabled: draft.dictationEnabled
                )
                Picker("認識言語", selection: $draft.languageMode) {
                    ForEach(LanguageMode.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
            }

            Section("Codexで調べる") {
                Toggle("音声でCodexに質問する", isOn: $draft.codexResearchEnabled)
                keyRecorderRow(
                    title: "質問キー",
                    keyCode: draft.codexResearchKeyCode,
                    target: .codexResearch,
                    enabled: draft.codexResearchEnabled
                )
                Text("キーを約0.2秒押すと録音を開始し、離すとCodexへ送ります。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let recordingError {
                    Text(recordingError)
                        .font(.caption)
                        .foregroundStyle(.red)
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
        .onDisappear {
            recorder?.stop()
            recorder = nil
            recordingTarget = nil
            (NSApp.delegate as? AppDelegate)?.setKeyRecording(false)
        }
    }

    @ViewBuilder
    private func keyRecorderRow(
        title: String,
        keyCode: Int,
        target: RecordingTarget,
        enabled: Bool
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 12) {
                Text(DictationKey(rawValue: keyCode)?.displayName ?? "未設定")
                    .foregroundStyle(enabled ? .primary : .secondary)
                Button(recordingTarget == target ? "設定するキーを押してください" : "変更") {
                    beginKeyRecording(target)
                }
                .disabled(!enabled || (recordingTarget != nil && recordingTarget != target))
            }
        }
    }

    private func beginKeyRecording(_ target: RecordingTarget) {
        if recordingTarget == target {
            recorder?.cancel()
            return
        }

        recorder?.stop()
        recordingError = nil
        recordingTarget = target
        (NSApp.delegate as? AppDelegate)?.setKeyRecording(true)

        let nextRecorder = ModifierKeyRecorder()
        recorder = nextRecorder
        let started = nextRecorder.start(
            onRecorded: { key in record(key, for: target) },
            onCancelled: { finishKeyRecording() }
        )
        if !started {
            recordingError = "キーを取得できません。アクセシビリティ権限を確認してください。"
            finishKeyRecording()
        }
    }

    private func record(_ key: DictationKey, for target: RecordingTarget) {
        var didRecord = false
        switch target {
        case .dictation:
            if draft.codexResearchEnabled, key.rawValue == draft.codexResearchKeyCode {
                recordingError = "Codex質問キーとは別のキーを押してください。"
            } else {
                draft.dictationKeyCode = key.rawValue
                didRecord = true
            }
        case .codexResearch:
            if draft.dictationEnabled, key.rawValue == draft.dictationKeyCode {
                recordingError = "通常の音声入力とは別のキーを押してください。"
            } else {
                draft.codexResearchKeyCode = key.rawValue
                didRecord = true
            }
        }
        if didRecord {
            model.updateSettings(draft)
        }
        finishKeyRecording()
    }

    private func finishKeyRecording() {
        recorder?.stop()
        recorder = nil
        recordingTarget = nil
        (NSApp.delegate as? AppDelegate)?.setKeyRecording(false)
    }
}
