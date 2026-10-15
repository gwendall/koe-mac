import AppKit
import ApplicationServices
import Carbon.HIToolbox

// Where the words go. Koe remembers the app you were in when you started
// talking; when you stop, it types into the field focused at that moment if
// it takes text (you may have clicked another field, even in another app),
// else back in the app you started from. Never into a password field, never
// while macOS has secure keyboard entry on. Every Accessibility call is
// bounded: Electron apps can take seconds to answer.
@MainActor
enum Target {
    // The app frontmost when a dictation starts, Koe itself excepted.
    struct Origin {
        let app: NSRunningApplication?
    }

    static func origin() -> Origin {
        let front = NSWorkspace.shared.frontmostApplication
        return Origin(app: front?.processIdentifier == getpid() ? nil : front)
    }

    // A field, and what it held just before the paste.
    struct Field {
        let element: AXUIElement
        let app: NSRunningApplication
        let before: String?

        // Whether `text` shows up in the field. Nil when the field does not
        // say (many Electron and web views).
        func received(_ text: String) -> Bool? {
            guard let before, let now = Target.value(of: element) else { return nil }
            return Target.arrived(text, before: before, now: now)
        }

        // Whether the field still reads as it did before the paste.
        var unchanged: Bool? {
            guard let before, let now = Target.value(of: element) else { return nil }
            return now == before
        }
    }

    enum Verdict {
        case field(Field)   // a text field: type here
        case unknown(NSRunningApplication)  // the app does not say: try anyway
        case nowhere(String)  // no field: copy instead, and say why

        var app: NSRunningApplication? {
            switch self {
            case .field(let field): return field.app
            case .unknown(let app): return app
            case .nowhere: return nil
            }
        }
    }

    // Where to type, now. `origin` is where the dictation started.
    static func resolve(from origin: Origin) -> Verdict {
        if IsSecureEventInputEnabled() { return .nowhere(Words.say("Secure typing is on")) }
        // The field focused now, in whatever app is in front.
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() {
            switch inspect(front) {
            case .some(let verdict): return verdict
            case .none: break
            }
        }
        // Else back to the app the dictation started in.
        guard let app = origin.app, !app.isTerminated else { return .nowhere(Words.say("No text field in front")) }
        app.activate()
        RunLoop.current.run(until: Date().addingTimeInterval(0.12))
        // The app answered: nothing focused. A blind ⌘V would lose the words.
        return inspect(app) ?? .nowhere(Words.say("No text field in front"))
    }

    // What the app's focused element is: a field, a field that cannot take
    // the words, or (nil) nothing focused at all.
    private static func inspect(_ app: NSRunningApplication) -> Verdict? {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.3)
        var focused: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &focused)
        #if KOE_EVAL
        Log.note("target", ["app": app.bundleIdentifier ?? "?", "status": status.rawValue])
        #endif
        guard status == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            // The app does not answer (games, a busy app), or is built on
            // Chromium (VS Code, Slack, Discord, Notion…), which keeps quiet
            // about its fields until a screen reader asks: it may still take ⌘V.
            let silent: Set<AXError> = [.cannotComplete, .apiDisabled, .notImplemented]
            return silent.contains(status) || (status == .noValue && webShell(app)) ? .unknown(app) : nil
        }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.3)
        let role = string(element, kAXRoleAttribute) ?? ""
        let subrole = string(element, kAXSubroleAttribute) ?? ""
        #if KOE_EVAL
        Log.note("target", ["role": role, "subrole": subrole, "value": value(of: element) != nil,
                            "settable": settable(element, kAXValueAttribute) || settable(element, kAXSelectedTextAttribute)])
        #endif
        if subrole == kAXSecureTextFieldSubrole as String { return .nowhere(Words.say("That's a password field")) }
        // Chromium shells show a screen reader a window of the text, not all
        // of it: what it says about the field can't prove or disprove a paste.
        if webShell(app) { return .unknown(app) }
        let textual: Set<String> = [kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String, "AXSearchField", "AXWebArea"]
        if textual.contains(role) || settable(element, kAXValueAttribute) || settable(element, kAXSelectedTextAttribute) {
            return .field(Field(element: element, app: app, before: value(of: element)))
        }
        // A file list, a button, a picture: ⌘V there loses the words. A table
        // or a cell may still take them (a spreadsheet), and so may anything odd.
        let inert: Set<String> = ["AXOutline", "AXList", "AXBrowser", "AXRow", "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton",
                                  "AXMenuButton", "AXSlider", "AXImage", "AXMenuItem", "AXMenuBarItem", "AXTabGroup", "AXToolbar",
                                  "AXWindow", "AXApplication", "AXScrollBar", "AXDisclosureTriangle"]
        // The Finder takes text only in its fields; ⌘V on the desktop pastes nothing.
        let finder = app.bundleIdentifier == "com.apple.finder"
        return inert.contains(role) || finder ? .nowhere(Words.say("No text field in front")) : .unknown(app)
    }

    // The words' start shows up once more than it did: pasted over a
    // selection, the field may even get shorter. Quotes and spaces compared
    // loosely, as an app may curl or tighten them as they land.
    nonisolated static func arrived(_ text: String, before: String, now: String) -> Bool {
        func loose(_ text: some StringProtocol) -> String {
            String(text.map { character -> Character in
                switch character {
                case "’", "‘": return "'"
                case "“", "”", "«", "»": return "\""
                case "\u{a0}", "\u{202f}", "\n", "\t": return " "
                default: return character
                }
            })
        }
        let probe = loose(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !probe.isEmpty else { return false }
        let before = loose(before), now = loose(now)
        return now.components(separatedBy: probe).count > before.components(separatedBy: probe).count
    }

    // An app drawn by an embedded Chromium: Electron, or the Chromium Embedded Framework.
    private static func webShell(_ app: NSRunningApplication) -> Bool {
        guard let frameworks = app.bundleURL?.appendingPathComponent("Contents/Frameworks").path,
              let names = try? FileManager.default.contentsOfDirectory(atPath: frameworks) else { return false }
        return names.contains { $0.hasPrefix("Electron Framework") || $0.hasPrefix("Chromium Embedded Framework") }
    }

    nonisolated static func value(of element: AXUIElement) -> String? { string(element, kAXValueAttribute) }

    // The few characters just before the cursor (`count` UTF-16 units at
    // most), when the field says; "" at its very start.
    nonisolated static func textBeforeCursor(in element: AXUIElement, count: Int = 40) -> String? {
        guard let text = value(of: element) else { return nil }
        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
              let range, CFGetTypeID(range) == AXValueGetTypeID() else { return nil }
        var cursor = CFRange()
        guard AXValueGetValue(range as! AXValue, .cfRange, &cursor), cursor.location >= 0 else { return nil }
        let utf16 = Array(text.utf16)
        guard cursor.location <= utf16.count else { return nil }
        return String(decoding: utf16[max(0, cursor.location - count)..<cursor.location], as: UTF16.self)
    }

    nonisolated private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func settable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success && settable.boolValue
    }
}
