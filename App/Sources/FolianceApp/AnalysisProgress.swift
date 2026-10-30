import Foundation

/// Estimates work across phases; percentages are estimates, never a timer animation.
struct AnalysisProgress {
    var phases = 1
    var phase = -1
    var fraction = 0.0
    var started = Date()
    var phaseStarted = Date()
    var samples = 0
    var phaseCompleted = 0
    var phaseTotal = 0
    var requiresConservativeChatGPTETA = false
    var completionUpdates = 0
    private var estimateCompletedHighWater = 0
    private(set) var isMergingSummary = false
    private(set) var mergeCompleted = 0
    mutating func begin(phases: Int, chatGPT: Bool = false, now: Date = Date()) {
        self = AnalysisProgress(phases: max(1, phases), started: now, phaseStarted: now,
                                requiresConservativeChatGPTETA: chatGPT)
    }
    mutating func next(now: Date = Date()) {
        phase += 1; phaseStarted = now; samples = 0; phaseCompleted = 0; phaseTotal = 0
        completionUpdates = 0; estimateCompletedHighWater = 0
        isMergingSummary = false; mergeCompleted = 0
        fraction = max(fraction, Double(phase) / Double(phases))
    }
    mutating func update(completed: Int, total: Int, now: Date = Date()) {
        guard total > 0 else { return }
        if requiresConservativeChatGPTETA, completed < 0 {
            phaseStarted = now; samples = 0; phaseCompleted = 0; phaseTotal = total
            completionUpdates = 0; estimateCompletedHighWater = 0
            isMergingSummary = false; mergeCompleted = 0
            return
        }
        let positiveCompletion = max(0, completed)
        if positiveCompletion > estimateCompletedHighWater {
            completionUpdates += 1
            estimateCompletedHighWater = positiveCompletion
        }
        samples = max(samples, completed)
        phaseCompleted = positiveCompletion; phaseTotal = total
        // Reserve time for merging and source checks whose workload is not known yet.
        let within = (isMergingSummary ? 0 : min(0.9, Double(max(0, completed)) / Double(total) * 0.9))
        fraction = max(fraction, (Double(max(0, phase)) + within) / Double(phases))
    }
    mutating func updateSummaryMerge(completed: Int, total: Int, now: Date = Date()) {
        guard requiresConservativeChatGPTETA, total > 0 else { return }
        if !isMergingSummary {
            isMergingSummary = true
            phaseStarted = now; samples = 0; phaseCompleted = 0
            completionUpdates = 0; estimateCompletedHighWater = 0
            mergeCompleted = 0
        }
        let mergeDone = max(0, completed)
        if mergeDone > estimateCompletedHighWater {
            completionUpdates += 1
            estimateCompletedHighWater = mergeDone
        }
        mergeCompleted = max(mergeCompleted, mergeDone)
        samples = max(samples, mergeCompleted)
        phaseCompleted = mergeCompleted; phaseTotal = total
        let within = 0.9 + 0.1 * min(1, Double(mergeCompleted) / Double(total))
        fraction = max(fraction, (Double(max(0, phase)) + within) / Double(phases))
    }
    func activity(now: Date = Date()) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(started)))
        let duration = "\(elapsed / 60):" + String(format: "%02d", elapsed % 60)
        let count = phaseTotal > 0 ? "\(phaseCompleted) van \(phaseTotal) \(isMergingSummary ? "samenvoegingen" : "stappen") gereed · " : ""
        return count + "Verstreken \(duration) · " + (phaseTotal > 0 && phaseCompleted >= phaseTotal ? "Afronden…" : "Bezig; wachten op of verwerken van antwoord…")
    }
    var percent: Int { min(99, max(0, Int(fraction * 100))) }
    func remaining(now: Date = Date()) -> String {
        let elapsed = now.timeIntervalSince(phaseStarted)
        let warmedUp = requiresConservativeChatGPTETA
            ? completionUpdates >= 3 && elapsed >= 15
            : samples >= 2 && elapsed >= 3
        guard warmedUp, phaseCompleted > 0, phaseTotal > phaseCompleted else {
            return phaseTotal > 0 && phaseCompleted >= phaseTotal ? "Deze fase wordt afgerond…" : "Resterende tijd voor deze fase berekenen…"
        }
        let seconds = max(1, elapsed / Double(phaseCompleted) * Double(phaseTotal - phaseCompleted))
        if seconds < 60 { return "Deze fase: nog ongeveer minder dan een minuut" }
        return "Deze fase: nog ongeveer \(Int(ceil(seconds / 60))) min"
    }
    mutating func resetChatGPTEstimateForCancellation(now: Date = Date()) {
        guard requiresConservativeChatGPTETA else { return }
        phaseStarted = now; samples = 0; phaseCompleted = 0
        completionUpdates = 0; estimateCompletedHighWater = 0
        isMergingSummary = false; mergeCompleted = 0
    }
}
