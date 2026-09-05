import SwiftData
import SwiftUI

/// Everything DashPilot recorded about one finished shift, and how far it can
/// be trusted.
///
/// The history row answers *what shift is this and roughly how did it perform*.
/// This screen answers the two questions the row has no space for: **what
/// exactly happened in this shift**, and **how trustworthy are these numbers**.
/// That second question is why the route section states segments and gaps and
/// why an unavailable rate is explained here rather than simply left out — a
/// driver who wonders why there is no per-mile figure should be told, and the
/// row is the wrong place to tell them.
///
/// It is a summary, not a dashboard. No chart, no map, no gauge and no score:
/// the shift's own recorded facts, the three rates derived from them, the log of
/// deliveries recorded during it, and the two destructive-ish actions that
/// belong to a finished shift — editing what it paid, and deleting it.
///
/// Only completed shifts reach it. A running shift has no finalised duration, no
/// earnings it is allowed to record and nothing that may be deleted, and the
/// service refuses the deletion regardless of what any screen presents.
struct CompletedShiftDetailView: View {
    let shift: Shift

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    /// Measured once when the screen appears rather than in `body`.
    ///
    /// A shift's route can hold thousands of positions and a body is
    /// re-evaluated on every redraw. `nil` means "not measured yet", which is a
    /// third state distinct from "measured nothing" and is shown as such.
    @State private var recordedDistance: RouteDistance?

    /// Earnings are edited in the existing sheet — one editor, one parser, one
    /// set of draft and Cancel semantics — rather than a second implementation
    /// belonging to this screen.
    @State private var isEditingEarnings = false

    @State private var isConfirmingDeletion = false
    @State private var deletionError: ShiftLifecycleError?

    /// Set the moment the store accepts the delete.
    ///
    /// The shift object outlives the row that pushed this screen: SwiftUI may
    /// rebuild the destination once more while the navigation stack pops, and
    /// reading a property of a deleted model is not something to find out about
    /// on a driver's device. Nothing below reads the shift again once this is
    /// set.
    @State private var isDeleted = false

    var body: some View {
        if isDeleted || shift.isDeleted {
            // The shift is gone and the stack is popping; there is nothing left
            // to read, let alone display.
            Color.clear
        } else {
            content
        }
    }

