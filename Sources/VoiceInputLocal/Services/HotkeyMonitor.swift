import Foundation
import ApplicationServices
import CoreGraphics

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

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
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
        let mask = (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: Self.eventCallback,
            userInfo: context
        ) else {
            Dbg.log("[hotkey] event tap creation failed keyCode=\(targetKeyCode) accessibilityTrusted=\(AccessibilityPermission.isTrusted())")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        Dbg.log("[hotkey] event tap started keyCode=\(targetKeyCode) accessibilityTrusted=\(AccessibilityPermission.isTrusted())")
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
        activationTask?.cancel()
        activationTask = nil
        activationState.reset()
    }

    private func handle(type: CGEventType, keyCode: UInt16, flags: CGEventFlags) {
        if type == .keyDown {
            guard cancelsDelayedActivationOnOtherKey else { return }
            perform(activationState.otherKeyPressed())
            return
        }
        guard type == .flagsChanged, keyCode == targetKeyCode else { return }
        let isDown = flags.contains(modifierFlag(for: targetKeyCode))
        Dbg.log("[hotkey] flagsChanged keyCode=\(keyCode) isDown=\(isDown)")
        perform(isDown
            ? activationState.press(requiresDelay: activationDelay > 0)
            : activationState.release())
    }

    private func perform(_ action: HoldActivationState.Action) {
        switch action {
        case .none:
            break
        case .scheduleActivation:
            Dbg.log("[hotkey] activation scheduled keyCode=\(targetKeyCode) delay=\(activationDelay)")
            activationTask?.cancel()
            let delay = activationDelay
            activationTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.perform(self.activationState.activatePending())
            }
        case .cancelPending:
            Dbg.log("[hotkey] pending activation cancelled keyCode=\(targetKeyCode)")
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
    private func modifierFlag(for keyCode: UInt16) -> CGEventFlags {
        switch keyCode {
        case 58, 61: return .maskAlternate
        case 54, 55: return .maskCommand
        case 59, 62: return .maskControl
        case 56, 60: return .maskShift
        case 63: return .maskSecondaryFn
        default: return .maskAlternate
        }
    }

    private static let eventCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async {
                if let tap = monitor.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        DispatchQueue.main.async {
            monitor.handle(type: type, keyCode: keyCode, flags: flags)
        }
        return Unmanaged.passUnretained(event)
    }
}
