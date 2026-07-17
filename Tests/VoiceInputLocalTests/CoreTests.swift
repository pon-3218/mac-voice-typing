import XCTest
@testable import VoiceInputLocal

final class CoreTests: XCTestCase {
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
}
