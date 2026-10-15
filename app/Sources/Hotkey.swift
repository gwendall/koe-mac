import AppKit
import CoreGraphics

// Watches the fn (Globe) key, anywhere. A key pressed while fn is down makes
// it a shortcut of its own (fn + an arrow, fn + F1…), so Koe lets go. While Koe
// owns fn, its own presses are kept from macOS, which would otherwise open the
// emoji picker or start its own dictation. Needs Accessibility.
@MainActor
final class Hotkey {
    var onDown: (() -> Void)?
    var onUp: (() -> Void)?
    var onChord: (() -> Void)?

    private var tap: CFMachPort?
    fileprivate var fnDown = false

    var isRunning: Bool { tap != nil }

    // False until macOS lets Koe watch the keyboard (Accessibility).
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask), callback: hotkeyEvent,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        fnDown = false
    }

    // Whether the event goes on to the rest of the Mac.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .keyDown where fnDown:
            onChord?()
            return true
        case .flagsChanged:
            let down = event.flags.contains(.maskSecondaryFn)
            // fn's own key is 63 (kVK_Function); arrows and F-keys raise the
            // flag too, as part of their own key press.
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            guard keycode == 63, down != fnDown else { return true }
            fnDown = down
            if down { onDown?() } else { onUp?() }
            return false
        default:
            return true
        }
    }
}

private func hotkeyEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let hotkey = Unmanaged<Hotkey>.fromOpaque(refcon).takeUnretainedValue()
    // The tap's source runs on the main run loop.
    return MainActor.assumeIsolated {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            hotkey.reenable()
            return Unmanaged.passUnretained(event)
        }
        return hotkey.handle(type, event) ? Unmanaged.passUnretained(event) : nil
    }
}
