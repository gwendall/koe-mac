import AVFoundation

// A sound file as 16 kHz mono floats, for `--transcribe`.
enum Audio {
    static func read(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        guard let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { return [] }
        try file.read(into: input)
        guard let converter = AVAudioConverter(from: file.processingFormat, to: target),
              let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(file.length) * 16_000 / file.processingFormat.sampleRate) + 1024)
        else { return [] }
        var fed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return input
        }
        if let error { throw error }
        guard let data = output.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
    }
}
