import AppKit
import CoreGraphics

// `Koe --self-test`: the guards that kept Koe 0.1 out of trouble, checked
// without a keyboard, a microphone or a model. Exits 1 on any failure.
@MainActor
enum SelfTest {
    private static var failures = 0
    private static var checks = 0

    static func check(_ condition: Bool, _ name: String) {
        checks += 1
        if !condition {
            failures += 1
            print("FAIL \(name)")
        }
    }

    static func run() -> Int32 {
        Words.english = true
        vocabulary()
        audio()
        shortcuts()
        hotkey()
        journal()
        fuzz()
        languages()
        deadline()
        print("\(checks - failures)/\(checks) checks passed")
        return failures == 0 ? 0 : 1
    }

    private static func vocabulary() {
        let words = ["Gwendall", "OpenAI", "Koe"]
        check(Vocabulary.correct("Parle à Gwendal.", with: words) == "Parle à Gwendall.", "vocabulary: one letter off, punctuation kept")
        check(Vocabulary.correct("Open Ai is here", with: words) == "OpenAI is here", "vocabulary: words run together")
        check(Vocabulary.correct("go to the toe", with: words) == "go to the toe", "vocabulary: short words and far words untouched")
        check(Vocabulary.correct("Gwendall said", with: words) == "Gwendall said", "vocabulary: already right")
        check(Vocabulary.correct("What is the plan?", with: ["wham", "koe", "kami"]) == "What is the plan?", "vocabulary: a real word next to one of yours stays (what, wham)")
        check(Vocabulary.correct("Tell Gwendal and Kubernetis", with: ["Gwendall", "Kubernetes"]) == "Tell Gwendall and Kubernetes", "vocabulary: a near miss that is no word becomes yours")
        check(Vocabulary.correct("Parle à Gwendall.", with: words) == "Parle à Gwendall.", "vocabulary: a short word before one of yours is kept")
        check(Vocabulary.correct("Merci… Gwendall", with: words) == "Merci… Gwendall", "vocabulary: a mark before one of yours is kept")
        check(Vocabulary.correct("Tu connais Gwendal ?", with: words) == "Tu connais Gwendall ?", "vocabulary: French spacing before ? kept")
        check(Vocabulary.correct("café crème", with: []) == "café crème", "vocabulary: empty dictionary")
        check(Transcriber.clean(" mot <unk>ssi<unk>  <unk> qui ") == "mot ssi qui", "model: <unk> removed")
        // Fillers, always taken out (Polish.swift, evals/polish).
        check(Fillers.strip("Um, can you send me the the report before, uh, Friday?") == "Can you send me the the report before Friday?", "fillers: um and uh, commas and all")
        check(Fillers.strip("Wir treffen uns um zehn.") == "Wir treffen uns um zehn.", "fillers: German um, a word, stays")
        check(Fillers.strip("Euh, je serai là, euh, vers 19h.") == "Je serai là vers 19h.", "fillers: euh")
        check(Fillers.strip("Eh, ¿puedes revisar el informe?") == "¿Puedes revisar el informe?", "fillers: Spanish, its capital back")
        check(Fillers.strip("Okay, eh?") == "Okay, eh?", "fillers: a closing eh stays")
        check(Fillers.strip("Er kommt morgen.") == "Er kommt morgen.", "fillers: German er stays")
        check(Fillers.strip("Uh.") == "Uh.", "fillers: nothing but a filler is left as is")
        check(Fillers.strip("Ship it.") == "Ship it.", "fillers: nothing to take, nothing touched")
        // The polishing model's answer is kept only close to what was said.
        check(Polisher.keep("Can you send me the report?", said: "Um can you send me the the report?") != nil, "polish: a clean-up is kept")
        check(Polisher.keep("Paris.", said: "What's the capital of France?") == nil, "polish: an answer is thrown away")
        check(Polisher.keep("", said: "Ship it.") == nil, "polish: nothing is thrown away")
    }

