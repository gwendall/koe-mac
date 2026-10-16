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
    // How long the microphone has been quiet, up to now (audio thread).
    private var quiet = 0
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    static var permission: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }

    static func askPermission(_ done: @escaping @MainActor (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async { MainActor.assumeIsolated { done(granted) } }
        }
    }

    func start() throws {
        feeding = false
        lock.lock(); samples.removeAll(keepingCapacity: true); quiet = 0; lock.unlock()
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
        // AirPods coming or going, a USB mic unplugged, the default changing,
        // or just the chosen microphone settling in: macOS stops the engine.
        // Koe goes on listening on whatever microphone there is now, and only
        // gives up when there is none.
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.resume()
        }
    }

    private func resume() {
        guard let engine, !engine.isRunning else { return }
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0, let converter = AVAudioConverter(from: format, to: target) else {
            onInterrupted?()
            return
        }
        self.converter = converter
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.take(buffer)
        }
        do {
            try engine.start()
            Log.note("microphone", ["resumed": Int(format.sampleRate)])
        } catch {
            input.removeTap(onBus: 0)
            onInterrupted?()
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

    // Seconds since the voice last rose above a quiet room.
    var quietFor: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return Double(quiet) / 16_000
    }

    private func heard(_ chunk: [Float]) {
        // Loudness in dB, -50 (silence) to -10 (a raised voice), as 0 to 1.
        let power = chunk.reduce(Float(0)) { $0 + $1 * $1 } / Float(chunk.count)
        let db = 10 * log10(max(power, 1e-10))
        lock.lock()
        samples.append(contentsOf: chunk)
        quiet = db < -42 ? quiet + chunk.count : 0
        lock.unlock()
        onSamples?(chunk)

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
    func feed(_ url: URL, done: (@MainActor () -> Void)? = nil) {
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
            DispatchQueue.main.async { MainActor.assumeIsolated { done?() } }
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

    // Leading and trailing silence off, around the speech; the middle is
    // never touched. Silence is judged against the room's own noise, never
    // against the loudest moment: a knock on the desk once made a softly
    // spoken last few words count as silence, and they were lost. Half a
    // second is kept after the speech, more than the model needs to end well.
    static func trimmed(_ samples: [Float]) -> [Float] {
        let frame = 480 // 30 ms
        guard samples.count > frame * 10 else { return samples }
        var levels: [Float] = []
        levels.reserveCapacity(samples.count / frame + 1)
        for start in stride(from: 0, to: samples.count, by: frame) {
            let end = min(start + frame, samples.count)
            var sum: Float = 0
            for i in start..<end { sum += samples[i] * samples[i] }
            levels.append((sum / Float(end - start)).squareRoot())
        }
        // The room: the quietest tenth of the recording.
        let floor = levels.sorted()[levels.count / 10]
        let threshold = max(floor * 3, 1e-3)
        guard let first = levels.firstIndex(where: { $0 > threshold }),
              let last = levels.lastIndex(where: { $0 > threshold }), first < last else { return samples }
        let before = 4_800, after = 8_000
        return Array(samples[max(0, first * frame - before)..<min(samples.count, (last + 1) * frame + after)])
    }
}
