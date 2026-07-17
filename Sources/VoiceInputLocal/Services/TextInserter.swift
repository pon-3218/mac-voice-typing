import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

/// 認識テキストをクリップボードへ保存し、ホールド開始時にフォーカスしていた入力欄へ挿入する。
enum TextInserter {

    /// 認識中にフォーカスが変わっても入力先を失わないよう、ホールド開始時の要素を保持する。
    final class FocusedTarget {
        fileprivate let element: AXUIElement
        fileprivate let processID: pid_t

        fileprivate init(element: AXUIElement, processID: pid_t) {
            self.element = element
            self.processID = processID
        }
    }

    enum DeliveryResult: Equatable {
        case directTyping
        case accessibility
        case commandPaste
        case clipboardOnly
        case empty
    }

    /// ホールド開始時点の入力先を取得する。VoiceInputLocal のHUDは非アクティブなので、元の入力欄を保持できる。
    static func captureFocusedTarget() -> FocusedTarget? {
        guard AccessibilityPermission.isTrusted() else { return nil }
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue else { return nil }

        let element = unsafeBitCast(focusedValue, to: AXUIElement.self)
        var processID: pid_t = 0
        guard AXUIElementGetPid(element, &processID) == .success, processID > 0 else { return nil }
        return FocusedTarget(element: element, processID: processID)
    }

    @discardableResult
    static func deliver(_ text: String, to capturedTarget: FocusedTarget? = nil) -> DeliveryResult {
        let target = capturedTarget ?? captureFocusedTarget()
        let result = deliver(
            text,
            copy: copyToClipboard,
            typeIntoFocusedField: { text in
                guard let target else { return false }
                return typeUsingUnicodeEvents(text, into: target)
            },
            insertIntoFocusedField: { text in
                guard let target else { return false }
                return insertUsingAccessibility(text, into: target)
            },
            pasteFromClipboard: {
                pasteUsingCommandV(into: target)
            }
        )
        Dbg.log("[dictation][insert] result=\(String(describing: result)) accessibilityTrusted=\(AccessibilityPermission.isTrusted()) targetPid=\(target?.processID ?? 0)")
        return result
    }

    /// 副作用を注入できる配信境界。入力経路のフォールバック順をユニットテストするために分離する。
    @discardableResult
    static func deliver(
        _ text: String,
        copy: (String) -> Void,
        typeIntoFocusedField: (String) -> Bool,
        insertIntoFocusedField: (String) -> Bool,
        pasteFromClipboard: () -> Bool
    ) -> DeliveryResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        copy(trimmed)
        if typeIntoFocusedField(trimmed) { return .directTyping }
        if insertIntoFocusedField(trimmed) { return .accessibility }
        if pasteFromClipboard() { return .commandPaste }
        return .clipboardOnly
    }

    static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// 対象アプリと入力欄へフォーカスを戻してから、通常のキーボード入力としてUnicode文字を送る。
    /// Web/Electronの入力欄でも入力イベントが発火するため、AXValueの直接書き換えより安全に扱える。
    private static func typeUsingUnicodeEvents(_ text: String, into target: FocusedTarget) -> Bool {
        guard focus(target) else { return false }

        for character in text {
            var units = Array(String(character).utf16)
            guard !units.isEmpty,
                  let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            else { return false }

            units.withUnsafeMutableBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
                up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
            }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
        return true
    }

    /// 標準入力欄では、保持した要素の現在選択範囲へ直接挿入する。
    private static func insertUsingAccessibility(_ text: String, into target: FocusedTarget) -> Bool {
        guard focus(target) else { return false }
        return AXUIElementSetAttributeValue(
            target.element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        ) == .success
    }

    /// 対象アプリを前面に戻し、保持した入力欄へフォーカスを設定する。
    private static func focus(_ target: FocusedTarget) -> Bool {
        guard AccessibilityPermission.isTrusted(),
              NSRunningApplication(processIdentifier: target.processID) != nil else { return false }

        let application = AXUIElementCreateApplication(target.processID)
        _ = AXUIElementSetAttributeValue(
            application,
            kAXFrontmostAttribute as CFString,
            kCFBooleanTrue
        )
        let result = AXUIElementSetAttributeValue(
            target.element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        let focused = result == .success || isCurrentlyFocused(target.element)
        if focused {
            // AXの前面化・フォーカス変更がイベント配送へ反映されるまでの最小限の待機。
            Thread.sleep(forTimeInterval: 0.03)
        }
        return focused
    }

    private static func isCurrentlyFocused(_ element: AXUIElement) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue else { return false }
        return CFEqual(focusedValue, element)
    }

    /// Unicode入力もAX挿入も使えない入力欄向けの最終フォールバック。
    private static func pasteUsingCommandV(into target: FocusedTarget?) -> Bool {
        if let target, !focus(target) { return false }
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}

/// アクセシビリティ権限の確認・要求。
enum AccessibilityPermission {
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// プロンプトを出して要求する（システム設定への誘導つき）。
    @discardableResult
    static func requestPrompt() -> Bool {
        // kAXTrustedCheckOptionPrompt の文字列値。プロンプト＋システム設定への誘導を出す。
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
