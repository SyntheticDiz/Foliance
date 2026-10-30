import Foundation

private struct ChatGPTScheduledOperationResult<Output: Sendable>: Sendable {
    let output: Output
    let requests: ChatGPTRequestObservation.Snapshot
    let completedAt: TimeInterval
}

/// Shared limits for work sent to the online ChatGPT provider.
enum ChatGPTWork {
    static let maximumConcurrentRequests = 32
    static let maximumConcurrency = maximumConcurrentRequests

    static func passageConcurrency(model: String) -> Int {
        let worker = AIConfiguration.workerModel(model)
        return AIConfiguration.chatGPTSelection(worker) == nil ? 2 : maximumConcurrency
    }

    /// Summary merges run through the orchestrator, so use its selected ChatGPT
    /// configuration to distinguish cloud work from local-provider work.
    static func summaryMergeConcurrency(orchestratorModel model: String) -> Int {
        AIConfiguration.chatGPTSelection(AIConfiguration.orchestratorModel(model)) == nil ? 2 : maximumConcurrency
    }

    static func textChunkLimit(model: String) -> Int {
        AIConfiguration.isChatGPT(model) ? 3_000 : 900
    }

    /// Runs at most 32 operations at a time by default and returns values in input order.
    /// A thrown error or parent cancellation cancels outstanding sibling tasks.
    static func batch<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        operation: @escaping @Sendable (Input) async throws -> Output
    ) async throws -> [Output] {
        guard !inputs.isEmpty else { return [] }
        var results = Array<Output?>(repeating: nil, count: inputs.count)
        try await forEach(inputs, operation: operation) { index, output in
            results[index] = output
        }
        return results.map { $0! }
    }

    /// Default callers retain ordered delivery and up to 32 concurrent operations.
    /// The ChatGPT passage path may publish finished packages immediately, while
    /// its caller rebuilds visible results in source order.
    static func forEach<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        maximumConcurrent: Int = maximumConcurrentRequests,
        orderedDelivery: Bool = true,
        adaptiveBackoff: Bool = true,
        onRetry: @escaping @Sendable () async -> Void = {},
        operation: @escaping @Sendable (Input) async throws -> Output,
        onOrderedResult: (Int, Output) async -> Void
    ) async throws {
        try await schedule(inputs, maximumConcurrent: maximumConcurrent, maximumWindow: maximumConcurrency,
                           orderedDelivery: orderedDelivery, adaptiveBackoff: adaptiveBackoff,
                           onRetry: onRetry, sleep: productionSleep, jitter: productionJitter,
                           now: productionUptime,
                           operation: operation, onOrderedResult: onOrderedResult)
    }

    /// Summary merges use the selected orchestrator and the shared cloud limit.
    /// Results retain their source indexes; temporary overloads reduce this
    /// invocation's window and share a bounded cooldown across all work.
    static func summaryMergeForEach<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        orchestratorModel model: String,
        orderedDelivery: Bool = true,
        onRetry: @escaping @Sendable () async -> Void = {},
        operation: @escaping @Sendable (Input) async throws -> Output,
        onOrderedResult: (Int, Output) async -> Void
    ) async throws {
        try await schedule(inputs, maximumConcurrent: summaryMergeConcurrency(orchestratorModel: model), maximumWindow: maximumConcurrency,
                           orderedDelivery: orderedDelivery, adaptiveBackoff: true,
                           onRetry: onRetry, sleep: productionSleep, jitter: productionJitter,
                           now: productionUptime,
                           operation: operation, onOrderedResult: onOrderedResult)
    }

    /// Deterministic seam for scheduler regression tests. Production callers use
    /// the fixed backoff policy and real cancellation-aware sleeps above.
    static func forEachTesting<Input: Sendable, Output: Sendable>(
        _ inputs: [Input], maximumConcurrent: Int = maximumConcurrentRequests,
        orderedDelivery: Bool = true,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void,
        jitter: @escaping @Sendable () -> TimeInterval = { 0 },
        now: @escaping @Sendable () -> TimeInterval = productionUptime,
        observeOperation: Bool = false,
        onRetry: @escaping @Sendable () async -> Void = {},
        onWindowChange: @escaping @Sendable (Int) async -> Void = { _ in },
        operation: @escaping @Sendable (Input) async throws -> Output,
        onOrderedResult: (Int, Output) async -> Void
    ) async throws {
        try await schedule(inputs, maximumConcurrent: maximumConcurrent, maximumWindow: maximumConcurrency,
                           orderedDelivery: orderedDelivery, adaptiveBackoff: true,
                           onRetry: onRetry, sleep: sleep, jitter: jitter,
                           now: now, observeOperation: observeOperation,
                           onWindowChange: onWindowChange,
                           operation: operation, onOrderedResult: onOrderedResult)
    }

    private static func schedule<Input: Sendable, Output: Sendable>(
        _ inputs: [Input], maximumConcurrent: Int, maximumWindow: Int,
        orderedDelivery: Bool, adaptiveBackoff: Bool,
        onRetry: @escaping @Sendable () async -> Void,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void,
        jitter: @escaping @Sendable () -> TimeInterval,
        now: @escaping @Sendable () -> TimeInterval,
        observeOperation: Bool = false,
        onWindowChange: @escaping @Sendable (Int) async -> Void = { _ in },
        operation: @escaping @Sendable (Input) async throws -> Output,
        onOrderedResult: (Int, Output) async -> Void
    ) async throws {
        guard !inputs.isEmpty else { return }
        try await withThrowingTaskGroup(of: (Int, Result<ChatGPTScheduledOperationResult<Output>, Error>).self) { group in
            let requestedWindow = min(maximumWindow, max(1, maximumConcurrent))
            var window = requestedWindow
            var nextIndex = 0, nextToPublish = 0, active = 0
            var completed: [Int: Output] = [:]
            var retryCount: [Int: Int] = [:]
            var retryErrors: [Int: Error] = [:]
            var pendingRetries: [Int] = []
            var retriesInFlight: Set<Int> = []
            var cooldown: TimeInterval = 0
            var retryWaitBudget: TimeInterval = 0
            var recoveryStartedAt: TimeInterval?
            var recoverySuccesses = 0
            await onWindowChange(window)
            func enqueue(_ index: Int) {
                let input = inputs[index]
                let observation = ChatGPTRequestObservation.Recorder(now: now)
                group.addTask {
                    await ChatGPTRequestObservation.$current.withValue(observation) {
                        do {
                            try Task.checkCancellation()
                            if observeOperation {
                                let output = try await ChatGPTRequestObservation.perform { try await operation(input) }
                                return (index, .success(ChatGPTScheduledOperationResult(output: output, requests: observation.snapshot(), completedAt: now())))
                            }
                            let output = try await operation(input)
                            return (index, .success(ChatGPTScheduledOperationResult(output: output, requests: observation.snapshot(), completedAt: now())))
                        } catch { return (index, .failure(error)) }
                    }
                }
            }
            while nextIndex < min(window, inputs.count) {
                enqueue(nextIndex); nextIndex += 1; active += 1
            }
            while let (index, result) = try await group.next() {
                active -= 1
                retriesInFlight.remove(index)
                try Task.checkCancellation()
                switch result {
                case .failure(let error):
                    guard adaptiveBackoff, let serverDelay = retryDelay(error) else { throw error }
                    let attempt = retryCount[index, default: 0]
                    guard attempt < maximumRetriesPerItem else { throw error }
                    let delay: TimeInterval
                    if let serverDelay {
                        // A long server delay is returned to the caller instead of
                        // silently retrying before the provider says it is safe.
                        guard serverDelay <= maximumAutomaticWait else { throw error }
                        delay = serverDelay
                    } else {
                        delay = min(20, 5 * pow(2, Double(attempt))) + max(0, jitter())
                    }
                    retryCount[index] = attempt + 1
                    retryErrors[index] = error
                    // Several in-flight requests can report the same pressure
                    // burst. Reduce once, then drain that burst before waiting
                    // and starting the next wave. Otherwise 32 simultaneous
                    // rejections would collapse the window to one immediately.
                    if cooldown == 0 {
                        window = max(1, window / 2)
                        let pressureAt = now()
                        recoveryStartedAt = pressureAt
                        recoverySuccesses = 0
                        await onWindowChange(window)
                    }
                    cooldown = max(cooldown, delay)
                    pendingRetries.append(index)
                    AnalysisMetrics.current?.retry(AnalysisMetrics.phase)
                    await onRetry()
                case .success(let operationResult):
                    let output = operationResult.output
                    if let recoveryEpoch = recoveryStartedAt,
                       operationResult.requests.isFullySuccessfulRequestOperation,
                       let requestStartedAt = operationResult.requests.firstRequestUptime,
                       requestStartedAt > recoveryEpoch {
                        recoverySuccesses += 1
                        if cooldown == 0, pendingRetries.isEmpty, retriesInFlight.isEmpty,
                           operationResult.completedAt - recoveryEpoch >= recoveryStableSeconds,
                           recoverySuccesses >= max(minimumRecoverySuccesses, 2 * window),
                           window < requestedWindow {
                            window = min(requestedWindow, window + max(1, window / 4))
                            selfResetRecovery()
                            await onWindowChange(window)
                        }
                    }
                    if orderedDelivery {
                        completed[index] = output
                        while let value = completed.removeValue(forKey: nextToPublish) {
                            await onOrderedResult(nextToPublish, value)
                            nextToPublish += 1
                        }
                    } else { await onOrderedResult(index, output) }
                }
                if cooldown > 0 && active > 0 { continue }
                while active < window && (!pendingRetries.isEmpty || nextIndex < inputs.count) {
                    if cooldown > 0 {
                        guard retryWaitBudget + cooldown <= maximumRetryWaitBudget else {
                            if let index = pendingRetries.first, let error = retryErrors[index] { throw error }
                            throw ChatGPTError.rateLimited(retryAfter: cooldown)
                        }
                        try await sleep(cooldown)
                        try Task.checkCancellation()
                        retryWaitBudget += cooldown
                        cooldown = 0
                    }
                    if !pendingRetries.isEmpty {
                        let index = pendingRetries.removeFirst()
                        retriesInFlight.insert(index)
                        enqueue(index)
                    }
                    else { enqueue(nextIndex); nextIndex += 1 }
                    active += 1
                }
            }
            try Task.checkCancellation()

            func selfResetRecovery() {
                recoveryStartedAt = now()
                recoverySuccesses = 0
            }
        }
    }

    private static let maximumRetriesPerItem = 3
    private static let maximumAutomaticWait: TimeInterval = 60
    private static let maximumRetryWaitBudget: TimeInterval = 180
    private static let recoveryStableSeconds: TimeInterval = 30
    private static let minimumRecoverySuccesses = 8

    private static func retryDelay(_ error: Error) -> TimeInterval?? {
        guard let error = error as? ChatGPTError else { return nil }
        switch error {
        case .rateLimited(let delay), .temporarilyUnavailable(let delay):
            if let delay, delay.isFinite, delay >= 0 { return .some(delay == 0 ? 1 : delay) }
            return .some(nil)
        case .http(503): return .some(nil)
        default: return nil
        }
    }

    private static let productionSleep: @Sendable (TimeInterval) async throws -> Void = { seconds in
        try await Task.sleep(for: .seconds(seconds))
    }

    private static let productionJitter: @Sendable () -> TimeInterval = { Double.random(in: 0...1) }
    private static let productionUptime: @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
}