    private static func audio() {
        let zeros = [Float](repeating: 0, count: 48_000)
        check(Recorder.isSilent(zeros), "silence: 3 s of nothing is silent")
        check(!Recorder.isSilent([Float](repeating: 0, count: 16_000)), "silence: under 2 s is never judged")
        // The soft dictation Koe 0.1 once threw away: RMS 0.0088.
        let soft = (0..<48_000).map { Float(sin(Double($0) * 0.05)) * 0.0124 }
        check(!Recorder.isSilent(soft), "silence: a soft voice is not silence")

        let tone = (0..<16_000).map { Float(sin(Double($0) * 0.1)) * 0.3 }
        let pause = [Float](repeating: 0, count: 16_000)
        let trimmed = Recorder.trimmed(pause + tone + pause)
        check(trimmed.count < 16_000 + 4_800 + 8_000 + 1_500 && trimmed.count >= 16_000, "trim: edges cut, 0.3 s kept before, 0.5 s after")
        let middle = Recorder.trimmed(tone + pause + tone)
        check(middle.count >= 48_000 - 960, "trim: a pause in the middle is never cut")
        let quiet = pause + tone.map { $0 * 0.02 } + pause
        check(Recorder.trimmed(quiet).count >= 16_000, "trim: a quiet voice is kept whole")
        // A knock on the desk, then the last words said softly (18 dB down):
        // they once counted as silence and were lost.
        let hiss = (0..<16_000).map { Float(sin(Double($0) * 1.7)) * 0.001 }
        let knock = [Float](repeating: 0.95, count: 40)
        let ending = hiss + knock + tone + tone.map { $0 * 0.125 } + hiss
        check(Recorder.trimmed(ending).count >= 40 + 32_000 + 8_000 - 960, "trim: soft last words after a knock are kept")
    }

    private static func shortcuts() {
        let control = NSEvent.ModifierFlags.control.rawValue, option = NSEvent.ModifierFlags.option.rawValue
        let command = NSEvent.ModifierFlags.command.rawValue
        check(Shortcut(kind: .combo, keyCode: 49, modifiers: control | option).refusal == nil, "shortcut: ⌃⌥Space accepted")
        check(Shortcut(kind: .combo, keyCode: 8, modifiers: command).refusal != nil, "shortcut: ⌘C refused")
        check(Shortcut(kind: .combo, keyCode: 49, modifiers: 0).refusal != nil, "shortcut: Space alone refused")
        check(Shortcut(kind: .combo, keyCode: 96, modifiers: 0).refusal == nil, "shortcut: F5 alone accepted")
        check(Shortcut(kind: .combo, keyCode: 53, modifiers: control).refusal != nil, "shortcut: Escape refused")
        check(Shortcut(kind: .combo, keyCode: 49, modifiers: command).refusal != nil, "shortcut: ⌘Space refused")
        check(Shortcut(kind: .modifier, keyCode: 61).label == "Right ⌥", "shortcut: right option label")
        check(Shortcut(kind: .modifier, keyCode: 61).forcesToggle, "shortcut: a modifier alone toggles")
        check(!Shortcut.fn.forcesToggle, "shortcut: fn can be held")
        check(Shortcut(kind: .combo, keyCode: 49, modifiers: control | option).label == "⌃⌥Space", "shortcut: combination label")
    }

