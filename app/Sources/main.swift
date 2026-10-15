import AppKit

let args = Array(CommandLine.arguments.dropFirst())

// `Koe --version`: what the updater checks a download says.
if args.first == "--version" {
    print("koe \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")")
    exit(0)
}

if args.first == "--self-test" {
    exit(MainActor.assumeIsolated { SelfTest.run() })
}

// The pixel font, for the windows' titles too.
if let font = Bundle.main.url(forResource: "Silkscreen-Regular", withExtension: "ttf") {
    CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil)
}

// `Koe --render-sounds <dir>` writes every sound as a WAV file, to listen to them.
if args.first == "--render-sounds", args.count > 1 {
    let dir = URL(fileURLWithPath: args[1])
    for (index, sound) in Chime.Sound.all.enumerated() {
        try Chime.wav(Chime.samples(sound)).write(to: dir.appendingPathComponent(String(format: "%02d %@.wav", index + 1, sound.name)))
    }
    exit(0)
}

// `Koe --transcribe <file>…` types nothing: it prints what Koe hears in each
// file, and how long it took, with the installed model (or $KOE_MODEL_DIR).
if args.first == "--transcribe", args.count > 1 {
    Words.english = true
    let done = DispatchSemaphore(value: 0)
    var status: Int32 = 0
    Task.detached {
        do {
            let directory = ProcessInfo.processInfo.environment["KOE_MODEL_DIR"].map { URL(fileURLWithPath: $0) } ?? Model.installed
            guard let directory else { throw NSError(domain: "Koe", code: 4, userInfo: [NSLocalizedDescriptionKey: "no model installed"]) }
            let transcriber = Transcriber()
            let loading = Date()
            try await transcriber.load(directory)
            print(String(format: "loaded in %.0f ms", Date().timeIntervalSince(loading) * 1000))
            for path in args.dropFirst() {
                let samples = try Audio.read(URL(fileURLWithPath: path))
                let start = Date()
                let text = try await transcriber.transcribe(samples)
                print(String(format: "%@ (%.1f s of audio, %.0f ms): %@", (path as NSString).lastPathComponent,
                             Double(samples.count) / 16_000, Date().timeIntervalSince(start) * 1000, text))
            }
        } catch {
            print("error: \(error.localizedDescription)")
            status = 1
        }
        done.signal()
    }
    done.wait()
    exit(status)
}

// `Koe --render-toasts <dir>` draws every pill as a PNG, to look at them.
if args.first == "--render-toasts", args.count > 1 {
    Words.english = true
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        Shots.toasts(to: URL(fileURLWithPath: args[1]))
    }
    exit(0)
}

// `Koe --render-journey <dir>` draws every screen a newcomer meets.
if args.first == "--render-journey", args.count > 1 {
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        Journey.render(to: URL(fileURLWithPath: args[1]))
    }
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = Koe()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
