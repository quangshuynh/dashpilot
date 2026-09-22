import Foundation

/// One delivery the app is willing to remind the driver about, and what the
/// reminder offers.
///
/// ## It is a suggestion, and the distinction is the whole feature
///
/// DashPilot observes no delivery platform and reads no order. It cannot see a
/// driver walk into a restaurant, take a bag or get back into the car. What it
/// can see is its **own record**: that a delivery has recorded nothing newer
/// than its acceptance for the last three quarters of an hour, which is a fact
/// about the record rather than a fact about the world.
///
/// So nothing here writes a timestamp, and nothing here is a detection. A
/// suggestion is a sentence and a button; the button runs exactly the lifecycle
/// action the delivery's own card already offers, through exactly the same
/// service, and only because the driver pressed it. Every word the type prints
/// is chosen so that a driver who is genuinely still waiting reads it as a
/// question they can ignore rather than as a claim they have to correct.
///
/// ## Nothing about it is stored
///
/// A suggestion is derived from the timestamps a delivery already records, for
/// the instant it is asked about, and is thrown away with the screen that asked.
/// There is no column, no entity, no schema version and no exported field: a
/// reminder is not a fact about the driver's work, and a store that remembered
/// which reminders a driver had seen would be recording their attention rather
/// than their deliveries.
nonisolated struct DeliveryProgressSuggestion: Identifiable, Equatable, Sendable {
    /// The delivery this is about. The panel acts on the record with this
    /// identity and never on whichever card happens to sit in the same place.
    let deliveryID: UUID

    /// What the interface calls that delivery.
    let number: Int

    /// The state the delivery is in, which is the state the reminder is about.
    let state: DeliveryState

    /// The delivery's own next lifecycle action.
    ///
    /// Always ``DeliveryState/nextAction`` for ``state``, never a step chosen
    /// here: the suggestion offers the one thing the card below it offers, so
    /// there is no path by which pressing a reminder records something the
    /// ordinary control could not.
    let action: DeliveryAction

    /// How long the delivery has recorded nothing newer, at the instant the
    /// suggestion was derived.
    ///
    /// Stated rather than kept private, because it is the whole of the evidence
    /// and a driver is owed it. It is a duration and never a judgement: the
    /// interface prints it and says what it is, and says nothing about whether
    /// it is long.
    let stillRecordingNothingNewerFor: TimeInterval

    /// A suggestion is about one delivery at a time, so the delivery's identity
    /// is the suggestion's.
    var id: UUID { deliveryID }

    /// What the interface calls the delivery, from the app's one definition of
    /// that name.
    var title: String { NumberedDelivery.title(number: number) }

    /// The fact the reminder rests on, written as a fact.
    ///
    /// It describes **the record**: what the delivery last recorded and how long
    /// ago. It does not say the driver arrived, waited, collected anything or
    /// went anywhere, because DashPilot did not see any of that.
    var evidenceStatement: String {
        let figure = DurationText.short(stillRecordingNothingNewerFor)
        switch state {
        case .accepted:
            return "Accepted \(figure) ago · no arrival recorded"
        case .arrivedAtPickup:
            return "At the pickup \(figure) ago · no pickup recorded"
        case .pickedUp, .delivered, .cancelled:
            return "Nothing newer recorded for \(figure)"
        }
    }

    /// The same fact spoken, where a middle dot is punctuation rather than a
    /// word and the delivery has to name itself.
    var spokenEvidenceStatement: String {
        let figure = DurationText.spoken(stillRecordingNothingNewerFor)
        switch state {
        case .accepted:
            return "\(title) was accepted \(figure) ago and records no arrival at the pickup."
        case .arrivedAtPickup:
            return "\(title) reached the pickup \(figure) ago and records no pickup."
        case .pickedUp, .delivered, .cancelled:
            return "\(title) has recorded nothing newer for \(figure)."
        }
    }

    /// The question, which is a question on purpose.
    ///
    /// Not `You arrived`, not `You picked up`, not `DashPilot detected`. The app
    /// has no evidence for any of those sentences and writing one would be the
    /// single thing this feature must not do: teach a driver that DashPilot
    /// knows where they are, so that the day it is wrong they believe it.
    var question: String {
        switch state {
        case .accepted: "Already at the pickup?"
        case .arrivedAtPickup: "Already picked this order up?"
        case .pickedUp, .delivered, .cancelled: "Is this still in progress?"
        }
    }

    /// The sentence that says what the app does **not** know, printed and spoken
    /// with every suggestion and never abbreviated away.
    ///
    /// It is a constant rather than a per-state string because it is a statement
    /// about DashPilot rather than about any delivery, and because a caveat that
    /// varies reads as a caveat that might sometimes not apply.
    static let uncertaintyStatement = """
        DashPilot cannot tell where you are. This is a reminder from your own recorded times, \
        not something it observed.
        """

    /// What the confirming control prints.
    ///
    /// It names the delivery, unlike the card's own lifecycle button, which sits
    /// under a heading that has already named one. A reminder can appear beside
    /// another reminder for a different delivery, so the name is the only thing
    /// telling the two apart, and a control that records a lifecycle event
    /// against the wrong order is the mistake this whole area is designed
    /// against.
    var actionTitle: String { "Mark \(title) \(action.title)" }

    /// What VoiceOver hears for it: the app's existing spoken form of the
    /// action, named for its delivery exactly as every control on a list of
    /// deliveries is.
    var spokenActionLabel: String {
        "\(title). \(action.spokenLabel). Records it now, from this reminder."
    }

    /// What the dismissing control prints. Two words, and neither of them
    /// `Cancel`: nothing here cancels a delivery.
    var dismissTitle: String { "Not Yet" }

    /// What VoiceOver hears for it, which states the consequence rather than the
    /// word, because the consequence is that nothing at all happens.
    var spokenDismissLabel: String {
        "Not yet. Hides this reminder for \(title). Nothing is recorded and \(title) is unchanged."
    }

    /// The whole reminder as one spoken element, for the card that combines it.
    var spokenLabel: String {
        [spokenEvidenceStatement, question, Self.uncertaintyStatement].joined(separator: " ")
    }
}

