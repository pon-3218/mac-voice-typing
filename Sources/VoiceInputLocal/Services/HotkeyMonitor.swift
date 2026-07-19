import Foundation
import AppKit

struct HoldActivationState {
    enum Action: Equatable {
        case none
        case scheduleActivation
        case cancelPending
        case activate
        case release
    }

    private var isPressed = false
    private var activationPending = false
    private var isActive = false

    mutating func press(requiresDelay: Bool) -> Action {
        guard !isPressed else { return .none }
        isPressed = true
        if requiresDelay {
            activationPending = true
            return .scheduleActivation
        }
        isActive = true
        return .activate
    }

    mutating func activatePending() -> Action {
        guard isPressed, activationPending else { return .none }
        activationPending = false
        isActive = true
        return .activate
    }

    mutating func otherKeyPressed() -> Action {
        guard activationPending else { return .none }
        activationPending = false
        return .cancelPending
    }

    mutating func release() -> Action {
        guard isPressed else { return .none }
        isPressed = false
        if activationPending {
            activationPending = false
            return .cancelPending
        }
        if isActive {
            isActive = false
            return .release
        }
        return .none
    }

    mutating func reset() {
        isPressed = false
        activationPending = false
        isActive = false
    }
}

/// 設定された修飾キーの押下/解放をグローバル＋ローカルで監視する。
/// グローバル監視にはアクセシビリティ（入力監視）権限が必要。
@MainActor
final class HotkeyMonitor {

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var activationState = HoldActivationState()
    private var activationTask: Task<Void, Never>?

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    /// 監視対象の keyCode（既定 63 = Fn）。設定で変更可能。
    var targetKeyCode: UInt16 = 63
    var activationDelay: TimeInterval = 0
    var cancelsDelayedActivationOnOtherKey = false

    func start() {
        stop()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
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
        activationTask?.cancel()
        activationTask = nil
        activationState.reset()
    }

    private func handle(_ event: NSEvent) {
        if event.type == .keyDown {
            guard cancelsDelayedActivationOnOtherKey else { return }
            perform(activationState.otherKeyPressed())
            return
        }
        guard event.keyCode == targetKeyCode else { return }
        let isDown = event.modifierFlags.contains(modifierFlag(for: targetKeyCode))
        perform(isDown
            ? activationState.press(requiresDelay: activationDelay > 0)
            : activationState.release())
    }

    private func perform(_ action: HoldActivationState.Action) {
        switch action {
        case .none:
            break
        case .scheduleActivation:
            activationTask?.cancel()
            let delay = activationDelay
            activationTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.perform(self.activationState.activatePending())
            }
        case .cancelPending:
            activationTask?.cancel()
            activationTask = nil
        case .activate:
            activationTask = nil
            Dbg.log("[hotkey] press keyCode=\(targetKeyCode)")
            onPress?()
        case .release:
            Dbg.log("[hotkey] release keyCode=\(targetKeyCode)")
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
