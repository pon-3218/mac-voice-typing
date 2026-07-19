import XCTest
@testable import VoiceInputLocal

final class CoreTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testDefaultSettingsEnableMenuBarDictation() {
        let settings = AppSettings.makeDefault()
        XCTAssertTrue(settings.dictationEnabled)
        XCTAssertTrue(settings.autoLaunch)
        XCTAssertEqual(settings.dictationKeyCode, DictationKey.fn.rawValue)
    }

    func testTextDeliveryFallsBackToPaste() {
        var copied = ""
        var typed = false
        var pasted = false
        let result = TextInserter.deliver(
            " テスト ",
            copy: { copied = $0 },
            typeIntoFocusedField: { _ in typed = true; return false },
            insertIntoFocusedField: { _ in false },
            pasteFromClipboard: { pasted = true; return true }
        )
        XCTAssertEqual(result, .commandPaste)
        XCTAssertEqual(copied, "テスト")
        XCTAssertTrue(typed)
        XCTAssertTrue(pasted)
    }

    func testTextDeliveryUsesDirectTypingBeforeAccessibilityAndPaste() {
        var insertedUsingAccessibility = false
        var pasted = false
        let result = TextInserter.deliver(
            "入力テスト",
            copy: { _ in },
            typeIntoFocusedField: { _ in true },
            insertIntoFocusedField: { _ in insertedUsingAccessibility = true; return true },
            pasteFromClipboard: { pasted = true; return true }
        )
        XCTAssertEqual(result, .directTyping)
        XCTAssertFalse(insertedUsingAccessibility)
        XCTAssertFalse(pasted)
    }

    func testHistoryRecordKeepsRecognitionMetadata() throws {
        let record = DictationRecord(text: "入力テスト", duration: 1.25, languageMode: .japanese)
        let decoded = try JSONDecoder().decode(DictationRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded, record)
    }

    func testCaptureIsIdleUntilDictationStarts() {
        let capture = OnDemandMicrophoneCapture()
        XCTAssertFalse(capture.isCapturing)
        XCTAssertEqual(OnDemandMicrophoneCapture.postRollSeconds, 0.30, accuracy: 0.001)
    }

    func testDistributionEntitlementsAllowAudioInput() throws {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent("VoiceInputLocal.entitlements"))
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        XCTAssertEqual(plist["com.apple.security.device.audio-input"] as? Bool, true)
    }

    func testBuildScriptAppliesDistributionEntitlements() throws {
        let script = try String(
            contentsOf: repositoryRoot.appendingPathComponent("build-app.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(script.contains("--entitlements \"${ENTITLEMENTS}\""))
        XCTAssertTrue(script.contains("VoiceInputLocal.entitlements"))
    }

    func testStatusItemIsExplicitlyVisibleAndRestorable() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/VoiceInputLocal/VoiceInputLocalApp.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("item.autosaveName = \"VoiceInputLocal.statusItem\""))
        XCTAssertTrue(source.contains("item.isVisible = true"))
    }

    func testSigningSetupDoesNotPublishReusablePasswords() throws {
        let script = try String(
            contentsOf: repositoryRoot.appendingPathComponent("tools/setup-signing.sh"),
            encoding: .utf8
        )
        XCTAssertFalse(script.contains("KC_PW=\"voiceinput-local\""))
        XCTAssertFalse(script.contains("P12_PW=\"voiceinput\""))
    }

    func testReleaseChecksumsUsePortableFileNames() throws {
        let script = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/release.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(script.contains("shasum -a 256 \"${archive_path:t}\""))
        XCTAssertTrue(script.contains("shasum -a 256 \"${stable_archive_path:t}\""))
    }

    func testOnboardingIsFirstRunOnlyAndReopenableFromMenu() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/VoiceInputLocal/VoiceInputLocalApp.swift"),
            encoding: .utf8
        )
        let onboarding = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/VoiceInputLocal/Views/OnboardingView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("OnboardingState.needsPresentation"))
        XCTAssertTrue(source.contains("NSMenuItem(title: \"使い方…\""))
        XCTAssertTrue(onboarding.contains("Fnを押したまま話す"))
        XCTAssertTrue(onboarding.contains("ログイン時に自動で起動"))
    }

    func testCaptureDoesNotEnableFailingVoiceProcessingPath() throws {
        let capture = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/VoiceInputLocal/Services/OnDemandMicrophoneCapture.swift"),
            encoding: .utf8
        )
        let app = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/VoiceInputLocal/VoiceInputLocalApp.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(capture.contains("setVoiceProcessingEnabled(true)"))
        XCTAssertFalse(capture.contains("voiceProcessingOtherAudioDuckingConfiguration"))
        XCTAssertFalse(capture.contains("duckingLevel = .max"))
        XCTAssertTrue(app.contains("func applicationWillTerminate"))
        XCTAssertTrue(app.contains("dictation.cancel()"))
    }

    func testBatchTranscriberCollectsTheCompleteFinalTranscript() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/VoiceInputLocal/Services/BatchTranscriber.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("FinalTranscriptAssembler"))
        XCTAssertTrue(source.contains("result.range.start.seconds"))
        XCTAssertTrue(source.contains("return try await collector.value"))
        XCTAssertFalse(source.contains("catch { }"))
    }

    func testFinalTranscriptAssemblerOrdersSegmentsAndReplacesDuplicateRanges() {
        var assembler = FinalTranscriptAssembler()

        assembler.upsert(start: 1.0, end: 2.0, text: "の日本語")
        assembler.upsert(start: 0.0, end: 1.0, text: "複数")
        assembler.upsert(start: 1.0, end: 2.0, text: "の日本語")
        assembler.upsert(start: 2.0, end: 3.0, text: "")

        XCTAssertEqual(assembler.text, "複数の日本語")
    }

    func testFinalTranscriptCollectorPropagatesFailureInsteadOfReturningPartialText() async {
        enum ResultStreamError: Error { case interrupted }
        let results = AsyncThrowingStream<(Double, Double, String), Error> { continuation in
            continuation.yield((0.0, 1.0, "あ"))
            continuation.finish(throwing: ResultStreamError.interrupted)
        }

        do {
            _ = try await FinalTranscriptAssembler.collect(results) {
                (start: $0.0, end: $0.1, text: $0.2)
            }
            XCTFail("結果列の失敗を部分文字列の成功として返してはいけない")
        } catch {
            XCTAssertTrue(error is ResultStreamError)
        }
    }

    func testSparkleUpdaterIsConfiguredAndPackaged() throws {
        let package = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let infoData = try Data(contentsOf: repositoryRoot.appendingPathComponent("Info.plist"))
        let info = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
        )
        let app = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/VoiceInputLocal/VoiceInputLocalApp.swift"),
            encoding: .utf8
        )
        let build = try String(
            contentsOf: repositoryRoot.appendingPathComponent("build-app.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(package.contains("sparkle-project/Sparkle"))
        XCTAssertTrue(package.contains(".product(name: \"Sparkle\""))
        XCTAssertEqual(
            info["SUFeedURL"] as? String,
            "https://github.com/pon-3218/mac-voice-typing/releases/latest/download/appcast.xml"
        )
        XCTAssertEqual(info["SUPublicEDKey"] as? String, "/pZPsjAugR1OBk4dmcXeBNj3ejbXEQUainCLNVQfifg=")
        XCTAssertEqual(info["SUEnableAutomaticChecks"] as? Bool, true)
        XCTAssertEqual(info["SUAutomaticallyUpdate"] as? Bool, true)
        XCTAssertTrue(app.contains("SPUStandardUpdaterController"))
        XCTAssertTrue(app.contains("supportsGentleScheduledUpdateReminders"))
        XCTAssertTrue(app.contains("アップデートを確認…"))
        XCTAssertTrue(build.contains("Sparkle.framework"))
        XCTAssertTrue(build.contains("Autoupdate"))
    }

    func testReleasePublishesSignedSparkleAppcast() throws {
        let release = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/release.sh"),
            encoding: .utf8
        )
        let workflow = try String(
            contentsOf: repositoryRoot.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )

        XCTAssertTrue(release.contains("generate_appcast"))
        XCTAssertTrue(release.contains("--ed-key-file -"))
        XCTAssertTrue(release.contains("appcast.xml"))
        XCTAssertTrue(workflow.contains("SPARKLE_EDDSA_PRIVATE_KEY"))
    }

    func testDefaultSettingsUseRightCommandForCodexResearch() {
        let settings = AppSettings.makeDefault()
        XCTAssertTrue(settings.codexResearchEnabled)
        XCTAssertEqual(settings.codexResearchKeyCode, DictationKey.rightCommand.rawValue)
        XCTAssertNotEqual(settings.codexResearchKeyCode, settings.dictationKeyCode)
    }

    func testLegacySettingsGainCodexResearchDefaultsWithoutLosingValues() throws {
        let legacy = """
        {
          "languageMode" : "english",
          "autoLaunch" : false,
          "dictationEnabled" : true,
          "dictationKeyCode" : 61
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: legacy)
        XCTAssertEqual(settings.languageMode, .english)
        XCTAssertFalse(settings.autoLaunch)
        XCTAssertEqual(settings.dictationKeyCode, DictationKey.rightOption.rawValue)
        XCTAssertTrue(settings.codexResearchEnabled)
        XCTAssertEqual(settings.codexResearchKeyCode, DictationKey.rightCommand.rawValue)
    }

    func testDelayedHoldIgnoresTapAndShortcutButActivatesLongPress() {
        var state = HoldActivationState()
        XCTAssertEqual(state.press(requiresDelay: true), .scheduleActivation)
        XCTAssertEqual(state.release(), .cancelPending)

        XCTAssertEqual(state.press(requiresDelay: true), .scheduleActivation)
        XCTAssertEqual(state.otherKeyPressed(), .cancelPending)
        XCTAssertEqual(state.activatePending(), .none)
        XCTAssertEqual(state.release(), .none)

        XCTAssertEqual(state.press(requiresDelay: true), .scheduleActivation)
        XCTAssertEqual(state.activatePending(), .activate)
        XCTAssertEqual(state.release(), .release)
    }

    func testModifierOnlyHoldUsesSessionEventTap() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/VoiceInputLocal/Services/HotkeyMonitor.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("CGEvent.tapCreate"))
        XCTAssertTrue(source.contains("CGEventType.flagsChanged"))
        XCTAssertTrue(source.contains("keyboardEventKeycode"))
        XCTAssertTrue(source.contains("tapDisabledByTimeout"))
    }

    func testAllPhysicalModifierKeyPositionsCanBeRecorded() {
        let inputs: [(Int, CGEventFlags, DictationKey)] = [
            (55, .maskCommand, .leftCommand),
            (54, .maskCommand, .rightCommand),
            (58, .maskAlternate, .leftOption),
            (61, .maskAlternate, .rightOption),
            (59, .maskControl, .leftControl),
            (62, .maskControl, .rightControl),
            (56, .maskShift, .leftShift),
            (60, .maskShift, .rightShift),
            (63, .maskSecondaryFn, .fn),
        ]

        for (keyCode, flags, expected) in inputs {
            let recorded = ModifierKeyRecorder.recordedKey(
                type: .flagsChanged,
                keyCode: keyCode,
                flags: flags
            )
            XCTAssertEqual(recorded?.rawValue, expected.rawValue)
        }
        XCTAssertNil(ModifierKeyRecorder.recordedKey(
            type: .flagsChanged,
            keyCode: 55,
            flags: []
        ))
    }

    func testSettingsRecordsTheActuallyPressedModifierKey() throws {
        let recorder = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/VoiceInputLocal/Services/ModifierKeyRecorder.swift"),
            encoding: .utf8
        )
        let settings = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/VoiceInputLocal/Views/SettingsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(recorder.contains("CGEvent.tapCreate"))
        XCTAssertTrue(recorder.contains("CGEventType.flagsChanged"))
        XCTAssertTrue(recorder.contains("keyboardEventKeycode"))
        XCTAssertTrue(settings.contains("設定するキーを押してください"))
        XCTAssertFalse(settings.contains("Picker(\"長押しキー\""))
    }

    func testCodexResearchUsesTextOnlyReadOnlyAppServerSession() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/VoiceInputLocal/Services/CodexResearchClient.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("codex_voice_research"))
        XCTAssertTrue(source.contains("app-server"))
        XCTAssertTrue(source.contains("approvalPolicy\": \"never"))
        XCTAssertTrue(source.contains("sandboxPolicy\": [\"type\": \"readOnly\""))
        XCTAssertTrue(source.contains("networkAccess\": true"))
        XCTAssertFalse(source.contains("localImage"))
    }

    func testCodexResearchClientSmoke() async throws {
        guard ProcessInfo.processInfo.environment["RUN_CODEX_RESEARCH_SMOKE"] == "1" else {
            throw XCTSkip("Codex CLI integration smoke test is opt-in")
        }
        let answer = try await CodexResearchClient().ask(
            question: "1足す1の答えを数字だけで返してください。",
            onPartialAnswer: { _ in }
        )
        XCTAssertEqual(answer.trimmingCharacters(in: .whitespacesAndNewlines), "2")
    }
}
