import Foundation

// Every dictation is on disk from its first second until its words are
// delivered. While Koe listens, the audio goes to <id>.pcm (16-bit, 16 kHz,
// synced every second) next to <id>.json, which says how far it got:
// recording, saved, transcribed. A crash, a force quit or a power cut loses
// at most the last second; at the next launch Koe finishes the job and puts
// the words on the clipboard, never typing them on its own. Files are only
// readable by their owner. At most 10 are kept, for 14 days.
final class Journal {
    struct Manifest: Codable {
        enum Status: String, Codable { case recording, saved, transcribed }
        let id: String
        let startedAt: Date
        let pid: Int32
        var status: Status
        var text: String?
    }

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Koe/Recordings")
    }

    let id: String
    private var manifest: Manifest
    private let queue = DispatchQueue(label: "koe.journal")
    private var handle: FileHandle?
    private var unsynced = 0
    private(set) var failed = false

    private static let keep = 10
    private static let maxAge: TimeInterval = 14 * 24 * 3600

    // Starts a recording's files, synced, before Koe says it listens.
    init() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: Self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        id = String(format: "%013d-%@", stamp, UUID().uuidString.prefix(8).lowercased())
        manifest = Manifest(id: id, startedAt: Date(), pid: getpid(), status: .recording, text: nil)
        let audio = Self.audioURL(id)
        guard manager.createFile(atPath: audio.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw NSError(domain: "Koe", code: 5, userInfo: [NSLocalizedDescriptionKey: "Can't write the recording"])
        }
        handle = try FileHandle(forWritingTo: audio)
        try Self.write(manifest)
    }

    // From the audio thread: queued, never blocks capture.
    func append(_ samples: [Float]) {
        queue.async { [self] in
            guard let handle, !failed else { return }
            var data = Data(capacity: samples.count * 2)
            for sample in samples {
                let value = Int16(max(-1, min(1, sample)) * 32767)
                withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
            }
            do {
                try handle.write(contentsOf: data)
                unsynced += samples.count
                if unsynced >= 16_000 {
                    try handle.synchronize()
                    unsynced = 0
                }
            } catch {
                failed = true
                Log.note("journal", ["write": "failed"])
            }
        }
    }

    // Recording over: the audio is complete and synced.
    func saved() {
        queue.sync {
            try? handle?.synchronize()
            try? handle?.close()
            handle = nil
        }
        manifest.status = .saved
        try? Self.write(manifest)
    }

    func transcribed(_ text: String) {
        guard !text.isEmpty else { return }
        manifest.status = .transcribed
        manifest.text = text
        try? Self.write(manifest)
    }

    // Delivered, or cancelled: gone. The manifest goes first, so a crash
    // in between never brings cancelled speech back.
    func discard() {
        queue.sync {
            try? handle?.close()
            handle = nil
        }
        Self.remove(id)
    }

    // MARK: - What a past launch left

    static func leftovers() -> [Manifest] {
        prune()
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.compactMap { name in
            guard let data = manager.contents(atPath: directory.appendingPathComponent(name).path),
                  let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return nil }
            // Another Koe still writing it.
            if manifest.pid != getpid(), kill(manifest.pid, 0) == 0, manifest.status == .recording { return nil }
            return manifest
        }.sorted { $0.startedAt > $1.startedAt }
    }

    // A leftover's audio; a torn last byte is ignored.
    static func audio(_ id: String) -> [Float] {
        guard let data = FileManager.default.contents(atPath: audioURL(id).path) else { return [] }
        let count = data.count / 2
        return data.withUnsafeBytes { raw in
            (0..<count).map { Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 2, as: Int16.self))) / 32767 }
        }
    }

    static func update(_ manifest: Manifest) { try? write(manifest) }

    static func remove(_ id: String) {
        let manager = FileManager.default
        try? manager.removeItem(at: manifestURL(id))
        try? manager.removeItem(at: audioURL(id))
    }

    private static func prune() {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
        let ids = Set(names.map { ($0 as NSString).deletingPathExtension })
        let dated = ids.compactMap { id -> (String, Date)? in
            let url = manager.fileExists(atPath: manifestURL(id).path) ? manifestURL(id) : audioURL(id)
            let date = (try? manager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? nil
            return date.map { (id, $0) }
        }.sorted { $0.1 > $1.1 }
        for (index, (id, date)) in dated.enumerated() where index >= keep || Date().timeIntervalSince(date) > maxAge {
            remove(id)
        }
    }

    private static func audioURL(_ id: String) -> URL { directory.appendingPathComponent(id + ".pcm") }
    private static func manifestURL(_ id: String) -> URL { directory.appendingPathComponent(id + ".json") }

    // Written to a temporary file, synced, then renamed: never half a manifest.
    private static func write(_ manifest: Manifest) throws {
        let data = try JSONEncoder().encode(manifest)
        let target = manifestURL(manifest.id)
        let temporary = target.appendingPathExtension("tmp")
        FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: temporary)
        try handle.synchronize()
        try handle.close()
        _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)
    }
}
