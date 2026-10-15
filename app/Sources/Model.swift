import CryptoKit
import Foundation

// Parakeet Ultra, the one voice model Koe runs: moondream/parakeet-ultra, a
// post-training of NVIDIA parakeet-tdt-0.6b-v3, converted to Core ML by
// FluidInference (CC BY 4.0). Fetched once from a pinned revision, each file
// checked against its SHA-256 before it is used. Koe 0.1 (the Tauri app) kept
// the same files, so a Mac that has them already downloads nothing.
enum Model {
    struct File {
        let path: String
        let sha256: String
        let size: Int64
    }

    static let base = URL(string: "https://huggingface.co/FluidInference/parakeet-ultra-coreml/resolve/95eaa59a39d4394f047a4dc5cce480388a60d1b6")!

    static let files: [File] = [
        File(path: "Decoder.mlmodelc/analytics/coremldata.bin", sha256: "fe92b6cfaa012abd5248c0bc877832f19807015abffc60d87b8ccc8ccb48b3b5", size: 243),
        File(path: "Decoder.mlmodelc/coremldata.bin", sha256: "3b06e66768f0df7e21795f50e2b29300e33eeb1a2579dc42c695279c2d308497", size: 560),
        File(path: "Decoder.mlmodelc/model.mil", sha256: "956f600207f88396017ca5c96cfa3acd5bfee60835a5b44b762e033a8fb28955", size: 13110),
        File(path: "Decoder.mlmodelc/weights/weight.bin", sha256: "02a0d219f281b9665bc10c8768649403b2eebbbf4b44c627041d948e0de11bb4", size: 23604992),
        File(path: "Encoder.mlmodelc/analytics/coremldata.bin", sha256: "d87101d824d6723cf95304da33755c3c60e762663b9ef2b0c4bd0aa166a09a0d", size: 243),
        File(path: "Encoder.mlmodelc/coremldata.bin", sha256: "397a84a4062f563cbc5f56077c674f09a61d85be5090f61d2f1932afb92ac0fe", size: 514),
        File(path: "Encoder.mlmodelc/model.mil", sha256: "f5d601568a4171d99a314c0fe3f6bc67715da2623732a3fb566e050ea83e5848", size: 1002653),
        File(path: "Encoder.mlmodelc/weights/weight.bin", sha256: "315ba01f33cadbf601d43ac7f5c86208b7aa75fdaa34705c9869d5abe3521c9b", size: 594211328),
        File(path: "JointDecisionv3.mlmodelc/analytics/coremldata.bin", sha256: "68d38ca646aebafa7a9329e2efda50f5767c49e89fdb5f77f212072bb66f97c4", size: 243),
        File(path: "JointDecisionv3.mlmodelc/coremldata.bin", sha256: "5e3af5a4ce686f6c237cadbd9284e10d333bc0e1546633cd0e430e6194044bc4", size: 592),
        File(path: "JointDecisionv3.mlmodelc/model.mil", sha256: "791b3c3cf3eb2079c84623fc880f6bba008d1366e5f8b03e9a8ed8bd4d7194a0", size: 11777),
        File(path: "JointDecisionv3.mlmodelc/weights/weight.bin", sha256: "3f310b85b82341c53ec383025ab094a4e462ee1c592e1ad7c6bfe39cff66ca25", size: 12642764),
        File(path: "Preprocessor.mlmodelc/analytics/coremldata.bin", sha256: "c9beeb989c8d66f8be11df59bc6df277ec76cee404f6865b46243835ef562f6d", size: 243),
        File(path: "Preprocessor.mlmodelc/coremldata.bin", sha256: "dbde3f2300842c1fd51ef3ff948a0bcffe65ffd2dca10707f2509f32c1d65b1d", size: 486),
        File(path: "Preprocessor.mlmodelc/metadata.json", sha256: "2a98699e22d279dd37fa1d238aeb1c6db1df0d6fad687775324157689d8f3acf", size: 2841),
        File(path: "Preprocessor.mlmodelc/model.mil", sha256: "4b8518a956450fec57f06c2a21bdffc26973f7f1fa6842fb38fe917f896b6b93", size: 28181),
        File(path: "Preprocessor.mlmodelc/weights/weight.bin", sha256: "129b76e3aeafa8afa3ea76d995b964b145fe83700d579f6ff42c4c38fa0968ea", size: 491072),
        File(path: "parakeet_vocab.json", sha256: "7ec60e05f1b24480736ec0eed40900f4626bce1fa9a60fd700ec7e2a59198735", size: 151122),
    ]

    static var total: Int64 { files.reduce(0) { $0 + $1.size } }

    private static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
    static var directory: URL { support.appendingPathComponent("Koe/Models/parakeet-ultra-coreml") }
    private static var legacy: URL { support.appendingPathComponent("fm.koe.app/models/parakeet-ultra-coreml") }
    private static var staging: URL { support.appendingPathComponent("Koe/Models/parakeet-ultra-coreml.downloading") }

    // Every file there, at its size. Sizes are cheap to check; the hashes
    // were checked when the files arrived.
    static func isComplete(_ directory: URL) -> Bool {
        files.allSatisfy { file in
            let attributes = try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(file.path).path)
            return (attributes?[.size] as? NSNumber)?.int64Value == file.size
        }
    }

    static var installed: URL? {
        if isComplete(directory) { return directory }
        if isComplete(legacy) { return legacy }
        return nil
    }

    // Downloads what is missing into a staging folder, checks every file,
    // then moves the folder into place. An interrupted download resumes with
    // the files it had verified. `progress` is 0 to 1, on the main thread.
    static func download(progress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        let manager = FileManager.default
        var done: Int64 = 0
        for file in files {
            let target = staging.appendingPathComponent(file.path)
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? manager.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.int64Value == file.size,
               (try? sha256(of: target)) == file.sha256 {
                done += file.size
                continue
            }
            let before = done
            let fetched = try await Fetch.file(base.appendingPathComponent(file.path)) { written in
                let share = Double(before + written) / Double(total)
                Task { @MainActor in progress(share) }
            }
            guard try sha256(of: fetched) == file.sha256 else {
                try? manager.removeItem(at: fetched)
                throw NSError(domain: "Koe", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(file.path) does not match its checksum"])
            }
            try? manager.removeItem(at: target)
            try manager.moveItem(at: fetched, to: target)
            done += file.size
        }
        try? manager.removeItem(at: directory)
        try manager.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.moveItem(at: staging, to: directory)
        return directory
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

// One download with its progress, to a temporary file.
private final class Fetch: NSObject, URLSessionDownloadDelegate {
    private let onProgress: (Int64) -> Void
    private var continuation: CheckedContinuation<URL, Error>?

    private init(_ onProgress: @escaping (Int64) -> Void) { self.onProgress = onProgress }

    static func file(_ url: URL, progress: @escaping (Int64) -> Void) async throws -> URL {
        let fetch = Fetch(progress)
        let session = URLSession(configuration: .default, delegate: fetch, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            fetch.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        onProgress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            continuation?.resume(throwing: NSError(domain: "Koe", code: status, userInfo: [NSLocalizedDescriptionKey: "HTTP \(status)"]))
            continuation = nil
            return
        }
        // The system deletes `location` when this returns: keep a copy.
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            continuation?.resume(returning: kept)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
