import AppKit
import Carbon.HIToolbox
import CoreGraphics

// Thousands of random inputs, from a fixed seed so a failure comes back the
// same way, through the parts that see the outside world: the keyboard, the
// model's text, the microphone's samples, the field Koe types into. Each run
// checks what must hold whatever comes in, not one expected answer.
extension SelfTest {
    struct Dice {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func int(_ range: ClosedRange<Int>) -> Int { range.lowerBound + Int(next() % UInt64(range.count)) }
        mutating func chance(_ odds: Double) -> Bool { Double(next() % 10_000) / 10_000 < odds }
        mutating func pick<T>(_ items: [T]) -> T { items[int(0...items.count - 1)] }
        mutating func float() -> Float { Float(next() % 2_000_001) / 1_000_000 - 1 }
    }

    static func fuzz() {
        var dice = Dice(state: 0x4B4F_45)
        fuzzHotkey(&dice)
        fuzzCapture(&dice)
        fuzzWords(&dice)
        fuzzAudio(&dice)
        fuzzTyping(&dice)
        layouts()
    }

    // MARK: - The keyboard

    private static let flagChoices: [CGEventFlags] = [.maskSecondaryFn, .maskAlternate, .maskCommand, .maskShift, .maskControl]

    private static func randomEvent(_ dice: inout Dice) -> (CGEventType, CGEvent) {
        var flags: CGEventFlags = []
        for flag in flagChoices where dice.chance(0.3) { flags.insert(flag) }
        let event: CGEvent
        let type: CGEventType
        switch dice.int(0...9) {
        case 0...3:
            type = .flagsChanged
            event = CGEvent(keyboardEventSource: nil, virtualKey: dice.pick([63, 179, 61, 58, 54, 55, 56, 59, 123, 96]), keyDown: true)!
        case 4...5:
            type = .keyDown
            event = CGEvent(keyboardEventSource: nil, virtualKey: dice.pick([49, 8, 53, 51, 96, 0, 63]), keyDown: true)!
            if dice.chance(0.2) { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        case 6...7:
            type = .keyUp
            event = CGEvent(keyboardEventSource: nil, virtualKey: dice.pick([49, 8, 53, 51, 96, 0, 63]), keyDown: false)!
        case 8:
            type = dice.pick([.scrollWheel, .leftMouseDown, .rightMouseDown])
            event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        default:
            type = Hotkey.systemDefined
            event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        }
        event.type = type
        event.flags = flags
        return (type, event)
    }

    // What the shortcut fires is always down, (chord), up, down, up…: never
    // two downs, never an up from nowhere, never stuck down once every key is
    // up. Keys that aren't Koe's always reach the app.
    private static func fuzzHotkey(_ dice: inout Dice) {
        let control = NSEvent.ModifierFlags.control.rawValue, option = NSEvent.ModifierFlags.option.rawValue
        let shortcuts: [Shortcut] = [.fn, Shortcut(kind: .modifier, keyCode: 61), Shortcut(kind: .modifier, keyCode: 54),
                                     Shortcut(kind: .combo, keyCode: 49, modifiers: control | option), Shortcut(kind: .combo, keyCode: 96)]
        for shortcut in shortcuts {
            var broken: [String] = []
            for run in 0..<1_500 {
                let hotkey = Hotkey()
                hotkey.shortcut = shortcut
                var log: [String] = []
                hotkey.onDown = { log.append("down") }
                hotkey.onUp = { log.append("up") }
                hotkey.onChord = { log.append("chord") }
                hotkey.onEscape = { log.append("escape") }
                hotkey.escapeActive = dice.chance(0.3)
                var leaked: String?
                for _ in 0..<dice.int(1...40) {
                    let (type, event) = randomEvent(&dice)
                    let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                    let taken = hotkey.escapeTaken
                    let passed = hotkey.handle(type, event)
                    // A plain key that is neither the shortcut, fn nor Escape must reach the app.
                    let mine = code == shortcut.keyCode || code == 63 || code == 179 || code == 53
                    if (type == .keyDown || type == .keyUp), !mine, !passed { leaked = "key \(code) kept from the app" }
                    if type == .keyDown, code == 53, !hotkey.escapeActive, !taken, !passed { leaked = "Escape kept while idle" }
                }
                // Every key up.
                switch shortcut.kind {
                case .fn: _ = hotkey.handle(.flagsChanged, event(.flagsChanged, 63))
                case .modifier: _ = hotkey.handle(.flagsChanged, event(.flagsChanged, shortcut.keyCode))
                case .combo: _ = hotkey.handle(.keyUp, event(.keyUp, shortcut.keyCode))
                }
                var down = false, valid = true
                for entry in log where entry != "escape" {
                    switch entry {
                    case "down": if down { valid = false }; down = true
                    case "up": if !down { valid = false }; down = false
                    default: if !down { valid = false } // a chord only while down
                    }
                }
                if !valid || down { broken.append("run \(run): \(log)") }
                if shortcut.kind == .modifier, log.filter({ $0 != "escape" }) != Array(repeating: ["down", "up"], count: log.filter { $0 == "down" }.count).flatMap({ $0 }) {
                    broken.append("run \(run): a modifier fires down and up together, got \(log)")
                }
                if let leaked { broken.append("run \(run): \(leaked)") }
            }
            check(broken.isEmpty, "fuzz: \(shortcut.label), 1500 random key sequences \(broken.prefix(3))")
        }
    }

    // Recording a shortcut through random keys: ends cleanly, never with
    // something it can't use as fn, a modifier or a combination.
    private static func fuzzCapture(_ dice: inout Dice) {
        var broken: [String] = []
        for run in 0..<1_000 {
            let hotkey = Hotkey()
            var results: [Shortcut?] = []
            hotkey.capture { results.append($0) }
            for _ in 0..<dice.int(1...25) {
                let (type, event) = randomEvent(&dice)
                _ = hotkey.handle(type, event)
                if !hotkey.isCapturing { break }
            }
            if hotkey.isCapturing { hotkey.cancelCapture() }
            if results.count != 1 { broken.append("run \(run): finished \(results.count) times") }
            if case .some(.some(let shortcut)) = results.first {
                if shortcut.label.isEmpty || shortcut.label.contains("?") { broken.append("run \(run): \(shortcut)") }
            }
        }
        check(broken.isEmpty, "fuzz: 1000 random shortcut recordings end once, with a usable key \(broken.prefix(3))")
    }

    // MARK: - The model's text

    private static func fuzzWords(_ dice: inout Dice) {
        let pieces = ["open", "ai", "Open", "AI", "gwendal", "Gwendall", "koe", "toe", "café", "crème", "l'été", "hello", "world",
                      ",", ".", "?", "!", "…", "<unk>", "  ", " ", "\n", "😀", "日本", "Ωmega", "naïve", "co-op", "e-mail", "-", "'", "\""]
        var broken: [String] = []
        for run in 0..<3_000 {
            var text = ""
            for _ in 0..<dice.int(0...14) { text += dice.pick(pieces) + (dice.chance(0.7) ? " " : "") }
            var words: [String] = []
            for _ in 0..<dice.int(0...4) { words.append(dice.pick(["Gwendall", "OpenAI", "Koe", "Kubernetes", "naïve", "e-mail", "日本語", "X"])) }

            let cleaned = Transcriber.clean(text)
            if cleaned.contains("<unk>") || cleaned.contains("  ") || cleaned != cleaned.trimmingCharacters(in: .whitespacesAndNewlines) {
                broken.append("clean \(run): \(text.debugDescription) → \(cleaned.debugDescription)")
            }
            let corrected = Vocabulary.correct(cleaned, with: words)
            let before = cleaned.split(separator: " ").count, after = corrected.split(separator: " ").count
            if after > before { broken.append("vocabulary \(run): more words \(cleaned.debugDescription) → \(corrected.debugDescription)") }
            if words.isEmpty, corrected != cleaned { broken.append("vocabulary \(run): changed with no words") }
            // A word it changed becomes one of yours, its punctuation kept.
            let original = Set(cleaned.split(separator: " ").map(String.init))
            for token in corrected.split(separator: " ").map(String.init) where !original.contains(token) {
                let bare = String(token.reversed().drop { $0.isPunctuation }.reversed())
                if !words.contains(bare) { broken.append("vocabulary \(run): invented \(token.debugDescription) from \(cleaned.debugDescription)") }
            }
            if Vocabulary.correct(corrected, with: words) != corrected {
                broken.append("vocabulary \(run): a second pass changes it again \(corrected.debugDescription) → \(Vocabulary.correct(corrected, with: words).debugDescription) words \(words) from \(cleaned.debugDescription)")
            }
        }
        check(broken.isEmpty, "fuzz: 3000 random transcripts cleaned and corrected \(broken.prefix(3))")
    }

    // MARK: - The microphone's samples

    private static func fuzzAudio(_ dice: inout Dice) {
        var broken: [String] = []
        for run in 0..<400 {
            var samples: [Float] = []
            for _ in 0..<dice.int(0...6) {
                let length = dice.int(0...24_000)
                switch dice.int(0...4) {
                case 0: samples += [Float](repeating: 0, count: length)
                case 1: samples += (0..<length).map { _ in dice.float() * 0.0005 } // hiss
                case 2: samples += (0..<length).map { Float(sin(Double($0) * 0.07)) * 0.4 }
                case 3: samples += (0..<length).map { _ in dice.float() } // loud noise
                default: samples += (0..<length).map { Float(sin(Double($0) * 0.03)) * 0.006 } // a soft voice
                }
            }
            if dice.chance(0.05), !samples.isEmpty { samples[dice.int(0...samples.count - 1)] = dice.pick([.nan, .infinity, -.infinity]) }
            let odd = samples.contains { !$0.isFinite }

            let trimmed = Recorder.trimmed(samples)
            if trimmed.count > samples.count { broken.append("trim \(run): grew") }
            if !odd, let peak = samples.map(abs).max(), peak > 0 {
                // Every loud sample is kept: trimming only takes quiet edges.
                let loud = samples.filter { abs($0) >= peak * 0.5 }.count
                if trimmed.filter({ abs($0) >= peak * 0.5 }).count != loud { broken.append("trim \(run): cut a loud part") }
                if !trimmed.isEmpty, samples.firstRange(of: trimmed) == nil { broken.append("trim \(run): not one piece of the recording") }
            }
            if Recorder.isSilent(samples), samples.contains(where: { abs($0) > 1e-3 }) {
                broken.append("silence \(run): called silent with sound in it")
            }
        }
        check(broken.isEmpty, "fuzz: 400 random recordings trimmed, silence judged \(broken.prefix(3))")

        // The journal keeps whatever the microphone sends, odd values included.
        guard let journal = try? Journal() else { return check(false, "fuzz: journal created") }
        var total = 0
        for _ in 0..<60 {
            var chunk = (0..<dice.int(0...3_000)).map { _ in dice.float() * 1.5 }
            if dice.chance(0.2), !chunk.isEmpty { chunk[0] = dice.pick([.nan, .infinity, -.infinity, 7]) }
            journal.append(chunk)
            total += chunk.count
        }
        journal.saved()
        let back = Journal.audio(journal.id)
        check(back.count == total && back.allSatisfy { $0.isFinite && abs($0) <= 1 }, "fuzz: journal keeps \(total) odd samples, all in range")
        journal.discard()
    }

    // MARK: - The field Koe types into

    private static func fuzzTyping(_ dice: inout Dice) {
        // The space between two dictations.
        check(Paster.joined("Hello.", after: "d") == " Hello.", "join: after a word, a space")
        check(Paster.joined("Hello.", after: ".") == " Hello.", "join: after a full stop, a space")
        check(Paster.joined("Hello.", after: " ") == "Hello.", "join: after a space, none")
        check(Paster.joined("Hello.", after: "\n") == "Hello.", "join: on a new line, none")
        check(Paster.joined("Hello.", after: nil) == "Hello.", "join: at the start, none")
        check(Paster.joined("Hello.", after: "(") == "Hello.", "join: after an opening bracket, none")
        check(Paster.joined("Hello.", after: "«") == "Hello.", "join: after a guillemet, none")
        check(Paster.joined("gwendall.dev", after: "@") == "gwendall.dev", "join: after @, none")
        check(Paster.joined(", then", after: "d") == ", then", "join: before its own comma, none")
        check(Paster.joined("? Oui.", after: "i") == "? Oui.", "join: before its own question mark, none")
        check(Paster.joined("", after: "d") == "", "join: nothing stays nothing")

        // Did the words land? Appended, over a selection, in the middle, curled.
        let words = "Hello Koe, this is my very first dictation."
        check(Target.arrived(words, before: "", now: words), "arrived: into an empty field")
        check(Target.arrived(words, before: "Dear Sam,", now: "Dear Sam, " + words), "arrived: after text")
        check(Target.arrived(words, before: "a very long paragraph that was selected and replaced entirely by the words",
                             now: words), "arrived: over a selection, the field shorter")
        check(Target.arrived(words, before: "start end", now: "start " + words + " end"), "arrived: in the middle")
        check(Target.arrived("Don't stop", before: "", now: "Don’t stop"), "arrived: an app curled the apostrophe")
        check(Target.arrived(words, before: words, now: words + " " + words), "arrived: the same words twice")
        check(!Target.arrived(words, before: "abc", now: "abc"), "arrived: nothing changed")
        check(!Target.arrived(words, before: words, now: words), "arrived: the words were already there, nothing new")
        check(!Target.arrived(words, before: "abc", now: "abcd"), "arrived: something else changed")
        check(!Target.arrived(" ", before: "", now: " "), "arrived: no words, no proof")

        var broken: [String] = []
        let alphabet = Array("abc déf GHI ,.?!'’\"😀日本\n")
        for run in 0..<2_000 {
            let field = String((0..<dice.int(0...60)).map { _ in dice.pick(alphabet) })
            let text = String((1...dice.int(1...50)).map { _ in dice.pick(alphabet) })
            let joined = Paster.joined(text, after: field.last)
            if joined != text && joined != " " + text { broken.append("join \(run)") }
            // Pasting anywhere in the field shows the words.
            let at = field.index(field.startIndex, offsetBy: dice.int(0...field.count))
            let pasted = String(field[..<at]) + joined + String(field[at...])
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !Target.arrived(text, before: field, now: pasted) {
                broken.append("arrived \(run): \(text.debugDescription) into \(field.debugDescription)")
            }
        }
        check(broken.isEmpty, "fuzz: 2000 random pastes are seen landing \(broken.prefix(3))")
    }

    // ⌘V on the key that types v in each layout.
    private static func layouts() {
        func key(_ id: String) -> CGKeyCode? {
            let query = [kTISPropertyInputSourceID as String: id] as CFDictionary
            guard let sources = TISCreateInputSourceList(query, true)?.takeRetainedValue() as? [TISInputSource],
                  let source = sources.first else { return nil }
            return Paster.key(typing: "v", in: source)
        }
        check(key("com.apple.keylayout.US") == 9, "layout: QWERTY pastes with ⌘ and key 9")
        check(key("com.apple.keylayout.French") == 9, "layout: AZERTY too")
        check(key("com.apple.keylayout.German") == 9, "layout: QWERTZ too")
        check(key("com.apple.keylayout.Dvorak") == 47, "layout: Dvorak's v is on key 47, not ⌘K")
        check(key("com.apple.keylayout.DVORAK-QWERTYCMD") == 9, "layout: Dvorak – QWERTY ⌘ goes back to key 9 with ⌘")
        check(key("com.apple.keylayout.Colemak") == 9, "layout: Colemak keeps v on key 9")
        check(Paster.vKey() < 128, "layout: this Mac's paste key is a real key")
    }
}