/// One delivery as the assistance policy reads it: an identity, the number the
/// interface calls it, and the timestamps it records.
///
/// A value rather than the model, so the policy is a pure function that can be
/// tested without a store, a container or a main actor. The record is
/// ``DeliveryLifecycleRecord``, which is the app's one reading of a delivery's
/// timestamps, so the state this policy sees is the state every other part of
/// the app sees.
nonisolated struct AssistedDelivery: Equatable, Sendable {
    let id: UUID
    let number: Int
    let record: DeliveryLifecycleRecord

    init(id: UUID, number: Int, record: DeliveryLifecycleRecord) {
        self.id = id
        self.number = number
        self.record = record
    }

    /// The same delivery as the interface already holds it.
    init(_ numbered: NumberedDelivery) {
        self.init(
            id: numbered.delivery.id,
            number: numbered.number,
            record: DeliveryLifecycleRecord(numbered.delivery)
        )
    }
}

/// When DashPilot is willing to remind a driver that a lifecycle event may have
/// gone unrecorded.
///
/// ## The rule, and why it is this one
///
/// **Elapsed time in the delivery's current state, and nothing else.** A
/// delivery that has recorded nothing newer than its acceptance for half an hour
/// is either a long drive to a pickup or an arrival nobody tapped, and DashPilot
/// cannot tell which — so it says so and offers the tap. That is the whole
/// signal.
///
/// ## What was considered and refused, each for a measured reason
///
/// - **Location, in any form.** `investigate/historical-pickup-anchor` measured
///   this and its finding stands: the most common stationary state in delivery
///   work is a driver parked waiting for an offer, which is long, clean and
///   high-accuracy, so a stop-only rule fires hardest on the driver's most
///   common idle state. The discriminator it found — a position derived for a
///   pickup a driver has visited before — is gated on a recall figure nobody has
///   measured on real shifts, and needs three bracketed observations of a place
///   before it will say anything about it. A rule that cannot fire for a new
///   driver at a new restaurant is not the rule to build a reminder on.
/// - **Core Motion.** A new authorization scope, which `AGENTS.md` forbids
///   adding incidentally and which the same investigation already refused.
/// - **A notification.** Nothing here reaches a notification, and DashPilot
///   still registers none. A reminder that fires on a time threshold is exactly
///   the reminder that would fire while the driver is at a customer's door.
/// - **A driver's own recorded pickup-wait median.** It exists, and using it
///   would make the threshold a *prediction* derived from history, which is the
///   claim `AGENTS.md` reserves for things the app can stand behind. A fixed,
///   stated, tunable number claims only to be a fixed number.
///
/// ## Which states it speaks about
///
/// `accepted` and `arrivedAtPickup` only. A delivery that has been picked up is
/// deliberately never the subject of a reminder: with stacked orders, carrying
/// one for three quarters of an hour while delivering another is ordinary work
/// rather than a missed tap, so elapsed time is at its least informative exactly
/// there. The two states it does speak about are also the two the driver is
/// standing still for, which is when a phone is in the hand and a reminder is
/// safe to act on.
///
/// ## Thresholds
///
/// Initial engineering choices, defensible rather than calibrated: nothing has
/// been recorded on a real shift to tune them against. They are properties so
/// that they can be, and they are separate properties although they currently
/// hold the same figure, because a drive to a pickup and a wait at one are
/// different activities and the day there is data to separate them is the day
/// they diverge.
nonisolated struct DeliveryProgressAssistance: Equatable, Sendable {
    /// How long a delivery may record only its acceptance before the app offers
    /// to record the arrival.
    ///
    /// Half an hour. A drive to a pickup longer than that is unusual, and a
    /// reminder that arrives late costs nothing: the tap it offers is the same
    /// tap whenever it is taken.
    var minimumTimeSinceAcceptance: TimeInterval = 30 * 60

    /// How long a delivery may sit at its pickup before the app offers to record
    /// the pickup.
    ///
    /// Half an hour, against a recorded pickup-wait median across the project's
    /// synthetic fixtures of about eleven minutes. Long enough that an ordinary
    /// busy restaurant does not produce one.
    var minimumTimeSinceArrival: TimeInterval = 30 * 60

    init(
        minimumTimeSinceAcceptance: TimeInterval = 30 * 60,
        minimumTimeSinceArrival: TimeInterval = 30 * 60
    ) {
        self.minimumTimeSinceAcceptance = minimumTimeSinceAcceptance
        self.minimumTimeSinceArrival = minimumTimeSinceArrival
    }

    /// Every delivery the app is willing to say something about, in the order it
    /// was given them.
    ///
    /// **Each delivery is judged on its own record.** Nothing here reads a
    /// sibling, an offer, the shift or another delivery's state, so a stacked
    /// driver gets a reminder for the order that is actually stale and not for
    /// the one beside it.
    func suggestions(among deliveries: [AssistedDelivery], asOf now: Date) -> [DeliveryProgressSuggestion] {
        deliveries.compactMap { suggestion(for: $0, asOf: now) }
    }

    /// The reminder for one delivery, or `nil` where there is nothing the app
    /// can honestly offer.
    ///
    /// Returns `nil` for: a finished delivery, in either terminal state; a
    /// delivery already picked up; a row whose recorded times contradict each
    /// other or that records a pickup with no arrival, which is a store the app
    /// cannot write and not evidence of anything; a delivery whose latest
    /// recorded instant is in the future; and a delivery that has simply not
    /// been waiting long enough.
    func suggestion(for delivery: AssistedDelivery, asOf now: Date) -> DeliveryProgressSuggestion? {
        let record = delivery.record

        // A terminal delivery is never the subject of a reminder. It is the
        // first rule rather than a consequence of the switch below, because it
        // is the one a reader of this file should not have to derive.
        guard !record.isFinished else { return nil }

        // An anomalous chain is not evidence. Two times running backwards do not
        // say which of them is wrong, and a pickup with no arrival is a row the
        // lifecycle refuses to produce; neither is something to build a sentence
        // on.
        guard record.isChronological, !record.recordsPickupWithoutArrival else { return nil }

        let state = record.state
        let since: Date
        let threshold: TimeInterval

        switch state {
        case .accepted:
            since = record.acceptedAt
            threshold = minimumTimeSinceAcceptance
        case .arrivedAtPickup:
            guard let arrivedAtPickupAt = record.arrivedAtPickupAt else { return nil }
            since = arrivedAtPickupAt
            threshold = minimumTimeSinceArrival
        // Deliberately silent. See the type's own documentation: elapsed time
        // says least about a delivery that is already in the car.
        case .pickedUp: return nil
        case .delivered, .cancelled: return nil
        }

        let elapsed = now.timeIntervalSince(since)
        guard elapsed >= threshold else { return nil }

        // The action is the delivery's own next step, read from the state rather
        // than chosen here. The `guard` is unreachable for the two states above
        // and is what makes that true by construction rather than by comment.
        guard let action = state.nextAction else { return nil }

        return DeliveryProgressSuggestion(
            deliveryID: delivery.id,
            number: delivery.number,
            state: state,
            action: action,
            stillRecordingNothingNewerFor: elapsed
        )
    }
}
