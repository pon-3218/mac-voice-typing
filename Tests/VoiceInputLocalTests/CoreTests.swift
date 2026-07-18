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
}
