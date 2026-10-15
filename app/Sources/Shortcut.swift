import AppKit
import Carbon.HIToolbox

// The key that makes Koe listen: fn (the default), one modifier key on its
// own, left and right told apart (right ⌥ is a favorite), or a combination
// such as ⌃⌥Space. Keys are kept by their physical code, so a shortcut means
// the same key on AZERTY and QWERTY; only its label follows the layout.
struct Shortcut: Codable, Equatable {
    enum Kind: String, Codable { case fn, modifier, combo }

    var kind: Kind
    // modifier: the side-specific key; combo: the main key.
    var keyCode: UInt16 = 0
    // combo: ⌘ ⌃ ⌥ ⇧, as NSEvent.ModifierFlags.
    var modifiers: UInt = 0

    static let fn = Shortcut(kind: .fn)
    // What Koe offers when fn is shared: useless on its own on a Mac, and
    // other dictation apps' default too.
    static let rightOption = Shortcut(kind: .modifier, keyCode: 61)

    // A modifier on its own fires on release, so it can only start and stop.
    var forcesToggle: Bool { kind == .modifier }

    static let modifierKeys: [UInt16: (label: String, flag: NSEvent.ModifierFlags)] = [
        55: ("Left ⌘", .command), 54: ("Right ⌘", .command),
        58: ("Left ⌥", .option), 61: ("Right ⌥", .option),
        59: ("Left ⌃", .control), 62: ("Right ⌃", .control),
        56: ("Left ⇧", .shift), 60: ("Right ⇧", .shift),
    ]

    static let relevant: NSEvent.ModifierFlags = [.command, .control, .option, .shift]

    var label: String {
        switch kind {
        case .fn: return "fn"
        case .modifier: return Words.say(Self.modifierKeys[keyCode]?.label ?? "?")
        case .combo:
            let flags = NSEvent.ModifierFlags(rawValue: modifiers)
            var text = ""
            if flags.contains(.control) { text += "⌃" }
            if flags.contains(.option) { text += "⌥" }
            if flags.contains(.shift) { text += "⇧" }
            if flags.contains(.command) { text += "⌘" }
            return text + Self.keyName(keyCode)
        }
    }

    // Why this combination cannot be Koe's, or nil.
    var refusal: String? {
        guard kind == .combo else { return nil }
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        if keyCode == UInt16(kVK_Escape) { return Words.say("Escape stops Koe, it can't start it") }
        let functionKey = Self.functionKeys[keyCode] != nil
        if !functionKey && flags.intersection([.command, .control, .option]).isEmpty {
            return Words.say("Add ⌃, ⌥ or ⌘, so typing doesn't start Koe")
        }
        // ⌘ and one letter or digit belongs to every app's menus.
        if flags == .command && !functionKey && keyCode != UInt16(kVK_Space) {
            return Words.say("⌘ with one key is taken by apps; add ⌃ or ⌥")
        }
        if flags == [.command] && keyCode == UInt16(kVK_Space) { return Words.say("⌘Space opens Spotlight") }
        return nil
    }

    private static let functionKeys: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]
    private static let named: [UInt16: String] = [
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
    ]

    // The key's name on the current keyboard layout.
    static func keyName(_ code: UInt16) -> String {
        if let name = functionKeys[code] ?? named[code] { return Words.say(name) }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "#\(code)" }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var dead: UInt32 = 0, length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { raw -> OSStatus in
            let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            return UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "#\(code)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }

    // Saved in the defaults; fn when nothing valid is there.
    static var saved: Shortcut {
        get {
            guard let data = UserDefaults.standard.data(forKey: "shortcut"),
                  let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data),
                  shortcut.refusal == nil else { return .fn }
            return shortcut
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "shortcut") }
    }

    // Other apps that may start on fn along with Koe: those that tap the
    // modifier keys as they go down (read from the system's own list of
    // keyboard taps, whoever made them; macOS's own are left out, by where
    // they live), and dictation apps known to use fn, open now. Said, and
    // asked about once, never decided for you.
    static var rivals: [String] {
        var names: [String] = []
        func add(_ app: NSRunningApplication) {
            guard app.processIdentifier != getpid(), !isApple(app), let name = app.localizedName, !names.contains(name) else { return }
            names.append(name)
        }
        var count: UInt32 = 0
        if CGGetEventTapList(0, nil, &count) == .success, count > 0 {
            var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
            if CGGetEventTapList(count, &taps, &count) == .success {
                let modifiers = UInt64(1) << CGEventType.flagsChanged.rawValue
                for tap in taps.prefix(Int(count)) where tap.enabled && tap.eventsOfInterest & modifiers != 0 {
                    if let app = NSRunningApplication(processIdentifier: pid_t(tap.tappingProcess)) { add(app) }
                }
            }
        }
        let known = ["Wispr Flow", "Superwhisper", "Aqua Voice", "Willow", "Monologue", "Spokenly", "VoiceInk", "OpenWhispr", "FluidVoice", "Hex"]
        for app in NSWorkspace.shared.runningApplications
        where known.contains(where: { app.localizedName?.localizedCaseInsensitiveCompare($0) == .orderedSame }) { add(app) }
        return names
    }

    // Apple's own apps and helpers: signed into the system's folders, or Apple's bundle IDs.
    private static func isApple(_ app: NSRunningApplication) -> Bool {
        if app.bundleIdentifier?.hasPrefix("com.apple.") == true { return true }
        let path = app.executableURL?.path ?? app.bundleURL?.path ?? ""
        return ["/System/", "/usr/", "/Library/Apple/"].contains { path.hasPrefix($0) }
    }

    // The apps you said may share fn with Koe ("Keep fn").
    static var sharing: [String] {
        get { UserDefaults.standard.stringArray(forKey: "fnSharedWith") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "fnSharedWith") }
    }

    // What macOS does with 🌐 itself (Keyboard settings, "Press 🌐 key to"),
    // which Koe holds back while fn is its shortcut.
    static var globeUse: String? {
        let value = UserDefaults(suiteName: "com.apple.HIToolbox")?.object(forKey: "AppleFnUsageType") as? Int
        switch value {
        case 1: return Words.say("change the input source")
        case 2: return Words.say("show the emoji picker")
        case 3: return Words.say("start Apple's dictation")
        default: return nil
        }
    }
}
