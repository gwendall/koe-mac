import AppKit
import SwiftUI

// `Koe --render-journey <dir>`: every screen a newcomer meets, in every
// state, light and dark, drawn from the app's own views, to look at.
@MainActor
enum Journey {
    static func render(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Words.english = !Words.languageAsked

        func state(_ change: (KoeState) -> Void = { _ in }) -> KoeState {
            let state = KoeState()
            state.shortcut = .fn
            state.submits = false
            state.words = []
            state.inputs = []
            state.input = nil
            change(state)
            return state
        }

        let screens: [(String, AnyView, NSSize)] = [
            ("01-welcome", AnyView(Welcome(state: state(), step: 0)), NSSize(width: 460, height: 560)),
            ("02-permissions-start", AnyView(Welcome(state: state { $0.microphone = nil; $0.accessibility = false; $0.modelShare = 0.12 }, step: 1)), NSSize(width: 460, height: 560)),
            ("03-permissions-mic-on", AnyView(Welcome(state: state { $0.microphone = true; $0.accessibility = false; $0.modelShare = 0.64 }, step: 1)), NSSize(width: 460, height: 560)),
            ("04-permissions-mic-denied", AnyView(Welcome(state: state { $0.microphone = false; $0.accessibility = false; $0.modelShare = 0.8 }, step: 1)), NSSize(width: 460, height: 560)),
            ("05-permissions-all-on-waking", AnyView(Welcome(state: state { $0.microphone = true; $0.accessibility = true }, step: 1)), NSSize(width: 460, height: 560)),
            ("06-permissions-ready", AnyView(Welcome(state: state { $0.microphone = true; $0.accessibility = true; $0.modelReady = true }, step: 1)), NSSize(width: 460, height: 560)),
            ("07-permissions-download-failed", AnyView(Welcome(state: state { $0.microphone = true; $0.accessibility = true; $0.modelFailed = true }, step: 1)), NSSize(width: 460, height: 560)),
            ("08-try-empty", AnyView(Welcome(state: state { $0.microphone = true; $0.accessibility = true; $0.modelReady = true }, step: 2)), NSSize(width: 460, height: 560)),
            ("09-try-listening", AnyView(Welcome(state: state { $0.microphone = true; $0.accessibility = true; $0.modelReady = true; $0.listening = true }, step: 2)), NSSize(width: 460, height: 560)),
            ("10-try-typed", AnyView(Welcome(state: state { $0.microphone = true; $0.accessibility = true; $0.modelReady = true }, step: 2, practice: "Bonjour Koe, ça marche vraiment bien. ")), NSSize(width: 460, height: 560)),
            ("11-try-modifier-toggle", AnyView(Welcome(state: state { $0.microphone = true; $0.accessibility = true; $0.modelReady = true; $0.shortcut = Shortcut(kind: .modifier, keyCode: 61) }, step: 2)), NSSize(width: 460, height: 560)),
            ("11b-all-set", AnyView(Welcome(state: state { $0.microphone = true; $0.accessibility = true; $0.modelReady = true }, step: 3)), NSSize(width: 460, height: 560)),
            ("12-settings", AnyView(SettingsView(state: state { $0.microphone = true; $0.accessibility = true; $0.modelReady = true })), NSSize(width: 480, height: 640)),
            ("13-settings-capturing", AnyView(SettingsView(state: state { $0.microphone = true; $0.accessibility = true; $0.capturing = true })), NSSize(width: 480, height: 640)),
            ("14-settings-refused", AnyView(SettingsView(state: state { $0.microphone = true; $0.accessibility = true; $0.captureError = Shortcut(kind: .combo, keyCode: 8, modifiers: NSEvent.ModifierFlags.command.rawValue).refusal })), NSSize(width: 480, height: 640)),
            ("15-settings-modifier", AnyView(SettingsView(state: state { $0.microphone = true; $0.accessibility = true; $0.shortcut = Shortcut(kind: .modifier, keyCode: 61) })), NSSize(width: 480, height: 640)),
            ("16-settings-missing-permissions", AnyView(SettingsView(state: state { $0.microphone = false; $0.accessibility = false })), NSSize(width: 480, height: 640)),
            ("18-settings-how-koe-works", AnyView(SettingsView(state: state { $0.microphone = true; $0.accessibility = true; $0.modelReady = true }, height: 1500)), NSSize(width: 480, height: 1500)),
            ("19-settings-polish-off", AnyView(SettingsView(state: state { $0.microphone = true; $0.accessibility = true; $0.modelReady = true }, height: 1500)), NSSize(width: 480, height: 1500)),
            ("20-settings-polish-downloading", AnyView(SettingsView(state: state { $0.microphone = true; $0.accessibility = true; $0.modelReady = true; $0.polish = true; $0.polishShare = 0.37 }, height: 1500)), NSSize(width: 480, height: 1500)),
            ("21-settings-polish-ready", AnyView(SettingsView(state: state { $0.microphone = true; $0.accessibility = true; $0.modelReady = true; $0.polish = true; $0.polishReady = true }, height: 1500)), NSSize(width: 480, height: 1500)),
            ("17-settings-dictionary", AnyView(SettingsView(state: state { $0.microphone = true; $0.accessibility = true; $0.words = ["Gwendall", "Koe", "FluidAudio"]; $0.submits = true })), NSSize(width: 480, height: 640)),
        ]
        for (name, view, size) in screens {
            for dark in [false, true] {
                draw(view, size: size, dark: dark, to: directory.appendingPathComponent("\(name)\(dark ? "-dark" : "").png"))
            }
        }

        let anchor = NSRect(x: 600, y: 860, width: 22, height: 22)
        let notes: [(String, Toast.Style)] = [
            ("t1-hello", Toast.hello),
            ("t4-copied-password", Toast.note(Words.say("COPIED"), Words.say("%1$@: “%2$@”", Words.say("That's a password field"), "hunter2"))),
            ("t5-almost-ready", Toast.note(Words.say("ALMOST READY"), Words.say("Koe's voice model is at %@", Words.percent(42)))),
            ("t6-no-sound", Toast.note(Words.say("NO SOUND"), Words.say("The microphone sent nothing. Check it in Settings"))),
            ("t7-cancelled", Toast.note(Words.say("CANCELLED"), Words.say("Nothing was typed"))),
            ("t8-recovered", Toast.note(Words.say("RECOVERED"), Words.say("Your last dictation is on the clipboard"))),
            ("t9-mic-off", Toast.note(Words.say("MICROPHONE OFF"), Words.say("Allow Koe in Privacy & Security"))),
        ]
        for (name, style) in notes {
            let toast = Toast()
            toast.show(style, under: anchor)
            Shots.picture(toast.host, to: directory.appendingPathComponent("\(name).png"), background: 0.93)
            toast.window.orderOut(nil)
        }
    }

    private static func draw(_ view: AnyView, size: NSSize, dark: Bool, to url: URL) {
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: size),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        guard let content = window.contentView,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }
}
