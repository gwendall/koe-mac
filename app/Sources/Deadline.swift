import Foundation

// Whichever comes first: the work's answer, or nil at the deadline. The work
// is left behind, never awaited, so something stuck can't hold Koe with it
// (a task group would wait for its stuck child before returning).
enum Deadline {
    static func race<T: Sendable>(_ seconds: Double, _ work: @escaping @Sendable () async -> T?) async -> T? {
        await withCheckedContinuation { continuation in
            let once = Once()
            Task.detached {
                let value = await work()
                once.run { continuation.resume(returning: value) }
            }
            Task.detached {
                try? await Task.sleep(for: .seconds(seconds))
                once.run { continuation.resume(returning: nil) }
            }
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false

        func run(_ body: () -> Void) {
            lock.lock()
            let first = !done
            done = true
            lock.unlock()
            if first { body() }
        }
    }
}
