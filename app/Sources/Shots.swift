import AppKit

// Pictures of Koe's pills, drawn offscreen, for `--render-toasts`: every one
// Koe can show, so each language's longest lines can be seen to fit.
@MainActor
enum Shots {
    static func toasts(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let anchor = NSRect(x: 600, y: 860, width: 22, height: 22)
        let words = Koe.opening(of: "Hello Koe, this is my very first dictation.")
        let copied = { (why: String) in Toast.note(Words.say("COPIED"), Words.say("%1$@: “%2$@”", why, words)) }
        let rightOption = Shortcut(kind: .modifier, keyCode: 61).label
        let combo = Shortcut(kind: .combo, keyCode: 49, modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue).label
        let styles: [(String, Toast.Style)] = [
            ("hello", Toast.hello),
            ("no-sound-listening", Toast.note(Words.say("KOE LISTENS"), Words.say("No sound: check your microphone"))),
            ("almost-ready", Toast.note(Words.say("ALMOST READY"), Words.say("Koe's voice model is at %@", Words.percent(42)))),
            ("almost-ready-waking", Toast.note(Words.say("ALMOST READY"), Words.say("Koe is waking its voice model"))),
            ("needs-you", Toast.note(Words.say("KOE NEEDS YOU"), Words.say("Click the bubble, then Settings"))),
            ("one-moment", Toast.note(Words.say("ONE MOMENT"), Words.say("Koe is still working on your words"))),
            ("no-voice-model", Toast.note(Words.say("NO VOICE MODEL"), Words.say("Click the bubble to try again"))),
            ("microphone-off", Toast.note(Words.say("MICROPHONE OFF"), Words.say("Allow Koe in Privacy & Security"))),
            ("cant-save-audio", Toast.note(Words.say("CAN'T SAVE AUDIO"), Words.say("Your disk may be full"))),
            ("no-microphone", Toast.note(Words.say("NO MICROPHONE"), Words.say("Plug one in, or pick one in Settings"))),
            ("no-sound", Toast.note(Words.say("NO SOUND"), Words.say("The microphone sent nothing. Check it in Settings"))),
            ("not-typed", Toast.note(Words.say("NOT TYPED"), Words.say("Saved. Retry it from the menu"))),
            ("nothing-heard", Toast.note(Words.say("NOTHING HEARD"), Words.say("Hold %@ and talk, let go to type", Shortcut.fn.label))),
            ("nothing-heard-toggle", Toast.note(Words.say("NOTHING HEARD"), Words.say("Press %@ to talk, press it again to stop", rightOption))),
            ("nothing-heard-combo", Toast.note(Words.say("NOTHING HEARD"), Words.say("Press %@ to talk, press it again to stop", combo))),
            ("copied-secure", copied(Words.say("Secure typing is on"))),
            ("copied-no-field", copied(Words.say("No text field in front"))),
            ("copied-password", copied(Words.say("That's a password field"))),
            ("copied-refused", copied(Words.say("The field didn't take it"))),
            ("copied-from-menu", Toast.note(Words.say("COPIED"), Words.say("Paste it anywhere with ⌘V"))),
            ("cancelled", Toast.note(Words.say("CANCELLED"), Words.say("Nothing was typed"))),
            ("recovered", Toast.note(Words.say("RECOVERED"), Words.say("Your last dictation is on the clipboard"))),
            ("no-answer", Toast.note(Words.say("NO ANSWER"), Words.say("Couldn't check for updates"))),
            ("up-to-date", Toast.note(Words.say("UP TO DATE"), Words.say("Koe %@ is the latest", "2.0.0"))),
            ("out", Toast.note(Words.say("KOE %@ IS OUT", "2.0.1"), Words.say("Get it from koe.fm"))),
            ("report-copied", Toast.note(Words.say("REPORT COPIED"), Words.say("No dictated text is in it"))),
        ]
        for (name, style) in styles {
            let toast = Toast()
            toast.show(style, under: anchor)
            picture(toast.host, to: directory.appendingPathComponent("\(name).png"))
            toast.window.orderOut(nil)
        }

        // The dictation's pill, low on the screen, in each of its moments.
        let moments: [(String, (Indicator) -> Void)] = [
            ("indicator-1-waiting", { _ in }),
            ("indicator-2-listening", { $0.setLevel(0.75) }),
            ("indicator-3-working", { $0.work() }),
            ("indicator-4-done", { $0.work(); $0.done() }),
        ]
        for (name, moment) in moments {
            let indicator = Indicator()
            indicator.show()
            moment(indicator)
            picture(indicator.host, to: directory.appendingPathComponent("\(name).png"))
            indicator.window.orderOut(nil)
        }
    }

    static func picture(_ view: NSView, to url: URL, background: CGFloat = 0.92) {
        guard let layer = view.layer else { return }
        let scale: CGFloat = 2, size = view.bounds.size
        guard let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.setFillColor(CGColor(gray: background, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
        context.scaleBy(x: scale, y: scale)
        layer.render(in: context)
        guard let image = context.makeImage() else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }
}
