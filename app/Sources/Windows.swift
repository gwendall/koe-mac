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
        thinScrollers(in: window)
        return window
    }

    // The thin scroller that shows only while scrolling, even on a Mac set to
    // always show them: the wide one ate the settings' right edge. Again
    // whenever the Mac's choice changes, as AppKit puts its own back.
    private static func thinScrollers(in window: NSWindow) {
        weak var window = window
        func apply() {
            var views = window?.contentView.map { [$0] } ?? []
            while let view = views.popLast() {
                if let scroll = view as? NSScrollView {
                    scroll.scrollerStyle = .overlay
                    scroll.autohidesScrollers = true
                }
                views += view.subviews
            }
        }
        // The form's scroll view comes with SwiftUI's first layout.
        DispatchQueue.main.async { apply() }
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { apply() }
        }
        NotificationCenter.default.addObserver(forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { DispatchQueue.main.async { apply() } }
        }
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
// Progress in the brand's gradient; without a share, a stretch of it that
// runs back and forth (work under way, of no known length).
struct CandyBar: View {
    let share: Double?
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                if let share {
                    Capsule().fill(Brand.gradient).frame(width: max(8, geometry.size.width * share))
                } else {
                    TimelineView(.animation) { context in
                        let phase = (sin(context.date.timeIntervalSinceReferenceDate * 2.2) + 1) / 2
                        let width = geometry.size.width * 0.28
                        Capsule().fill(Brand.gradient).frame(width: width)
                            .offset(x: (geometry.size.width - width) * phase)
                    }
                }
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel(Words.say("Download"))
        .accessibilityValue(share.map { Words.percent(Int($0 * 100)) } ?? "")
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
    @State private var cheered = false
    // Whether the shortcut ever reached Koe on Try it, and if ten seconds went by without.
    @State private var heard = false
    @State private var silent = false

    init(state: KoeState, step: Int = 0, practice: String = "") {
        self.state = state
        _step = State(initialValue: step)
        _practice = State(initialValue: practice)
        _cheered = State(initialValue: !practice.isEmpty)
    }

