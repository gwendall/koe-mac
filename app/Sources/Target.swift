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

        // Whether `text` shows up in the field: its value grew by the text.
        // Nil when the field does not say (many Electron and web views).
        func received(_ text: String) -> Bool? {
            guard let before, let now = Target.value(of: element) else { return nil }
            return now.count >= before.count + text.count / 2 && now.contains(text.prefix(40))
        }
    }

    enum Verdict {
        case field(Field)   // a text field: type here
        case unknown(NSRunningApplication)  // the app does not say: try anyway
        case nowhere(String)  // no field: copy instead, and say why
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
        guard status == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            // The app does not answer (Electron, games): it may still take ⌘V.
            return status == .cannotComplete || status == .apiDisabled || status == .notImplemented ? .unknown(app) : nil
        }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.3)
        let role = string(element, kAXRoleAttribute) ?? ""
        let subrole = string(element, kAXSubroleAttribute) ?? ""
        if subrole == kAXSecureTextFieldSubrole as String { return .nowhere(Words.say("That's a password field")) }
        let textual: Set<String> = [kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String, "AXSearchField", "AXWebArea"]
        if textual.contains(role) || settable(element, kAXValueAttribute) || settable(element, kAXSelectedTextAttribute) {
            return .field(Field(element: element, app: app, before: value(of: element)))
        }
        return .unknown(app)
    }

    nonisolated static func value(of element: AXUIElement) -> String? { string(element, kAXValueAttribute) }

    // The character just before the cursor, when the field says.
    nonisolated static func characterBeforeCursor(in element: AXUIElement) -> Character? {
        guard let text = value(of: element) else { return nil }
        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
              let range, CFGetTypeID(range) == AXValueGetTypeID() else { return nil }
        var cursor = CFRange()
        guard AXValueGetValue(range as! AXValue, .cfRange, &cursor), cursor.location > 0 else { return nil }
        let utf16 = Array(text.utf16)
        guard cursor.location <= utf16.count else { return nil }
        return String(utf16CodeUnits: [utf16[cursor.location - 1]], count: 1).first
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
