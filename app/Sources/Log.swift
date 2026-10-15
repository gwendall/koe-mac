import AppKit

// A small diagnostic log, Koe/koe.log, kept to about 3 MB (two older files
// roll behind it). It says what happened, never what was said: no dictated
// text, no clipboard, no key pressed besides "the shortcut". Nothing leaves
// the Mac unless you copy the report yourself.
enum Log {
    private static let queue = DispatchQueue(label: "koe.log")
    private static let limit = 1 << 20

    static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Koe/koe.log")
    }

    static func note(_ event: String, _ details: [String: Any] = [:]) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let fields = details.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        let line = "\(stamp) \(event)\(fields.isEmpty ? "" : " " + fields)\n"
        queue.async {
            let manager = FileManager.default
            try? manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = try? manager.attributesOfItem(atPath: file.path)[.size] as? Int, size > limit {
                let older = file.appendingPathExtension("1"), oldest = file.appendingPathExtension("2")
                try? manager.removeItem(at: oldest)
                try? manager.moveItem(at: older, to: oldest)
                try? manager.moveItem(at: file, to: older)
            }
            if !manager.fileExists(atPath: file.path) {
                manager.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            if let handle = try? FileHandle(forWritingTo: file) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            }
        }
    }

    // What to paste in a message when something goes wrong.
    static func report(_ state: [String: String]) -> String {
        queue.sync {}
        let info = ProcessInfo.processInfo
        var lines = [
            "Koe \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")",
            "macOS \(info.operatingSystemVersionString)",
        ]
        lines += state.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
        let tail = (try? String(contentsOf: file, encoding: .utf8))?.split(separator: "\n").suffix(300) ?? []
        return (lines + ["", "Log:"] + tail.map(String.init)).joined(separator: "\n")
    }
}
