import AppKit
import SwiftUI

// Koe's two windows: the welcome, shown on first launch until Koe is ready
// and you have typed your first words with it, and the settings. Both follow
// the brand: Silkscreen titles, the rounded sans, the bubble in candy.
@MainActor
enum Windows {
    private static var welcome: NSWindow?
    private static var settings: NSWindow?

    static func showWelcome(_ state: KoeState) {
        if welcome == nil {
            welcome = window(Welcome(state: state), title: Words.say("Welcome to Koe"), size: NSSize(width: 460, height: 560))
        }
        present(welcome!)
    }

    static func closeWelcome() {
        welcome?.close()
        welcome = nil
    }

    static func showSettings(_ state: KoeState) {
        if settings == nil {
            settings = window(SettingsView(state: state), title: Words.say("Koe Settings"), size: NSSize(width: 480, height: 640))
        }
        present(settings!)
    }

    static var welcomeWindow: NSWindow? { welcome }
    static var settingsWindow: NSWindow? { settings }

    private static func window<V: View>(_ view: V, title: String, size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = title
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.center()
        return window
    }

    private static func present(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Pieces

enum Brand {
    static let gradient = LinearGradient(colors: [Color(cg: Pixels.candy[0]), Color(cg: Pixels.candy[1]), Color(cg: Pixels.candy[2])],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
    static let ink = Color(cg: Pixels.ink)

    static func title(_ text: String, size: CGFloat = 16) -> some View {
        Text(text.uppercased())
            .font(.custom("Silkscreen", size: size))
            .tracking(-size / 8)
    }

    static func body(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension Color {
    init(cg: CGColor) { self.init(nsColor: NSColor(cgColor: cg) ?? .black) }
}

// The bubble with its face, as on the icon.
struct BubbleIcon: View {
    var size: CGFloat = 96
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.236, style: .continuous)
            .fill(Brand.gradient)
            .frame(width: size, height: size)
            .overlay(Image(nsImage: BubbleIcon.face).interpolation(.none).resizable().frame(width: size * 0.77, height: size * 0.77))
            .shadow(color: Color(cg: Pixels.glow).opacity(0.35), radius: size * 0.12, y: size * 0.04)
    }

    static let face: NSImage = {
        let rows = [
            ".....................", ".....................", ".....................", ".....................",
            ".......#######.......", ".....##ooooooo##.....", "....#ooooooooooo#....", "....#ooooooooooo#....",
            "...#ooo#ooooo#ooo#...", "...#oo#o#ooo#o#oo#...", "...#ooooooooooooo#...", "...#opoo#####oopo#...",
            "...#oooo#ppp#oooo#...", "....#oooo###ooooo#...", "....#oooooooooooo#...", ".....##oooooooooo#...",
            ".......###########...", ".....................", ".....................", ".....................", ".....................",
        ]
        let context = CGContext(data: nil, width: 21, height: 21, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for (y, row) in rows.enumerated() {
            for (x, cell) in row.enumerated() {
                let color: CGColor? = cell == "#" ? Pixels.ink : cell == "o" ? Pixels.butter : cell == "p" ? Pixels.blush : nil
                guard let color else { continue }
                context.setFillColor(color)
                context.fill(CGRect(x: x, y: 20 - y, width: 1, height: 1))
            }
        }
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: 21, height: 21))
    }()
}

struct PillButton: View {
    let title: String
    var prominent = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Brand.body(13, weight: .semibold))
                .padding(.horizontal, 18).padding(.vertical, 8)
                .foregroundStyle(prominent ? Brand.ink : .primary)
                .background(prominent ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.secondary.opacity(0.15)), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct StepRow: View {
    let done: Bool
    // The step to do now gets the candy button; the others wait in gray.
    var next = true
    let title: String
    let detail: String
    var button: String?
    var action: () -> Void = {}
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(done ? Color(cg: Pixels.candy[0]) : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Brand.body(14, weight: .semibold))
                Text(detail).font(Brand.body(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !done, let button { PillButton(title: button, prominent: next, action: action) }
        }
    }
}

// Progress in the brand's gradient.
struct CandyBar: View {
    let share: Double
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule().fill(Brand.gradient).frame(width: max(8, geometry.size.width * share))
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel(Words.say("Download"))
        .accessibilityValue(Words.percent(Int(share * 100)))
    }
}

// A key, drawn as a keycap.
struct Keycap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Brand.body(13, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Welcome

struct Welcome: View {
    @ObservedObject var state: KoeState
    @State private var step: Int
    @State private var practice: String
    @FocusState private var practiceFocused: Bool

    init(state: KoeState, step: Int = 0, practice: String = "") {
        self.state = state
        _step = State(initialValue: step)
        _practice = State(initialValue: practice)
    }

    private var permissionsDone: Bool { state.microphone == true && state.accessibility }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: hello
                case 1: permissions
                default: tryIt
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 36)
            .padding(.top, 36)
            dots.padding(.bottom, 20)
        }
        .frame(width: 460, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: step)
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Circle().fill(index == step ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.secondary.opacity(0.3)))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }

    private var hello: some View {
        VStack(spacing: 18) {
            Spacer()
            BubbleIcon(size: 112)
            Brand.title(Words.say("Hi, I'm Koe"), size: 24)
            Text(Words.say("Talk. It types."))
                .font(Brand.body(20, weight: .semibold))
            Text(Words.say("Hold a key, say what you want to write, let go: your words land where your cursor is. Everything stays on this Mac."))
                .font(Brand.body(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            PillButton(title: Words.say("Set Up Koe")) { step = 1 }
                .keyboardShortcut(.defaultAction)
            Spacer().frame(height: 12)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 22) {
            Brand.title(Words.say("Get Koe ready"), size: 16)
            Text(Words.say("Koe only listens while you hold your shortcut, and only types where you ask."))
                .font(Brand.body(14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            // First, as it comes down while the two switches are flipped.
            modelRow
            StepRow(done: state.microphone == true, next: true, title: Words.say("Microphone"),
                    detail: state.microphone == false
                        ? Words.say("Turned off. Turn Koe on in Privacy & Security › Microphone.")
                        : Words.say("To hear you."),
                    button: state.microphone == false ? Words.say("Open Settings") : Words.say("Allow")) {
                state.microphone == false ? state.openMicrophoneSettings() : state.askMicrophone()
            }
            StepRow(done: state.accessibility, next: state.microphone == true, title: Words.say("Accessibility"),
                    detail: state.accessibility
                        ? Words.say("Koe hears your shortcut in every app.")
                        : Words.say("To hear your shortcut from any app, and to type the words for you. Turn Koe on in the list that opens."),
                    button: Words.say("Open Settings")) { state.openAccessibility() }
            Spacer()
            HStack {
                Spacer()
                PillButton(title: Words.say("Continue"), prominent: permissionsDone) { step = 2 }
                    .disabled(!permissionsDone)
                    .opacity(permissionsDone ? 1 : 0.5)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 8)
        }
    }

    private var modelRow: some View {
        let detail: String
        if state.modelFailed {
            detail = Words.say("The download stopped. Check your connection.")
        } else if let share = state.modelShare {
            detail = Words.say("So Koe hears you on this Mac, never online.") + " "
                + Words.say("Downloading once (630 MB): %@. You can go on meanwhile.", Words.percent(Int(share * 100)))
        } else if state.modelReady {
            detail = Words.say("Ready, on this Mac. Works offline.")
        } else {
            detail = Words.say("Getting ready…")
        }
        return VStack(alignment: .leading, spacing: 8) {
            StepRow(done: state.modelReady, title: Words.say("Voice model"), detail: detail,
                    button: state.modelFailed ? Words.say("Try Again") : nil) { state.retryModel() }
            if let share = state.modelShare {
                CandyBar(share: share).padding(.leading, 30)
            }
        }
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 18) {
            Brand.title(Words.say("Try it"), size: 16)
            HStack(spacing: 6) {
                Text(state.effectiveToggles ? Words.say("Click in the box, press") : Words.say("Click in the box, hold"))
                Keycap(text: state.shortcut.label)
                Text(state.effectiveToggles ? Words.say("say hello, press it again.") : Words.say("and say hello, then let go."))
            }
            .font(Brand.body(14))
            TextEditor(text: $practice)
                .font(Brand.body(15))
                .focused($practiceFocused)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(height: 140)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(state.listening ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.secondary.opacity(0.25)),
                                                                   lineWidth: state.listening ? 2 : 1))
            if !state.modelReady {
                Text(Words.say("The voice model is still getting ready…")).font(Brand.body(12)).foregroundStyle(.secondary)
            } else if practice.isEmpty {
                Text(state.listening ? Words.say("Listening…") : Words.say("Your words will appear here."))
                    .font(Brand.body(12)).foregroundStyle(.secondary)
            } else {
                Text(Words.say("That's it. Koe works the same in any app."))
                    .font(Brand.body(13, weight: .semibold))
            }
            Text(Words.say("Koe lives in the menu bar, up there: the little bubble. Click it for your last dictations and settings."))
                .font(Brand.body(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
            HStack {
                Button(Words.say("Change the Shortcut…")) { state.finishWelcome(); Windows.closeWelcome(); NotificationCenter.default.post(name: .koeShowSettings, object: nil) }
                    .buttonStyle(.link)
                Spacer()
                PillButton(title: practice.isEmpty ? Words.say("Skip") : Words.say("Done"), prominent: !practice.isEmpty) {
                    state.finishWelcome()
                    Windows.closeWelcome()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 8)
        }
        .onAppear {
            // The box must be where the words go, even when the step was
            // reached with Koe in the background.
            NSApp.activate(ignoringOtherApps: true)
            Windows.welcomeWindow?.makeKeyAndOrderFront(nil)
            practiceFocused = true
            state.tryIt = { text in
                practice += (practice.isEmpty || practice.hasSuffix(" ") ? "" : " ") + text + " "
                practiceFocused = true
            }
        }
        .onDisappear { state.tryIt = nil }
    }
}

extension Notification.Name {
    static let koeShowSettings = Notification.Name("koeShowSettings")
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var state: KoeState
    @State private var newWord = ""

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    BubbleIcon(size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Brand.title("Koe", size: 16)
                        Text(state.howTo).font(Brand.body(12)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if state.microphone != true || !state.accessibility {
                Section(Words.say("Permissions")) {
                    if state.microphone != true {
                        LabeledContent(Words.say("Microphone")) {
                            Button(state.microphone == false ? Words.say("Open Settings") : Words.say("Allow")) {
                                state.microphone == false ? state.openMicrophoneSettings() : state.askMicrophone()
                            }
                        }
                    }
                    if !state.accessibility {
                        LabeledContent(Words.say("Accessibility")) {
                            Button(Words.say("Open Settings")) { state.openAccessibility() }
                        }
                    }
                }
            }

            Section(Words.say("Shortcut")) {
                LabeledContent(Words.say("Start Koe with")) {
                    Button {
                        state.capturing ? state.cancelCapture() : state.startCapture()
                    } label: {
                        Text(state.capturing ? Words.say("Press your shortcut…") : state.shortcut.label)
                            .font(Brand.body(13, weight: .semibold))
                            .frame(minWidth: 120)
                    }
                }
                if state.capturing {
                    Text(Words.say("fn, a modifier on its own (like right ⌥), or a combination like ⌃⌥Space. Escape cancels."))
                        .font(Brand.body(11)).foregroundStyle(.secondary)
                }
                if let error = state.captureError {
                    Text(error).font(Brand.body(11)).foregroundStyle(.red)
                }
                Picker(Words.say("Mode"), selection: Binding(get: { state.effectiveToggles }, set: { state.toggles = $0 })) {
                    Text(Words.say("Hold to talk")).tag(false)
                    Text(Words.say("Press to start and stop")).tag(true)
                }
                .disabled(state.shortcut.forcesToggle)
                if state.shortcut.forcesToggle {
                    Text(Words.say("A modifier on its own starts and stops Koe when you release it."))
                        .font(Brand.body(11)).foregroundStyle(.secondary)
                }
                if state.shortcut.kind == .fn, let use = Shortcut.globeUse {
                    Text(Words.say("On its own, macOS would %@ with 🌐. While it is Koe's shortcut, Koe keeps that from happening.", use))
                        .font(Brand.body(11)).foregroundStyle(.secondary)
                }
            }

            Section(Words.say("Microphone")) {
                Picker(Words.say("Listen with"), selection: $state.input) {
                    Text(Words.say("System Default (%@)", Devices.defaultName() ?? "—")).tag(String?.none)
                    ForEach(state.inputs, id: \.uid) { input in Text(input.name).tag(Optional(input.uid)) }
                    if let chosen = state.input, !state.inputs.contains(where: { $0.uid == chosen }) {
                        Text(Words.say("Unplugged microphone")).tag(Optional(chosen))
                    }
                }
            }

            Section(Words.say("Typing")) {
                Toggle(Words.say("Press Return after typing"), isOn: $state.submits)
                Text(Words.say("Sends the message in chats and terminals. Koe never presses Return if the words did not arrive."))
                    .font(Brand.body(11)).foregroundStyle(.secondary)
                Toggle(Words.say("Keep my last dictations in the menu"), isOn: $state.keepsRecent)
            }

            Section(Words.say("Dictionary")) {
                Text(Words.say("Names and words Koe should spell your way."))
                    .font(Brand.body(11)).foregroundStyle(.secondary)
                ForEach(state.words, id: \.self) { word in
                    HStack {
                        Text(word)
                        Spacer()
                        Button { state.words.removeAll { $0 == word } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Words.say("Remove %@", word))
                    }
                }
                HStack {
                    TextField(Words.say("Add a word"), text: $newWord)
                        .onSubmit(add)
                    Button(Words.say("Add"), action: add).disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Koe") {
                Toggle(Words.say("Sounds"), isOn: Binding(get: { !state.muted }, set: { state.muted = !$0 }))
                Toggle(Words.say("Open at Login"), isOn: Binding(get: { state.login }, set: { state.setLogin($0) }))
                Toggle(Words.say("Update Automatically"), isOn: $state.updates)
                LabeledContent(Words.say("Something wrong?")) {
                    Button(Words.say("Copy Diagnostic Report")) { state.copyReport() }
                }
            }
        }
        .formStyle(.grouped)
        .tint(Color(cg: Pixels.candy[0]))
        .frame(width: 480, height: 640)
        .onChange(of: state.toggles) { state.save() }
        .onChange(of: state.submits) { state.save() }
        .onChange(of: state.keepsRecent) { state.save() }
        .onChange(of: state.muted) { state.save() }
        .onChange(of: state.updates) { state.save() }
        .onChange(of: state.input) { state.save() }
        .onChange(of: state.words) { state.save() }
    }

    private func add() {
        let word = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, !state.words.contains(word) else { return }
        state.words.append(word)
        newWord = ""
    }
}
