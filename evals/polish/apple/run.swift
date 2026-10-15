import Foundation
import FoundationModels

// apple/run in.json out.json: each case through Apple's on-device model,
// greedy, a fresh session per text (as Koe would), prewarmed, timed.
struct Case: Decodable { let system: String; let shots: [[String]]; let text: String }
struct Out: Encodable { let text: String; let ms: Double }

let args = CommandLine.arguments
let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
var outs: [Out] = []
let done = DispatchSemaphore(value: 0)
Task {
    for item in cases {
        let examples = item.shots.map { "\($0[0])\nCleaned: \($0[1])" }.joined(separator: "\n\n")
        let session = LanguageModelSession(instructions: item.system + "\n\nExamples:\n\n" + examples)
        session.prewarm()
        try? await Task.sleep(for: .milliseconds(300))
        let start = Date()
        var text = ""
        do {
            let reply = try await session.respond(to: item.text, options: GenerationOptions(sampling: .greedy))
            text = reply.content
        } catch {
            text = "ERROR: \(error)"
        }
        outs.append(Out(text: text, ms: Date().timeIntervalSince(start) * 1000))
        FileHandle.standardError.write("\(outs.count)/\(cases.count)\n".data(using: .utf8)!)
    }
    try! JSONEncoder().encode(outs).write(to: URL(fileURLWithPath: args[2]))
    done.signal()
}
done.wait()
