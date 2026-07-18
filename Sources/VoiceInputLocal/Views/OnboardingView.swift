import AppKit
import SwiftUI

enum OnboardingState {
    private static let completionKey = "onboarding.completed.v1"

    static var needsPresentation: Bool {
        !UserDefaults.standard.bool(forKey: completionKey)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completionKey)
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var accessibilityTrusted = false
    let onRequestPermissions: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .top, spacing: 18) {
                Image(systemName: "text.cursor")
                    .font(.system(size: 38, weight: .medium))
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 6) {
                    Text("押して話す。離すと入力。")
                        .font(.system(size: 26, weight: .semibold))
                    Text("Voice Input Localはメニューバーで待機します。")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 20) {
                onboardingStep(number: "1", title: "入力欄を選ぶ", detail: "文章を入れたい場所へカーソルを置きます。")
                onboardingStep(number: "2", title: "Fnを押したまま話す", detail: "押している間だけマイクを使用します。")
                onboardingStep(number: "3", title: "離すと文字が入る", detail: "文字起こしはこのMac上で処理されます。")
            }

            HStack(spacing: 22) {
                permissionStatus(title: "マイク", allowed: model.microphoneGranted)
                permissionStatus(title: "文字入力", allowed: accessibilityTrusted)
                Spacer()
                Label(
                    model.settings.autoLaunch ? "ログイン時に自動で起動" : "自動起動は設定で変更できます",
                    systemImage: model.settings.autoLaunch ? "checkmark" : "gearshape"
                )
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("権限を設定", action: onRequestPermissions)
                Spacer()
                Button("使い始める", action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 620, height: 470, alignment: .topLeading)
        .task {
            while !Task.isCancelled {
                model.refreshPermissions()
                accessibilityTrusted = AccessibilityPermission.isTrusted()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func onboardingStep(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Text(number)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 16, weight: .medium))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func permissionStatus(title: String, allowed: Bool) -> some View {
        Label(
            allowed ? "\(title) 許可済み" : "\(title) 設定が必要",
            systemImage: allowed ? "checkmark.circle.fill" : "circle"
        )
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(allowed ? Color.green : Color.secondary)
    }
}
