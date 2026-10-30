import Foundation

/// Durable user work is separate from the disposable model cache.
enum SavedWork {
    static var directory: URL { SavedSelection.directory.deletingLastPathComponent().appendingPathComponent("werk") }
    static let failure = Notification.Name("FolianceWorkSaveFailure")
    private static let queue = DispatchQueue(label: "Foliance.saved-work", qos: .utility)
    private static let enqueueLock = NSLock()
    private static var enqueueGeneration: UInt64 = 0
    private struct PendingWrite: @unchecked Sendable {
        let perform: @Sendable () -> Void
    }
    // Pending values are protected by enqueueLock. Replacing a value with the
    // same storage ID keeps its original queue position while releasing the
    // superseded snapshot before it is encoded.
    private static var pendingWrites: [String: PendingWrite] = [:]
    private static var pendingOrder: [String] = []
    private static var pendingHead = 0
    private static var workerScheduled = false
    static var scheduledGeneration: UInt64 {
        enqueueLock.lock(); defer { enqueueLock.unlock() }
        return enqueueGeneration
    }
    // Accessed only by `queue`; failures are replaced by a later successful save
    // to the same file and consumed by the next drain barrier.
    private static var failuresSinceDrain: [String: String] = [:]
    static func read<T: Decodable>(_ type: T.Type, key: String, directory: URL = directory) -> T? {
        queue.sync {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(key + ".json")) else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        }
    }
    /// Enqueues an immutable snapshot. Only snapshots that have not started
    /// encoding can be replaced; an in-flight atomic write always completes.
    static func schedule<T: Encodable & Sendable>(_ value: T, key: String, directory: URL = directory) {
        let storageID = directory.appendingPathComponent(key + ".json").standardizedFileURL.path
        enqueueLock.lock()
        enqueueGeneration &+= 1
        if pendingWrites[storageID] == nil {
            if pendingHead == pendingOrder.count {
                pendingOrder.removeAll(keepingCapacity: true)
                pendingHead = 0
            }
            pendingOrder.append(storageID)
        }
        pendingWrites[storageID] = PendingWrite(perform: {
            do {
                let data = try JSONEncoder().encode(value)
                try write(data, key: key, directory: directory)
                failuresSinceDrain.removeValue(forKey: storageID)
            } catch {
                let message = "Work could not be saved: " + error.localizedDescription
                failuresSinceDrain[storageID] = message
                NotificationCenter.default.post(name: failure, object: message)
            }
        })
        if !workerScheduled {
            workerScheduled = true
            queue.async { processPendingWrites() }
        }
        enqueueLock.unlock()
    }

    /// Drains the coalesced FIFO. The lock protects the empty-to-idle
    /// transition so an enqueue cannot be stranded between the final poll and
    /// clearing `workerScheduled`.
    private static func processPendingWrites() {
        while true {
            enqueueLock.lock()
            guard pendingHead < pendingOrder.count else {
                pendingOrder.removeAll(keepingCapacity: true)
                pendingHead = 0
                workerScheduled = false
                enqueueLock.unlock()
                return
            }
            let storageID = pendingOrder[pendingHead]
            pendingHead += 1
            let pending = pendingWrites.removeValue(forKey: storageID)
            if pendingHead == pendingOrder.count {
                pendingOrder.removeAll(keepingCapacity: true)
                pendingHead = 0
            }
            enqueueLock.unlock()
            pending?.perform()
        }
    }

    /// Suspends until all saves enqueued before this call have finished and returns
    /// their failures. If another save is queued while waiting, that save is drained
    /// too. Useful when a caller must not close after a failed save.
    static func drain() async -> [String] {
        var allFailures: [String] = []
        while true {
            let batch: (through: UInt64, current: UInt64, failures: [String]) = await withCheckedContinuation { continuation in
                enqueueLock.lock()
                let through = enqueueGeneration
                queue.async {
                    let failures = failuresSinceDrain.values.sorted()
                    failuresSinceDrain.removeAll(keepingCapacity: true)
                    enqueueLock.lock()
                    let current = enqueueGeneration
                    enqueueLock.unlock()
                    continuation.resume(returning: (through, current, failures))
                }
                enqueueLock.unlock()
            }
            allFailures.append(contentsOf: batch.failures)
            if batch.current == batch.through { return allFailures }
        }
    }

    static func write(_ data: Data, key: String, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(key + ".json"), options: .atomic)
    }
}
