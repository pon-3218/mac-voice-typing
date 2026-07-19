import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
final class ModifierKeyRecorder {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onRecorded: ((DictationKey) -> Void)?
    private var onCancelled: (() -> Void)?

    func start(
        onRecorded: @escaping (DictationKey) -> Void,
        onCancelled: @escaping () -> Void
    ) -> Bool {
        stop()
        self.onRecorded = onRecorded
        self.onCancelled = onCancelled

        let mask = (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: Self.eventCallback,
            userInfo: context
        ) else {
            self.onRecorded = nil
            self.onCancelled = nil
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        return true
    }

    func cancel() {
        let callback = onCancelled
        stop()
        callback?()
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
        onRecorded = nil
        onCancelled = nil
    }

    private func handle(type: CGEventType, keyCode: Int, flags: CGEventFlags) {
        if type == .keyDown, keyCode == 53 {
            cancel()
            return
        }
        guard let key = Self.recordedKey(type: type, keyCode: keyCode, flags: flags) else { return }
        let callback = onRecorded
        stop()
        callback?(key)
    }

    nonisolated static func recordedKey(
        type: CGEventType,
        keyCode: Int,
        flags: CGEventFlags
    ) -> DictationKey? {
        guard type == .flagsChanged,
              let key = DictationKey(rawValue: keyCode),
              key.isPressed(in: flags) else { return nil }
        return key
    }

    private static let eventCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let recorder = Unmanaged<ModifierKeyRecorder>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async {
                if let tap = recorder.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        DispatchQueue.main.async {
            recorder.handle(type: type, keyCode: keyCode, flags: flags)
        }
        return Unmanaged.passUnretained(event)
    }
}