    static func event(_ type: CGEventType, _ code: UInt16, _ flags: CGEventFlags = [], repeating: Bool = false) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: type != .keyUp)!
        event.type = type
        event.flags = flags
        if repeating { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        return event
    }

    private static func hotkey() {
        let hotkey = Hotkey()
        var log: [String] = []
        hotkey.onDown = { log.append("down") }
        hotkey.onUp = { log.append("up") }
        hotkey.onChord = { log.append("chord") }
        hotkey.onEscape = { log.append("escape") }

        // fn, on both of its key codes; macOS never sees it.
        hotkey.shortcut = .fn
        log = []
        check(!hotkey.handle(.flagsChanged, event(.flagsChanged, 63, .maskSecondaryFn)), "fn: press kept from macOS")
        check(!hotkey.handle(Hotkey.systemDefined, event(Hotkey.systemDefined, 0, .maskSecondaryFn)), "fn: emoji path kept while held")
        check(!hotkey.handle(.flagsChanged, event(.flagsChanged, 63)), "fn: release kept from macOS")
        check(hotkey.handle(Hotkey.systemDefined, event(Hotkey.systemDefined, 0)), "fn: media keys pass when fn is up")
        check(log == ["down", "up"], "fn: down then up")
        log = []
        _ = hotkey.handle(.flagsChanged, event(.flagsChanged, 179, .maskSecondaryFn))
        _ = hotkey.handle(.flagsChanged, event(.flagsChanged, 179))
        check(log == ["down", "up"], "fn: the Apple silicon globe key (179) too")
        log = []
        _ = hotkey.handle(.flagsChanged, event(.flagsChanged, 63, .maskSecondaryFn))
        check(hotkey.handle(.keyDown, event(.keyDown, 51, .maskSecondaryFn)), "fn: fn+delete still reaches the app")
        _ = hotkey.handle(.flagsChanged, event(.flagsChanged, 63))
        check(log == ["down", "chord", "up"], "fn: a key with fn is a chord")
        log = []
        check(hotkey.handle(.flagsChanged, event(.flagsChanged, 123, .maskSecondaryFn)), "fn: an arrow's own fn flag passes")
        check(log.isEmpty, "fn: an arrow is not fn")

        // A modifier alone: fires once, on release, only when nothing else happened.
        hotkey.shortcut = Shortcut(kind: .modifier, keyCode: 61)
        log = []
        _ = hotkey.handle(.flagsChanged, event(.flagsChanged, 61, .maskAlternate))
        _ = hotkey.handle(.flagsChanged, event(.flagsChanged, 61))
        check(log == ["down", "up"], "modifier: a clean tap fires")
        log = []
        _ = hotkey.handle(.flagsChanged, event(.flagsChanged, 61, .maskAlternate))
        _ = hotkey.handle(.keyDown, event(.keyDown, 8, .maskAlternate))
        _ = hotkey.handle(.flagsChanged, event(.flagsChanged, 61))
        check(log.isEmpty, "modifier: ⌥C does not fire")
        log = []
        _ = hotkey.handle(.flagsChanged, event(.flagsChanged, 56, .maskShift))
        _ = hotkey.handle(.flagsChanged, event(.flagsChanged, 61, [.maskShift, .maskAlternate]))
        _ = hotkey.handle(.flagsChanged, event(.flagsChanged, 61, .maskShift))
        _ = hotkey.handle(.flagsChanged, event(.flagsChanged, 56))
        check(log.isEmpty, "modifier: with another modifier held, it does not fire")
        log = []
        _ = hotkey.handle(.flagsChanged, event(.flagsChanged, 61, .maskAlternate))
        _ = hotkey.handle(.scrollWheel, event(.scrollWheel, 0, .maskAlternate))
        _ = hotkey.handle(.flagsChanged, event(.flagsChanged, 61))
        check(log.isEmpty, "modifier: ⌥-scroll does not fire")

        // A combination: fires on its key, repeats ignored, kept from the app.
        hotkey.shortcut = Shortcut(kind: .combo, keyCode: 49, modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue)
        log = []
        check(!hotkey.handle(.keyDown, event(.keyDown, 49, [.maskControl, .maskAlternate])), "combo: kept from the app")
        _ = hotkey.handle(.keyDown, event(.keyDown, 49, [.maskControl, .maskAlternate], repeating: true))
        check(!hotkey.handle(.keyUp, event(.keyUp, 49, [.maskControl, .maskAlternate])), "combo: release kept too")
        check(log == ["down", "up"], "combo: down then up, repeat ignored")
        log = []
        check(hotkey.handle(.keyDown, event(.keyDown, 49, .maskControl)), "combo: other modifiers pass")
        check(log.isEmpty, "combo: ⌃Space is not ⌃⌥Space")

        // Escape: Koe's only while it listens or types.
        log = []
        check(hotkey.handle(.keyDown, event(.keyDown, 53)), "escape: passes when Koe is idle")
        hotkey.escapeActive = true
        check(!hotkey.handle(.keyDown, event(.keyDown, 53)), "escape: kept while Koe listens")
        check(log == ["escape"], "escape: cancels")
        hotkey.escapeActive = false // the dictation is gone; the key is still down
        check(!hotkey.handle(.keyDown, event(.keyDown, 53, repeating: true)), "escape: its repeats stay Koe's")
        check(!hotkey.handle(.keyUp, event(.keyUp, 53)), "escape: its release stays Koe's (terminals report releases)")
        check(log == ["escape"], "escape: cancels once")
        check(hotkey.handle(.keyUp, event(.keyUp, 53)), "escape: the next release is the app's")
        hotkey.escapeActive = true
        let touches = hotkey.touches
        _ = hotkey.handle(.keyDown, event(.keyDown, 0))
        _ = hotkey.handle(.leftMouseDown, event(.leftMouseDown, 0))
        check(hotkey.touches == touches + 2, "touches: a key and a click that reach the app count")
        _ = hotkey.handle(.keyDown, event(.keyDown, 53))
        check(hotkey.touches == touches + 2, "touches: Koe's own Escape doesn't")
        hotkey.escapeActive = false

        // Recording a shortcut.
        var captured: Shortcut??
        hotkey.capture { captured = .some($0) }
        _ = hotkey.handle(.flagsChanged, event(.flagsChanged, 61, .maskAlternate))
        _ = hotkey.handle(.flagsChanged, event(.flagsChanged, 61))
        check(captured == .some(Shortcut(kind: .modifier, keyCode: 61)), "capture: right ⌥ alone")
        captured = nil
        hotkey.capture { captured = .some($0) }
        _ = hotkey.handle(.flagsChanged, event(.flagsChanged, 59, .maskControl))
        _ = hotkey.handle(.flagsChanged, event(.flagsChanged, 58, [.maskControl, .maskAlternate]))
        _ = hotkey.handle(.keyDown, event(.keyDown, 49, [.maskControl, .maskAlternate]))
        _ = hotkey.handle(.keyUp, event(.keyUp, 49, [.maskControl, .maskAlternate]))
        check(captured??.label == "⌃⌥Space", "capture: a combination, committed on release")
        captured = nil
        hotkey.capture { captured = .some($0) }
        _ = hotkey.handle(.flagsChanged, event(.flagsChanged, 63, .maskSecondaryFn))
        _ = hotkey.handle(.flagsChanged, event(.flagsChanged, 63))
        check(captured == .some(.fn), "capture: fn")
        captured = nil
        hotkey.capture { captured = .some($0) }
        _ = hotkey.handle(.keyDown, event(.keyDown, 53))
        check(captured == .some(nil), "capture: Escape cancels")
        check(!hotkey.isCapturing, "capture: over")
    }

    // A model that never answers lets go at its deadline, not after it.
    private static func deadline() {
        let done = DispatchSemaphore(value: 0)
        var answer: String? = "late"
        let start = Date()
        Task.detached {
            answer = await Deadline.race(0.2) { try? await Task.sleep(for: .seconds(30)); return "late" }
            done.signal()
        }
        done.wait()
        check(answer == nil && Date().timeIntervalSince(start) < 2, "deadline: a stuck model lets go in time")
        Task.detached {
            answer = await Deadline.race(5) { "quick" }
            done.signal()
        }
        done.wait()
        check(answer == "quick", "deadline: a quick answer comes through")
    }

    private static func journal() {
        guard let journal = try? Journal() else { return check(false, "journal: created") }
        let audio = (0..<20_000).map { Float(sin(Double($0) * 0.1)) * 0.5 }
        journal.append(audio)
        journal.saved()
        let left = Journal.leftovers().first { $0.id == journal.id }
        check(left?.status == .saved, "journal: saved before transcription")
        let back = Journal.audio(journal.id)
        check(back.count == audio.count && abs(back[100] - audio[100]) < 0.001, "journal: audio comes back")
        journal.transcribed("bonjour")
        check(Journal.leftovers().first { $0.id == journal.id }?.text == "bonjour", "journal: words kept until delivered")
        journal.discard()
        check(Journal.leftovers().allSatisfy { $0.id != journal.id }, "journal: gone once delivered")
    }
}