    private var permissionsDone: Bool { state.microphone == true && state.accessibility }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: hello
                case 1: permissions
                case 2: tryIt
                default: allSet
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
            ForEach(0..<4) { index in
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
                .padding(.bottom, 10)
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
        } else if state.modelPreparing {
            detail = Words.say("Preparing it for this Mac's Neural Engine: the first time only, it can take a minute.")
        } else {
            detail = Words.say("Getting ready…")
        }
        return VStack(alignment: .leading, spacing: 8) {
            StepRow(done: state.modelReady, title: Words.say("Voice model"), detail: detail,
                    button: state.modelFailed ? Words.say("Try Again") : nil) { state.retryModel() }
            if let share = state.modelShare {
                CandyBar(share: share).padding(.leading, 30)
            } else if state.modelPreparing {
                CandyBar(share: nil).padding(.leading, 30)
            }
        }
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 18) {
            Brand.title(Words.say("Try it"), size: 16)
            HStack(spacing: 6) {
                Text(state.shortcut.forcesToggle ? Words.say("Click in the box, press") : Words.say("Click in the box, hold"))
                Keycap(text: state.shortcut.label)
                Text(state.shortcut.forcesToggle ? Words.say("say hello, press it again.") : Words.say("and say hello, then let go."))
            }
            .font(Brand.body(14))
            if let rival = state.unsettled.first {
                SharedFn(rival: rival, keep: state.keepFn, switchKey: state.useRightOption)
            }
            TextEditor(text: $practice)
                .font(Brand.body(15))
                .focused($practiceFocused)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(height: 140)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(state.listening || !practice.isEmpty ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.secondary.opacity(0.25)),
                                                                   lineWidth: state.listening || !practice.isEmpty ? 2 : 1))
            if !state.modelReady {
                Text(Words.say("The voice model is still getting ready…")).font(Brand.body(12)).foregroundStyle(.secondary)
            } else if practice.isEmpty && !state.listening && silent {
                // Ten seconds and the shortcut never reached Koe: something else may take it first.
                Text(Words.say("Nothing when you press %@? Another app may take it first: give Koe another key below.", state.shortcut.label))
                    .font(Brand.body(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if practice.isEmpty {
                Text(state.listening ? Words.say("Listening…") : Words.say("Your words will appear here."))
                    .font(Brand.body(12)).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color(cg: Pixels.candy[0]))
                        .scaleEffect(cheered ? 1 : 0.3)
                    Text(Words.say("That's it. Koe works the same in any app."))
                        .font(Brand.body(13, weight: .semibold))
                }
            }
            Text(Words.say("Koe lives in the menu bar, up there: the little bubble. Click it for your last dictations and settings."))
                .font(Brand.body(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
            HStack {
                Button(Words.say("Change the Shortcut…")) { state.finishWelcome(); Windows.closeWelcome(); NotificationCenter.default.post(name: .koeShowSettings, object: nil) }
                    .buttonStyle(.link)
                Spacer()
                PillButton(title: practice.isEmpty ? Words.say("Skip") : Words.say("Continue"), prominent: !practice.isEmpty) {
                    if practice.isEmpty {
                        state.finishWelcome()
                        Windows.closeWelcome()
                    } else {
                        step = 3
                    }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { if !heard { silent = true } }
            state.tryIt = { text in
                practice += (practice.isEmpty || practice.hasSuffix(" ") ? "" : " ") + text + " "
                practiceFocused = true
            }
        }
        .onDisappear { state.tryIt = nil }
        .onChange(of: state.listening) { _, listening in
            if listening {
                heard = true
                silent = false
            }
        }
        // The first words in the box: a check, right here, to read them by.
        // The finale waits for Continue.
        .onChange(of: practice.isEmpty) { _, empty in
            guard !empty, !cheered else { return }
            state.cheer()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { cheered = true }
        }
    }

    // The end: the bubble jumps for joy in a burst of pixels, up the chord.
    private var allSet: some View {
        AllSet(state: state) {
            state.finishWelcome()
            Windows.closeWelcome()
        }
    }
}

struct AllSet: View {
    @ObservedObject var state: KoeState
    let done: () -> Void
    @State private var since = Date()
    @State private var landed = false
    private var still: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    var body: some View {
        ZStack {
            if !still { Confetti(since: since) }
            VStack(spacing: 18) {
                Spacer()
                BubbleIcon(size: 120)
                    .scaleEffect(landed ? 1 : 0.4)
                    .rotationEffect(.degrees(landed ? 0 : -14))
                    .offset(y: landed ? 0 : 30)
                Brand.title(Words.say("You're all set"), size: 24)
                Text(Words.say("Koe waits in your menu bar, ready wherever you type."))
                    .font(Brand.body(15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(state.howTo)
                    .font(Brand.body(14, weight: .semibold))
                    .multilineTextAlignment(.center)
                Spacer()
                PillButton(title: Words.say("Start Using Koe"), action: done)
                    .keyboardShortcut(.defaultAction)
                Spacer().frame(height: 12)
            }
        }
        .onAppear {
            since = Date()
            state.celebrate()
            withAnimation(still ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.45)) { landed = true }
        }
    }
}

// A burst of pixel confetti in Koe's colors, thrown up from behind the
// bubble and falling away in a little over two seconds.
struct Confetti: View {
    let since: Date
    private static let colors: [Color] = (Pixels.candy + [Pixels.butter, Pixels.blush]).map { Color(cg: $0) }
    private struct Bit { let angle, speed, spin, size: Double; let color: Int }
    private static let bits: [Bit] = {
        var seed: UInt64 = 0x4B4F45
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(1 << 31)
        }
        return (0..<70).map { _ in
            Bit(angle: -.pi / 2 + (next() - 0.5) * 2.2, speed: 260 + next() * 320, spin: (next() - 0.5) * 12,
                size: next() < 0.5 ? 6 : 9, color: Int(next() * 5) % 5)
        }
    }()

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(since)
            Canvas { canvas, size in
                guard t < 2.6 else { return }
                let origin = CGPoint(x: size.width / 2, y: size.height * 0.36)
                for bit in Self.bits {
                    let x = origin.x + cos(bit.angle) * bit.speed * t
                    let y = origin.y + sin(bit.angle) * bit.speed * t + 520 * t * t
                    var square = canvas
                    square.opacity = max(0, 1 - t / 2.6)
                    square.translateBy(x: x, y: y)
                    square.rotate(by: .radians(bit.spin * t))
                    square.fill(Path(CGRect(x: -bit.size / 2, y: -bit.size / 2, width: bit.size, height: bit.size)),
                                with: .color(Self.colors[bit.color]))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension Notification.Name {
    static let koeShowSettings = Notification.Name("koeShowSettings")
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var state: KoeState
    // Taller only to draw the whole form at once (`--render-journey`).
    var height: CGFloat = 640
    @State private var newWord = ""

    var body: some View {
        ZStack(alignment: .top) {
            form
            // The title bar is see-through: what scrolls under it fades out
            // instead of running into the title.
            LinearGradient(stops: [.init(color: Color(nsColor: .windowBackgroundColor), location: 0),
                                   .init(color: Color(nsColor: .windowBackgroundColor), location: 0.55),
                                   .init(color: Color(nsColor: .windowBackgroundColor).opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 52)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
        .frame(width: 480, height: height)
    }

    private var form: some View {
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
                            .frame(minWidth: 36)
                    }
                }
                if state.capturing {
                    Text(Words.say("fn, a modifier on its own (like right ⌥), or a combination like ⌃⌥Space. Escape cancels."))
                        .font(Brand.body(11)).foregroundStyle(.secondary)
                }
                if let error = state.captureError {
                    Text(error).font(Brand.body(11)).foregroundStyle(.red)
                }
                Text(state.howTo).font(Brand.body(11)).foregroundStyle(.secondary)
                if state.shortcut.forcesToggle {
                    Text(Words.say("A modifier on its own starts and stops Koe when you release it."))
                        .font(Brand.body(11)).foregroundStyle(.secondary)
                }
                if state.shortcut.kind == .fn, let rival = state.rivals.first {
                    HStack {
                        Text(Words.say("%@ is open and may use fn too: both would start at once.", rival))
                            .font(Brand.body(11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(Words.say("Use %@", Shortcut.rightOption.label)) { state.useRightOption() }
                    }
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
                Toggle(isOn: $state.submits) {
                    Explained(Words.say("Press Return after typing"),
                              Words.say("Sends the message in chats and terminals. Koe never presses Return if the words did not arrive."))
                }
                Toggle(Words.say("Keep my last dictations in the menu"), isOn: $state.keepsRecent)
                Toggle(isOn: $state.polish) { Explained(Words.say("Polish the words"), polishDetail) }
                if state.polish, let share = state.polishShare {
                    CandyBar(share: share)
                } else if state.polish, !state.polishReady, !state.polishFailed {
                    CandyBar(share: nil)
                }
                if state.polish, state.polishFailed {
                    Button(Words.say("Try Again")) { state.polishChanged() }
                }
            }

            Section(Words.say("Dictionary")) {
                Text(Words.say("Names and words Koe should spell your way."))
                    .font(Brand.body(11)).foregroundStyle(.secondary)
                if !state.words.isEmpty {
                    Tags(words: state.words) { word in state.words.removeAll { $0 == word } }
                }
                // A field that looks like one: a form's TextField shows its
                // title as a label and the box itself barely at all.
                HStack(spacing: 8) {
                    TextField("", text: $newWord, prompt: Text(Words.say("Add a word")))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button(Words.say("Add"), action: add)
                        .keyboardShortcut(.defaultAction)
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Koe") {
                Picker(Words.say("Pill while you talk"), selection: $state.place) {
                    ForEach(Indicator.Place.allCases) { place in Text(place.name).tag(place) }
                }
                Toggle(Words.say("Sounds"), isOn: Binding(get: { !state.muted }, set: { state.muted = !$0 }))
                Toggle(Words.say("Open at Login"), isOn: Binding(get: { state.login }, set: { state.setLogin($0) }))
                Toggle(Words.say("Update Automatically"), isOn: $state.updates)
                LabeledContent(Words.say("Something wrong?")) {
                    Button(Words.say("Copy Diagnostic Report")) { state.copyReport() }
                }
            }

            Section(Words.say("How Koe works")) {
                FactRow(icon: Facts.chip, title: Words.say("It hears you on this Mac"),
                        detail: Words.say("Parakeet Ultra, an open-weight model built on NVIDIA's Parakeet, runs on your chip's Neural Engine."))
                FactRow(icon: Facts.bolt, title: Words.say("In a tenth of a second"),
                        detail: Words.say("No round trip to a server: a sentence is typed the moment you let go."))
                FactRow(icon: Facts.lock, title: Words.say("Nothing leaves your Mac"),
                        detail: Words.say("No account, no server, works offline. Your voice is never sent anywhere."))
                FactRow(icon: Facts.globe, title: Words.say("25 languages"),
                        detail: Words.say("It finds yours on its own, even when you switch mid-dictation."))
                FactRow(icon: Facts.sparkle, title: Words.say("Polished, if you like"),
                        detail: Words.say("Turn on Polish the words, under Typing: Qwen3.5 2B, a small open model, tidies your words on this Mac in about a tenth of a second."))
                FactRow(icon: Facts.book, title: Words.say("Your words"),
                        detail: Words.say("Add names and jargon to the dictionary, and Koe spells them your way."))
                Text(Words.say("Parakeet Ultra by moondream, from NVIDIA Parakeet TDT 0.6B v3. Core ML by FluidInference. CC BY 4.0.")
                     + " " + Words.say("Polishing: Qwen3.5 2B by the Qwen team (Apache 2.0), through llama.cpp (MIT)."))
                    .font(Brand.body(10)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .tint(Color(cg: Pixels.candy[0]))
        .onChange(of: state.submits) { state.save() }
        .onChange(of: state.polish) {
            state.save()
            state.polishChanged()
        }
        .onChange(of: state.keepsRecent) { state.save() }
        .onChange(of: state.muted) { state.save() }
        .onChange(of: state.place) {
            state.save()
            state.showPill()
        }
        .onChange(of: state.updates) { state.save() }
        .onChange(of: state.input) { state.save() }
        .onChange(of: state.words) { state.save() }
    }

    private var polishDetail: String {
        guard state.polish else {
            return Words.say("A small language model on this Mac takes out repeats and corrections, spells your dictionary words and fixes punctuation. 1.3 GB, downloaded once; it adds about a tenth of a second.")
        }
        if state.polishLoadFailed { return Words.say("Couldn't start the model on this Mac. Try again.") }
        if state.polishFailed { return Words.say("The download stopped. Check your connection.") }
        if let share = state.polishShare {
            return Words.say("Downloading once (1.3 GB): %@. Koe types without it meanwhile.", Words.percent(Int(share * 100)))
        }
        if state.polishReady { return Words.say("On, on this Mac: your words are polished before they're typed.") }
        return Words.say("Getting ready…")
    }

    private func add() {
        let word = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, !state.words.contains(word) else { return }
        state.words.append(word)
        newWord = ""
    }
}

// One thing that makes Koe what it is, with its pixel icon.
struct FactRow: View {
    let icon: NSImage
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: icon).interpolation(.none).resizable().frame(width: 18, height: 18).padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Brand.body(13, weight: .semibold))
                Text(detail).font(Brand.body(11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

// The settings' pixel icons, 9 by 9, in bubblegum.
enum Facts {
    static let chip = icon(["..#.#.#..", ".#######.", "##.....##", ".#.###.#.", "##.###.##", ".#.###.#.", "##.....##", ".#######.", "..#.#.#.."])
    static let bolt = icon(["....###..", "...###...", "..###....", ".#######.", "....###..", "...###...", "..###....", ".##......", "........."])
    static let lock = icon(["...###...", "..#...#..", "..#...#..", ".#######.", ".#######.", ".###.###.", ".###.###.", ".#######.", "........."])
    static let globe = icon(["..#####..", ".#..#..#.", "#..#.#..#", "#########", "#..#.#..#", "#########", "#..#.#..#", ".#..#..#.", "..#####.."])
    static let sparkle = icon(["....#....", "....#....", "...###...", "..#####..", "#########", "..#####..", "...###...", "....#....", "....#...."])
    static let book = icon([".###.###.", "#...#...#", "#.#.#.#.#", "#...#...#", "#.#.#.#.#", "#...#...#", "#########", ".........", "........."])

    private static func icon(_ rows: [String]) -> NSImage {
        let image = Pixels.image(rows, color: Pixels.candy[0])
        return image.map { NSImage(cgImage: $0, size: NSSize(width: 9, height: 9)) } ?? NSImage()
    }
}

// fn is shared: another app may start on it too. Koe asks once, both
// answers side by side.
struct SharedFn: View {
    let rival: String
    let keep: () -> Void
    let switchKey: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color(cg: Pixels.candy[0]))
                VStack(alignment: .leading, spacing: 2) {
                    Text(Words.say("%@ also uses fn", rival)).font(Brand.body(13, weight: .semibold))
                    Text(Words.say("Both would start at once. Keep fn for Koe, or give Koe another key."))
                        .font(Brand.body(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Spacer()
                PillButton(title: Words.say("Keep fn"), prominent: false, action: keep)
                PillButton(title: Words.say("Use %@", Shortcut.rightOption.label), prominent: false, action: switchKey)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
    }
}

// A setting's name with its explanation under it, in the same row as its
// switch, so the two read as one.
struct Explained: View {
    let title: String, detail: String
    init(_ title: String, _ detail: String) { self.title = title; self.detail = detail }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
            Text(detail).font(Brand.body(11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// The dictionary's words as tags that wrap, each with its own ✕.
struct Tags: View {
    let words: [String]
    let remove: (String) -> Void

    var body: some View {
        Flow(spacing: 6) {
            ForEach(words, id: \.self) { word in
                HStack(spacing: 4) {
                    Text(word).font(Brand.body(12))
                    Button { remove(word) } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Words.say("Remove %@", word))
                }
                .padding(.leading, 9).padding(.trailing, 7).padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
        }
    }
}

// Lays its views out in lines, left to right, wrapping at the width it has.
struct Flow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let frames = place(subviews, in: width)
        return CGSize(width: proposal.width ?? frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (frame, view) in zip(place(subviews, in: bounds.width), subviews) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func place(_ subviews: Subviews, in width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += line + spacing
                line = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            line = max(line, size.height)
        }
        return frames
    }
}
