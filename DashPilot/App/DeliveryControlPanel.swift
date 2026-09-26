import SwiftData
import SwiftUI

/// The running shift's delivery controls: one card per delivery being worked,
/// each offering only its own next step.
///
/// ## Why a list rather than one button
///
/// A driver can be carrying two or three orders at once, so there is no single
/// "the delivery" for one control to advance. The panel shows each active
/// delivery separately and gives each one a single primary button — whatever
/// ``DeliveryState/nextAction`` says comes next for *that* delivery — so the
/// driver never picks a lifecycle event out of a menu, and never picks which
/// delivery a tap belongs to out of an implicit rule. Two active deliveries
/// means two buttons, each already saying the right thing.
///
/// `Start Delivery` stays available underneath at all times while the shift
/// runs, because accepting another order is normal work rather than an
/// exception. Beside it sits the one control for an offer that held more than
/// one delivery, which records the same kind of work in one write.
///
/// ## Deliveries accepted together are shown together
///
/// Cards are arranged by the offer they arrived in. An offer that held more
/// than one delivery gets a heading over its cards saying so; an offer of one
/// gets nothing at all, which is what the ordinary case looked like before
/// offers existed. The heading is a label and never a control: nothing acts on
/// an offer as a unit, every button still belongs to one delivery, and each card
/// keeps its own next step.
///
/// Every button acts on the persisted delivery its card was built from, so the
/// numbering is a label and nothing more: it could change and a tap would still
/// reach the same record.
///
/// Nothing here is detected. Every tap records an event the driver witnessed;
/// DashPilot does not know that an order was accepted, handed over or received.
///
/// The active deliveries are read from the store rather than held in view
/// state, which is what makes relaunch recovery ordinary: deliveries left active
/// when the app was terminated are all still active on the next launch, each
/// with its own next step.
struct DeliveryControlPanel: View {
    let shift: Shift

    @Environment(\.modelContext) private var modelContext
    /// Write-only from here, like ``RootView``'s: a delivery starting or
    /// advancing changes what the shift's Live Activity should say, including
    /// whether it may offer a step control at all.
    @Environment(ShiftLiveActivityService.self) private var liveActivity

    /// Every unfinished delivery in the store.
    ///
    /// A `@Query` rather than the shift's relationship alone, because it is what
    /// rebuilds the panel when a delivery is inserted or advanced. It says
    /// *which* deliveries are running; the shift supplies the order they were
    /// accepted in, which is where each card's number comes from.
    @Query(
        filter: #Predicate<Delivery> { $0.deliveredAt == nil && $0.cancelledAt == nil },
        sort: \Delivery.acceptedAt
    )
    private var unfinishedDeliveries: [Delivery]

    @State private var lifecycleError: DeliveryLifecycleError?

    /// The delivery a cancellation is being confirmed for. Held as the numbered
    /// delivery itself rather than as a flag, so the confirmation can name which
    /// one it is about and act on that record.
    @State private var pendingCancellation: NumberedDelivery?

    /// The delivery just marked delivered, and the amount it was expected to
    /// pay, when it had one recorded.
    ///
    /// Captured **before** the transition and held here, rather than re-read
    /// from the delivery afterwards, for two reasons. The delivered delivery
    /// leaves ``activeDeliveries`` the moment the write lands, so its card is
    /// gone and there is nothing left on screen to hang the sheet off; and the
    /// figure being offered has to be the one the driver entered, not whatever
    /// the store happens to say a moment later.
    @State private var pendingEarningsConfirmation: PendingEarningsConfirmation?

    /// Whether the sheet that records an offer of several deliveries is up.
    @State private var isStartingGroupedOffer = false

    /// Whether the sheet that corrects which deliveries arrived together is up.
    @State private var isCorrectingOffers = false

    /// Whether the sheet that reopens a delivery marked delivered by mistake is
    /// up.
    @State private var isReopeningDelivery = false

    /// The instant the progress reminders are derived against.
    ///
    /// Held rather than read in `body` for the reason ``ActiveShiftPanel`` holds
    /// its measurement: a view body that read `.now` would derive a different
    /// answer on every redraw for reasons that have nothing to do with the
    /// clock, and would never redraw when the only thing that changed *was* the
    /// clock. It is advanced by the task below.
    @State private var suggestionClock = Date.now

    /// The reminders the driver has waved away, for as long as this screen
    /// lives.
    ///
    /// **Ephemeral on purpose.** A dismissal is not a fact about the delivery,
    /// and a store that remembered which reminders a driver had seen would be
    /// recording their attention rather than their work. It costs a reminder
    /// coming back after a relaunch, which is the right way round: the app
    /// forgets that it asked rather than forgetting that the delivery is stale.
    ///
    /// The key is the delivery **and the state it was in**, so advancing a
    /// delivery clears its dismissal by moving past it, and a delivery that goes
    /// stale again in its new state can be mentioned again.
    @State private var dismissedSuggestions: Set<DismissedSuggestion> = []

