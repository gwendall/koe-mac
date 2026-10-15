import AppKit
import ServiceManagement

// The menu bar app. Hold fn (or press it, then press again) and talk: the
// words land where the cursor is. A click on the bubble opens the menu: the
// last dictations, and the few things one can change.
@MainActor
final class Koe: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let toast = Toast()
    private let hotkey = Hotkey()
    private let recorder = Recorder()
    private let transcriber = Transcriber()

    private enum Phase { case idle, listening, transcribing }
    private var phase = Phase.idle

    // The model: where it is once there, and how far its download got.
    private var modelDirectory: URL?
    private var modelLoaded = false
    private var downloadShare: Double?
    private var downloadFailed = false

    private var startedAt = Date()
    private var resetFace: DispatchWorkItem?
    private var permissionTimer: Timer?

    private var sounds: [Chime.Sound: NSSound] = [:]
    private var playing: NSSound?

    // Settings, few on purpose.
    private var muted: Bool {
        get { UserDefaults.standard.bool(forKey: "muted") }
        set { UserDefaults.standard.set(newValue, forKey: "muted") }
    }
    // Hold fn and talk (the default), or press fn to start and again to stop.
    private var toggles: Bool {
        get { UserDefaults.standard.bool(forKey: "toggles") }
        set { UserDefaults.standard.set(newValue, forKey: "toggles") }
    }

    // The last dictations, newest first, for the menu.
    private struct Dictation: Codable {
        let text: String
        let at: Date
    }
    private static let kept = 5
    private var recent: [Dictation] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "recent") else { return [] }
            return (try? JSONDecoder().decode([Dictation].self, from: data)) ?? []
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(Array(newValue.prefix(Self.kept))), forKey: "recent") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        show(Pixels.ready)
        item.button?.setAccessibilityLabel("Koe")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        hotkey.onDown = { [weak self] in self?.fnDown() }
        hotkey.onUp = { [weak self] in self?.fnUp() }
        hotkey.onChord = { [weak self] in self?.cancel() }
        recorder.onLevel = { [weak self] level in self?.toast.setLevel(level) }

        if !UserDefaults.standard.bool(forKey: "ranBefore") {
            UserDefaults.standard.set(true, forKey: "ranBefore")
            after(0.6) { [weak self] in self?.pop(Toast.hello) }
        }
        watchKeyboard()
        prepareModel()
    }

    // MARK: - fn

    private func fnDown() {
        switch phase {
        case .idle: start()
        case .listening where toggles: finish()
        default: break
        }
    }

    private func fnUp() {
        guard phase == .listening, !toggles else { return }
        finish()
    }

    private func start() {
        guard modelLoaded else {
            play(.refused)
            if let share = downloadShare {
                pop(Toast.note(Words.say("ALMOST READY"), Words.say("Koe's voice model is at %@", Words.percent(Int(share * 100)))))
            } else {
                pop(Toast.note(Words.say("ALMOST READY"), Words.say("Koe is loading its voice model")))
            }
            return
        }
        switch Recorder.permission {
        case .notDetermined:
            Recorder.askPermission { [weak self] granted in
                if !granted { self?.microphoneRefused() }
            }
            return
        case .denied, .restricted:
            microphoneRefused()
            return
        default:
            break
        }
        do {
            try recorder.start()
        } catch {
            play(.refused)
            pop(Toast.note(Words.say("NO MICROPHONE"), Words.say("Plug one in, or pick one in Sound settings")))
            return
        }
        phase = .listening
        startedAt = Date()
        resetFace?.cancel()
        show(Pixels.listening)
        play(.start)
        pop(Toast.listening)
    }

    private func finish() {
        guard phase == .listening else { return }
        let samples = recorder.stop()
        toast.dismiss()
        play(.stop)
        // A tap on fn, not a dictation.
        guard Date().timeIntervalSince(startedAt) > 0.25, samples.count > 4_000 else {
            phase = .idle
            show(Pixels.ready)
            return
        }
        phase = .transcribing
        Task { [weak self] in
            guard let self else { return }
            let text = (try? await transcriber.transcribe(samples)) ?? ""
            self.typed(text)
        }
    }

    // fn + another key: a shortcut of its own, not a dictation.
    private func cancel() {
        guard phase == .listening else { return }
        _ = recorder.stop()
        toast.dismiss()
        phase = .idle
        show(Pixels.ready)
    }

    private func typed(_ text: String) {
        phase = .idle
        guard !text.isEmpty else {
            show(Pixels.ready)
            play(.refused)
            pop(Toast.note(Words.say("NOTHING HEARD"), Words.say("Hold fn and talk")))
            return
        }
        Paster.type(text)
        recent = [Dictation(text: text, at: Date())] + recent
        show(Pixels.typed)
        play(.typed)
        pop(Toast.typed)
        let reset = DispatchWorkItem { [weak self] in
            guard self?.phase == .idle else { return }
            self?.show(Pixels.ready)
        }
        resetFace = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: reset)
    }

    private func microphoneRefused() {
        play(.refused)
        pop(Toast.note(Words.say("MICROPHONE OFF"), Words.say("Allow Koe in Privacy & Security")))
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }

    // MARK: - Permissions and the model

    // fn and ⌘V both need Accessibility. Until it is on, Koe asks once and
    // checks every two seconds.
    private func watchKeyboard() {
        if hotkey.start() { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        after(1.2) { [weak self] in
            self?.pop(Toast.note(Words.say("ALLOW KOE"), Words.say("Accessibility lets fn start it")))
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.hotkey.start() else { return }
                timer.invalidate()
                self.permissionTimer = nil
                if self.modelLoaded { self.pop(Toast.hello) }
            }
        }
    }

    private func prepareModel() {
        if let directory = Model.installed {
            load(directory)
            return
        }
        downloadShare = 0
        downloadFailed = false
        Task { [weak self] in
            do {
                let directory = try await Model.download { share in self?.downloadShare = share }
                self?.downloadShare = nil
                self?.load(directory)
            } catch {
                self?.downloadShare = nil
                self?.downloadFailed = true
            }
        }
    }

    private func load(_ directory: URL) {
        modelDirectory = directory
        Task { [weak self] in
            guard let self else { return }
            do {
                try await transcriber.load(directory)
                self.modelLoaded = true
            } catch {
                self.downloadFailed = true
            }
        }
    }

    // MARK: - The menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = NSMenuItem(title: statusLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        if downloadFailed {
            menu.addItem(entry(Words.say("Try Again"), #selector(retry)))
        }

        let dictations = recent
        if !dictations.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: Words.say("Click to copy"), action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = Words.locale
            formatter.unitsStyle = .short
            for (index, dictation) in dictations.enumerated() {
                let line = dictation.text.count > 44 ? String(dictation.text.prefix(43)) + "…" : dictation.text
                let row = entry(line, #selector(copyDictation(_:)))
                row.tag = index
                row.toolTip = dictation.text
                row.attributedTitle = Self.titled(line, detail: formatter.localizedString(for: dictation.at, relativeTo: Date()))
                menu.addItem(row)
            }
        }

        menu.addItem(.separator())
        let hold = entry(Words.say("Hold fn and Talk"), #selector(holdMode))
        hold.state = toggles ? .off : .on
        menu.addItem(hold)
        let press = entry(Words.say("Press fn to Start and Stop"), #selector(toggleMode))
        press.state = toggles ? .on : .off
        menu.addItem(press)
        let sound = entry(Words.say("Sound"), #selector(toggleSound))
        sound.state = muted ? .off : .on
        menu.addItem(sound)
        let login = entry(Words.say("Open at Login"), #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(entry(Words.say("About Koe"), #selector(openSite)))
        menu.addItem(entry(Words.say("Quit Koe"), #selector(quit), key: "q"))
    }

    private var statusLine: String {
        if downloadFailed { return Words.say("The voice model did not download") }
        if let share = downloadShare { return Words.say("Getting the voice model… %@", Words.percent(Int(share * 100))) }
        if !modelLoaded { return Words.say("Waking the voice model…") }
        if !hotkey.isRunning { return Words.say("Allow Koe in Accessibility to use fn") }
        return toggles ? Words.say("Press fn to talk") : Words.say("Hold fn to talk")
    }

    private func entry(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // A dictation's first words, and how long ago, in gray.
    private static func titled(_ text: String, detail: String) -> NSAttributedString {
        let title = NSMutableAttributedString(string: text, attributes: [.font: NSFont.menuFont(ofSize: 0)])
        title.append(NSAttributedString(string: "   " + detail, attributes: [
            .font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return title
    }

    @objc private func copyDictation(_ sender: NSMenuItem) {
        let dictations = recent
        guard dictations.indices.contains(sender.tag) else { return }
        Paster.copy(dictations[sender.tag].text)
        play(.select)
        pop(Toast.note(Words.say("COPIED"), Words.say("Paste it anywhere")))
    }

    @objc private func holdMode() {
        toggles = false
        play(.select)
    }

    @objc private func toggleMode() {
        toggles = true
        play(.select)
    }

    @objc private func toggleSound() {
        muted.toggle()
        if !muted { play(.check(true)) }
    }

    @objc private func toggleLogin() {
        let on = SMAppService.mainApp.status != .enabled
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            play(.check(on))
        } catch {
            play(.refused)
        }
    }

    @objc private func retry() {
        prepareModel()
    }

    @objc private func openSite() {
        NSWorkspace.shared.open(URL(string: "https://koe.fm")!)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Looks and sounds

    // The bubble in the menu bar, in the menu bar's ink: 3 device pixels a
    // cell, 16.5 points square.
    private func show(_ sprite: [String]) {
        guard let image = Pixels.image(sprite, color: CGColor(gray: 0, alpha: 1), scale: 3) else { return }
        let icon = NSImage(cgImage: image, size: NSSize(width: 16.5, height: 16.5))
        icon.isTemplate = true
        item.button?.image = icon
    }

    private func pop(_ style: Toast.Style) {
        guard let button = item.button, let window = button.window else { return }
        toast.show(style, under: window.convertToScreen(button.convert(button.bounds, to: nil)))
    }

    private func play(_ sound: Chime.Sound) {
        guard !muted else { return }
        let player: NSSound
        if let made = sounds[sound] {
            player = made
        } else {
            guard let made = NSSound(data: Chime.wav(Chime.samples(sound))) else { return }
            sounds[sound] = made
            player = made
        }
        playing?.stop()
        player.stop()
        player.play()
        playing = player
    }

    private func after(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { work() } }
    }
}
