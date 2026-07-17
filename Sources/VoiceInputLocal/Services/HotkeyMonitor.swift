import Foundation
import AppKit

/// 設定された修飾キーの押下/解放をグローバル＋ローカルで監視する。
/// グローバル監視にはアクセシビリティ（入力監視）権限が必要。
@MainActor
final class HotkeyMonitor {

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var targetKeyDown = false

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    /// 監視対象の keyCode（既定 63 = Fn）。設定で変更可能。
    var targetKeyCode: UInt16 = 63

    func start() {
        stop()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handle(event)
            return event
        }
        Dbg.log("[hotkey] started keyCode=\(targetKeyCode) accessibilityTrusted=\(AccessibilityPermission.isTrusted())")
    }

    func stop() {
        if let g = globalMonitor { NSEvent.removeMonitor(g) }
        if let l = localMonitor { NSEvent.removeMonitor(l) }
        globalMonitor = nil
        localMonitor = nil
        targetKeyDown = false
    }

    private func handle(_ event: NSEvent) {
        guard event.keyCode == targetKeyCode else { return }
        handleState(event.modifierFlags.contains(modifierFlag(for: targetKeyCode)), source: "event")
    }

    private func handleState(_ isDown: Bool, source: String) {
        if isDown && !targetKeyDown {
            targetKeyDown = true
            Dbg.log("[hotkey] press keyCode=\(targetKeyCode) source=\(source)")
            onPress?()
        } else if !isDown && targetKeyDown {
            targetKeyDown = false
            Dbg.log("[hotkey] release keyCode=\(targetKeyCode) source=\(source)")
            onRelease?()
        }
    }

    /// keyCode に対応する修飾フラグ。
    private func modifierFlag(for keyCode: UInt16) -> NSEvent.ModifierFlags {
        switch keyCode {
        case 58, 61: return .option
        case 54, 55: return .command
        case 59, 62: return .control
        case 56, 60: return .shift
        case 63: return .function
        default: return .option
        }
    }
}
