import SwiftUI
import AppKit
import Sparkle

@main
struct VoiceInputLocalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Settings {
            SettingsView().environment(model)
                .frame(width: 520, height: 520)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate, SPUStandardUserDriverDelegate {
    private var statusItem: NSStatusItem?
    private var historyWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private let hotkey = HotkeyMonitor()
    private let codexHotkey = HotkeyMonitor()
    private let dictation = DictationController()
    private let hud = DictationHUDController()
    private let codexResearch = CodexResearchController()
    private lazy var codexResearchWindow = CodexResearchWindowController(controller: codexResearch)
    private var updaterController: SPUStandardUpdaterController!
    private var prewarmTask: Task<Void, Never>?
    private var permissionRequestInFlight = false
    private var automaticSetupStarted = false
    private var permissionWatchTask: Task<Void, Never>?
    private weak var previouslyActiveApplication: NSRunningApplication?
    private var activeDestination: DictationController.Destination?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
        setupStatusItem()
        setupDictation()
        AppModel.shared.refreshPermissions()
        var shouldStartAutomaticSetup = true
        if ProcessInfo.processInfo.arguments.contains("--open-settings") {
            openSettings()
        } else if ProcessInfo.processInfo.arguments.contains("--open-history") {
            openHistory()
        } else if ProcessInfo.processInfo.arguments.contains("--open-onboarding")
                    || OnboardingState.needsPresentation {
            openOnboarding()
            shouldStartAutomaticSetup = false
        }
        if shouldStartAutomaticSetup {
            startAutomaticSetupIfNeeded()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppModel.shared.refreshPermissions()
        let settings = AppModel.shared.settings
        if (settings.dictationEnabled || settings.codexResearchEnabled), AccessibilityPermission.isTrusted() {
            applyPreferences()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionWatchTask?.cancel()
        prewarmTask?.cancel()
        hotkey.stop()
        codexHotkey.stop()
        dictation.cancel()
    }

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    private func setupDictation() {
        hotkey.onPress = { [weak self] in
            guard let self, AppModel.shared.settings.dictationEnabled else { return }
            AppModel.shared.refreshPermissions()
            guard AppModel.shared.microphoneGranted else {
                self.requestMissingPermissionsForHotkey()
                return
            }
            self.beginListening(destination: .textInput)
        }
        hotkey.onRelease = { [weak self] in self?.endListening(destination: .textInput) }

        codexHotkey.activationDelay = 0.2
        codexHotkey.cancelsDelayedActivationOnOtherKey = true
        codexHotkey.onPress = { [weak self] in
            guard let self, AppModel.shared.settings.codexResearchEnabled else { return }
            AppModel.shared.refreshPermissions()
            guard AppModel.shared.microphoneGranted else {
                self.requestMissingPermissionsForHotkey()
                return
            }
            self.beginListening(destination: .codexResearch)
        }
        codexHotkey.onRelease = { [weak self] in self?.endListening(destination: .codexResearch) }

        dictation.onFinished = { [weak self] in
            self?.activeDestination = nil
            self?.hud.hide()
        }
        dictation.onTranscribedText = { [weak self] text, duration, language, destination in
            switch destination {
            case .textInput:
                AppModel.shared.addDictation(text: text, duration: duration, languageMode: language)
            case .codexResearch:
                self?.codexResearchWindow.ask(text)
            }
        }
        applyPreferences()
    }

    func applyPreferences() {
        let settings = AppModel.shared.settings
        hotkey.targetKeyCode = UInt16(settings.dictationKeyCode)
        codexHotkey.targetKeyCode = UInt16(settings.codexResearchKeyCode)
        if settings.dictationEnabled {
            hotkey.start()
        } else {
            hotkey.stop()
        }
        if settings.codexResearchEnabled {
            codexHotkey.start()
        } else {
            codexHotkey.stop()
        }
        if settings.dictationEnabled || settings.codexResearchEnabled {
            if AppModel.shared.microphoneGranted { dictation.prepareCapture() }
            prewarmTask?.cancel()
            let locale = Locale(identifier: settings.languageMode.preferredLocaleIdentifier)
            prewarmTask = Task.detached(priority: .background) { await MicStreamTranscriber.prewarm(locale: locale) }
        } else {
            dictation.cancel()
            prewarmTask?.cancel()
            prewarmTask = nil
        }
        LoginItem.setEnabled(settings.autoLaunch)
    }

    func setKeyRecording(_ isRecording: Bool) {
        if isRecording {
            hotkey.stop()
            codexHotkey.stop()
            dictation.cancel()
        } else {
            applyPreferences()
        }
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
        let onboarding = NSMenuItem(title: "使い方…", action: #selector(openOnboarding), keyEquivalent: "")
        onboarding.target = self
        menu.addItem(onboarding)
        let history = NSMenuItem(title: "履歴を開く", action: #selector(openHistory), keyEquivalent: "")
        history.target = self
        menu.addItem(history)
        let settings = NSMenuItem(title: "設定…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        if codexResearch.phase != .idle {
            let research = NSMenuItem(title: "Codexの回答を表示", action: #selector(showCodexResearch), keyEquivalent: "")
            research.target = self
            menu.addItem(research)
        }
        let updates = NSMenuItem(
            title: "アップデートを確認…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updates.target = updaterController
        updates.isEnabled = updaterController.updater.canCheckForUpdates
        menu.addItem(updates)
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

    private func requestOnboardingPermissions() {
        Task {
            if !AppModel.shared.microphoneGranted,
               !(await AppModel.shared.requestMicrophonePermission()) {
                AppModel.shared.openMicrophoneSettings()
            }
            if !AccessibilityPermission.isTrusted(),
               !AccessibilityPermission.requestPrompt() {
                AccessibilityPermission.openSettings()
            }
            applyPreferences()
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

    private func beginListening(destination: DictationController.Destination) {
        guard dictation.phase == .idle else { return }
        activeDestination = destination
        dictation.languageMode = AppModel.shared.settings.languageMode
        dictation.startListening(destination: destination)
        if dictation.phase == .listening { hud.show(dictation) }
    }

    private func endListening(destination: DictationController.Destination) {
        guard activeDestination == destination else { return }
        dictation.stopAndDeliver()
    }

    @objc private func showCodexResearch() {
        codexResearchWindow.show()
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

    @objc private func openOnboarding() {
        if onboardingWindow == nil {
            onboardingWindow = makeWindow(title: "Voice Input Localへようこそ", width: 620, height: 470) {
                OnboardingView(
                    onRequestPermissions: { [weak self] in
                        self?.requestOnboardingPermissions()
                    },
                    onFinish: { [weak self] in
                        OnboardingState.markCompleted()
                        self?.onboardingWindow?.orderOut(nil)
                        self?.applyPreferences()
                        self?.startAutomaticSetupIfNeeded()
                    }
                )
                .environment(AppModel.shared)
            }
        }
        show(onboardingWindow)
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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if OnboardingState.needsPresentation {
            openOnboarding()
        } else {
            openSettings()
        }
        return true
    }
}
