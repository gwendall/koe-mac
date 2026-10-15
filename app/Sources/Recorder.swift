import AVFoundation

// The microphone, as 16 kHz mono floats: what Parakeet listens to. The voice's
// level comes back on the main thread, for the toast's bars.
final class Recorder {
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let lock = NSLock()
    private var samples: [Float] = []
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    static var permission: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }

    static func askPermission(_ done: @escaping @MainActor (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async { MainActor.assumeIsolated { done(granted) } }
        }
    }

    func start() throws {
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "Koe", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone"])
        }
        converter = AVAudioConverter(from: format, to: target)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.take(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock(); defer { lock.unlock() }
        let taken = samples
        samples = []
        return taken
    }

    private func take(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate + 64)
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let data = out.floatChannelData?[0], out.frameLength > 0 else { return }
        let chunk = Array(UnsafeBufferPointer(start: data, count: Int(out.frameLength)))
        lock.lock(); samples.append(contentsOf: chunk); lock.unlock()

        // Loudness in dB, -50 (silence) to -10 (a raised voice), as 0 to 1.
        let power = chunk.reduce(Float(0)) { $0 + $1 * $1 } / Float(chunk.count)
        let db = 10 * log10(max(power, 1e-10))
        let level = max(0, min(1, (db + 50) / 40))
        DispatchQueue.main.async { [weak self] in self?.onLevel?(level) }
    }
}
