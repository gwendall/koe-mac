import FluidAudio
import Foundation

// Parakeet Ultra on the Neural Engine, loaded once and kept. The first load
// after an install or a macOS update compiles the model (seconds); later ones
// take a tenth of a second.
actor Transcriber {
    private var manager: AsrManager?
    private var loadedFrom: URL?

    // FluidAudio turns away anything shorter than 0.3 s: pad with silence.
    private static let minimumSamples = 4_800

    var isLoaded: Bool { manager != nil }

    func load(_ directory: URL) async throws {
        if manager != nil, loadedFrom == directory { return }
        let version = AsrModelVersion.ultra
        let models = try AsrModels.loadLocal(from: directory, version: version)
        let next = AsrManager(config: ASRConfig(tdtConfig: TdtConfig(blankId: version.blankId),
                                                encoderHiddenSize: version.encoderHiddenSize))
        try await next.loadModels(models)
        manager = next
        loadedFrom = directory
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard let manager else {
            throw NSError(domain: "Koe", code: 3, userInfo: [NSLocalizedDescriptionKey: "The voice model is not loaded"])
        }
        var audio = samples
        if audio.count < Self.minimumSamples { audio += [Float](repeating: 0, count: Self.minimumSamples - audio.count) }
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(audio, decoderState: &state)
        return Self.clean(result.text)
    }

    // Parakeet writes `<unk>` for what it cannot spell (often punctuation).
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "<unk>", with: "")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
