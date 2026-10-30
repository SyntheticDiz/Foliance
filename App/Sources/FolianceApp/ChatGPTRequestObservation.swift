import Foundation

/// Records provider requests made by one scheduled operation. A missing observer
/// is intentionally a no-op, so requests outside ChatGPTWork are unaffected.
enum ChatGPTRequestObservation {
    @TaskLocal static var current: Recorder? = nil

    struct Snapshot: Sendable {
        let requestCount: Int
        let successfulCount: Int
        let failedCount: Int
        let firstRequestUptime: TimeInterval?

        var isFullySuccessfulRequestOperation: Bool {
            requestCount > 0 && successfulCount == requestCount && failedCount == 0
        }
    }

    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private let now: @Sendable () -> TimeInterval
        private var requestCount = 0
        private var successfulCount = 0
        private var failedCount = 0
        private var firstRequestUptime: TimeInterval?

        init(now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
            self.now = now
        }

        func requestStarted() {
            lock.lock(); defer { lock.unlock() }
            requestCount += 1
            if firstRequestUptime == nil { firstRequestUptime = now() }
        }

        func requestFinished(succeeded: Bool) {
            lock.lock(); defer { lock.unlock() }
            if succeeded { successfulCount += 1 } else { failedCount += 1 }
        }

        func snapshot() -> Snapshot {
            lock.lock(); defer { lock.unlock() }
            return Snapshot(requestCount: requestCount, successfulCount: successfulCount,
                            failedCount: failedCount, firstRequestUptime: firstRequestUptime)
        }
    }

    /// Marks one real or explicitly simulated provider call within the current
    /// scheduler operation. This also gives scheduler tests a deterministic seam.
    static func perform<T>(_ operation: () async throws -> T) async throws -> T {
        guard let recorder = current else { return try await operation() }
        recorder.requestStarted()
        do {
            let result = try await operation()
            recorder.requestFinished(succeeded: true)
            return result
        } catch {
            recorder.requestFinished(succeeded: false)
            throw error
        }
    }
}
