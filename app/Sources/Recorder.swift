import AVFoundation
import AudioToolbox

// The microphone, as 16 kHz mono floats: what Parakeet listens to. A fresh
// engine for each dictation, on the chosen microphone or the system's
// default. Nothing in the audio callback blocks: samples are copied out under
// a short lock, handed to the journal's queue, and the level goes to the main
// thread for the toast's bars.
final class Recorder {
    var onLevel: ((Float) -> Void)?
    // Each chunk as it arrives, from the audio thread: the journal's.
    var onSamples: (([Float]) -> Void)?
    // The microphone went away or changed under a dictation (main thread).
    var onInterrupted: (() -> Void)?

    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var observer: NSObjectProtocol?
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
        feeding = false
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if var id = Devices.current(), let unit = input.audioUnit {
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
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
        self.engine = engine
        // AirPods leaving, a USB mic unplugged, the default changing.
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.onInterrupted?()
        }
    }

    // Stops for good: the engine is torn down before the next one starts.
    func stop() -> [Float] {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        lock.lock(); defer { lock.unlock() }
        let taken = samples
        samples = []
        return taken
    }

    private func take(_ buffer: AVAudioPCMBuffer) {
        guard let converter, !feeding else { return }
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
        heard(chunk)
    }

    private func heard(_ chunk: [Float]) {
        lock.lock(); samples.append(contentsOf: chunk); lock.unlock()
        onSamples?(chunk)

        // Loudness in dB, -50 (silence) to -10 (a raised voice), as 0 to 1.
        let power = chunk.reduce(Float(0)) { $0 + $1 * $1 } / Float(chunk.count)
        let db = 10 * log10(max(power, 1e-10))
        let level = max(0, min(1, (db + 50) / 40))
        DispatchQueue.main.async { [weak self] in self?.onLevel?(level) }
    }

    // A microphone that sent nothing at all: over 2 s and flat zero. Never
    // a judgment on a quiet voice (a soft 167 s dictation at RMS 0.0088 was
    // once thrown away by a stricter rule).
    // Eval builds only: a sound file heard in place of the microphone, at
    // its own pace, for end-to-end runs that make no sound in the room.
    private var feeding = false

    #if KOE_EVAL
    func feed(_ url: URL) {
        guard engine != nil, let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let converter = AVAudioConverter(from: file.processingFormat, to: target),
              let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(file.length) * 16_000 / file.processingFormat.sampleRate + 1024))
        else { return }
        var fed = false
        converter.convert(to: out, error: nil) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard let data = out.floatChannelData?[0] else { return }
        let all = Array(UnsafeBufferPointer(start: data, count: Int(out.frameLength)))
        feeding = true
        DispatchQueue.global().async { [weak self] in
            for start in stride(from: 0, to: all.count, by: 1_600) {
                self?.heard(Array(all[start..<min(start + 1_600, all.count)]))
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
    }
    #endif

    static func isSilent(_ samples: [Float]) -> Bool {
        guard samples.count > 32_000 else { return false }
        var sum: Float = 0, peak: Float = 0
        for sample in samples {
            sum += sample * sample
            peak = max(peak, abs(sample))
        }
        return (sum / Float(samples.count)).squareRoot() < 1e-4 && peak < 1e-3
    }

    // Leading and trailing silence off, 0.3 s kept around the speech; the
    // middle is never touched, so no word is ever cut.
    static func trimmed(_ samples: [Float]) -> [Float] {
        let frame = 480 // 30 ms
        guard samples.count > frame * 10 else { return samples }
        let peak = samples.lazy.map(abs).max() ?? 0
        guard peak > 0 else { return samples }
        // Judged on a copy brought to the same level, so a quiet voice counts as speech.
        let threshold = peak * 0.04
        func loud(_ start: Int) -> Bool {
            let end = min(start + frame, samples.count)
            var sum: Float = 0
            for i in start..<end { sum += samples[i] * samples[i] }
            return (sum / Float(end - start)).squareRoot() > threshold
        }
        var first = 0
        while first < samples.count && !loud(first) { first += frame }
        var last = samples.count - frame
        while last > first && !loud(last) { last -= frame }
        guard first < last else { return samples }
        let pad = 4_800
        return Array(samples[max(0, first - pad)..<min(samples.count, last + frame + pad)])
    }
}
