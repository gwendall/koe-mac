import AppKit
import CoreGraphics

// Watches the keyboard for Koe's shortcut, anywhere (docs: Shortcut.swift).
//
// - fn: its presses are kept from macOS (the emoji picker, the input source,
//   Apple's dictation), on both of its key codes (63, and 179 on Apple silicon
//   keyboards) and the system event macOS uses as a second path while fn is
//   held. A key pressed with fn makes it a shortcut of its own, not Koe's.
// - A modifier alone fires once, on release, and only if nothing else (a
//   key, a click, a scroll, another modifier) happened while it was down:
//   ⌘C must never start Koe.
// - A combination fires on its key, auto-repeat ignored, and is kept from
//   the app in front.
// - Escape cancels while Koe listens or types, and only then is kept from
//   the app in front.
// Needs Accessibility. macOS switches the tap off when it is slow or when
// Accessibility is revoked: it is switched back on, or rebuilt. Only the
// keyboard goes through a tap that can hold events back; clicks and scrolls
// are only watched (a listen-only tap), so a Koe in trouble can never take
// the mouse away. And Koe lets go of the keyboard the moment it loses
// Accessibility (Koe.swift, `guardTrust`).
@MainActor
final class Hotkey {
    var shortcut = Shortcut.saved { didSet { reset() } }
    var onDown: (() -> Void)?
    var onUp: (() -> Void)?
    var onChord: (() -> Void)?
    // Set while Koe listens or types: Escape is Koe's then.
    var escapeActive = false
    var onEscape: (() -> Void)?
    // Recording a new shortcut: everything goes there, nothing fires.
    var onCapture: ((Shortcut?) -> Void)?
    var isCapturing: Bool { onCapture != nil }
    // Keys and clicks seen so far, Koe's own shortcut aside: while it stands
    // still, the cursor has not moved since Koe last typed.
    private(set) var touches = 0

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var watch: CFMachPort?
    private var watchSource: CFRunLoopSource?
    // fn and combination state, and a modifier tap still clean.
    fileprivate var fnDown = false
    private var comboDown = false
    private var modifierDown = false
    private var modifierClean = false
    // While capturing: the modifier pressed alone so far, fn pressed alone.
    private var capturedModifier: UInt16?
    private var capturedFn = false
    private var capturedCombo: Shortcut?

    static let systemDefined = CGEventType(rawValue: 14)!

    var isRunning: Bool { tap.map { CFMachPortIsValid($0) } ?? false }