    private var content: some View {
        List {
            shiftSection
            earningsSection
            routeSection
            performanceSection
            // Last of the reading sections, deliberately. The four above
            // summarise the shift in a fixed number of lines; this one grows
            // with the shift, and a long per-delivery log between the header
            // and the figures would bury everything that summarises it.
            deliveriesSection
            deleteSection
        }
        .navigationTitle(shift.startedAt.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: shift.id) { recordedDistance = shift.recordedDistance() }
        .sheet(isPresented: $isEditingEarnings) {
            ShiftEarningsEditor(shift: shift)
        }
        // An alert rather than a confirmation dialog: a dialog is presented as a
        // popover in some layouts, where iOS drops the explicit Cancel button
        // and leaves dismissal to a tap outside. For the one irreversible action
        // in the app, both choices must always be on screen and labelled.
        .alert("Delete this shift?", isPresented: $isConfirmingDeletion) {
            Button("Delete Shift", role: .destructive, action: delete)
                .accessibilityIdentifier("confirmDeleteShiftButton")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deletionWarning)
        }
        .alert(
            "Shift Not Deleted",
            isPresented: isShowingDeletionError,
            presenting: deletionError
        ) { _ in
            Button("OK", role: .cancel) { deletionError = nil }
        } message: { error in
            Text(error.errorDescription ?? "The shift could not be deleted.")
        }
    }

    // MARK: Shift

    private var shiftSection: some View {
        Section {
            LabeledContent("Started") {
                Text(shift.startedAt, format: .dateTime.hour().minute())
            }
            if let endedAt = shift.endedAt {
                LabeledContent("Ended") {
                    Text(endedAt, format: .dateTime.hour().minute())
                }
            }
            if let duration = shift.completedDuration {
                durationRow(
                    "Elapsed",
                    spokenAs: "elapsed shift time",
                    duration: duration,
                    identifier: "shiftDetailDuration"
                )
            }

            // Both are absent rather than zero when the shift recorded no
            // deliveries: a shift nobody recorded a delivery on is not a shift
            // that spent no time on deliveries, and the screen must not say it
            // was.
            if deliveryActiveTime.isAvailable {
                durationRow(
                    "Delivery active",
                    spokenAs: "delivery active time",
                    duration: deliveryActiveTime.duration,
                    identifier: "shiftDetailDeliveryActiveTime"
                )

                if let nonDelivery = deliveryActiveTime.nonDeliveryDuration(inElapsed: shift.completedDuration) {
                    durationRow(
                        "Non-delivery",
                        spokenAs: "non-delivery time",
                        duration: nonDelivery,
                        identifier: "shiftDetailNonDeliveryTime"
                    )
                }
            }
        } header: {
            Text("Shift")
        } footer: {
            Text(deliveryTimeExplanation)
        }
    }

    /// What the two derived durations mean, and what neither of them claims.
    ///
    /// The overlap sentence appears only when this shift actually has overlap,
    /// because it explains a discrepancy a driver can otherwise see — the
    /// delivery list adding up to more than the figure above it — and stating it
    /// for a shift with no stacked work would explain nothing.
    private var deliveryTimeExplanation: String {
        guard deliveryActiveTime.isAvailable else {
            return """
            Elapsed time is the whole shift, from starting it to ending it.
            """
        }

        var sentences = [
            """
            Delivery active time is the part of the shift at least one recorded delivery was open \
            for, from accepting it until you marked it delivered or cancelled.
            """
        ]
        if deliveryActiveTime.hasOverlappingDeliveries {
            sentences.append(
                """
                Deliveries you worked at the same time are counted once, so this is less than their \
                durations added together.
                """
            )
        }
        sentences.append(
            """
            Non-delivery time is the rest of the shift. It is not idle time: it includes waiting for \
            an offer, repositioning, breaks, and any work you did not record. DashPilot does not know \
            what you were doing during either.
            """
        )
        return sentences.joined(separator: " ")
    }

    /// One duration, printed short and spoken in full.
    ///
    /// The visible label is short because three of these sit under one heading;
    /// `spokenAs` is what VoiceOver hears, where "Elapsed, 3 hr" would leave the
    /// three figures told apart by one word each and read the units wrong.
    private func durationRow(
        _ title: String,
        spokenAs spokenTitle: String,
        duration: TimeInterval,
        identifier: String
    ) -> some View {
        LabeledContent(title) {
            Text(DurationText.short(duration)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(DurationText.spoken(duration)) \(spokenTitle)")
        .accessibilityIdentifier(identifier)
    }

    // MARK: Earnings

    private var earningsSection: some View {
        Section {
            if let earnings = shift.grossEarnings {
                LabeledContent("Gross earnings") {
                    Text(earnings.formatted(locale: locale))
                        .monospacedDigit()
                }
                .accessibilityIdentifier("shiftDetailEarnings")
            } else {
                Text("No amount recorded")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("shiftDetailEarnings")
            }

            Button {
                isEditingEarnings = true
            } label: {
                Label(
                    shift.grossEarnings == nil ? "Add Earnings" : "Edit Earnings",
                    systemImage: shift.grossEarnings == nil ? "plus.circle" : "pencil"
                )
            }
            .accessibilityIdentifier("editShiftEarningsButton")
        } header: {
            Text("Earnings")
        } footer: {
            Text(
                """
                What this shift paid, as you choose to record it. DashPilot is not connected to any \
                delivery platform, so nothing is imported. A shift with no amount recorded is not the \
                same as one that paid \(Money.zero.formatted(locale: locale)) — removing an amount is \
                offered inside the editor.
                """
            )
        }
    }

    // MARK: Route

    private var routeSection: some View {
        Section {
            if let quality {
                VStack(alignment: .leading, spacing: 6) {
                    Text(quality.mileageStatement(locale: locale))
                        .font(.headline)
                        .monospacedDigit()

                    ForEach(routeCaveats(of: quality), id: \.self) { caveat in
                        Text(caveat)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                // The bare spoken figure, because every caveat that qualifies it
                // is already read out below it — the compact history row is the
                // one that has to fold them into the mileage phrase.
                .accessibilityLabel(
                    ([quality.spokenMileage(locale: locale)] + routeCaveats(of: quality))
                        .joined(separator: ". ")
                )
                .accessibilityIdentifier("shiftDetailRecordedMileage")

                if let segments = quality.segmentStatement {
                    Text(segments).accessibilityIdentifier("shiftDetailCaptureSegments")
                }
                if let gaps = quality.gapStatement {
                    Text(gaps).accessibilityIdentifier("shiftDetailCaptureGaps")
                }
            } else {
                Text("Measuring the recorded route…")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Route")
        } footer: {
            Text(
                """
                A capture segment is an unbroken stretch of recording; a gap is a stretch of the shift \
                the route does not account for, including before the first recorded position and after \
                the last. DashPilot leaves the distance across a gap out rather than guessing at it, so \
                recorded mileage is a floor: the miles driven were this many or more.
                """
            )
        }
    }

    /// The statements that qualify a route, in the order they are read: what is
    /// missing from it, and then what that means for the numbers derived from it.
    ///
    /// A route with nothing to qualify produces none, and the section says only
    /// what it measured.
    private func routeCaveats(of quality: RouteQuality) -> [String] {
        [
            quality.unmeasurableExplanation,
            quality.partialExplanation,
            quality.inferredContinuityExplanation
        ].compactMap { $0 }
    }

    // MARK: Performance

    private var performanceSection: some View {
        Section {
            if let metrics {
                rateRow(
                    "Per shift hour",
                    spokenAs: "gross earnings per shift hour",
                    rate: metrics.grossPerElapsedHour,
                    identifier: "shiftDetailHourlyRate"
                )
                rateRow(
                    "Per active delivery hour",
                    spokenAs: "gross earnings per delivery active hour",
                    rate: metrics.grossPerDeliveryActiveHour,
                    identifier: "shiftDetailActiveHourlyRate"
                )
                rateRow(
                    "Per recorded mile",
                    spokenAs: "gross earnings per recorded mile",
                    rate: metrics.grossPerRecordedMile,
                    identifier: "shiftDetailPerMileRate"
                )
            } else {
                Text("Working out this shift's rates…")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Performance")
        } footer: {
            Text(
                """
                Every figure here is gross: nothing for fuel, wear, insurance or tax is subtracted \
                anywhere in DashPilot. Per shift hour divides by the whole elapsed shift, waiting \
                and repositioning included. Per active delivery hour divides by the time a recorded \
                delivery was open, counting deliveries you worked at once only once — it is not a \
                wage, and it says nothing about what you were doing in that time. Per recorded mile \
                divides by recorded miles, which are normally fewer than the miles driven, so it is \
                normally higher than earnings per mile driven.
                """
            )
        }
    }

    /// One derived rate, or one sentence saying why there is not one.
    ///
    /// An unavailable rate is never a dash or a zero. The visible label is short
    /// because it sits under a "Performance" heading; `spokenAs` is what
    /// VoiceOver hears, where "per shift hour" alone would lose the fact that
    /// the numerator is gross earnings.
    @ViewBuilder
    private func rateRow(
        _ title: String,
        spokenAs spokenTitle: String,
        rate: ShiftRate,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch rate {
            case let .available(amount):
                LabeledContent(title) {
                    Text(amount.formatted(locale: locale)).monospacedDigit()
                }
            case let .unavailable(reason):
                LabeledContent(title) {
                    Text("Not available").foregroundStyle(.secondary)
                }
                Text(reason.explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rateAccessibilityLabel(spokenTitle: spokenTitle, rate: rate))
        .accessibilityIdentifier(identifier)
    }

    private func rateAccessibilityLabel(spokenTitle: String, rate: ShiftRate) -> String {
        switch rate {
        case let .available(amount):
            "\(amount.formatted(locale: locale)) \(spokenTitle)"
        case let .unavailable(reason):
            "No \(spokenTitle). \(reason.explanation)"
        }
    }

    // MARK: Deliveries

    /// What this shift recorded delivery by delivery.
    ///
    /// A list and two derived intervals, not an analysis. Nothing here rates a
    /// restaurant, scores a shift, averages a wait or compares one delivery to
    /// another: those need data DashPilot does not have, and a number presented
    /// beside a name is read as a judgement of it.
    ///
    /// A cancelled delivery appears with the times that genuinely occurred. It
    /// is not hidden and not counted as completed — it is work the driver did
    /// that did not end in a delivery.
    ///
    /// Deliveries worked at the same time appear here with overlapping times,
    /// which is what stacked work looks like rather than a fault in the record.
    /// They are listed in the order they were accepted, and each one's intervals
    /// are its own. Nothing here is summed across deliveries: the one figure
    /// that spans them is the shift section's delivery active time, which unions
    /// their intervals rather than adding their durations.
    private var deliveriesSection: some View {
        Section {
            let summary = shift.deliverySummary

            Text(summary.statement)
                .font(.headline)
                .accessibilityLabel(summary.spokenStatement)
                .accessibilityIdentifier("shiftDetailDeliverySummary")

            // Numbered by the shift rather than by position in this list, so a
            // delivery is called the same thing here as it was on the running
            // shift.
            ForEach(shift.numberedDeliveries) { numbered in
                DeliveryHistoryRow(numbered: numbered)
            }
        } header: {
            Text("Deliveries")
        } footer: {
            Text(
                """
                Every time below was recorded because you tapped a control during the shift. \
                DashPilot is not connected to any delivery platform and detects nothing on its own, \
                so a delivery you did not record is not here. Deliveries you worked at the same time \
                overlap in this list, and their durations are never added together — the shift's \
                delivery active time counts shared minutes once. No amount is attributed to an \
                individual delivery.
                """
            )
        }
    }

    // MARK: Deletion

    private var deleteSection: some View {
        Section {
            Button("Delete Shift", role: .destructive) {
                isConfirmingDeletion = true
            }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("deleteShiftButton")
        } footer: {
            Text(deletionWarning)
        }
    }

    /// What deleting actually destroys, said the same way in the footer and in
    /// the confirmation.
    ///
    /// The route positions are named explicitly. They are the part a driver is
    /// least likely to have in mind and the part they cannot re-enter by hand,
    /// and a count is a fact about the shift rather than a location.
    private var deletionWarning: String {
        let sampleCount = shift.routeSamples.count
        let deleted = switch sampleCount {
        case 0: "the amount recorded on it. It recorded no route positions"
        case 1: "the 1 route position recorded during it, and the amount recorded on it"
        default: "the \(sampleCount) route positions recorded during it, and the amount recorded on it"
        }
        return "Deleting this shift also deletes \(deleted). This cannot be undone."
    }

    private var isShowingDeletionError: Binding<Bool> {
        Binding(
            get: { deletionError != nil },
            set: { isShowing in if !isShowing { deletionError = nil } }
        )
    }

    private func delete() {
        do {
            try ShiftService(context: modelContext).deleteCompletedShift(shift)
            // Before dismissing, not after: the flag is what stops this screen
            // reading a model the store no longer holds while the stack pops.
            isDeleted = true
            dismiss()
        } catch let error as ShiftLifecycleError {
            deletionError = error
        } catch {
            deletionError = .storeUnavailable(underlying: error)
        }
    }

    // MARK: Derived values

    private var quality: RouteQuality? {
        recordedDistance.map(RouteQuality.init)
    }

    /// How much of this shift a recorded delivery was active for.
    ///
    /// Derived here rather than held in state, unlike the route: it unions a
    /// handful of timestamps where the route walks thousands of positions, so it
    /// costs nothing to recompute and the shift section can state it without
    /// waiting for the measurement the performance section needs.
    private var deliveryActiveTime: DeliveryActiveTime {
        shift.deliveryActiveTime()
    }

    /// Derived from the distance measured once above, exactly as the history row
    /// does it: ``ShiftMetricsCalculator`` owns every rule, including which rates
    /// exist at all, and this screen only decides how to say so.
    private var metrics: ShiftMetrics? {
        recordedDistance.map { shift.metrics(for: $0) }
    }

}

/// One delivery in a completed shift's history.
///
/// The lifecycle events that happened, and the two intervals both of whose ends
/// exist. An interval with a missing end is left out rather than filled in with
/// zero or with the shift's own times.
private struct DeliveryHistoryRow: View {
    let numbered: NumberedDelivery

    /// Naming a pickup is offered here as well as on the running shift, because
    /// this is where a driver sitting still afterwards actually reviews what
    /// they recorded — and where they notice a place tapped onto the wrong card.
    @State private var isEditingPickupPlace = false

    /// The place's own recorded history, reached from the delivery that names
    /// it. This is a review surface: it is offered on a finished shift and
    /// nowhere on a running one.
    @State private var isShowingPickupHistory = false

    private var delivery: Delivery { numbered.delivery }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The recorded facts, read as one element. The controls below sit
            // deliberately outside it: a button folded into a combined element
            // is not reachable by VoiceOver.
            VStack(alignment: .leading, spacing: 4) {
                Label(
                    "\(numbered.title) · \(delivery.state.historyDescription)",
                    systemImage: delivery.state.symbolName
                )
                .font(.subheadline.weight(.semibold))

                // The place supplements the local number rather than replacing
                // it: `Delivery 2` is what this delivery was called all shift.
                // Absent when none was recorded — a "no pickup place" line on
                // every delivery would be noise on the ordinary case.
                if let place = delivery.pickupPlace {
                    Label(place.displayName, systemImage: "bag")
                        .font(.footnote)
                }

                ForEach(events, id: \.label) { event in
                    LabeledContent(event.label) {
                        Text(event.date, format: .dateTime.hour().minute())
                            .monospacedDigit()
                    }
                    .font(.footnote)
                }

                ForEach(intervals, id: \.label) { interval in
                    LabeledContent(interval.label) {
                        Text(DurationText.short(interval.duration))
                            .monospacedDigit()
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier("shiftDetailDeliveryRow")

            HStack(spacing: 16) {
                Button {
                    isEditingPickupPlace = true
                } label: {
                    Label(
                        numbered.pickupPlaceActionTitle(hasPlace: delivery.pickupPlace != nil),
                        systemImage: delivery.pickupPlace == nil ? "plus.circle" : "pencil"
                    )
                    .font(.footnote)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(numbered.spokenPickupPlaceLabel(hasPlace: delivery.pickupPlace != nil))
                .accessibilityIdentifier("shiftDetailPickupPlaceButton")

                // Only where there is a place to have a history. A delivery
                // that names none has nothing to group by, and offering the
                // control anyway would suggest the app knows where it was.
                if let place = delivery.pickupPlace {
                    Button {
                        isShowingPickupHistory = true
                    } label: {
                        Label("Pickup History", systemImage: "clock.arrow.circlepath")
                            .font(.footnote)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Recorded pickup waits at \(place.displayName)")
                    .accessibilityIdentifier("shiftDetailPickupHistoryButton")
                }
            }
        }
        .padding(.vertical, 2)
        .sheet(isPresented: $isEditingPickupPlace) {
            PickupPlaceEditor(numbered: numbered)
        }
        .sheet(isPresented: $isShowingPickupHistory) {
            if let place = delivery.pickupPlace {
                PickupPlaceHistoryView(place: place)
            }
        }
    }

    /// The lifecycle events that were actually recorded, in order.
    private var events: [(label: String, date: Date)] {
        var recorded: [(String, Date)] = [("Accepted", delivery.acceptedAt)]
        if let arrivedAtPickupAt = delivery.arrivedAtPickupAt {
            recorded.append(("Arrived at pickup", arrivedAtPickupAt))
        }
        if let pickedUpAt = delivery.pickedUpAt {
            recorded.append(("Picked up", pickedUpAt))
        }
        if let deliveredAt = delivery.deliveredAt {
            recorded.append(("Delivered", deliveredAt))
        }
        if let cancelledAt = delivery.cancelledAt {
            recorded.append(("Cancelled", cancelledAt))
        }
        return recorded.map { (label: $0.0, date: $0.1) }
    }

    /// The intervals both of whose ends exist. Nothing else is derived here.
    private var intervals: [(label: String, duration: TimeInterval)] {
        var derived: [(String, TimeInterval)] = []
        if let pickupWait = delivery.pickupWait {
            derived.append(("Waited at pickup", pickupWait))
        }
        if let completedDuration = delivery.completedDuration {
            derived.append(("Accepted to delivered", completedDuration))
        }
        return derived.map { (label: $0.0, duration: $0.1) }
    }

    /// Sentences rather than a table, because a row read as a list of
    /// unattached times is unintelligible.
    private var accessibilityLabel: String {
        var sentences = ["\(numbered.title), \(delivery.state.historyDescription.lowercased())"]
        // The place is spoken as it is written. The key it is matched by is
        // never exposed anywhere, aloud or otherwise.
        if let place = delivery.pickupPlace {
            sentences.append("Picked up from \(place.displayName)")
        }
        sentences += events.map { event in
            "\(event.label) at \(event.date.formatted(date: .omitted, time: .shortened))"
        }
        sentences += intervals.map { interval in
            "\(interval.label) \(DurationText.spoken(interval.duration))"
        }
        return sentences.joined(separator: ". ")
    }
}

#if DEBUG
#Preview("Measured route and earnings") {
    PreviewSupport.completedShiftDetail(.withEarningsAndRoute)
}

#Preview("No earnings, no route") {
    PreviewSupport.completedShiftDetail(.withoutEarningsOrRoute)
}
#endif
