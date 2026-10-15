import AppKit

// Pictures of Koe's pills, drawn offscreen, for `--render-toasts`: every one
// Koe can show, so each language's longest lines can be seen to fit.
@MainActor
enum Shots {
    static func toasts(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let anchor = NSRect(x: 600, y: 860, width: 22, height: 22)
        let copied = { (why: String) in Toast.note(Words.say("COPIED"), Words.say("%@. Paste it with ⌘V", why)) }
        let rightOption = Shortcut(kind: .modifier, keyCode: 61).label
        let combo = Shortcut(kind: .combo, keyCode: 49, modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue).label
        let styles: [(String, Toast.Style, Float?)] = [
            ("listening", Toast.listening, 0.7),
            ("listening-no-sound", Toast.listening, 0.1),
            ("typed", Toast.typed, nil),
            ("hello", Toast.hello, nil),
            ("almost-ready", Toast.note(Words.say("ALMOST READY"), Words.say("Koe's voice model is at %@", Words.percent(42))), nil),
            ("almost-ready-waking", Toast.note(Words.say("ALMOST READY"), Words.say("Koe is waking its voice model")), nil),
            ("needs-you", Toast.note(Words.say("KOE NEEDS YOU"), Words.say("Click the bubble, then Settings")), nil),
            ("one-moment", Toast.note(Words.say("ONE MOMENT"), Words.say("Koe is still working on your words")), nil),
            ("no-voice-model", Toast.note(Words.say("NO VOICE MODEL"), Words.say("Click the bubble to try again")), nil),
            ("microphone-off", Toast.note(Words.say("MICROPHONE OFF"), Words.say("Allow Koe in Privacy & Security")), nil),
            ("cant-save-audio", Toast.note(Words.say("CAN'T SAVE AUDIO"), Words.say("Your disk may be full")), nil),
            ("no-microphone", Toast.note(Words.say("NO MICROPHONE"), Words.say("Plug one in, or pick one in Settings")), nil),
            ("no-sound", Toast.note(Words.say("NO SOUND"), Words.say("The microphone sent nothing. Check it in Settings")), nil),
            ("not-typed", Toast.note(Words.say("NOT TYPED"), Words.say("Saved. Retry it from the menu")), nil),
            ("nothing-heard", Toast.note(Words.say("NOTHING HEARD"), Words.say("Hold %@ and talk, let go to type", Shortcut.fn.label)), nil),
            ("nothing-heard-toggle", Toast.note(Words.say("NOTHING HEARD"), Words.say("Press %@ to talk, press it again to stop", rightOption)), nil),
            ("nothing-heard-combo", Toast.note(Words.say("NOTHING HEARD"), Words.say("Press %@ to talk, press it again to stop", combo)), nil),
            ("copied-secure", copied(Words.say("Secure typing is on")), nil),
            ("copied-no-field", copied(Words.say("No text field in front")), nil),
            ("copied-password", copied(Words.say("That's a password field")), nil),
            ("copied-refused", copied(Words.say("The field didn't take it")), nil),
            ("copied-from-menu", Toast.note(Words.say("COPIED"), Words.say("Paste it anywhere with ⌘V")), nil),
            ("cancelled", Toast.note(Words.say("CANCELLED"), Words.say("Nothing was typed")), nil),
            ("recovered", Toast.note(Words.say("RECOVERED"), Words.say("Your last dictation is on the clipboard")), nil),
            ("no-answer", Toast.note(Words.say("NO ANSWER"), Words.say("Couldn't check for updates")), nil),
            ("up-to-date", Toast.note(Words.say("UP TO DATE"), Words.say("Koe %@ is the latest", "2.0.0")), nil),
            ("out", Toast.note(Words.say("KOE %@ IS OUT", "2.0.1"), Words.say("Get it from koe.fm")), nil),
            ("report-copied", Toast.note(Words.say("REPORT COPIED"), Words.say("No dictated text is in it")), nil),
        ]
        for (name, style, level) in styles {
            let toast = Toast()
            toast.show(style, under: anchor)
            if let level { toast.setLevel(level) }
            if name == "listening-no-sound" { toast.setCaption(Words.say("No sound: check your microphone")) }
            guard let layer = toast.host.layer else { continue }
            let scale: CGFloat = 2
            let size = toast.host.bounds.size
            guard let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            context.setFillColor(CGColor(gray: 0.92, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
            context.scaleBy(x: scale, y: scale)
            layer.render(in: context)
            guard let image = context.makeImage() else { continue }
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("\(name).png"))
            toast.window.orderOut(nil)
        }
    }
}