    /// The delivery just marked delivered, while the offer to take it back is
    /// still on screen.
    ///
    /// Held as the numbered delivery and the state it would go back to, for the
    /// reason ``PendingEarningsConfirmation`` holds its amount: the card leaves
    /// ``activeDeliveries`` with the write, so there is nothing left on screen to
    /// read either from, and the offer has to name the delivery it belongs to.
    @State private var recentlyDelivered: RecentCompletion?

    private var activeDeliveries: [NumberedDelivery] {
        let running = Set(unfinishedDeliveries.lazy.filter { $0.shift?.id == shift.id }.map(\.id))
        return shift.numberedDeliveries.filter { running.contains($0.id) }
    }

    /// The cards, arranged by the offer they were accepted in.
    ///
    /// The order is the order the deliveries already had, so a shift of
    /// one-delivery offers shows exactly the list it showed before.
    private var activeGroups: [DeliveryGroup] {
        DeliveryGroup.grouping(activeDeliveries, within: shift.numberedOffers)
    }

    /// The reminders on screen right now, in the order the deliveries appear.
    ///
    /// Derived on every read from the store's own timestamps, filtered by what
    /// the driver has already waved away. It reads no location, no sensor and
    /// nothing outside this shift's deliveries, and it writes nothing at all.
    private var progressSuggestions: [DeliveryProgressSuggestion] {
        // A shift that is not running has no reminder to give: a paused one is
        // stopped because the driver said so, and an ended one has no delivery
        // in progress to be stale.
        guard shift.lifecycleState == .running else { return [] }

        return Self.assistance
            .suggestions(among: activeDeliveries.map(AssistedDelivery.init), asOf: suggestionClock)
            .filter { !dismissedSuggestions.contains(DismissedSuggestion($0)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            undoBanner
            suggestions
            status

            ForEach(activeGroups) { group in
                VStack(alignment: .leading, spacing: 16) {
                    if group.isGrouped, let offer = group.offer {
                        OfferGroupHeader(offer: offer)
                    }

                    ForEach(group.deliveries) { numbered in
                        ActiveDeliveryCard(
                            numbered: numbered,
                            offer: group.isGrouped ? group.offer : nil,
                            advance: { perform(.advance(numbered)) },
                            cancel: { pendingCancellation = numbered }
                        )
                    }
                }
            }

            startControl
            groupedOfferControl
            correctionControl
            recoveryControl
        }
        .padding(.vertical, 8)
        // The window the immediate undo is offered for, counted in one-second
        // ticks while the banner is actually on screen. It restarts with each
        // completion, because the offer names the latest one.
        .task(id: recentlyDelivered?.id) {
            guard recentlyDelivered != nil else { return }
            var remaining = Self.undoSeconds

            while !Task.isCancelled, remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                // A second the driver cannot see does not count: the earnings
                // confirmation is raised by the same tap and covers this.
                guard pendingEarningsConfirmation == nil else { continue }
                remaining -= 1
            }

            guard !Task.isCancelled else { return }
            recentlyDelivered = nil
        }
        // The reminders' clock. It only advances while the shift is actually
        // running, so a paused or finished shift costs nothing, and it advances
        // slowly because the thresholds are measured in tens of minutes and a
        // sentence reading "29 minutes" for one more tick is not a defect.
        .task(id: shift.lifecycleState) {
            guard shift.lifecycleState == .running else { return }
            while !Task.isCancelled {
                suggestionClock = .now
                try? await Task.sleep(for: .seconds(Self.suggestionRefreshSeconds))
            }
        }
        .alert(
            pendingCancellation.map { "Cancel \($0.title)?" } ?? "Cancel this delivery?",
            isPresented: isConfirmingCancellation,
            presenting: pendingCancellation
        ) { numbered in
            // The destructive button repeats which delivery it will cancel.
            // With several in progress, "Cancel Delivery" alone would be asking
            // the driver to remember which card they tapped.
            Button("Cancel \(numbered.title)", role: .destructive) { perform(.cancel(numbered)) }
                .accessibilityIdentifier("confirmCancelDeliveryButton")
            Button("Keep Delivering", role: .cancel) { pendingCancellation = nil }
        } message: { numbered in
            Text(
                """
                \(numbered.title) is kept in this shift's history as cancelled, with the times you \
                already recorded. Nothing is deleted, and your other deliveries are not affected.
                """
            )
        }
        .alert(
            "Delivery Not Updated",
            isPresented: isShowingLifecycleError,
            presenting: lifecycleError
        ) { _ in
            Button("OK", role: .cancel) { lifecycleError = nil }
        } message: { error in
            Text(error.errorDescription ?? "The delivery could not be updated.")
        }
        // Raised only by a delivery that carried an expectation, and only after
        // the delivered event is already in the store. A driver who records no
        // expected amounts never meets it.
        .sheet(item: $pendingEarningsConfirmation) { pending in
            DeliveryEarningsConfirmation(numbered: pending.numbered, expected: pending.expected)
        }
        // Reached only from the secondary control below the start button. The
        // count it confirms is written through the same path every other
        // lifecycle action on this screen is.
        .sheet(isPresented: $isStartingGroupedOffer) {
            NewOfferSheet { count in perform(.startOffer(count)) }
        }
        // A review action, reached from one control rather than from a button on
        // every card, and writing nothing until a correction is confirmed inside
        // it.
        .sheet(isPresented: $isCorrectingOffers) {
            OfferCorrectionView(shift: shift)
        }
        // The deliberate way back from a mis-tap, for the driver who did not
        // catch the offer above. Like the correction sheet, it writes nothing
        // until a reopening is confirmed inside it.
        .sheet(isPresented: $isReopeningDelivery) {
            DeliveryRecoveryView(shift: shift)
        }
    }

