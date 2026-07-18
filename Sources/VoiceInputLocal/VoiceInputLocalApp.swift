import SwiftUI
import AppKit

@main
struct VoiceInputLocalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Settings {
            SettingsView().environment(model)
                .frame(width: 500, height: 390)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var historyWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private let hotkey = HotkeyMonitor()
    private let dictation = DictationController()
    private let hud = DictationHUDController()
    private var prewarmTask: Task<Void, Never>?
    private var permissionRequestInFlight = false
    private var automaticSetupStarted = false
    private var permissionWatchTask: Task<Void, Never>?
    private weak var previouslyActiveApplication: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupDictation()
        AppModel.shared.refreshPermissions()
        if ProcessInfo.processInfo.arguments.contains("--open-settings") {
            openSettings()
        } else if ProcessInfo.processInfo.arguments.contains("--open-history") {
            openHistory()
        }
        startAutomaticSetupIfNeeded()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppModel.shared.refreshPermissions()
        if AppModel.shared.settings.dictationEnabled, AccessibilityPermission.isTrusted() {
            if AppModel.shared.microphoneGranted { dictation.prepareCapture() }
            hotkey.start()
        }
    }

    private func setupDictation() {
        hotkey.onPress = { [weak self] in
            guard let self, AppModel.shared.settings.dictationEnabled else { return }
            AppModel.shared.refreshPermissions()
            guard AppModel.shared.microphoneGranted else {
                self.requestMissingPermissionsForHotkey()
                return
            }
            self.beginListening()
        }
        hotkey.onRelease = { [weak self] in self?.dictation.stopAndDeliver() }
        dictation.onFinished = { [weak self] in self?.hud.hide() }
        dictation.onDeliveredText = { text, duration, language in
            AppModel.shared.addDictation(text: text, duration: duration, languageMode: language)
        }
        applyPreferences()
    }

    func applyPreferences() {
        let settings = AppModel.shared.settings
        hotkey.targetKeyCode = UInt16(settings.dictationKeyCode)
        if settings.dictationEnabled {
            if AppModel.shared.microphoneGranted { dictation.prepareCapture() }
            hotkey.start()
            prewarmTask?.cancel()
            let locale = Locale(identifier: settings.languageMode.preferredLocaleIdentifier)
            prewarmTask = Task.detached(priority: .background) { await MicStreamTranscriber.prewarm(locale: locale) }
        } else {
            hotkey.stop()
            prewarmTask?.cancel()
            prewarmTask = nil
        }
        LoginItem.setEnabled(settings.autoLaunch)
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "VoiceInputLocal.statusItem"
        item.isVisible = true
        let icon = NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "音声入力")
        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        let menuIcon = icon?.withSymbolConfiguration(configuration) ?? icon
        menuIcon?.isTemplate = true
        item.button?.image = menuIcon
        item.button?.imageScaling = .scaleProportionallyDown
        item.button?.toolTip = "Voice Input Local"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.statusItem?.isVisible = true
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        AppModel.shared.refreshPermissions()
        let enabled = AppModel.shared.settings.dictationEnabled
        let stateTitle: String
        switch dictation.phase {
        case .idle:
            if !enabled {
                stateTitle = "音声入力 停止中"
            } else if !AccessibilityPermission.isTrusted() {
                stateTitle = "アクセシビリティの許可が必要"
            } else if dictation.lastError != nil {
                stateTitle = "前回の音声入力でエラー"
            } else {
                stateTitle = "ホールドキーで音声入力"
            }
        case .listening: stateTitle = "● 聞き取り中"
        case .transcribing: stateTitle = "文字起こし中"
        }
        let state = NSMenuItem(title: stateTitle, action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)

        if !AppModel.shared.microphoneGranted {
            let permission = NSMenuItem(title: "マイクを許可", action: #selector(requestMicrophone), keyEquivalent: "")
            permission.target = self
            menu.addItem(permission)
        }
        if !AccessibilityPermission.isTrusted() {
            let permission = NSMenuItem(title: "アクセシビリティを許可", action: #selector(requestAccessibility), keyEquivalent: "")
            permission.target = self
            menu.addItem(permission)
        }
        menu.addItem(.separator())
        let history = NSMenuItem(title: "履歴を開く", action: #selector(openHistory), keyEquivalent: "")
        history.target = self
        menu.addItem(history)
        let settings = NSMenuItem(title: "設定…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func requestMicrophone() {
        Task {
            if !(await AppModel.shared.requestMicrophonePermission()) {
                AppModel.shared.openMicrophoneSettings()
            }
        }
    }

    @objc private func requestAccessibility() {
        if AccessibilityPermission.requestPrompt() {
            applyPreferences()
        } else {
            AccessibilityPermission.openSettings()
        }
    }

    /// 初回起動を最短化する。必要な権限を順番に要求し、許可後は自動で待機状態へ移る。
    private func startAutomaticSetupIfNeeded() {
        guard !automaticSetupStarted else { return }
        AppModel.shared.refreshPermissions()
        guard !AppModel.shared.microphoneGranted || !AccessibilityPermission.isTrusted() else { return }

        automaticSetupStarted = true
        previouslyActiveApplication = NSWorkspace.shared.frontmostApplication
        openSettings()

        permissionWatchTask?.cancel()
        permissionWatchTask = Task { [weak self] in
            guard let self else { return }
            if !AppModel.shared.microphoneGranted {
                _ = await AppModel.shared.requestMicrophonePermission()
            }
            if !AccessibilityPermission.isTrusted() {
                _ = AccessibilityPermission.requestPrompt()
                if !AccessibilityPermission.isTrusted() {
                    AccessibilityPermission.openSettings()
                }
            }

            while !Task.isCancelled {
                AppModel.shared.refreshPermissions()
                if AppModel.shared.microphoneGranted, AccessibilityPermission.isTrusted() {
                    applyPreferences()
                    settingsWindow?.orderOut(nil)
                    previouslyActiveApplication?.activate(options: [])
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func beginListening() {
        guard dictation.phase == .idle else { return }
        dictation.languageMode = AppModel.shared.settings.languageMode
        dictation.startListening()
        if dictation.phase == .listening { hud.show(dictation) }
    }

    private func requestMissingPermissionsForHotkey() {
        guard !permissionRequestInFlight else { return }
        permissionRequestInFlight = true
        Task {
            if !AppModel.shared.microphoneGranted {
                _ = await AppModel.shared.requestMicrophonePermission()
            }
            permissionRequestInFlight = false
            if !AppModel.shared.microphoneGranted {
                openSettings()
            }
        }
    }

    @objc private func openHistory() {
        if historyWindow == nil {
            historyWindow = makeWindow(title: "音声入力履歴", width: 760, height: 560) {
                DictationHistoryView().environment(AppModel.shared)
            }
        }
        show(historyWindow)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "音声入力設定", width: 500, height: 420) {
                SettingsView().environment(AppModel.shared)
            }
        }
        show(settingsWindow)
    }

    private func makeWindow<Content: View>(
        title: String,
        width: CGFloat,
        height: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: width, height: height)
        window.center()
        window.delegate = self
        window.contentView = NSHostingView(rootView: content())
        return window
    }

    private func show(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
