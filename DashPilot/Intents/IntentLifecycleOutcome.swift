import Foundation

/// What an intent recorded, and the sentence DashPilot says back about it.
///
/// A voice surface has no screen to glance at afterwards, so the confirmation
/// is the only report the driver gets. That makes the wording part of the
/// feature rather than decoration around it, which is why it lives in a tested
/// value type instead of being assembled inside an intent.
///
/// Two rules hold for every sentence here:
///
/// - **It states only what was just recorded.** No earnings, no distance, no
///   place name, no rate. An intent writes one timestamp, and the confirmation
///   says so.
/// - **What is unknown is left unsaid rather than filled in.** The delivery
///   number and the in-progress count are optional for that reason: a
///   confirmation that invented "Delivery 1" would be naming a record the app
///   had not identified.
nonisolated enum IntentLifecycleOutcome: Equatable, Sendable {
    /// A shift began at the recorded time.
    case shiftStarted(at: Date)

    /// A shift ended, having run for `duration`.
    ///
    /// The duration is optional because it is read from the shift rather than
    /// assumed: a shift the store somehow holds without an end has no length to
    /// report, and zero is a different claim from "not known".
    case shiftEnded(duration: TimeInterval?)

    /// A delivery began, alongside however many were already running.
    case deliveryStarted(number: Int?, inProgress: Int?)

    /// One delivery reached `state`, read back from the delivery after the
    /// write rather than from what was asked for.
    case deliveryEventRecorded(number: Int?, state: DeliveryState)

    /// What Siri says, and what the Shortcuts app shows.
    var confirmation: String {
        switch self {
        case let .shiftStarted(date):
            // The route caution travels with every start, and says the thing
            // that is actually true: recording carries on once it is running,
            // but it can only be *started* with the app on screen. A shift
            // started by voice and driven with the phone locked records no
            // mileage at all, and the driver has no screen to notice it on.
            """
            Shift started at \(date.formatted(date: .omitted, time: .shortened)). \
            Open DashPilot to start recording your route.
            """
        case let .shiftEnded(duration):
            if let duration {
                "Shift ended after \(DurationText.spoken(duration))."
            } else {
                "Shift ended."
            }
        case let .deliveryStarted(number, inProgress):
            [Self.started(number), Self.inProgressStatement(inProgress)]
                .compactMap { $0 }
                .joined(separator: " ")
        case let .deliveryEventRecorded(number, state):
            "\(Self.name(number)) recorded as \(state.historyDescription.lowercased())."
        }
    }

    private static func started(_ number: Int?) -> String {
        "\(name(number)) started."
    }

    /// How many deliveries are running, in the same words the running shift
    /// prints, or nothing when the count is not known.
    private static func inProgressStatement(_ inProgress: Int?) -> String? {
        guard let inProgress else { return nil }
        return "\(DeliverySummary(completed: 0, cancelled: 0, inProgress: inProgress).inProgressStatement)."
    }

    /// What the delivery is called, in the same words the interface uses, or
    /// the plain noun when its number is not known.
    private static func name(_ number: Int?) -> String {
        guard let number else { return "Delivery" }
        return NumberedDelivery.title(number: number)
    }
}