    /// Taking back the `Delivered` that has just been recorded, for as long as
    /// the driver is plausibly still looking at the screen.
    ///
    /// At the top of the panel rather than where the card was, because the card
    /// is gone: the write that raised this is the write that removed it. It
    /// names the delivery in print and says aloud what pressing it does, since a
    /// listener has no card left to refer back to.
    ///
    /// Deliberately low friction. There is no confirmation, because the action
    /// being taken back happened seconds ago and undoing it immediately is the
    /// least consequential correction in the app. The deliberate path under
    /// `Reopen a Delivered Delivery` is the one that confirms.
    @ViewBuilder
    private var undoBanner: some View {
        if let recent = recentlyDelivered {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                // A symbol and a sentence, never a tint alone.
                Label(recent.numbered.deliveredStatement, systemImage: DeliveryState.delivered.symbolName)
                    .dashFont(.body)
                    .accessibilityIdentifier("undoDeliveredBanner")

                Spacer(minLength: 0)

                Button("Undo") { perform(.undo(recent)) }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(recent.numbered.spokenUndoDeliveredLabel(restoredTo: recent.restored))
                    .accessibilityIdentifier("undoDeliveredButton")
            }
            .dashInsetSurface()
        }
    }

    /// The reminders, above everything else on the panel and below the undo.
    ///
    /// Passive: it is drawn where it is rather than raised, it interrupts
    /// nothing, and a driver who ignores it entirely works exactly the shift
    /// they worked before it existed. There is no alert, no sheet and no
    /// notification anywhere in this feature.
    ///
    /// It sits above the delivery cards rather than inside them so that a driver
    /// carrying three orders reads one short list of what may be out of date
    /// instead of scanning three cards for a highlighted one, and so that the
    /// cards themselves are unchanged for the driver who never sees a reminder.
    @ViewBuilder
    private var suggestions: some View {
        if !progressSuggestions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(progressSuggestions) { suggestion in
                    DeliveryProgressSuggestionCard(
                        suggestion: suggestion,
                        confirm: { confirm(suggestion) },
                        dismiss: { dismissedSuggestions.insert(DismissedSuggestion(suggestion)) }
                    )
                }
            }
        }
    }

    /// How many deliveries are being worked, and what the shift has recorded so
    /// far. Both are glanceable and neither is a number that moves.
    @ViewBuilder
    private var status: some View {
        let summary = shift.deliverySummary

        VStack(alignment: .leading, spacing: 4) {
            // A symbol and a phrase, never colour alone: the state has to be
            // readable in bright sun and to someone who does not see the tint.
            Label(summary.inProgressStatement, systemImage: activeDeliveries.isEmpty ? "pause.circle" : "shippingbox.fill")
                .dashFont(.status)

            if !summary.isEmpty {
                Text(summary.statement)
                    .dashFont(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel([summary.inProgressStatement, summary.spokenStatement].joined(separator: ". "))
        .accessibilityIdentifier("deliveryStatus")
    }

    /// Starting another delivery, available whenever the shift is running.
    ///
    /// Prominent only when nothing is in progress. While deliveries are running,
    /// the buttons the driver reaches for are the ones advancing them, and two
    /// competing prominent controls beside a kerb is how the wrong one gets
    /// tapped.
    @ViewBuilder
    private var startControl: some View {
        let button = Button { perform(.start) } label: {
            Text(DeliveryAction.start.title)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .accessibilityLabel(DeliveryAction.start.spokenLabel)
        .accessibilityIdentifier("startDeliveryButton")

        if activeDeliveries.isEmpty {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    /// Recording an offer that contained more than one delivery.
    ///
    /// Deliberately small and secondary, and deliberately never prominent: most
    /// offers are one delivery, the button above already records those in one
    /// tap, and two competing prominent controls beside a kerb is how the wrong
    /// one gets pressed. It opens a sheet rather than acting, because a count is
    /// a thing to confirm.
    private var groupedOfferControl: some View {
        Button {
            isStartingGroupedOffer = true
        } label: {
            Label("Offer With Several Deliveries", systemImage: "square.stack.3d.up")
                .dashFont(.body)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Start an offer containing several deliveries")
        .accessibilityIdentifier("startOfferButton")
    }

    /// Correcting which deliveries were accepted together.
    ///
    /// Shown only once the shift holds two deliveries, because grouping is a
    /// statement about more than one of them and there is nothing to correct
    /// below that. Small, secondary and never prominent, like the control above
    /// it: this is not a step in recording work, and a driver who never
    /// mis-taps never needs it.
    ///
    /// It is here as well as in the completed shift's history because the
    /// mistake is noticed at the kerb as often as afterwards, and correcting it
    /// then is one sheet away rather than waiting for the shift to end. Nothing
    /// it does is a lifecycle action, so nothing it does can be done by mistake
    /// to a delivery in progress.
    @ViewBuilder
    private var correctionControl: some View {
        if shift.deliveries.count > 1 {
            Button {
                isCorrectingOffers = true
            } label: {
                Label("Correct Grouping", systemImage: "arrow.triangle.branch")
                    .dashFont(.body)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Correct which deliveries were accepted together")
            .accessibilityIdentifier("correctOffersButton")
        }
    }

    /// Reopening a delivery that was marked delivered by mistake.
    ///
    /// Shown only once the shift holds a delivery recorded as delivered, because
    /// that is the only thing it acts on. Small, secondary and never prominent,
    /// like the two controls above it: this is not a step in recording work, and
    /// a driver who never mis-taps never needs it.
    ///
    /// It is here rather than in a completed shift's history because that is
    /// where it can work. A shift cannot end while a delivery is in progress, so
    /// reopening one after the shift has finished would leave a delivery nothing
    /// could complete; the refusal lives in ``DeliveryService``.
    @ViewBuilder
    private var recoveryControl: some View {
        if shift.deliveries.contains(where: { $0.state == .delivered }) {
            Button {
                isReopeningDelivery = true
            } label: {
                Label("Reopen a Delivered Delivery", systemImage: "arrow.uturn.backward.circle")
                    .dashFont(.body)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Reopen a delivery you marked delivered by mistake")
            .accessibilityIdentifier("reopenDeliveryButton")
        }
    }

    // MARK: Actions

    /// What a control asked for, and which delivery it asked for it on.
    ///
    /// Cancelling is kept apart from the ordered lifecycle steps because it is
    /// not one of them: it is available from every active state rather than
    /// following one. So is undoing a completion, which records no event and
    /// removes one.
    private enum Operation {
        case start
        case startOffer(Int)
        case advance(NumberedDelivery)
        case cancel(NumberedDelivery)
        case undo(RecentCompletion)
    }

    private func perform(_ operation: Operation) {
        let service = DeliveryService(context: modelContext)
        do {
            switch operation {
            case .start:
                try service.startDelivery()
            case let .startOffer(count):
                try service.startOffer(deliveryCount: count)
            case let .advance(numbered):
                // The step is read from the delivery's own state and applied to
                // that same delivery, so a card can only ever advance itself.
                switch numbered.delivery.state.nextAction {
                case .arriveAtPickup: try service.markArrivedAtPickup(numbered.delivery)
                case .pickUp: try service.markPickedUp(numbered.delivery)
                case .complete:
                    // Read before the write, because the card disappears with
                    // it. Nothing is offered unless an expectation is the only
                    // amount this delivery carries: one that already has a
                    // recorded gross has been answered, and asking again would
                    // invite overwriting it by reflex.
                    let expected = numbered.delivery.hasUnconfirmedExpectedEarnings
                        ? numbered.delivery.expectedEarnings
                        : nil
                    try service.markDelivered(numbered.delivery)
                    // Only after the transition actually succeeded. A refused
                    // write leaves a delivery still in progress, and offering to
                    // record what it paid would be the screen disagreeing with
                    // the store about whether it is over.
                    if let expected {
                        pendingEarningsConfirmation = PendingEarningsConfirmation(
                            numbered: numbered,
                            expected: expected
                        )
                    }
                    offerToUndo(numbered)
                case .start, nil: break
                }
            case let .cancel(numbered):
                pendingCancellation = nil
                try service.cancelDelivery(numbered.delivery)
            case let .undo(recent):
                // The offer goes whatever happens next: a refusal is reported by
                // the alert below, and leaving the control up would invite a
                // second press at a delivery the store has already refused to
                // reopen.
                recentlyDelivered = nil
                try service.reopenDelivered(recent.numbered.delivery)
            }
        } catch let error as DeliveryLifecycleError {
            lifecycleError = error
        } catch {
            lifecycleError = .storeUnavailable(underlying: error)
        }

        // After every outcome, refused or not. Reconciling reads the store, so a
        // refusal costs one pass that finds nothing changed, and the alternative
        // — reconciling only on success — would be this screen deciding what the
        // store now holds.
        liveActivity.reconcile()
    }

    /// Records the step a reminder offered, through the path the delivery's own
    /// card uses.
    ///
    /// **It resolves the delivery by identity**, from the active list, and never
    /// by position: a reminder is drawn above the cards rather than beside one,
    /// so there is no visual ordering for it to trust even if it wanted to. A
    /// delivery that has left the active list between the draw and the tap
    /// resolves to nothing and nothing happens, which is the same outcome the
    /// service would produce and one fewer alert.
    ///
    /// The operation is ``Operation/advance(_:)`` — the card's own — so the step
    /// taken is ``DeliveryState/nextAction``'s answer for that delivery, read
    /// from the store at the moment of the tap rather than from the reminder.
    /// A reminder therefore cannot record a stale step, and there is no second
    /// lifecycle path to keep in agreement with the first.
    private func confirm(_ suggestion: DeliveryProgressSuggestion) {
        guard let numbered = activeDeliveries.first(where: { $0.id == suggestion.deliveryID }) else { return }
        perform(.advance(numbered))
    }

    /// The policy, held once rather than built per read, and held here rather
    /// than injected: a view has no business tuning it, and a test that wants
    /// different thresholds tests ``DeliveryProgressAssistance`` directly.
    private static let assistance = DeliveryProgressAssistance()

    /// How often the reminders' clock is advanced, in seconds.
    ///
    /// The thresholds are tens of minutes, so this only has to be short enough
    /// that a reminder appears while the driver is still looking at the screen
    /// and long enough that the panel is not re-deriving a list every second for
    /// a figure printed to the minute.
    private static let suggestionRefreshSeconds = 30

    /// A reminder the driver has waved away: which delivery, and which state it
    /// was in.
    ///
    /// The state is half the key deliberately. Dismissing "you may have arrived"
    /// says nothing about whether the driver will want to be told, half an hour
    /// later, that they may have picked the order up.
    private struct DismissedSuggestion: Hashable {
        let deliveryID: UUID
        let state: DeliveryState

        init(_ suggestion: DeliveryProgressSuggestion) {
            self.deliveryID = suggestion.deliveryID
            self.state = suggestion.state
        }
    }

    /// How many seconds on screen the immediate undo is offered for.
    ///
    /// Long enough to look down, read which delivery it names and press it,
    /// short enough that it is gone before the next door. It is a convenience
    /// with a deadline rather than a second way to reach the correction: the
    /// deliberate control under the panel has no deadline at all, which is why
    /// this one can have one.
    ///
    /// The figure is a judgement rather than a measurement, and it has never
    /// been held in a hand. A driver who walks back to the car before noticing
    /// is meant to reach the deliberate control, not this.
    ///
    /// It is counted in one-second ticks rather than slept through in one go,
    /// which is the cadence the running shift's own panel already keeps. A
    /// single sleep of the whole window stops the app going quiet for the length
    /// of it, and anything waiting for the app to go quiet, XCUITest included,
    /// waits the window out with it.
    private static let undoSeconds = 20

    /// Offers to take back the completion just recorded, where there is
    /// something truthful to take it back to.
    ///
    /// The state is derived by the same rule the write will apply, so the offer
    /// cannot exist for a delivery the service would refuse. A row it refuses is
    /// one the app cannot produce, and no banner is shown for one.
    private func offerToUndo(_ numbered: NumberedDelivery) {
        guard let restored = try? DeliveryRecovery(
            reopening: DeliveryLifecycleRecord(numbered.delivery)
        ).restoredState else { return }

        recentlyDelivered = RecentCompletion(numbered: numbered, restored: restored)
    }

    /// A delivery marked delivered a moment ago, and the state taking that back
    /// would return it to.
    ///
    /// The state is carried rather than looked up when the button is pressed, so
    /// the sentence VoiceOver reads is the one that describes what will actually
    /// happen, and so the banner is unpresentable for a delivery that cannot be
    /// reopened.
    private struct RecentCompletion: Identifiable {
        let numbered: NumberedDelivery
        let restored: DeliveryState

        var id: UUID { numbered.id }
    }

    /// A delivery that has just been recorded as delivered, together with the
    /// amount it was expected to pay.
    ///
    /// The expectation is carried rather than looked up so the sheet is
    /// unpresentable without one: there is no state in which the confirmation
    /// appears offering nothing, and no path by which it could show a figure
    /// read back out of the recorded gross column.
    private struct PendingEarningsConfirmation: Identifiable {
        let numbered: NumberedDelivery
        let expected: Money

        var id: UUID { numbered.id }
    }

    private var isConfirmingCancellation: Binding<Bool> {
        Binding(
            get: { pendingCancellation != nil },
            set: { isShowing in if !isShowing { pendingCancellation = nil } }
        )
    }

    private var isShowingLifecycleError: Binding<Bool> {
        Binding(
            get: { lifecycleError != nil },
            set: { isShowing in if !isShowing { lifecycleError = nil } }
        )
    }
}

/// One reminder that a lifecycle event may have gone unrecorded.
///
/// ## What it is careful about
///
/// It states a **fact about the record** — what the delivery last recorded and
/// how long ago — then asks a question, then says plainly that DashPilot did not
/// observe any of it. The order is the point: the driver reads the evidence
/// before the suggestion, and the caveat is never further away than the
/// suggestion is.
///
/// Neither control is destructive and neither is prominent. The confirming one
/// is bordered rather than borderedProminent, because the prominent control on
/// this screen is the delivery's own next step and a reminder must not compete
/// with it; both are full-width with a 44-point minimum, because the driver may
/// be standing at a kerb.
///
/// ## Two elements, not one
///
/// The sentence is one combined element so a listener hears the evidence, the
/// question and the caveat as one statement rather than as three fragments, and
/// the two buttons name their delivery for themselves, because a listener moving
/// between reminders has no card heading to refer back to.
private struct DeliveryProgressSuggestionCard: View {
    let suggestion: DeliveryProgressSuggestion
    let confirm: () -> Void
    let dismiss: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                // A symbol and a sentence, never a tint alone: the card has to
                // be readable in bright sun and to a driver who does not see
                // the colour.
                Label(suggestion.question, systemImage: "questionmark.circle")
                    .dashFont(.status)

                Text("\(suggestion.title) · \(suggestion.evidenceStatement)")
                    .dashFont(.supporting)
                    .foregroundStyle(.secondary)

                // Never abbreviated away and never behind a disclosure. It is
                // the sentence that keeps the card a question.
                Text(DeliveryProgressSuggestion.uncertaintyStatement)
                    .dashFont(.supporting)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(suggestion.spokenLabel)
            .accessibilityIdentifier("deliverySuggestion")

            controls
        }
        .dashInsetSurface()
    }

    /// Side by side at ordinary text sizes and stacked at accessibility ones,
    /// for the reason the completed delivery's actions became a grid: two
    /// controls sharing half a phone each come out a word to a line as soon as
    /// the text grows, and one of them has to hold a delivery's name.
    @ViewBuilder
    private var controls: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                confirmButton
                dismissButton
            }
        } else {
            HStack(spacing: 8) {
                confirmButton
                dismissButton
            }
        }
    }

    private var confirmButton: some View {
        Button(action: confirm) {
            Text(suggestion.actionTitle)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .contentShape(Rectangle())
        .accessibilityLabel(suggestion.spokenActionLabel)
        .accessibilityIdentifier("deliverySuggestionActionButton")
    }

    private var dismissButton: some View {
        Button(action: dismiss) {
            Text(suggestion.dismissTitle)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .contentShape(Rectangle())
        .accessibilityLabel(suggestion.spokenDismissLabel)
        .accessibilityIdentifier("deliverySuggestionDismissButton")
    }
}

/// The heading over the cards of one offer that contained several deliveries.
///
/// A label, never a control. There is nothing to act on at this level: an offer
/// is not advanced, not completed and not cancelled, and every button on the
/// screen belongs to exactly one delivery. What it adds is the one fact the
/// cards below cannot state for themselves, which is that they arrived
/// together.
///
/// It is one accessibility element, so a listener hears the group once rather
/// than hearing each half of it; each card names its own grouping again, because
/// a driver moving between cards by touch never has to have heard this.
private struct OfferGroupHeader: View {
    let offer: NumberedOffer

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("\(offer.title) · \(offer.groupStatement)", systemImage: "square.stack.3d.up.fill")
                .dashFont(.status)

            // Only once some of the offer's deliveries have finished. While they
            // are all running it would repeat the line above it.
            if let remaining = offer.remainingStatement {
                Text(remaining)
                    .dashFont(.supporting)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [offer.spokenGroupStatement, offer.remainingStatement]
                .compactMap { $0 }
                .joined(separator: " ")
        )
        .accessibilityIdentifier("offerGroupHeader")
    }
}

/// One delivery in progress: which one it is, what it is doing, and the single
/// step available next.
///
/// The card names itself in print and aloud. With two on screen, a control
/// identified only by its position is unusable without sight and easy to
/// mis-tap with it.
private struct ActiveDeliveryCard: View {
    let numbered: NumberedDelivery

    /// The offer this delivery arrived in, when it held more than one delivery.
    ///
    /// `nil` for the ordinary case of an offer of one, and for a delivery that
    /// records no offer at all, which is a row the app cannot produce. Both are
    /// drawn exactly as a card was drawn before offers existed.
    let offer: NumberedOffer?

    let advance: () -> Void
    let cancel: () -> Void

    @Environment(\.locale) private var locale

    /// Presented from the card's secondary pickup control. Sheet state rather
    /// than a navigation push, because naming a pickup is a short aside from the
    /// running shift rather than somewhere to be.
    @State private var isEditingPickupPlace = false

    /// Presented from the card's secondary expected-pay control, for the same
    /// reason and in the same shape.
    @State private var isEditingExpectedEarnings = false

    private var delivery: Delivery { numbered.delivery }

    /// How often the time-in-state line is redrawn. It is written to the
    /// minute, so a redraw every quarter of a minute keeps it on time without
    /// a per-second tick on a screen that already has one.
    private static let clockCadence: TimeInterval = 15

    var body: some View {
        VStack(alignment: .leading, spacing: DashSpacing.lg) {
            TimelineView(.periodic(from: .now, by: Self.clockCadence)) { context in
                identity(asOf: context.date)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spokenStatus(asOf: context.date))
                    .accessibilityIdentifier("activeDeliveryStatus")
            }

            // The one step this delivery can take, dominant on the card. A card
            // for a finished delivery does not exist, so the absence is
            // defensive.
            if let action = delivery.state.nextAction {
                VStack(alignment: .leading, spacing: DashSpacing.sm) {
                    Text("Next")
                        .dashFont(.metricLabel)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Button(action: advance) {
                        Text(action.title)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityLabel(numbered.spokenLabel(for: action))
                    .accessibilityIdentifier("deliveryActionButton")
                }
            }

            // Everything else a driver may do to this delivery, quiet and
            // below the step: optional details, and cancelling. None of them is
            // prominent, so none of them competes with the step at a kerb.
            secondaryControls
        }
        .padding(.vertical, DashSpacing.sm)
        .sheet(isPresented: $isEditingPickupPlace) {
            PickupPlaceEditor(numbered: numbered)
        }
        .sheet(isPresented: $isEditingExpectedEarnings) {
            DeliveryExpectedEarningsEditor(numbered: numbered)
        }
    }

    /// Which delivery this is, what state it is in and for how long, and what
    /// is known about it. Only facts it records: a place and an expected
    /// amount appear where they were entered and are absent otherwise.
    @ViewBuilder
    private func identity(asOf now: Date) -> some View {
        VStack(alignment: .leading, spacing: DashSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: DashSpacing.md) {
                Text(numbered.title)
                    .dashFont(.title)
                    .fixedSize(horizontal: false, vertical: true)

                // The offer's name alone, because the heading above has already
                // said how many deliveries it held. It is here so a driver
                // scrolled past the heading can still tell which cards belong
                // together.
                if let offer {
                    Text(offer.title)
                        .dashFont(.supporting)
                        .foregroundStyle(.secondary)
                }
            }

            // The state in a symbol and words, and how long it has been the
            // state, from the delivery's own recorded instant.
            DashStatusLabel(
                title: stateLine(asOf: now),
                symbol: delivery.state.symbolName,
                tint: .accentColor
            )

            if let place = delivery.pickupPlace {
                Label(place.displayName, systemImage: "bag")
                    .dashFont(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Named "Expected pay" wherever it is printed, so it is never one
            // word away from the "Gross earnings" a finished delivery shows.
            if let expected = delivery.expectedEarnings {
                LabeledContent("Expected pay") {
                    Text(expected.formatted(locale: locale)).monospacedDigit()
                }
                .dashFont(.body)
                .foregroundStyle(.secondary)
            }

            Text("Accepted \(delivery.acceptedAt.formatted(date: .omitted, time: .shortened))")
                .dashFont(.supporting)
                .foregroundStyle(.secondary)
        }
    }

    /// `Waiting at the pickup · 7 min`, or the state alone where there is no
    /// instant to measure from.
    private func stateLine(asOf now: Date) -> String {
        let description = delivery.state.statusDescription
        guard let elapsed = DeliveryLifecycleRecord(delivery).timeInCurrentState(asOf: now) else {
            return description
        }
        return "\(description) · \(DurationText.short(elapsed))"
    }

    /// Details and cancelling, below the step and quieter than it.
    ///
    /// One control to a line, always. Side by side, two half-width titles came
    /// out a word to a line at the default size, which is the defect the
    /// completed delivery's grid was built to fix. Cancelling is a plain
    /// destructive control that names its delivery and asks for confirmation,
    /// so it cannot be mistaken for the step above it.
    private var secondaryControls: some View {
        VStack(alignment: .leading, spacing: DashSpacing.xs) {
            pickupPlaceControl
            expectedEarningsControl
            Button("Cancel \(numbered.title)", role: .destructive, action: cancel)
                .dashFont(.body)
                .buttonStyle(.borderless)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel(numbered.spokenCancelLabel)
                .accessibilityIdentifier("cancelDeliveryButton")
        }
    }

    /// The one control for what this delivery is expected to pay.
    ///
    /// A sheet rather than a field on the card, for exactly the reason
    /// ``pickupPlaceControl`` opens one: a keyboard that appears beside the
    /// lifecycle buttons is the interaction this project refuses to design. The
    /// sheet can be dismissed and ignored entirely, and the delivery advances
    /// identically with no amount on it.
    private var expectedEarningsControl: some View {
        Button {
            isEditingExpectedEarnings = true
        } label: {
            Label(
                numbered.expectedEarningsActionTitle(hasExpected: delivery.expectedEarnings != nil),
                systemImage: delivery.expectedEarnings == nil ? "plus.circle" : "pencil"
            )
            .dashFont(.body)
        }
        .buttonStyle(.borderless)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(
            numbered.spokenExpectedEarningsLabel(hasExpected: delivery.expectedEarnings != nil)
        )
        .accessibilityIdentifier("expectedEarningsButton")
    }

    /// The one control for pickup identity: add it, or change what is recorded.
    ///
    /// Deliberately not a text field on the card. A running shift is the one
    /// screen a driver may look at with the engine on, and a keyboard that
    /// appears beside the lifecycle buttons is exactly the interaction this
    /// project refuses to design. The sheet it opens can be answered in one tap
    /// from a recent place, or dismissed and ignored entirely.
    private var pickupPlaceControl: some View {
        Button {
            isEditingPickupPlace = true
        } label: {
            Label(
                numbered.pickupPlaceActionTitle(hasPlace: delivery.pickupPlace != nil),
                systemImage: delivery.pickupPlace == nil ? "plus.circle" : "pencil"
            )
            .dashFont(.body)
        }
        .buttonStyle(.borderless)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(numbered.spokenPickupPlaceLabel(hasPlace: delivery.pickupPlace != nil))
        .accessibilityIdentifier("pickupPlaceButton")
    }

    /// "Delivery 2, waiting at the pickup, from Nowhere Noodles, accepted at
    /// 5:12 PM. Next step, mark order picked up." — the identity first, because
    /// that is what tells the listener which card they are on, the place only
    /// when one was recorded, and the step as its own sentence.
    ///
    /// An expected amount is appended as its own **sentence** rather than as
    /// another comma-separated clause, because it is the one part of this label
    /// that has to say what it is not: a figure heard in a run-on list beside a
    /// time and a place is heard as this delivery's earnings.
    private func spokenStatus(asOf now: Date) -> String {
        let accepted = delivery.acceptedAt.formatted(date: .omitted, time: .shortened)
        var parts = [numbered.spokenStatus]
        if let place = delivery.pickupPlace {
            parts.append("from \(place.displayName)")
        }
        parts.append("accepted at \(accepted)")

        var spoken = parts.joined(separator: ", ")
        // Its own sentence, and first of the three that follow: a listener
        // choosing between cards is choosing by what each one is waiting for,
        // and the step has to be heard before they reach the control that takes
        // it rather than discovered by arriving there.
        if let next = delivery.state.nextAction {
            spoken += ". \(next.spokenNextStep)"
        }
        // Its own sentence, and before the money: which deliveries arrived
        // together is what tells a listener which other cards on this screen
        // belong with this one, and it must not be heard as a clause of the
        // status above it.
        if let grouping = offer?.spokenGrouping(of: numbered) {
            spoken += ". \(grouping)"
        }
        if let expected = delivery.expectedEarnings {
            spoken += ". \(numbered.spokenExpectedEarnings(expected.formatted(locale: locale)))"
        }
        // Last, so every existing sentence keeps its place. From the
        // delivery's own recorded instant, never from anything observed.
        if let elapsed = DeliveryLifecycleRecord(delivery).timeInCurrentState(asOf: now) {
            spoken += ". In this state for \(DurationText.spoken(elapsed))"
        }
        return spoken
    }
}

#if DEBUG
#Preview("No delivery in progress") {
    PreviewSupport.rootView(container: PreviewSupport.populatedContainer())
}

#Preview("Two deliveries in progress") {
    PreviewSupport.rootView(container: PreviewSupport.activeDeliveryContainer())
}

#Preview("One offer of two, and an add-on offer") {
    PreviewSupport.rootView(container: PreviewSupport.stackedOfferContainer())
}
#endif
