import AppKit
import Combine

// What the windows show and change: one object, kept by the app, that the
// welcome and settings windows observe. The app does the work through the
// closures; the windows only ask.
@MainActor
final class KoeState: ObservableObject {
    // Permissions: nil while unknown.
    @Published var microphone: Bool?
    @Published var accessibility = false
    // The voice model.
    @Published var modelShare: Double?
    @Published var modelReady = false
    // Core ML fitting the model to this Mac's Neural Engine: the first load only, and slow.
    @Published var modelPreparing = false
    @Published var modelFailed = false
    // The shortcut, and recording a new one.
    @Published var shortcut = Shortcut.saved
    @Published var capturing = false
    @Published var captureError: String?
    // Options.
    @Published var submits = UserDefaults.standard.bool(forKey: "submits")
    @Published var keepsRecent = !UserDefaults.standard.bool(forKey: "forgetRecent")
    @Published var muted = UserDefaults.standard.bool(forKey: "muted")
    @Published var login = false
    @Published var updates = Update.isOn
    @Published var inputs: [Devices.Input] = []
    @Published var input = Devices.chosen
    @Published var words = Vocabulary.words
    // While Koe listens or types, for the try-it field.
    @Published var listening = false
    @Published var lastText: String?

    var askMicrophone: () -> Void = {}
    var openAccessibility: () -> Void = {}
    var openMicrophoneSettings: () -> Void = {}
    var startCapture: () -> Void = {}
    var cancelCapture: () -> Void = {}
    var retryModel: () -> Void = {}
    var setLogin: (Bool) -> Void = { _ in }
    var copyReport: () -> Void = {}
    var finishWelcome: () -> Void = {}
    var celebrate: () -> Void = {}
    // Set while the welcome's try-it box is on screen: the words go there.
    var tryIt: ((String) -> Void)?

    // How to start Koe, in words. Held, the shortcut talks until it comes
    // up; tapped, until it is tapped again. A modifier on its own fires on
    // release, so it can only be tapped.
    var howTo: String {
        shortcut.forcesToggle
            ? Words.say("Press %@ to talk, press it again to stop", shortcut.label)
            : Words.say("Hold %@ to talk, or tap it to start and stop", shortcut.label)
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(submits, forKey: "submits")
        defaults.set(!keepsRecent, forKey: "forgetRecent")
        defaults.set(muted, forKey: "muted")
        Update.isOn = updates
        Devices.chosen = input
        Vocabulary.words = words
        if !keepsRecent { defaults.removeObject(forKey: "recent") }
    }
}
