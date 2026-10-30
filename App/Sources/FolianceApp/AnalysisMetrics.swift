import Foundation

/// Local timing only: never records document text, prompts, responses or file names.
enum AnalysisMetrics {
    @TaskLocal static var current: Recorder? = nil
    @TaskLocal static var phase = "other"
    @TaskLocal static var outputDirectory: URL? = nil

    struct Phase: Codable, Sendable {
        var elapsedSeconds = 0.0
        var requests = 0
        var requestSeconds = 0.0 // Sum of request durations; can exceed wall time.
        var failedRequests = 0
        var retries = 0
        var cacheHits = 0
        var cacheMisses = 0
        var peakRequests = 0
    }
    struct Report: Codable, Sendable {
        let id: UUID
        let startedAt: Date
        let model: String
        let operation: String
        let appVersion: String?
        let build: String?
        let testRun: Bool?
        let elapsedSeconds: Double
        let firstResultSeconds: Double?
        let firstMainResultSeconds: Double?
        let firstSummarySeconds: Double?
        let outcome: String
        let phases: [String: Phase]
    }
    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private let id = UUID()
        private let startedAt = Date()
        private let start = ProcessInfo.processInfo.systemUptime
        private let model: String
        private let operation: String
        private let appVersion: String?
        private let build: String?
        private let testRun: Bool
        private var phases: [String: Phase] = [:]
        private var active: [String: Int] = [:]
        private var first: Double?
        private var firstMain: Double?
        private var firstSummary: Double?

        init(model: String, operation: String) {
            self.model = model
            self.operation = operation
            self.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            self.build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            self.testRun = AnalysisMetrics.isTestHost
        }
        func elapsed(_ phase: String, seconds: Double) {
            lock.lock(); defer { lock.unlock() }
            phases[phase, default: Phase()].elapsedSeconds += max(0, seconds)
        }
        func cache(_ phase: String, hit: Bool) {
            lock.lock(); defer { lock.unlock() }
            if hit { phases[phase, default: Phase()].cacheHits += 1 }
            else { phases[phase, default: Phase()].cacheMisses += 1 }
        }
        func retry(_ phase: String) {
            lock.lock(); defer { lock.unlock() }
            phases[phase, default: Phase()].retries += 1
        }
        func requestStarted(_ phase: String) {
            lock.lock(); defer { lock.unlock() }
            phases[phase, default: Phase()].requests += 1
            active[phase, default: 0] += 1
            phases[phase, default: Phase()].peakRequests = max(phases[phase, default: Phase()].peakRequests, active[phase, default: 0])
        }
        func requestEnded(_ phase: String, seconds: Double, failed: Bool) {
            lock.lock(); defer { lock.unlock() }
            phases[phase, default: Phase()].requestSeconds += max(0, seconds)
            if failed { phases[phase, default: Phase()].failedRequests += 1 }
            active[phase, default: 0] -= 1
        }
        func result(main: Bool) {
            lock.lock(); defer { lock.unlock() }
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            if first == nil { first = elapsed }
            if main && firstMain == nil { firstMain = elapsed }
        }
        func summaryReady() {
            lock.lock(); defer { lock.unlock() }
            if firstSummary == nil { firstSummary = ProcessInfo.processInfo.systemUptime - start }
        }
        func report(outcome: String) -> Report {
            lock.lock(); defer { lock.unlock() }
            return Report(id: id, startedAt: startedAt, model: model, operation: operation,
                          appVersion: appVersion, build: build, testRun: testRun,
                          elapsedSeconds: ProcessInfo.processInfo.systemUptime - start,
                          firstResultSeconds: first, firstMainResultSeconds: firstMain, firstSummarySeconds: firstSummary,
                          outcome: outcome, phases: phases)
        }
    }

    static func withPhase<T>(_ name: String, recorder: Recorder?, operation: () async throws -> T) async rethrows -> T {
        let start = ProcessInfo.processInfo.systemUptime
        defer { recorder?.elapsed(name, seconds: ProcessInfo.processInfo.systemUptime - start) }
        return try await $current.withValue(recorder) {
            try await $phase.withValue(name) { try await operation() }
        }
    }
    static func request<T>(_ operation: () async throws -> T) async rethrows -> T {
        guard let recorder = current else { return try await operation() }
        let name = phase, start = ProcessInfo.processInfo.systemUptime
        recorder.requestStarted(name)
        do {
            let result = try await operation()
            recorder.requestEnded(name, seconds: ProcessInfo.processInfo.systemUptime - start, failed: false)
            return result
        } catch {
            recorder.requestEnded(name, seconds: ProcessInfo.processInfo.systemUptime - start, failed: true)
            throw error
        }
    }
    static var directory: URL {
        if let outputDirectory { return outputDirectory }
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return defaultDirectory(cachesDirectory: cachesDirectory, temporaryDirectory: FileManager.default.temporaryDirectory,
                                processIdentifier: Int(ProcessInfo.processInfo.processIdentifier), testRun: isTestHost)
    }
    static var isTestHost: Bool { isTestHost(bundleURL: Bundle.main.bundleURL, processName: ProcessInfo.processInfo.processName) }

    static func isTestHost(bundleURL: URL, processName: String) -> Bool {
        let name = processName.lowercased()
        return bundleURL.pathExtension.lowercased() == "xctest"
            || name.contains("xctest")
            || name.hasSuffix("tests")
    }

    static func defaultDirectory(cachesDirectory: URL, temporaryDirectory: URL, processIdentifier: Int, testRun: Bool) -> URL {
        if testRun {
            return temporaryDirectory.appendingPathComponent("Foliance/analysis-metrics-tests/\(processIdentifier)", isDirectory: true)
        }
        return cachesDirectory.appendingPathComponent("Foliance/analysis-metrics", isDirectory: true)
    }
    /// Keep a bounded history; diagnostics must never affect an analysis outcome.
    private static let persistenceLock = NSLock()
    static func save(_ report: Report, to directory: URL) {
        persistenceLock.lock(); defer { persistenceLock.unlock() }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let url = directory.appendingPathComponent(report.id.uuidString + ".json")
            try encoder.encode(report).write(to: url, options: .atomic)
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
                .filter { $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
                .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            for old in files.dropFirst(20) { try? FileManager.default.removeItem(at: old) }
        } catch { /* Timing is best-effort; no document processing is blocked. */ }
    }
}
