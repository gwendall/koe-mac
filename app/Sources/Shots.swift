import AppKit

// Pictures of Koe's pills, drawn offscreen, for `--render-toasts`.
@MainActor
enum Shots {
    static func toasts(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let anchor = NSRect(x: 600, y: 860, width: 22, height: 22)
        let styles: [(String, Toast.Style, Float?)] = [
            ("listening", Toast.listening, 0.7),
            ("no-sound", Toast.listening, 0),
            ("typed", Toast.typed, nil),
            ("hello", Toast.hello, nil),
            ("almost-ready", Toast.note(Words.say("ALMOST READY"), Words.say("Koe's voice model is at %@", Words.percent(42))), nil),
        ]
        for (name, style, level) in styles {
            let toast = Toast()
            toast.show(style, under: anchor)
            if let level { toast.setLevel(level) }
            if name == "no-sound" { toast.setCaption(Words.say("No sound: check your microphone")) }
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
