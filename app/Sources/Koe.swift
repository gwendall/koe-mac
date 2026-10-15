import AppKit
import ServiceManagement

// The menu bar app. Hold the shortcut (fn by default) and talk: the words
// land where the cursor is. A click on the bubble opens the menu: the last
// dictations, Settings, updates.
//
// One dictation at a time, owned here on the main actor: idle, listening,
// transcribing. Its audio is in the journal from the first second until the
// words are delivered (Journal.swift); where they go is Target's call
// (Target.swift); how, Paster's (Paster.swift).
@MainActor
final class Koe: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let toast = Toast()
    private let indicator = Indicator()
    private let hotkey = Hotkey()
    private let recorder = Recorder()
    private var transcriber = Transcriber()
    private let polisher = Polisher()
    let state = KoeState()

    private enum Phase { case idle, listening, transcribing, typing }
    private var phase = Phase.idle { didSet { phaseChanged() } }

    // The dictation under way.
    private var journal: Journal?
    private var origin: Target.Origin?
    private var startedAt = Date()
    private var dictation = 0           // bumped by every start and cancel: stale results are dropped
    private var lastHeard = Date()      // the last time the voice moved the bars
    private var warnedSilence = false
    private var limitTimer: Timer?
    private var activity: NSObjectProtocol?
    private var resetFace: DispatchWorkItem?

    private var permissionTimer: Timer?
    private var updateTimer: Timer?
    private var poweringOff = false
    private var sounds: [Chime.Sound: NSSound] = [:]
    private var playing: NSSound?

    // Nothing longer than this: memory stays bounded, and Koe never listens forever.
    private static let longest: TimeInterval = 30 * 60
    // Shorter than this, a press is a tap: hands-free until the next one.
    private static let tap: TimeInterval = 0.4
    private var latched = false
    // Where Koe typed last, and the keyboard's count of keys and clicks then.
    private var lastTyped: (pid: pid_t, touches: Int, end: Character)?
    private var trustTimer: Timer?
    #if KOE_EVAL
    private var evalDoor: EvalDoor?
    #endif

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One Koe at a time: two would hear the shortcut twice and type twice.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "fm.koe.mac")
            .filter { $0.processIdentifier != getpid() }
        if let other = others.first {
            other.activate()
            NSApp.terminate(nil)
            return
        }
        Log.note("launch", ["version": Update.running])

        show(Pixels.ready)
        item.button?.setAccessibilityLabel("Koe")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        wireState()
        wireHotkey()
        recorder.onLevel = { [weak self] level in self?.heard(level) }
        recorder.onInterrupted = { [weak self] in
            Log.note("microphone", ["changed": "while listening"])
            self?.finish(tail: 0)
        }

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.phase == .listening { self?.finish(tail: 0) } }
        }
        center.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.poweringOff = true }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPermissions() }
        }
        NotificationCenter.default.addObserver(forName: .koeShowSettings, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.openSettings() }
        }

        checkPermissions()
        watchPermissions()
        guardTrust()
        prepareModel()
        preparePolish()
        scheduleUpdates()

        if !UserDefaults.standard.bool(forKey: "welcomed") {
            Windows.showWelcome(state)
        } else if state.microphone == false || !state.accessibility {
            pop(Toast.note(Words.say("KOE NEEDS YOU"), Words.say("Click the bubble, then Settings")))
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    // Never quit in the middle of a dictation; at shutdown the journal keeps it.
    // llama.cpp's Metal backend asserts when torn down at exit with a model
    // loaded: unload it first (Polish.swift), or each quit leaves a crash report.
    func applicationWillTerminate(_ notification: Notification) {
        let done = DispatchSemaphore(value: 0), polisher = self.polisher
        Task.detached {
            await polisher.unload()
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard phase != .idle, !poweringOff else { return .terminateNow }
        play(.refused)
        pop(Toast.note(Words.say("ONE MOMENT"), Words.say("Koe is still working on your words")))
        return .terminateCancel
    }

    private func wireState() {
        state.askMicrophone = { [weak self] in
            Recorder.askPermission { _ in self?.checkPermissions() }
        }
        state.openMicrophoneSettings = { [weak self] in
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            self?.stepAside()
        }
        state.openAccessibility = { [weak self] in
            // Puts Koe in the list, with macOS's own dialog, whose button
            // opens it. macOS shows that dialog only once: when it does not
            // come, the list is opened here, so there is always something in
            // front of you to switch on, and never both.
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if !Self.accessibilityDialogShown {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
            self?.stepAside()
        }
        state.startCapture = { [weak self] in self?.captureShortcut() }
        state.cancelCapture = { [weak self] in self?.hotkey.cancelCapture() }
        state.retryModel = { [weak self] in self?.prepareModel() }
        state.polishChanged = { [weak self] in self?.preparePolish() }
        state.setLogin = { [weak self] on in self?.setLogin(on) }
        state.copyReport = { [weak self] in self?.copyReport() }
        state.finishWelcome = { UserDefaults.standard.set(true, forKey: "welcomed") }
        state.celebrate = { [weak self] in self?.play(.hooray) }
        state.login = SMAppService.mainApp.status == .enabled
        state.inputs = Devices.inputs()
    }

    // MARK: - The shortcut

    private func wireHotkey() {
        hotkey.onDown = { [weak self] in self?.shortcutDown() }
        hotkey.onUp = { [weak self] in self?.shortcutUp() }
        hotkey.onChord = { [weak self] in
            // fn + another key: a shortcut of its own. Only a dictation just
            // started is dropped; one well under way is kept.
            guard let self, self.phase == .listening, Date().timeIntervalSince(self.startedAt) < 0.6 else { return }
            self.cancel(quietly: true)
        }
        hotkey.onEscape = { [weak self] in self?.cancel(quietly: false) }
        #if KOE_EVAL
        // Eval builds only (KOE_EVAL=1 scripts/build.sh): the shortcut and
        // Escape, pressed from outside, for end-to-end runs without a hand
        // on the keyboard. Never in a release.
        evalDoor = EvalDoor(["down", "up", "escape", "feed", "dictate"]) { [weak self] name, object in
            guard let self else { return }
            switch name {
            case "down": self.hotkey.onDown?()
            case "up": self.hotkey.onUp?()
            case "escape": self.hotkey.onEscape?()
            case "feed": if let object { self.recorder.feed(URL(fileURLWithPath: object)) }
            case "dictate":
                // A whole dictation of a file: pressed, the file heard, released
                // (pressed again in toggle mode; Escape for "<path>|escape"),
                // with no gap for the mic to fill.
                guard let parts = object?.components(separatedBy: "|") else { return }
                self.hotkey.onDown?()
                self.recorder.feed(URL(fileURLWithPath: parts[0])) { [weak self] in
                    guard let self else { return }
                    if parts.count > 1, parts[1] == "escape" { self.hotkey.onEscape?() }
                    else if self.latched || self.state.shortcut.forcesToggle { self.hotkey.onDown?() } else { self.hotkey.onUp?() }
                }
            default: break
            }
        }
        #endif
    }

    private func shortcutDown() {
        switch phase {
        case .idle: start()
        case .listening where latched || state.shortcut.forcesToggle: finish()
        default: break // one dictation at a time; still typing the last one
        }
    }

    // Up within a tap of going down: Koe goes on listening, hands free, until
    // the next press. Held longer: the dictation ends here.
    private func shortcutUp() {
        guard phase == .listening, !latched, !state.shortcut.forcesToggle else { return }
        if Date().timeIntervalSince(startedAt) < Self.tap {
            latched = true
            return
        }
        finish()
    }

    private func captureShortcut() {
        state.captureError = nil
        state.capturing = true
        hotkey.capture { [weak self] shortcut in
            guard let self else { return }
            self.state.capturing = false
            guard let shortcut else { return }
            if let refusal = shortcut.refusal {
                self.state.captureError = refusal
                self.play(.refused)
                return
            }
            Shortcut.saved = shortcut
            self.hotkey.shortcut = shortcut
            self.state.shortcut = shortcut
            self.play(.check(true))
            Log.note("shortcut", ["kind": shortcut.kind.rawValue])
        }
    }

    // MARK: - A dictation

    private func start() {
        guard state.modelReady else {
            play(.refused)
            if state.modelFailed {
                pop(Toast.note(Words.say("NO VOICE MODEL"), Words.say("Click the bubble to try again")))
            } else if let share = state.modelShare {
                pop(Toast.note(Words.say("ALMOST READY"), Words.say("Koe's voice model is at %@", Words.percent(Int(share * 100)))))
            } else {
                pop(Toast.note(Words.say("ALMOST READY"), Words.say("Koe is waking its voice model")))
            }
            return
        }
        switch Recorder.permission {
        case .authorized: break
        case .notDetermined:
            Recorder.askPermission { [weak self] _ in self?.checkPermissions() }
            return
        default:
            play(.refused)
            pop(Toast.note(Words.say("MICROPHONE OFF"), Words.say("Allow Koe in Privacy & Security")))
            state.openMicrophoneSettings()
            return
        }
        let journal: Journal
        do {
            journal = try Journal()
        } catch {
            play(.refused)
            pop(Toast.note(Words.say("CAN'T SAVE AUDIO"), Words.say("Your disk may be full")))
            return
        }
        recorder.onSamples = { [weak journal] chunk in journal?.append(chunk) }
        do {
            try recorder.start()
        } catch {
            journal.discard()
            play(.refused)
            pop(Toast.note(Words.say("NO MICROPHONE"), Words.say("Plug one in, or pick one in Settings")))
            Log.note("microphone", ["start": "failed"])
            return
        }
        dictation += 1
        self.journal = journal
        origin = Target.origin()
        startedAt = Date()
        lastHeard = Date()
        warnedSilence = false
        latched = false
        phase = .listening
        resetFace?.cancel()
        show(Pixels.listening)
        play(.start)
        indicator.show()
        limitTimer = Timer.scheduledTimer(withTimeInterval: Self.longest, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
    }

    // The bars, and once a dictation "no sound" when a microphone sends
    // nothing for 3 s after a 5 s grace (Bluetooth microphones take a moment
    // to wake).
    private func heard(_ level: Float) {
        guard phase == .listening else { return }
        indicator.setLevel(level)
        if level > 0.05 {
            lastHeard = Date()
        } else if !warnedSilence, Date().timeIntervalSince(startedAt) > 5, Date().timeIntervalSince(lastHeard) > 3 {
            warnedSilence = true
            pop(Toast.note(Words.say("KOE LISTENS"), Words.say("No sound: check your microphone")))
        }
    }

    // The key comes up as the last syllable ends, and the audio of it is still
    // on its way: the microphone listens a moment longer before it stops
    // (less after a tap, which comes once the talking is done). The sound and
    // the pill answer at once. Koe 0.1 lost last words without this.
    private func finish(tail: TimeInterval? = nil) {
        guard phase == .listening, let journal else { return }
        limitTimer?.invalidate()
        play(.stop)
        let seconds = Date().timeIntervalSince(startedAt)
        phase = .transcribing
        indicator.work()
        let current = dictation
        DispatchQueue.main.asyncAfter(deadline: .now() + (tail ?? (latched ? 0.2 : 0.35))) { [weak self] in
            guard let self, self.dictation == current else { return } // cancelled meanwhile
            self.close(journal, after: seconds)
        }
    }

    private func close(_ journal: Journal, after seconds: TimeInterval) {
        let samples = recorder.stop()
        journal.saved()
        // A tap on the shortcut, not a dictation.
        guard seconds > 0.25, samples.count > 4_000 else {
            Log.note("dictation", ["tap": true])
            indicator.hide()
            journal.discard()
            self.journal = nil
            phase = .idle
            show(Pixels.ready)
            return
        }
        if Recorder.isSilent(samples) {
            indicator.hide()
            journal.discard()
            self.journal = nil
            phase = .idle
            show(Pixels.ready)
            play(.refused)
            pop(Toast.note(Words.say("NO SOUND"), Words.say("The microphone sent nothing. Check it in Settings")))
            Log.note("dictation", ["silent": true, "seconds": Int(seconds)])
            return
        }
        let current = dictation
        let origin = self.origin ?? Target.origin()
        Task { [weak self] in
            guard let self else { return }
            let text = await self.transcribe(samples)
            guard self.dictation == current else { return } // cancelled meanwhile
            guard let text else {
                // Kept in the journal: the menu offers it again.
                self.indicator.hide()
                self.journal = nil
                self.phase = .idle
                self.show(Pixels.ready)
                self.play(.refused)
                self.pop(Toast.note(Words.say("NOT TYPED"), Words.say("Saved. Retry it from the menu")))
                return
            }
            journal.transcribed(text)
            await self.deliver(text, from: origin, journal: journal)
        }
    }

    // The words, or nil if the model failed or took too long.
    private func transcribe(_ samples: [Float]) async -> String? {
        let audio = Recorder.trimmed(samples)
        let seconds = Double(audio.count) / 16_000
        // About 0.1 s for a sentence, 4 s for half an hour: far past that the
        // model is stuck, and Koe lets go (the words stay in the journal).
        let deadline = 15 + seconds / 2
        let started = Date()
        let model = transcriber
        let text = await Deadline.race(deadline) { try? await model.transcribe(audio) }
        if text == nil, Date().timeIntervalSince(started) >= deadline {
            // A stuck model would hold every dictation after this one: start afresh.
            Log.note("model", ["stuck": Int(seconds)])
            transcriber = Transcriber()
            state.modelReady = false
            prepareModel()
        }
        Log.note("transcribed", ["audio": String(format: "%.1f", seconds), "ms": Int(Date().timeIntervalSince(started) * 1000),
                                 "words": text.map { $0.split(separator: " ").count } ?? -1])
        guard let text, !text.isEmpty else { return text == nil ? nil : "" }
        return await polished(Vocabulary.correct(Fillers.strip(text)))
    }

    // MARK: - Polishing

    // The words through the polishing model when it is on and ready, within
    // 1.5 s; else as they are. The dictionary has the last word.
    private func polished(_ text: String) async -> String {
        guard state.polish, state.polishReady else { return text }
        let started = Date(), words = Vocabulary.words, polisher = self.polisher
        let answer = await Deadline.race(1.5) { await polisher.polish(text, words: words) }
        Log.note("polished", ["ms": Int(Date().timeIntervalSince(started) * 1000), "kept": answer != nil])
        return answer.map { Vocabulary.correct($0) } ?? text
    }

    // Switched on: the model comes down (1.3 GB, in the background, Koe typing
    // without it meanwhile) and loads. Switched off: out of memory.
    private func preparePolish() {
        guard state.polish else {
            state.polishReady = false
            Task { await polisher.unload() }
            return
        }
        state.polishFailed = false
        state.polishLoadFailed = false
        if PolishModel.installed { return loadPolish() }
        guard state.polishShare == nil else { return } // already coming
        state.polishShare = 0
        Task { [weak self] in
            do {
                try await PolishModel.download { share in self?.state.polishShare = share }
                self?.state.polishShare = nil
                if self?.state.polish == true { self?.loadPolish(announce: true) }
            } catch {
                self?.state.polishShare = nil
                self?.state.polishFailed = true
                Log.note("polish", ["download": "failed"])
            }
        }
    }

    // `announce`: just downloaded, the settings maybe closed long ago: say it's on.
    private func loadPolish(announce: Bool = false) {
        Task { [weak self] in
            guard let self else { return }
            let started = Date()
            do {
                try await polisher.load(PolishModel.file)
                state.polishReady = state.polish
                Log.note("polish", ["loaded_ms": Int(Date().timeIntervalSince(started) * 1000)])
                if announce, state.polishReady, phase == .idle {
                    play(.check(true))
                    pop(Toast.note(Words.say("POLISHING IS ON"), Words.say("Your words are polished before they're typed")))
                }
            } catch {
                state.polishFailed = true
                state.polishLoadFailed = true
                Log.note("polish", ["load": "failed"])
            }
        }
    }

    private func deliver(_ text: String, from origin: Target.Origin, journal: Journal) async {
        self.journal = nil
        guard !text.isEmpty else {
            indicator.hide()
            journal.discard()
            phase = .idle
            show(Pixels.ready)
            play(.refused)
            pop(Toast.note(Words.say("NOTHING HEARD"), state.howTo))
            return
        }
        let result: Paster.Result
        let koeInFront = NSApp.isActive || NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid()
        if koeInFront, let tryIt = state.tryIt {
            // The welcome's try-it box, on screen with Koe in front.
            tryIt(text)
            result = .typed
        } else if koeInFront, let field = NSApp.keyWindow?.firstResponder as? NSTextView, field.isEditable {
            // Another of Koe's own fields (the dictionary, in the settings).
            field.insertText(text + " ", replacementRange: field.selectedRange())
            result = .typed
        } else {
            // Too late to cancel: ⌘V may already be on its way.
            phase = .typing
            let verdict = Target.resolve(from: origin)
            var follows: Character?
            if let last = lastTyped, last.touches == hotkey.touches, last.pid == verdict.app?.processIdentifier { follows = last.end }
            result = await Paster.type(text, into: verdict, submit: state.submits, follows: follows)
            if case .copied = result { lastTyped = nil } else if let app = verdict.app {
                // Read after the paste: Koe's own ⌘V and Return count as keys.
                lastTyped = (app.processIdentifier, hotkey.touches, state.submits ? "\n" : text.last ?? " ")
            }
        }
        remember(text)
        journal.discard()
        phase = .idle
        Log.note("delivered", ["result": "\(result)".components(separatedBy: "(").first ?? "?"])
        switch result {
        case .typed, .probably:
            // The words showing up say it, and the check: no sound, as one
            // after every dictation would soon wear.
            indicator.done()
            show(Pixels.typed)
        case .copied(let why):
            Log.note("copied", ["why": why])
            indicator.hide()
            show(Pixels.typed)
            play(.select)
            pop(Toast.note(Words.say("COPIED"), Words.say("%1$@: “%2$@”", why, Self.opening(of: text))))
        }
        let reset = DispatchWorkItem { [weak self] in
            guard self?.phase == .idle else { return }
            self?.show(Pixels.ready)
        }
        resetFace = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: reset)
    }

    // The words' first few, for the toast: enough to know which dictation it is.
    static func opening(of text: String) -> String {
        guard text.count > 28 else { return text }
        let cut = text.prefix(28)
        let words = cut.split(separator: " ").dropLast()
        return (words.isEmpty ? String(cut) : words.joined(separator: " ")) + "…"
    }

    // Escape, or fn with another key.
    private func cancel(quietly: Bool) {
        switch phase {
        case .listening:
            limitTimer?.invalidate()
            _ = recorder.stop()
        case .transcribing:
            _ = recorder.stop() // still listening out its tail, maybe
        case .typing, .idle:
            return
        }
        dictation += 1
        indicator.hide()
        journal?.discard()
        journal = nil
        phase = .idle
        show(Pixels.ready)
        Log.note("dictation", ["cancelled": quietly ? "chord" : "escape"])
        if !quietly {
            play(.stop)
            pop(Toast.note(Words.say("CANCELLED"), Words.say("Nothing was typed")))
        }
    }

    private func phaseChanged() {
        hotkey.escapeActive = phase != .idle
        state.listening = phase == .listening
        // No App Nap while Koe has your words.
        if phase == .idle {
            if let activity { ProcessInfo.processInfo.endActivity(activity) }
            activity = nil
        } else if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Dictation")
        }
    }

    // MARK: - What a past launch left

    // Recordings a crash or a force quit interrupted: finished now, and the
    // newest words put on the clipboard. Never typed on their own.
    private func recoverLeftovers() async {
        let leftovers = Journal.leftovers().filter { $0.pid != getpid() || $0.status == .saved }
        guard !leftovers.isEmpty, phase == .idle else { return }
        var newest: String?
        for var manifest in leftovers {
            var text = manifest.text
            if text == nil {
                let audio = Journal.audio(manifest.id)
                if audio.count > 4_000, !Recorder.isSilent(audio) { text = await transcribe(audio) }
            }
            guard let text, !text.isEmpty else {
                Journal.remove(manifest.id)
                continue
            }
            manifest.status = .transcribed
            manifest.text = text
            Journal.update(manifest)
            remember(text, at: manifest.startedAt)
            if newest == nil { newest = text }
            Journal.remove(manifest.id)
        }
        Log.note("recovered", ["count": leftovers.count])
        if let newest {
            Paster.copy(newest)
            pop(Toast.note(Words.say("RECOVERED"), Words.say("Your last dictation is on the clipboard")))
        }
    }

    // MARK: - Permissions and the model

    private func checkPermissions() {
        switch Recorder.permission {
        case .authorized: state.microphone = true
        case .notDetermined: state.microphone = nil
        default: state.microphone = false
        }
        state.accessibility = AXIsProcessTrusted()
        // Rebuilt when Accessibility comes back after being revoked.
        if state.accessibility { hotkey.start() } else { hotkey.stop() }
        state.inputs = Devices.inputs()
    }

    // macOS's "would like to control this Mac" dialog, on screen.
    private static var accessibilityDialogShown: Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { ($0[kCGWindowOwnerName as String] as? String) == "universalAccessAuthWarn" }
    }

    // While you are in System Settings, Koe's windows stay out of the way:
    // they would hide the list, and the Touch ID prompt that comes with it.

    // (NSApp.hide leaves a menu bar app's windows on screen: they are taken
    // off it instead.)
    private var steppedAside: NSWindow?

    private func stepAside() {
        guard let window = [Windows.welcomeWindow, Windows.settingsWindow].compactMap({ $0 }).first(where: \.isVisible) else { return }
        steppedAside = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            if self?.steppedAside === window { window.orderOut(nil) }
        }
        watchPermissions()
    }

    // A permission just came on, or System Settings was closed: back.
    private func comeBack(gained: Bool) {
        if gained { play(.check(true)) }
        guard let window = steppedAside else { return }
        steppedAside = nil
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // Every 1.5 s until both permissions are on: no relaunch needed.
    // Every 2 s, while Koe holds the keyboard: still allowed to? Accessibility
    // switched off, or the app replaced on disk under a running Koe (a new
    // build), leaves a tap macOS no longer trusts, and the keys it hands back
    // are refused: the Mac stops answering. Koe lets go at once, and takes the
    // keyboard back when Accessibility does.
    private func guardTrust() {
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.hotkey.isRunning else { return }
                guard !AXIsProcessTrusted() || !CGPreflightPostEventAccess() else { return }
                self.hotkey.stop()
                self.state.accessibility = false
                Log.note("accessibility", ["lost": true])
                self.watchPermissions()
            }
        }
    }

    private func watchPermissions() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                let before = (self.state.microphone, self.state.accessibility)
                self.checkPermissions()
                let gained = (before.0 != true && self.state.microphone == true) || (!before.1 && self.state.accessibility)
                if gained {
                    self.comeBack(gained: true)
                } else if self.steppedAside != nil,
                          NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").isEmpty {
                    self.comeBack(gained: false)
                }
                if self.state.microphone == true, self.state.accessibility, self.steppedAside == nil {
                    timer.invalidate()
                    self.permissionTimer = nil
                }
            }
        }
    }

    private func prepareModel() {
        state.modelFailed = false
        if let directory = Model.installed {
            load(directory)
            return
        }
        state.modelShare = 0
        Task { [weak self] in
            do {
                let directory = try await Model.download { share in self?.state.modelShare = share }
                self?.state.modelShare = nil
                self?.load(directory)
            } catch {
                self?.state.modelShare = nil
                self?.state.modelFailed = true
                Log.note("model", ["download": "failed"])
            }
        }
    }

    private func load(_ directory: URL) {
        Task { [weak self] in
            guard let self else { return }
            let started = Date()
            self.state.modelPreparing = true
            defer { self.state.modelPreparing = false }
            do {
                try await transcriber.load(directory)
                self.state.modelReady = true
                Log.note("model", ["loaded_ms": Int(Date().timeIntervalSince(started) * 1000)])
                await self.recoverLeftovers()
            } catch {
                self.state.modelFailed = true
                Log.note("model", ["load": "failed"])
            }
        }
    }

    // MARK: - Updates

    private func scheduleUpdates() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForUpdate(asked: false) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            MainActor.assumeIsolated { self?.checkForUpdate(asked: false) }
        }
    }

    private func checkForUpdate(asked: Bool) {
        guard asked || Update.isOn else { return }
        let app = Bundle.main.bundleURL
        Task.detached { [weak self] in
            let latest = Update.latest()
            let newer = latest.map { Update.isNewer($0, than: Update.running) } ?? false
            let replaceable = newer && Update.canReplace(app)
            await self?.found(latest, newer: newer, replaceable: replaceable, asked: asked)
        }
    }

    private func found(_ latest: String?, newer: Bool, replaceable: Bool, asked: Bool) {
        guard let latest else {
            if asked { play(.refused); pop(Toast.note(Words.say("NO ANSWER"), Words.say("Couldn't check for updates"))) }
            return
        }
        guard newer else {
            if asked { play(.select); pop(Toast.note(Words.say("UP TO DATE"), Words.say("Koe %@ is the latest", Update.running))) }
            return
        }
        guard replaceable else {
            pop(Toast.note(Words.say("KOE %@ IS OUT", latest), Words.say("Get it from koe.fm")))
            return
        }
        install(latest)
    }

    // Never under a dictation: waits for idle, then swaps and relaunches.
    private func install(_ version: String) {
        guard phase == .idle else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in MainActor.assumeIsolated { self?.install(version) } }
            return
        }
        let app = Bundle.main.bundleURL
        Task.detached { [weak self] in
            let failure = Update.install(version, over: app)
            await self?.installed(version, failure: failure)
        }
    }

    private func installed(_ version: String, failure: String?) {
        if let failure {
            Log.note("update", ["failed": failure])
            return
        }
        Log.note("update", ["to": version])
        relaunch()
    }

    private func relaunch() {
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.1; done; exec /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? relaunch.run()
        NSApp.terminate(nil)
    }

    // MARK: - The menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = NSMenuItem(title: statusLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        if state.modelFailed { menu.addItem(entry(Words.say("Try Again"), #selector(retryModel))) }
        if state.microphone != true || !state.accessibility {
            menu.addItem(entry(Words.say("Finish Setting Up…"), #selector(openWelcome)))
        }
        if !Journal.leftovers().filter({ $0.status != .recording || $0.pid != getpid() }).isEmpty, phase == .idle {
            menu.addItem(entry(Words.say("Retry the Unfinished Dictation"), #selector(retryLeftovers)))
        }

        let dictations = recent
        if !dictations.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: Words.say("Recent · click to copy"), action: nil, keyEquivalent: "")
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
        menu.addItem(entry(Words.say("Settings…"), #selector(openSettings), key: ","))
        menu.addItem(entry(Words.say("Check for Updates…"), #selector(checkUpdatesNow)))
        menu.addItem(entry(Words.say("About Koe"), #selector(openSite)))
        menu.addItem(.separator())
        menu.addItem(entry(Words.say("Quit Koe"), #selector(quit), key: "q"))
    }

    private var statusLine: String {
        if state.modelFailed { return Words.say("The voice model didn't download") }
        if let share = state.modelShare { return Words.say("Getting the voice model… %@", Words.percent(Int(share * 100))) }
        if !state.modelReady { return Words.say("Waking the voice model…") }
        if state.microphone == false { return Words.say("Microphone off: allow it in Settings") }
        if !state.accessibility { return Words.say("Accessibility off: allow it in Settings") }
        switch phase {
        case .listening: return Words.say("Listening…")
        case .transcribing, .typing: return Words.say("Typing…")
        case .idle: return state.howTo
        }
    }

    private func entry(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

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
        pop(Toast.note(Words.say("COPIED"), Words.say("Paste it anywhere with ⌘V")))
    }

    @objc private func openSettings() {
        state.inputs = Devices.inputs()
        state.login = SMAppService.mainApp.status == .enabled
        Windows.showSettings(state)
    }

    @objc private func openWelcome() { Windows.showWelcome(state) }
    @objc private func retryModel() { prepareModel() }
    @objc private func retryLeftovers() { Task { await recoverLeftovers() } }
    @objc private func checkUpdatesNow() { checkForUpdate(asked: true) }
    @objc private func openSite() { NSWorkspace.shared.open(URL(string: "https://koe.fm")!) }
    @objc private func quit() { NSApp.terminate(nil) }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            play(.check(on))
        } catch {
            play(.refused)
        }
        state.login = SMAppService.mainApp.status == .enabled
    }

    private func copyReport() {
        let report = Log.report([
            "shortcut": state.shortcut.kind.rawValue,
            "mode": state.shortcut.forcesToggle ? "toggle" : "hold or tap",
            "microphone permission": "\(state.microphone.map { $0 ? "on" : "off" } ?? "not asked")",
            "accessibility": state.accessibility ? "on" : "off",
            "keyboard listener": hotkey.isRunning ? "running" : "stopped",
            "model": state.modelReady ? "ready" : state.modelFailed ? "failed" : "loading",
            "chosen microphone": state.input == nil ? "default" : "a specific one",
            "return after typing": state.submits ? "on" : "off",
        ])
        Paster.copy(report)
        play(.select)
        pop(Toast.note(Words.say("REPORT COPIED"), Words.say("No dictated text is in it")))
    }

    // MARK: - Recent dictations

    private struct Dictation: Codable {
        let text: String
        let at: Date
    }

    private var recent: [Dictation] {
        get {
            guard state.keepsRecent, let data = UserDefaults.standard.data(forKey: "recent") else { return [] }
            return (try? JSONDecoder().decode([Dictation].self, from: data)) ?? []
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(Array(newValue.prefix(5))), forKey: "recent") }
    }

    private func remember(_ text: String, at date: Date = Date()) {
        state.lastText = text
        guard state.keepsRecent else { return }
        recent = ([Dictation(text: text, at: date)] + recent).sorted { $0.at > $1.at }
    }

    // MARK: - Looks and sounds

    // The bubble in the menu bar, in the menu bar's ink: 3 device pixels a cell.
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
        guard !state.muted else { return }
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
}

#if KOE_EVAL
// The eval doors' ears. Delivered at once even while Koe is in the
// background, where macOS otherwise holds distributed notifications back.
final class EvalDoor: NSObject {
    private let act: @MainActor (String, String?) -> Void

    init(_ names: [String], act: @escaping @MainActor (String, String?) -> Void) {
        self.act = act
        super.init()
        for name in names {
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(heard(_:)), name: Notification.Name("fm.koe.mac.eval.\(name)"),
                                                                object: nil, suspensionBehavior: .deliverImmediately)
        }
        // AppKit suspends the center whenever Koe is not the active app.
        DistributedNotificationCenter.default().suspended = false
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            DistributedNotificationCenter.default().suspended = false
        }
    }

    @objc private func heard(_ note: Notification) {
        let name = String(note.name.rawValue.dropFirst("fm.koe.mac.eval.".count)), object = note.object as? String
        DispatchQueue.main.async { MainActor.assumeIsolated { self.act(name, object) } }
    }
}
#endif
