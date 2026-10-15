import Foundation

// Koe's sounds: Wham's 25% pulse wave, in A major instead of E (docs/brand.md).
// Synthesized when first played, so they ship as code, not as files.
enum Chime {
    static let rate = 44_100.0
    static let root = 880.0 // A5

    enum Sound: Hashable {
        case start        // Koe starts listening: two notes up
        case stop         // it stops: the same two, down
        case check(Bool)  // a menu option checked, or unchecked
        case select       // a menu value picked, a dictation copied
        case refused      // not now: out of the key
        case hooray       // the welcome's end: all set, up the chord and over

        static let all: [Sound] = [.start, .stop, .check(true), .check(false), .select, .refused, .hooray]

        var name: String {
            switch self {
            case .start: return "start"
            case .stop: return "stop"
            case .check(let on): return on ? "check" : "uncheck"
            case .select: return "select"
            case .refused: return "refused"
            case .hooray: return "hooray"
            }
        }
    }

    static func samples(_ sound: Sound) -> [Float] {
        switch sound {
        // A5 then E6.
        case .start: return notes([0, 7], gap: 0.05, ring: 0.1, peak: 0.16)
        case .stop: return notes([7, 0], gap: 0.05, ring: 0.09, peak: 0.13)
        // A6.
        // C#6 to A6, up, or down.
        case .check(let on): return on ? notes([4, 12], gap: 0.04, ring: 0.08, peak: 0.1) : notes([12, 4], gap: 0.04, ring: 0.07, peak: 0.08)
        // One E6.
        case .select: return notes([7], gap: 0.04, ring: 0.05, peak: 0.1)
        // E5 down to D#5, out of the key: no.
        case .refused: return notes([-5, -6], gap: 0.07, ring: 0.09, peak: 0.1)
        // A major up two octaves, A5 to A7, the top one left to ring.
        case .hooray: return notes([0, 4, 7, 12, 16, 19, 24], gap: 0.065, ring: 0.45, peak: 0.13)
        }
    }

    // `steps` semitones above A5, `gap` seconds apart, each cut by the next,
    // the last one ringing `ring`.
    private static func notes(_ steps: [Int], gap: Double, ring: Double, peak: Double) -> [Float] {
        var out = [Float](repeating: 0, count: Int((Double(steps.count - 1) * gap + ring + 0.02) * rate))
        for (index, step) in steps.enumerated() {
            let last = index == steps.count - 1
            pulse(&out, at: Double(index) * gap, length: last ? ring : gap, freq: root * pow(2, Double(step) / 12),
                  decay: last ? ring / 2.5 : gap)
        }
        return scaled(out, to: peak)
    }

    // A band-limited 25% pulse: its harmonics summed up to 18 kHz, so no aliasing hiss.
    private static func pulse(_ out: inout [Float], at start: Double, length: Double, freq: Double, decay: Double) {
        let duty = 0.25
        var harmonics: [(n: Double, amp: Double)] = []
        for k in 1...Int(18_000 / freq) {
            let n = Double(k)
            harmonics.append((n, 2 / (n * .pi) * sin(n * .pi * duty)))
        }
        let first = Int(start * rate)
        let count = Int(length * rate)
        for i in 0..<count where first + i < out.count {
            let t = Double(i) / rate
            let edge = min(1, t / 0.0015, (length - t) / 0.002) // no click at either end
            var value = 0.0
            for h in harmonics { value += h.amp * cos(2 * .pi * h.n * freq * t) }
            out[first + i] += Float(value * edge * exp(-t / decay))
        }
    }

    private static func scaled(_ samples: [Float], to peak: Double) -> [Float] {
        let top = samples.lazy.map(abs).max() ?? 1
        return samples.map { $0 / top * Float(peak) }
    }

    static func wav(_ samples: [Float]) -> Data {
        var data = Data()
        func le<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); le(36 + bytes); data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); le(UInt32(16)); le(UInt16(1)); le(UInt16(1))
        le(UInt32(rate)); le(UInt32(rate) * 2); le(UInt16(2)); le(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); le(bytes)
        for sample in samples { le(Int16(max(-1, min(1, sample)) * 32767)) }
        return data
    }
}
