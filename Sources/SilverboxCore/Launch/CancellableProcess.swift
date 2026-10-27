import Foundation

/// Serializes process startup, termination and cancellation. In particular,
/// Foundation's terminate() must never be called before run() succeeds.
nonisolated final class CancellableProcess: @unchecked Sendable {
    let process = Process()
    private let lock = NSLock()
    private var cancelled = false
    private var running = false

    func run() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { throw CancellationError() }
        try process.run()
        running = true
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if running, process.isRunning { process.terminate() }
    }

    func finished() {
        lock.lock()
        defer { lock.unlock() }
        running = false
    }
}
