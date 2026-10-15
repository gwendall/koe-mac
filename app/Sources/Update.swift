import Foundation

// Koe keeps itself up to date, as Wham does. A few times a day it asks GitHub
// which release is the latest; when that one is newer it downloads it, makes
// sure Koe's developer signed it and that it runs, and swaps it in. The
// request carries nothing about the Mac or its user. Blocking calls: run them
// off the main thread.
enum Update {
    static var base: String { UserDefaults.standard.string(forKey: "updateBase") ?? "https://github.com/gwendall/koe-mac" }

    // The only apps Koe installs over itself: Koe, signed by its developer.
    static let requirement = #"identifier "fm.koe.mac" and anchor apple generic and certificate leaf[subject.OU] = "NQCA86NEA3""#

    static var isOn: Bool {
        get { !UserDefaults.standard.bool(forKey: "noAutoUpdate") }
        set { UserDefaults.standard.set(!newValue, forKey: "noAutoUpdate") }
    }

    static var running: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    // GitHub answers /releases/latest with a redirect to /releases/tag/v2.1.0.
    static func latest() -> String? {
        let (status, answer) = output("/usr/bin/curl", ["-fsS", "--max-time", "30", "-o", "/dev/null", "-w", "%{redirect_url}", base + "/releases/latest"])
        guard status == 0, let answer, let range = answer.range(of: "/tag/v") else { return nil }
        let version = String(answer[range.upperBound...])
        return numbers(version) == nil ? nil : version
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let new = numbers(candidate), let old = numbers(current) else { return false }
        for i in 0..<max(new.count, old.count) where (i < new.count ? new[i] : 0) != (i < old.count ? old[i] : 0) {
            return (i < new.count ? new[i] : 0) > (i < old.count ? old[i] : 0)
        }
        return false
    }

    static func isGenuine(_ app: URL) -> Bool {
        output("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R=" + requirement, app.path]).status == 0
    }

    // A build from source never updates itself.
    static func canReplace(_ app: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path) && isGenuine(app)
    }

    // Downloads `version` and puts it where `app` is. Nil once done, or the step that failed.
    static func install(_ version: String, over app: URL) -> String? {
        let files = FileManager.default
        guard let folder = try? files.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true) else {
            return "no folder to download to"
        }
        defer { try? files.removeItem(at: folder) }
        let zip = folder.appendingPathComponent("Koe.zip")
        let fresh = folder.appendingPathComponent("Koe.app")
        guard output("/usr/bin/curl", ["-fsSL", "--max-time", "300", "-o", zip.path, "\(base)/releases/download/v\(version)/Koe.zip"]).status == 0 else { return "download" }
        guard output("/usr/bin/ditto", ["-x", "-k", zip.path, folder.path]).status == 0 else { return "unzip" }
        guard isGenuine(fresh) else { return "signature" }
        let said = output(fresh.appendingPathComponent("Contents/MacOS/Koe").path, ["--version"])
        guard said.status == 0, said.text == "koe \(version)" else { return "version" }
        do {
            _ = try files.replaceItemAt(app, withItemAt: fresh)
        } catch {
            return "replace: \(error.localizedDescription)"
        }
        return nil
    }

    private static func numbers(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...4).contains(parts.count), parts.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        return parts.compactMap { $0 }
    }

    private static func output(_ path: String, _ args: [String]) -> (status: Int32, text: String?) {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return (-1, nil) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return (process.terminationStatus, nil) }
        return (0, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
