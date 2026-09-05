import Foundation

/// How many deliveries a shift recorded, and how they ended.
///
/// A count, not an analysis. It exists so the completed-shift screen can state
/// what the shift holds in one tested sentence rather than assembling one out
/// of pluralised fragments in a view body, and it deliberately derives nothing
/// beyond counting: no rate per delivery, no average, no comparison between
/// shifts and no score. Those need data DashPilot does not have yet, and a
/// figure that looks like a performance measure is read as one.
nonisolated struct DeliverySummary: Equatable, Sendable {
    let completed: Int
    let cancelled: Int
    /// Deliveries still running. Zero for a completed shift, because a shift
    /// cannot end while one is active — kept because the type is also used
    /// against a store that could hold anomalous data.
    let inProgress: Int

    init(completed: Int, cancelled: Int, inProgress: Int = 0) {
        self.completed = completed
        self.cancelled = cancelled
        self.inProgress = inProgress
    }

    init(states: some Sequence<DeliveryState>) {
        var completed = 0
        var cancelled = 0
        var inProgress = 0
        for state in states {
            switch state {
            case .delivered: completed += 1
            case .cancelled: cancelled += 1
            case .accepted, .arrivedAtPickup, .pickedUp: inProgress += 1
            }
        }
        self.init(completed: completed, cancelled: cancelled, inProgress: inProgress)
    }

    var recorded: Int { completed + cancelled + inProgress }

    var isEmpty: Bool { recorded == 0 }

    /// The printed sentence, with each outcome named rather than summed.
    ///
    /// A cancelled delivery is history, not a completed one and not a deleted
    /// one, so it is counted separately and never folded into a single total.
    var statement: String {
        guard !isEmpty else { return "No deliveries recorded" }
        var parts: [String] = []
        if completed > 0 || cancelled == 0 {
            parts.append("\(completed) \(Self.noun(completed)) completed")
        }
        if cancelled > 0 {
            parts.append("\(cancelled) cancelled")
        }
        if inProgress > 0 {
            parts.append("\(inProgress) still in progress")
        }
        return parts.joined(separator: " · ")
    }

    /// The same facts as sentences, for VoiceOver, where the separator is not
    /// spoken and "1 deliveries" is heard rather than skimmed.
    var spokenStatement: String {
        guard !isEmpty else { return "No deliveries recorded" }
        var parts: [String] = []
        if completed > 0 || cancelled == 0 {
            parts.append("\(completed) \(Self.noun(completed)) completed")
        }
        if cancelled > 0 {
            parts.append("\(cancelled) \(Self.noun(cancelled)) cancelled")
        }
        if inProgress > 0 {
            parts.append("\(inProgress) \(Self.noun(inProgress)) still in progress")
        }
        return parts.joined(separator: ". ")
    }

    /// The running shift's headline: how many deliveries are being worked right
    /// now.
    ///
    /// Separate from ``statement`` because the two answer different questions. A
    /// driver glancing at a running shift wants to know how many orders they are
    /// carrying; the statement is the shift's whole record, in-progress count
    /// included.
    var inProgressStatement: String {
        guard inProgress > 0 else { return "No delivery in progress" }
        return "\(inProgress) \(Self.noun(inProgress)) in progress"
    }

    private static func noun(_ count: Int) -> String {
        count == 1 ? "delivery" : "deliveries"
    }
}