    // False until macOS lets Koe watch the keyboard (Accessibility).
    @discardableResult
    func start() -> Bool {
        if let tap, CFMachPortIsValid(tap) { return true }
        stop()
        func mask(_ types: [CGEventType]) -> CGEventMask { types.reduce(0) { $0 | 1 << CGEventMask($1.rawValue) } }
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask([.flagsChanged, .keyDown, .keyUp, Self.systemDefined]),
                                          callback: hotkeyEvent, userInfo: me) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        if let watch = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                         eventsOfInterest: mask([.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]),
                                         callback: hotkeyEvent, userInfo: me) {
            let watchSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, watch, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), watchSource, .commonModes)
            CGEvent.tapEnable(tap: watch, enable: true)
            self.watch = watch
            self.watchSource = watchSource
        }
        reset()
        return true
    }

    func stop() {
        for port in [tap, watch].compactMap({ $0 }) { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
        for loop in [source, watchSource].compactMap({ $0 }) { CFRunLoopRemoveSource(CFRunLoopGetMain(), loop, .commonModes) }
        tap = nil
        source = nil
        watch = nil
        watchSource = nil
    }

    // Starts listening for a new shortcut; `done` gets it, or nil if cancelled.
    func capture(_ done: @escaping (Shortcut?) -> Void) {
        capturedModifier = nil
        capturedFn = false
        capturedCombo = nil
        onCapture = done
    }

    func cancelCapture() {
        let done = onCapture
        onCapture = nil
        done?(nil)
    }

    fileprivate func reenable() {
        for port in [tap, watch].compactMap({ $0 }) { CGEvent.tapEnable(tap: port, enable: true) }
        reset()
    }

    // Back to what the keyboard holds now.
    private func reset() {
        fnDown = CGEventSource.flagsState(.combinedSessionState).contains(.maskSecondaryFn)
        comboDown = false
        modifierDown = false
        modifierClean = false
    }

    // Whether the event goes on to the rest of the Mac.
    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let passes = route(type, event)
        if passes, [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type) { touches += 1 }
        return passes
    }

    private func route(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if isCapturing { return captureEvent(type, event, code) }

        if type == .keyDown, code == 53, escapeActive {
            onEscape?()
            return false
        }

        switch shortcut.kind {
        case .fn: return fnEvent(type, event, code)
        case .modifier: return modifierEvent(type, event, code)
        case .combo: return comboEvent(type, event, code)
        }
    }

    private func fnEvent(_ type: CGEventType, _ event: CGEvent, _ code: UInt16) -> Bool {
        let fnKey = code == 63 || code == 179
        switch type {
        case .flagsChanged:
            let down = event.flags.contains(.maskSecondaryFn)
            // Arrows and F-keys raise the fn flag too, as part of their own press.
            guard fnKey else { return true }
            if down != fnDown {
                fnDown = down
                if down { onDown?() } else { onUp?() }
            }
            return false
        case .keyDown, .keyUp:
            if fnKey { return false }
            if type == .keyDown, fnDown { onChord?() }
            return true
        case Self.systemDefined:
            return !fnDown
        default:
            return true
        }
    }

    private func modifierEvent(_ type: CGEventType, _ event: CGEvent, _ code: UInt16) -> Bool {
        guard let mine = Shortcut.modifierKeys[shortcut.keyCode] else { return true }
        switch type {
        case .flagsChanged:
            let held = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)).intersection(Shortcut.relevant)
            if code == shortcut.keyCode {
                let down = held.contains(mine.flag) && !modifierDown
                if down {
                    modifierDown = true
                    // Clean only if this modifier is the only one held.
                    modifierClean = held == mine.flag && !event.flags.contains(.maskSecondaryFn)
                } else if modifierDown {
                    modifierDown = false
                    if modifierClean && held.isEmpty { onDown?(); onUp?() }
                    modifierClean = false
                }
            } else if modifierDown {
                modifierClean = false
            }
        case .keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, Self.systemDefined:
            if modifierDown { modifierClean = false }
        default:
            break
        }
        return true
    }

    private func comboEvent(_ type: CGEventType, _ event: CGEvent, _ code: UInt16) -> Bool {
        guard code == shortcut.keyCode else { return true }
        switch type {
        case .keyDown:
            let held = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)).intersection(Shortcut.relevant)
            guard held == NSEvent.ModifierFlags(rawValue: shortcut.modifiers) else { return true }
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0, !comboDown {
                comboDown = true
                onDown?()
            }
            return false
        case .keyUp:
            guard comboDown else { return true }
            comboDown = false
            onUp?()
            return false
        default:
            return true
        }
    }

    // Recording a shortcut: committed when the keys are released, as the
    // whole chord that was down; Escape alone cancels.
    private func captureEvent(_ type: CGEventType, _ event: CGEvent, _ code: UInt16) -> Bool {
        let held = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)).intersection(Shortcut.relevant)
        switch type {
        case .keyDown:
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return false }
            if code == 63 || code == 179 { return false }
            if code == 53 && held.isEmpty {
                cancelCapture()
                return false
            }
            capturedModifier = nil
            capturedFn = false
            capturedCombo = Shortcut(kind: .combo, keyCode: code, modifiers: held.rawValue)
            return false
        case .keyUp:
            if let combo = capturedCombo { finishCapture(combo) }
            return false
        case .flagsChanged:
            if code == 63 || code == 179 {
                if event.flags.contains(.maskSecondaryFn) {
                    capturedFn = capturedCombo == nil && held.isEmpty
                } else if capturedFn {
                    finishCapture(.fn)
                }
                return false
            }
            if Shortcut.modifierKeys[code] != nil, capturedCombo == nil {
                if !held.isEmpty {
                    // Only a single modifier pressed alone counts.
                    capturedModifier = held == Shortcut.modifierKeys[code]?.flag && capturedModifier == nil ? code : nil
                } else if let modifier = capturedModifier, modifier == code {
                    finishCapture(Shortcut(kind: .modifier, keyCode: code))
                } else {
                    capturedModifier = nil
                }
            }
            return true
        case Self.systemDefined:
            return !event.flags.contains(.maskSecondaryFn)
        default:
            return true
        }
    }

    private func finishCapture(_ shortcut: Shortcut) {
        let done = onCapture
        onCapture = nil
        capturedCombo = nil
        capturedModifier = nil
        capturedFn = false
        reset()
        done?(shortcut)
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
