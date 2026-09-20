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

    /// What the grid of pause corrections is allowed to do with the width it is
    /// given. An accessibility size gets one column rather than two.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

    /// Exporting is a sheet for the reason editing is: the file is written when
    /// it opens, and the driver can leave without sharing anything.
    @State private var isExporting = false

    /// Correcting which deliveries were accepted together, in the same sheet the
    /// running shift opens. History is where a driver reviews what they recorded
    /// and where a grouping mistake is most often noticed.
    @State private var isCorrectingOffers = false

    /// Correcting the moment the shift ended, in its own sheet. Offered here
    /// because this is the screen that states the end, and because
    /// ``ShiftEndCorrectionService`` refuses a running shift outright rather
    /// than relying on no screen offering the control.
    @State private var isCorrectingEnd = false

    /// Recording or changing the fuel economy and gas price this shift's fuel
    /// estimate is worked out under, in its own sheet. Offered here because this
    /// is the screen that states the recorded mileage the estimate divides.
    @State private var isEditingFuel = false

    /// The pause the editor is open on, or `.adding` for one being recorded
    /// after the fact. `nil` means the editor is closed.
    ///
    /// It holds the pause rather than a flag beside a separate selection, so
    /// there is no state in which the sheet is open with nothing to correct.
    @State private var pauseBeingEdited: PauseEdit?

    /// The pause awaiting a deletion confirmation, with the sentences the domain
    /// wrote for it. Nothing is written until it is confirmed.
    @State private var pendingPauseDeletion: PendingPauseDeletion?

    /// What the store said when a pause correction was refused, stated on the
    /// screen rather than swallowed.
    @State private var pauseCorrectionMessage: String?

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
            // The estimated section comes **after** every recorded figure and
            // every gross rate, deliberately. What the driver recorded and what
            // the route measured are the trustworthy part of this screen; an
            // estimate derived from two assumptions is not, and reading down the
            // screen should go from the one to the other rather than interleave
            // them. Keeping Performance where it was also leaves the rate rows
            // at the offset the existing journeys reach them at.
            fuelSection
            // The last two reading sections, deliberately, and in this order.
            // The four above summarise the shift in a fixed number of lines;
            // these two grow with it, and a long list between the header and
            // the figures would bury everything that summarises the shift.
            // Pauses come before the delivery log because the figures they
            // correct — the paused and working times — are the ones at the top
            // of the screen, and because a shift records far fewer pauses than
            // deliveries.
            pausesSection
            deliveriesSection
            exportSection
            deleteSection
        }
        .navigationTitle(shift.startedAt.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        // Keyed by the shift **and its recorded end**, because correcting the end
        // is the one action on this screen that changes what the route measures
        // to: it moves the window the walk is checked against and, for an
        // earlier end, deletes the positions beyond it. Keyed by the identifier
        // alone, the screen would keep drawing the mileage it measured on
        // arrival.
        .task(id: RouteMeasurementKey(shift: shift.id, endedAt: shift.endedAt)) {
            recordedDistance = shift.recordedDistance()
        }
        .sheet(isPresented: $isEditingEarnings) {
            ShiftEarningsEditor(shift: shift)
        }
        .sheet(isPresented: $isExporting) {
            ShiftExportSheet(scope: .shift(shift.id))
        }
        .sheet(isPresented: $isCorrectingOffers) {
            OfferCorrectionView(shift: shift)
        }
        .sheet(isPresented: $isCorrectingEnd) {
            ShiftEndCorrectionEditor(shift: shift)
        }
        .sheet(isPresented: $isEditingFuel) {
            FuelAssumptionsEditor(shift: shift)
        }
        .sheet(item: $pauseBeingEdited) { edit in
            ShiftPauseEditor(shift: shift, pause: edit.pause)
        }
        // An alert rather than a confirmation dialog, for the reason the shift's
        // own deletion uses one: a dialog is a popover in some layouts, where
        // iOS drops the explicit Cancel button, and a correction that removes a
        // recorded fact must always show both choices.
        .alert(
            pendingPauseDeletion.map { Text($0.prompt.title) } ?? Text("Delete Pause"),
            isPresented: isConfirmingPauseDeletion,
            presenting: pendingPauseDeletion
        ) { pending in
            Button(pending.prompt.confirmTitle, role: .destructive) { deletePause(pending.pause) }
                .accessibilityIdentifier("confirmDeleteShiftPauseButton")
            Button("Cancel", role: .cancel) { pendingPauseDeletion = nil }
        } message: { pending in
            Text(pending.prompt.detail)
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

            // Shown only for a shift that was actually paused. On every other
            // shift the working figure is the elapsed one to the second, and two
            // identical rows would invite a driver to look for a difference
            // between them that does not exist.
            if let pausedTime = shift.completedPausedTime, pausedTime.hasPauses {
                durationRow(
                    "Paused",
                    spokenAs: pausedTime.intervalCount == 1
                        ? "paused time, over 1 pause"
                        : "paused time, over \(pausedTime.intervalCount) pauses",
                    duration: pausedTime.duration,
                    identifier: "shiftDetailPausedTime"
                )

                if let working = shift.completedWorkingDuration {
                    durationRow(
                        "Working",
                        spokenAs: "working time",
                        duration: working,
                        identifier: "shiftDetailWorkingTime"
                    )
                }
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

                if let nonDelivery = deliveryActiveTime.nonDeliveryDuration(inElapsed: shift.completedWorkingDuration) {
                    durationRow(
                        "Non-delivery",
                        spokenAs: "non-delivery time",
                        duration: nonDelivery,
                        identifier: "shiftDetailNonDeliveryTime"
                    )
                }
            }

            // Here rather than in a section of its own, because the fact it
            // corrects is three rows above it and the figures it moves are the
            // two below that. Offered only once the shift has an end to correct;
            // the service refuses a running shift regardless of what any screen
            // presents.
            if shift.endedAt != nil {
                Button {
                    isCorrectingEnd = true
                } label: {
                    Label("Correct End Time", systemImage: "clock.arrow.circlepath")
                }
                .accessibilityLabel("Correct the time this shift ended")
                .accessibilityIdentifier("correctShiftEndButton")
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
            return ([elapsedSentence] + pauseSentences).joined(separator: " ")
        }

        var sentences = [elapsedSentence]
        sentences.append(contentsOf: pauseSentences)
        sentences.append(
            """
            Delivery active time is the part of the shift at least one recorded delivery was open \
            for, from accepting it until you marked it delivered or cancelled.
            """
        )
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
            Non-delivery time is the rest of the working time. It is not idle time: it includes \
            waiting for an offer, repositioning, and any work you did not record. DashPilot does not \
            know what you were doing during either.
            """
        )
        return sentences.joined(separator: " ")
    }

    private var elapsedSentence: String {
        "Elapsed time is the whole shift, from starting it to ending it."
    }

    /// What pausing did to this shift's figures, said only when it was paused.
    private var pauseSentences: [String] {
        guard let pausedTime = shift.completedPausedTime, pausedTime.hasPauses else { return [] }
        var sentences = [
            """
            Working time is the elapsed time less the time you had the shift paused, and it is what \
            the hourly rate below divides by.
            """
        ]
        sentences.append(
            """
            Nothing was recorded while the shift was paused at the time, and the distance between \
            where you paused and where you resumed is not counted.
            """
        )
        // Said because this screen can now change a pause after the fact.
        // Correcting or adding one never touches the route, so a shift can
        // record mileage inside a stretch it also records as paused. Stating it
        // is the alternative to the two dishonest repairs: deleting positions
        // that were really recorded, or claiming a gap that never happened.
        sentences.append(
            """
            A pause you corrected or added afterwards does not change the route: no recorded \
            position is ever added, moved or deleted, so the recorded mileage above still covers \
            everything this shift recorded.
            """
        )
        return sentences
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

    // MARK: Pauses

    /// The stretches this shift records as paused, and the corrections each one
    /// offers.
    ///
    /// ## Why it is here rather than on the running shift
    ///
    /// Choosing two times from two pickers is the sustained typing this app
    /// deliberately keeps away from a driver who may be at a wheel, and the live
    /// pause belongs to Resume and End, which reconcile route capture as they
    /// close it. ``ShiftPauseCorrectionService`` refuses a running shift outright
    /// rather than relying on no screen offering the control.
    ///
    /// ## Why it appears on a shift with no pauses
    ///
    /// Because forgetting to pause is the mistake with no other remedy. A shift
    /// that records no pause says so in one line and still offers to record one,
    /// which is the only way a driver who took a break and did not tap anything
    /// can say so afterwards.
    ///
    /// ## Why it is below the figures rather than beside them
    ///
    /// It grows with the shift, exactly as the delivery log does, and the four
    /// sections above it summarise the shift in a fixed number of lines. A
    /// correction surface of unknown height between the header and the rates
    /// would push what a driver opens this screen to read off the first screenful
    /// — which is what it did, and what the route and rate journeys caught.
    private var pausesSection: some View {
        Section {
            let pauses = shift.numberedPauses
            if pauses.isEmpty {
                Text("No pauses recorded")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("shiftDetailNoPauses")
            } else {
                ForEach(pauses) { numbered in
                    pauseRow(numbered)
                }
            }

            Button {
                pauseCorrectionMessage = nil
                pauseBeingEdited = .adding
            } label: {
                Label("Add Missed Pause", systemImage: "plus.circle")
            }
            .accessibilityLabel("Add a pause you did not record during the shift")
            .accessibilityIdentifier("addMissedPauseButton")

            if let pauseCorrectionMessage {
                Label(pauseCorrectionMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    // One element carrying the sentence rather than a glyph
                    // called "Warning" beside it, and never a colour alone.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(pauseCorrectionMessage)
                    .accessibilityIdentifier("shiftDetailPauseCorrectionMessage")
            }
        } header: {
            Text("Pauses")
        } footer: {
            Text(
                """
                Each pause is a stretch you recorded as not working, and together they are what this \
                shift's working time subtracts. Correcting one changes the working time and the \
                hourly figures over it; it never changes the shift's own start and end times, the \
                route recorded during it, or any amount you entered.
                """
            )
        }
    }

    /// One recorded pause: when it began, when it ended, how long it was, and
    /// the two corrections it offers.
    ///
    /// The facts are one combined element and the controls sit outside it, for
    /// the reason a delivery row's do: a button folded into a combined element
    /// is not reachable by VoiceOver. Both controls name the pause, because two
    /// rows offer two buttons that would otherwise be told apart only by where
    /// they sit.
    ///
    /// Nothing here is distinguished by colour alone. `Delete Pause` is a
    /// destructive role *and* says the word, and the pause is identified by its
    /// number in text rather than by its position in a list.
    private func pauseRow(_ numbered: NumberedPause) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                LabeledContent(numbered.title) {
                    Text(pauseTimes(numbered.pause)).monospacedDigit()
                }
                .font(.subheadline.weight(.semibold))

                if let duration = pauseDuration(numbered.pause) {
                    Text(DurationText.short(duration))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    // A row the app cannot write: an end before its start, or a
                    // pause left open on a finished shift. It is stated rather
                    // than hidden or shown as zero, because a pause that cannot
                    // be measured is left out of the shift's paused total and
                    // the driver should be told which one.
                    Text("This pause's times cannot be measured, so it is not counted in the paused time above.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(pauseAccessibilityLabel(numbered))
            .accessibilityIdentifier("shiftDetailPauseRow")

            LazyVGrid(columns: pauseActionColumns, alignment: .leading, spacing: 8) {
                Button {
                    pauseCorrectionMessage = nil
                    pauseBeingEdited = .correcting(numbered)
                } label: {
                    DeliveryActionLabel(title: "Edit Pause", systemImage: "pencil")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(numbered.spokenEditLabel)
                .accessibilityIdentifier("editShiftPauseButton")

                Button(role: .destructive) {
                    pauseCorrectionMessage = nil
                    pendingPauseDeletion = PendingPauseDeletion(
                        pause: numbered.pause,
                        prompt: .delete(
                            numbered.title,
                            duration: DurationText.short(pauseDuration(numbered.pause) ?? 0)
                        )
                    )
                } label: {
                    DeliveryActionLabel(title: "Delete Pause", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(numbered.spokenDeleteLabel)
                .accessibilityIdentifier("deleteShiftPauseButton")
            }
        }
        .padding(.vertical, 2)
    }

    /// Two columns, and one at accessibility text sizes, for the reason a
    /// completed delivery's corrections are laid out that way: two controls
    /// sharing a phone's width leave each enough room to say which pause it
    /// changes.
    private var pauseActionColumns: [GridItem] {
        let column = GridItem(.flexible(), spacing: 12, alignment: .topLeading)
        return Array(repeating: column, count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    /// When a pause began and ended, printed the way every other time on this
    /// screen is.
    private func pauseTimes(_ pause: ShiftPause) -> String {
        let started = pause.startedAt.formatted(.dateTime.hour().minute().locale(locale))
        guard let endedAt = pause.endedAt else { return "\(started) to no recorded resume" }
        return "\(started) to \(endedAt.formatted(.dateTime.hour().minute().locale(locale)))"
    }

    /// How long a pause was, or `nil` for a row that cannot say.
    ///
    /// `nil` covers both anomalies ``ShiftPauseInterval`` counts as unusable: a
    /// pause with no recorded end, and one whose end precedes its start. Neither
    /// becomes a zero, which would look like a measurement.
    private func pauseDuration(_ pause: ShiftPause) -> TimeInterval? {
        guard let endedAt = pause.endedAt, endedAt >= pause.startedAt else { return nil }
        return endedAt.timeIntervalSince(pause.startedAt)
    }

    /// One sentence rather than a row of unattached times, because a listener
    /// has no column headings to fall back on.
    private func pauseAccessibilityLabel(_ numbered: NumberedPause) -> String {
        let pause = numbered.pause
        let started = pause.startedAt.formatted(date: .omitted, time: .shortened)
        guard let endedAt = pause.endedAt else {
            return "\(numbered.title), paused at \(started), with no resume recorded"
        }
        let ended = endedAt.formatted(date: .omitted, time: .shortened)
        guard let duration = pauseDuration(pause) else {
            return """
            \(numbered.title), paused at \(started), resumed at \(ended). These times cannot be \
            measured, so this pause is not counted in the shift's paused time
            """
        }
        return "\(numbered.title), paused at \(started), resumed at \(ended), \(DurationText.spoken(duration))"
    }

    private var isConfirmingPauseDeletion: Binding<Bool> {
        Binding(
            get: { pendingPauseDeletion != nil },
            set: { isShowing in if !isShowing { pendingPauseDeletion = nil } }
        )
    }

    /// Removes the pause the driver confirmed, or states why it was refused.
    ///
    /// Nothing is reconciled with route capture or the Live Activity afterwards,
    /// and that is deliberate rather than an omission: both are about the
    /// **running** shift, and this one has ended.
    private func deletePause(_ pause: ShiftPause) {
        pendingPauseDeletion = nil
        pauseCorrectionMessage = nil
        do {
            try ShiftPauseCorrectionService(context: modelContext).delete(pause)
        } catch {
            pauseCorrectionMessage = (error as? any LocalizedError)?.errorDescription
                ?? "That pause could not be deleted."
        }
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
                offered inside the editor. Amounts you record against individual deliveries are \
                separate, and this figure is never worked out from them.
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

    // MARK: Estimated fuel

    /// What this shift's **recorded** miles are estimated to have consumed, and
    /// what that fuel cost at the price this shift recorded.
    ///
    /// Three things this section has to keep saying, because each is a claim a
    /// reader would otherwise supply for themselves:
    ///
    /// - It is an **estimate**, from figures the driver assumed. Nothing here
    ///   was read from a pump, a receipt or a vehicle.
    /// - It is **not a recorded expense**. A fuel purchase the driver records
    ///   under Expenses is a cost they actually paid; this is arithmetic. The
    ///   two are never added together and neither is derived from the other.
    /// - It covers **recorded** mileage only. Recorded miles are a floor on the
    ///   miles driven, so where the route is partial the estimate is a floor
    ///   too, and the section says so in the same words the route section does.
    private var fuelSection: some View {
        Section {
            if let fuelEstimate {
                fuelCostRow(fuelEstimate)

                if let consumption = fuelEstimate.consumption {
                    LabeledContent("Estimated gallons") {
                        Text(consumption.formattedGallons(locale: locale)).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        """
                        \(consumption.formattedGallons(width: .wide, locale: locale)) estimated, \
                        from recorded mileage
                        """
                    )
                    .accessibilityIdentifier("shiftDetailEstimatedGallons")
                }

                assumptionRows
            } else {
                Text("Working out this shift's fuel estimate…")
                    .foregroundStyle(.secondary)
            }

            Button {
                isEditingFuel = true
            } label: {
                Label(
                    shift.fuelAssumptions.hasAny ? "Edit Fuel Assumptions" : "Add Fuel Assumptions",
                    systemImage: shift.fuelAssumptions.hasAny ? "pencil" : "plus.circle"
                )
            }
            .accessibilityIdentifier("editFuelAssumptionsButton")
        } header: {
            Text("Estimated Fuel")
        } footer: {
            Text(fuelFooterStatement)
        }
    }

    /// The figure the section exists for, or one sentence saying why there is
    /// not one.
    ///
    /// Never a dash and never `$0.00`: a shift with no fuel economy recorded is
    /// not a shift whose fuel was free.
    @ViewBuilder
    private func fuelCostRow(_ estimate: FuelEstimate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch estimate {
            case let .available(consumption):
                LabeledContent("Estimated fuel cost") {
                    Text(consumption.cost.formatted(locale: locale)).monospacedDigit()
                }
                Text("Based on recorded mileage")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if consumption.isRoutePartial {
                    Text(Self.partialFuelStatement)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case let .unavailable(reason):
                LabeledContent("Estimated fuel cost") {
                    Text("Not available").foregroundStyle(.secondary)
                }
                Text(reason.explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(fuelCostAccessibilityLabel(estimate))
        .accessibilityIdentifier("shiftDetailEstimatedFuelCost")
    }

    /// The spoken form of the estimate, which has to carry what the eye reads
    /// from the caption under it: that the basis is recorded mileage, and that a
    /// partial route makes the figure a floor.
    private func fuelCostAccessibilityLabel(_ estimate: FuelEstimate) -> String {
        switch estimate {
        case let .available(consumption):
            var spoken = "\(consumption.cost.formatted(locale: locale)) estimated fuel cost, based on recorded mileage"
            if consumption.isRoutePartial {
                spoken += ". \(Self.partialFuelStatement)"
            }
            return spoken
        case let .unavailable(reason):
            return "No estimated fuel cost. \(reason.explanation)"
        }
    }

    /// The two assumptions, stated wherever either was recorded.
    ///
    /// Shown even when the other half is missing, so a driver looking at "Not
    /// available" can see which figure is already there. A half that was never
    /// recorded says so rather than showing a zero.
    @ViewBuilder
    private var assumptionRows: some View {
        let assumptions = shift.fuelAssumptions
        if assumptions.hasAny {
            LabeledContent("Miles per gallon") {
                if let milesPerGallon = assumptions.milesPerGallon {
                    Text(MilesPerGallonInput(locale: locale).text(for: milesPerGallon)).monospacedDigit()
                } else {
                    Text("Not recorded").foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                assumptions.milesPerGallon.map {
                    "\(MilesPerGallonInput(locale: locale).text(for: $0)) miles per gallon assumed"
                } ?? "No miles per gallon recorded"
            )
            .accessibilityIdentifier("shiftDetailFuelMilesPerGallon")

            LabeledContent("Gas price per gallon") {
                if let gasPrice = assumptions.gasPricePerGallon {
                    Text(gasPrice.formatted(locale: locale)).monospacedDigit()
                } else {
                    Text("Not recorded").foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                assumptions.gasPricePerGallon.map {
                    "\($0.formatted(locale: locale)) per gallon assumed"
                } ?? "No gas price recorded"
            )
            .accessibilityIdentifier("shiftDetailFuelGasPrice")
        }
    }

    /// What a partial route means for the estimate, in the route section's own
    /// terms.
    ///
    /// Written once and read by both the visible caption and the spoken label,
    /// so the eye and the ear are told the same thing.
    private static let partialFuelStatement = """
        This route is partial, so more miles were driven than were recorded and more fuel was \
        used than this estimates.
        """

    private var fuelFooterStatement: String {
        """
        Estimated fuel cost is recorded miles divided by your miles per gallon, priced at your gas \
        price per gallon. Both figures are your own assumptions, recorded with this shift, so \
        entering different ones later leaves this shift's estimate where it is. It is an estimate \
        and not a recorded expense: it is not proof of fuel bought, fuel burned, what this vehicle \
        costs to run, or anything deductible. A fuel purchase you record under Expenses is a \
        separate, recorded fact, and DashPilot never adds one to the other.
        """
    }

    // MARK: Performance

    private var performanceSection: some View {
        Section {
            if let metrics {
                rateRow(
                    "Per shift hour",
                    spokenAs: "gross earnings per shift hour",
                    rate: metrics.grossPerWorkingHour,
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
    /// A list, two derived intervals and — where the driver recorded one — an
    /// amount with the one rate it supports. Not an analysis. Nothing here rates
    /// a restaurant, scores a shift, averages a wait or compares one delivery to
    /// another: those need data DashPilot does not have, and a number presented
    /// beside a name is read as a judgement of it.
    ///
    /// Nothing is totalled either. A per-delivery amount is not summed, checked
    /// against the shift's own amount or shown as a shortfall against it: some
    /// deliveries go unrecorded, stacked orders may be paid together, and
    /// adjustments post at shift level, so a difference between the two is
    /// ordinary rather than a discrepancy to flag.
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
            //
            // The offers are resolved once for the whole list rather than
            // searched per row, and a row is handed one only where it held more
            // than one delivery: history states the grouping it has, and says
            // nothing at all about the ordinary offer of one.
            let offers = groupedOffersByDelivery
            ForEach(shift.numberedDeliveries) { numbered in
                DeliveryHistoryRow(numbered: numbered, offer: offers[numbered.id])
            }

            // One control for the whole list rather than one per row: grouping
            // is a statement about which deliveries arrived together, so it is
            // corrected by looking at all of them at once. Absent on a shift
            // holding a single delivery, where there is nothing to regroup.
            if shift.deliveries.count > 1 {
                Button("Correct Grouping") { isCorrectingOffers = true }
                    .accessibilityLabel("Correct which deliveries were accepted together")
                    .accessibilityIdentifier("correctOffersButton")
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
                delivery active time counts shared minutes once, and a per-delivery hourly figure \
                covers only that delivery's own lifecycle. Any amount here is one you recorded \
                against that delivery; nothing is taken from, or added to, the shift's own amount.
                """
            )
        }
    }

    // MARK: Export

    /// Taking this shift's record somewhere else.
    ///
    /// Between the log and the deletion, deliberately: it belongs with the two
    /// actions that act on the whole shift rather than with the figures, and it
    /// sits above deletion because a driver about to delete a shift may well
    /// want to keep a copy of it first.
    ///
    /// Offered only from a finished shift, like everything else on this screen.
    /// A running shift has no export control anywhere in the app.
    private var exportSection: some View {
        Section {
            Button {
                isExporting = true
            } label: {
                Label(ExportScope.shift(shift.id).actionTitle, systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel(ExportScope.shift(shift.id).spokenActionLabel)
            .accessibilityIdentifier("exportShiftButton")
        } header: {
            Text("Export")
        } footer: {
            Text(
                """
                Writes what DashPilot recorded for this shift — its times, its deliveries, the amounts \
                you typed and its recorded mileage — as a JSON or CSV file on this device, then offers \
                it to the share sheet. Recorded positions are not included, and nothing is sent \
                anywhere unless you send it.
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
        let sampleCount = shift.routeSampleCount
        // One phrase for both amounts: deleting a shift takes the figure
        // recorded on the shift itself *and* every figure recorded against one
        // of its deliveries, and a warning that named only the first would
        // understate what is about to be lost.
        let amounts = "every amount recorded on it and on its deliveries"
        let deleted = switch sampleCount {
        case 0: "\(amounts). It recorded no route positions"
        case 1: "the 1 route position recorded during it, and \(amounts)"
        default: "the \(sampleCount) route positions recorded during it, and \(amounts)"
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

    /// The offer each delivery arrived in, for the offers that held more than
    /// one.
    ///
    /// A delivery from an offer of one is absent, so the row it builds shows no
    /// grouping at all, which is what the ordinary case looked like before
    /// offers existed.
    private var groupedOffersByDelivery: [UUID: NumberedOffer] {
        var offers: [UUID: NumberedOffer] = [:]
        for offer in shift.numberedOffers where offer.isGrouped {
            for delivery in offer.deliveries {
                offers[delivery.id] = offer
            }
        }
        return offers
    }

    /// Derived from the distance measured once above, exactly as the history row
    /// does it: ``ShiftMetricsCalculator`` owns every rule, including which rates
    /// exist at all, and this screen only decides how to say so.
    private var metrics: ShiftMetrics? {
        recordedDistance.map { shift.metrics(for: $0) }
    }

    /// This shift's estimated fuel, or `nil` until the route has been measured.
    ///
    /// `nil` here is "not measured yet" and is shown as such, exactly as it is
    /// for ``metrics``. It is a third state distinct from an estimate that
    /// cannot be derived, which has a reason of its own.
    private var fuelEstimate: FuelEstimate? {
        recordedDistance.map { shift.fuelEstimate(for: $0) }
    }

}

/// One delivery in a completed shift's history.
///
/// The lifecycle events that happened, and the two intervals both of whose ends
/// exist. An interval with a missing end is left out rather than filled in with
/// zero or with the shift's own times.
private struct DeliveryHistoryRow: View {
    let numbered: NumberedDelivery

    /// The offer this delivery arrived in, when it held more than one delivery.
    ///
    /// `nil` for an offer of one, which is the ordinary case and needs no line
    /// saying that a delivery arrived by itself, and for a delivery that records
    /// no offer at all.
    let offer: NumberedOffer?

    @Environment(\.locale) private var locale

    /// What the grid of corrections below the record is allowed to do with the
    /// width it is given. An accessibility size gets one column rather than two.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Naming a pickup is offered here as well as on the running shift, because
    /// this is where a driver sitting still afterwards actually reviews what
    /// they recorded — and where they notice a place tapped onto the wrong card.
    @State private var isEditingPickupPlace = false

    /// The place's own recorded history, reached from the delivery that names
    /// it. This is a review surface: it is offered on a finished shift and
    /// nowhere on a running one.
    @State private var isShowingPickupHistory = false

    /// The amount this delivery paid, edited in its own sheet for the reason the
    /// shift's is: typing belongs after the driving, not during it.
    @State private var isEditingEarnings = false

    /// The tips this delivery received outside that amount, in their own sheet
    /// for the same reason, and a separate one because they are a list rather
    /// than a field.
    @State private var isEditingTips = false

    /// The times this delivery recorded, corrected in their own sheet: they move
    /// together, they are judged together, and a picker in a list row could not
    /// state the consequences the editor states before saving.
    @State private var isCorrectingTimes = false

    /// The correction awaiting confirmation. Nothing is written until it is
    /// confirmed, and dismissing the alert writes nothing at all.
    ///
    /// It holds the sentences rather than a reference, so the alert describes
    /// the correction in the words the domain wrote and the delivery itself is
    /// read again at the moment the write is attempted.
    @State private var pendingCancellation: HistoricalCancellationPrompt?

    /// What the store said when a correction was refused, stated on the row
    /// rather than swallowed.
    @State private var correctionMessage: String?

    @Environment(\.modelContext) private var modelContext

    private var delivery: Delivery { numbered.delivery }

    /// What this delivery actually paid, read once per body rather than
    /// assembled separately by each row that needs part of it.
    private var effectiveEarnings: EffectiveDeliveryEarnings { delivery.effectiveEarnings }

    /// The tips row's label, which says how many facts stand behind the figure.
    ///
    /// A single tip is the commonest case and reads better without a count, and
    /// a count is exactly what distinguishes two tips from one larger one.
    private var additionalTipsTitle: String {
        effectiveEarnings.additionalTipCount == 1
            ? "Additional tip"
            : "Additional tips (\(effectiveEarnings.additionalTipCount))"
    }

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

                // Which offer this delivery arrived in, said only where it
                // arrived with others. It is the one fact about a finished
                // delivery that the row cannot derive from its own timestamps.
                if let caption = offer?.groupingCaption(of: numbered) {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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

                // Absent when none was recorded, like the pickup place above
                // it. A "no amount recorded" line on every delivery would be
                // noise on the ordinary case, and the control below already
                // says whether there is one to add or to change.
                //
                // The label is `Gross earnings` on the ordinary delivery and
                // `Platform pay` on one that also carries tips, which is the one
                // place in the app the wording moves. Both name the same stored
                // fact. A delivery with tips has the other half of its total on
                // the very next line, and a first row still called `Gross
                // earnings` would read as the whole of what was paid; a delivery
                // with none has nothing to be one half of, and relabelling it
                // would make every ordinary card say something new about
                // nothing.
                if let earnings = delivery.grossEarnings {
                    LabeledContent(effectiveEarnings.hasAdditionalTips ? "Platform pay" : "Gross earnings") {
                        Text(earnings.formatted(locale: locale))
                            .monospacedDigit()
                    }
                    .font(.footnote)
                }

                // Both absent on the ordinary delivery, which is what keeps this
                // card exactly the size it has always been for a driver who
                // records no tips.
                if let tipsTotal = effectiveEarnings.additionalTipsTotal {
                    LabeledContent(additionalTipsTitle) {
                        Text(tipsTotal.formatted(locale: locale))
                            .monospacedDigit()
                    }
                    .font(.footnote)

                    if let total = effectiveEarnings.amount {
                        LabeledContent("Total recorded") {
                            Text(total.formatted(locale: locale))
                                .monospacedDigit()
                        }
                        .font(.footnote)
                    } else {
                        // Tips with no platform amount beside them. Said out
                        // loud, because a tip figure standing alone on a row
                        // would otherwise read as what the delivery earned.
                        Text("No platform pay recorded, so there is no total.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Only for a delivery that was actually delivered, and only over
                // its own lifecycle. Never summed with another row's.
                if let rate = delivery.effectiveEarningsPerDeliveryHour.amount {
                    LabeledContent("Per delivery hour") {
                        Text(rate.formatted(locale: locale))
                            .monospacedDigit()
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                // Shown whether or not a gross amount is recorded, and always
                // under its own heading. Two rows reading "Expected pay $8.50"
                // and "Gross earnings $7.25" are the point: what a delivery was
                // thought to be worth and what the driver recorded it as paying
                // are separate facts, and the only surface that can show both
                // at once is this one.
                if let expected = delivery.expectedEarnings {
                    LabeledContent("Expected pay") {
                        Text(expected.formatted(locale: locale))
                            .monospacedDigit()
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    // Said once, only where the absence is real. A delivery with
                    // an expectation and no recorded amount is the state the
                    // control below is offering to resolve, and leaving it
                    // implied would let the expected figure stand alone on the
                    // row as though it were the earnings.
                    if delivery.grossEarnings == nil {
                        Text("No gross earnings recorded.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier("shiftDetailDeliveryRow")

            // The corrections this delivery offers, laid out in a grid rather
            // than in one row. See ``availableActions`` and ``actionColumns``.
            LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 8) {
                ForEach(availableActions) { action in
                    // The identifier is the action's own identity, set here
                    // rather than three times below, so the control a journey
                    // looks up cannot drift from the one the grid ordered.
                    button(for: action)
                        .accessibilityIdentifier(action.rawValue)
                }
            }

            if let correctionMessage {
                Label(correctionMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("shiftDetailCorrectionMessage")
            }
        }
        .padding(.vertical, 2)
        // An alert rather than a confirmation dialog, for the reason the
        // recovery screen uses one: a dialog is a popover in some layouts, where
        // iOS drops the explicit Cancel button, and a correction that rewrites
        // how a recorded delivery ended must always show both choices.
        .alert(
            pendingCancellation.map { Text($0.title) } ?? Text("Correct to Cancelled"),
            isPresented: isConfirmingCancellation,
            presenting: pendingCancellation
        ) { prompt in
            Button(prompt.confirmTitle) { applyCancellation() }
                .accessibilityIdentifier("confirmCorrectToCancelledButton")
            Button("Cancel", role: .cancel) { pendingCancellation = nil }
        } message: { prompt in
            Text(prompt.detail)
        }
        .sheet(isPresented: $isEditingPickupPlace) {
            PickupPlaceEditor(numbered: numbered)
        }
        .sheet(isPresented: $isShowingPickupHistory) {
            if let place = delivery.pickupPlace {
                PickupPlaceHistoryView(place: place)
            }
        }
        .sheet(isPresented: $isEditingEarnings) {
            DeliveryEarningsEditor(numbered: numbered)
        }
        .sheet(isPresented: $isEditingTips) {
            DeliveryTipsEditor(numbered: numbered)
        }
        .sheet(isPresented: $isCorrectingTimes) {
            DeliveryTimeCorrectionEditor(numbered: numbered)
        }
    }

    // MARK: Actions

    /// The corrections this delivery offers, in the order they are read.
    ///
    /// A list rather than three conditional controls written straight into the
    /// layout, so that the grid is handed the number of actions there actually
    /// are: a delivery naming no place offers two, and the row that holds an odd
    /// last one has to leave the other cell empty rather than draw a control in
    /// it.
    private var availableActions: [DeliveryRowAction] {
        var available: [DeliveryRowAction] = [.pickupPlace]

        // Only where there is a place to have a history. A delivery that names
        // none has nothing to group by, and offering the control anyway would
        // suggest the app knows where it was.
        if delivery.pickupPlace != nil {
            available.append(.pickupHistory)
        }

        // Offered only for a finished delivery, which every delivery on a
        // completed shift is: a shift cannot end while one is still running.
        // Checked anyway, because a screen that merely never presents a control
        // is not the rule; the model's is.
        if delivery.state.isFinished {
            available.append(.earnings)
            // Beside the amount it sits beside on the row, and under the same
            // rule: a tip is money for work that has finished, and
            // `Delivery.recordAdditionalTip` refuses an unfinished delivery
            // whatever this screen offers.
            available.append(.additionalTips)
        }

        // Offered only where a correction would actually be accepted, which is
        // the same rule the control below keeps: the shift has to be over, the
        // delivery has to be finished, and the times it already records have to
        // be ones the domain will judge. A control that always refuses is worse
        // than no control.
        //
        // The proposal it is asked about is the delivery's **own** record, so
        // this asks "could anything here be corrected at all", never "is some
        // particular correction acceptable" — which is the editor's question and
        // is asked again while its pickers move.
        if canCorrectTimes {
            available.append(.correctTimes)
        }

        // Last, so the controls that record and correct facts keep the places
        // they had, and the one that rewrites how a delivery **ended** is met
        // after all of them. Offered only where it would actually succeed: the
        // shift has to be over, the delivery has to be recorded as delivered,
        // and its timestamps have to be ones the correction will accept. A
        // control that always refuses is worse than no control, which is the
        // rule the recovery screen already keeps.
        if canCorrectToCancelled {
            available.append(.correctToCancelled)
        }

        return available
    }

    /// Whether this row may offer to correct the times the delivery recorded.
    ///
    /// These are the two refusals a driver could never resolve from inside the
    /// editor: a delivery on a shift that has not ended has no window for its
    /// events to fall inside, and one that has not finished has no recorded
    /// history to correct. Neither moves because a picker did.
    ///
    /// **Deliberately not ``canCorrectToCancelled``'s shape**, which asks the
    /// domain whether the correction would be accepted as things stand. That is
    /// right there, where the correction takes no input and a control the rule
    /// would refuse could only ever refuse. Here the driver supplies the times,
    /// so a row whose stored chain already runs backwards — which the app cannot
    /// write, but a store could hold — is exactly the row this editor can
    /// repair, and hiding the control would leave it with no remedy at all.
    private var canCorrectTimes: Bool {
        delivery.shift?.completedWindow != nil && delivery.state.isFinished
    }

    /// Whether this row may offer the historical correction at all.
    ///
    /// The three conditions are asked in the order they are cheap, and the last
    /// of them is the domain rule itself rather than a second opinion about it:
    /// ``HistoricalDeliveryCancellation`` is what the write will consult, so a
    /// row it would refuse never grows a button.
    ///
    /// The shift check is not redundant even though this screen only ever shows
    /// finished shifts. The rule lives in the service, and a view that merely
    /// never presents a control is not a rule.
    private var canCorrectToCancelled: Bool {
        guard delivery.shift?.isActive == false else { return false }
        guard delivery.state == .delivered else { return false }
        return (try? HistoricalDeliveryCancellation(correcting: DeliveryLifecycleRecord(delivery))) != nil
    }

    /// Two columns of equal width, and one at accessibility text sizes.
    ///
    /// Three of these controls sharing a single row left each about a third of a
    /// phone's width, which is less than `Change Pickup Place` needs: on a real
    /// device the titles wrapped a word to a line and the whole area read as
    /// unfinished. Two columns give every action the same generous width,
    /// whatever its own title happens to be, and a title that still needs two
    /// lines gets them by making the row taller.
    ///
    /// At an accessibility size two columns would be the same mistake again, so
    /// the grid becomes a single column and the card grows downwards. Nothing
    /// here scales a font down, shortens a title or hard-codes a width for one
    /// device: the columns are fractions of whatever width the row is given.
    private var actionColumns: [GridItem] {
        let column = GridItem(.flexible(), spacing: 12, alignment: .topLeading)
        return Array(repeating: column, count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    /// One action's control, which is the only thing that knows what the action
    /// says, does and is called by VoiceOver.
    @ViewBuilder
    private func button(for action: DeliveryRowAction) -> some View {
        switch action {
        case .pickupPlace:
            let hasPlace = delivery.pickupPlace != nil
            Button {
                isEditingPickupPlace = true
            } label: {
                DeliveryActionLabel(
                    title: numbered.pickupPlaceActionTitle(hasPlace: hasPlace),
                    systemImage: hasPlace ? "pencil" : "plus.circle"
                )
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(numbered.spokenPickupPlaceLabel(hasPlace: hasPlace))

        case .pickupHistory:
            Button {
                isShowingPickupHistory = true
            } label: {
                DeliveryActionLabel(title: "Pickup History", systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(
                delivery.pickupPlace.map { "Recorded pickup waits at \($0.displayName)" } ?? "Recorded pickup waits"
            )

        case .earnings:
            let hasEarnings = delivery.grossEarnings != nil
            Button {
                isEditingEarnings = true
            } label: {
                DeliveryActionLabel(
                    title: numbered.earningsActionTitle(hasEarnings: hasEarnings),
                    systemImage: hasEarnings ? "pencil" : "plus.circle"
                )
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(numbered.spokenEarningsLabel(hasEarnings: hasEarnings))

        case .additionalTips:
            let tipCount = delivery.additionalTips.count
            Button {
                isEditingTips = true
            } label: {
                DeliveryActionLabel(
                    title: numbered.additionalTipsActionTitle(hasTips: tipCount > 0),
                    systemImage: tipCount > 0 ? "pencil" : "plus.circle"
                )
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(numbered.spokenAdditionalTipsLabel(tipCount: tipCount))

        case .correctTimes:
            Button {
                correctionMessage = nil
                isCorrectingTimes = true
            } label: {
                DeliveryActionLabel(
                    title: NumberedDelivery.correctTimesActionTitle,
                    // Deliberately not `clock.arrow.circlepath`, which `Pickup
                    // History` already carries two cells away in the same grid.
                    systemImage: "clock.badge.checkmark"
                )
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(numbered.spokenCorrectTimesLabel)

        case .correctToCancelled:
            Button {
                correctionMessage = nil
                pendingCancellation = .correct(
                    numbered,
                    keepsRecordedMoney: delivery.hasRecordedMoney
                )
            } label: {
                DeliveryActionLabel(
                    title: NumberedDelivery.correctToCancelledActionTitle,
                    systemImage: "arrow.uturn.backward"
                )
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(numbered.spokenCorrectToCancelledLabel)
        }
    }

    // MARK: Applying the correction

    private var isConfirmingCancellation: Binding<Bool> {
        Binding(
            get: { pendingCancellation != nil },
            set: { isShowing in if !isShowing { pendingCancellation = nil } }
        )
    }

    /// Writes the correction the driver confirmed, or states why it was refused.
    ///
    /// Nothing is reconciled with the Live Activity afterwards, and that is
    /// deliberate rather than an omission: the card represents the **running**
    /// shift, this delivery belongs to one that has ended, and the correction
    /// leaves the shift's own end timestamp exactly where it was. Nothing about
    /// the running shift can have changed.
    private func applyCancellation() {
        pendingCancellation = nil
        correctionMessage = nil

        do {
            try DeliveryService(context: modelContext).correctCompletionToCancellation(delivery)
        } catch {
            correctionMessage = (error as? any LocalizedError)?.errorDescription
                ?? "That delivery could not be corrected."
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
        // Spoken right after the delivery names itself, so a listener knows
        // which other rows in this history belong with it before hearing any of
        // its own figures.
        if let grouping = offer?.spokenGrouping(of: numbered) {
            sentences.append(grouping)
        }
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
        // The amount is named with its delivery rather than read out as a bare
        // figure, and the rate names its denominator in full — "per hour" alone
        // would be heard as a wage.
        if let earnings = delivery.grossEarnings {
            let amount = earnings.formatted(locale: locale)
            sentences.append(
                effectiveEarnings.hasAdditionalTips
                    ? numbered.spokenPlatformPayBesideTips(amount)
                    : numbered.spokenEarnings(amount)
            )
        }
        // Spoken in the order they are printed, and the total last, because a
        // listener has to hear the two halves before the figure they add up to.
        if let tipsTotal = effectiveEarnings.additionalTipsTotal {
            sentences.append(
                numbered.spokenAdditionalTips(
                    tipsTotal.formatted(locale: locale),
                    tipCount: effectiveEarnings.additionalTipCount
                )
            )
            if let total = effectiveEarnings.amount {
                sentences.append(numbered.spokenEffectiveEarnings(total.formatted(locale: locale)))
            } else {
                sentences.append(numbered.spokenNoPlatformPayBesideTips)
            }
        }
        if let rate = delivery.effectiveEarningsPerDeliveryHour.amount {
            sentences.append(numbered.spokenDeliveryHourRate(rate.formatted(locale: locale)))
        }
        // Spoken last and with the distinction carried in the sentence itself,
        // because a listener has no column headings to fall back on. Which
        // phrasing depends on whether a recorded amount was just read out: the
        // "no earnings recorded" sentence would be false where one was.
        if let expected = delivery.expectedEarnings {
            let amount = expected.formatted(locale: locale)
            sentences.append(
                delivery.grossEarnings == nil
                    ? numbered.spokenExpectedEarnings(amount)
                    : numbered.spokenExpectedEarningsBesideRecorded(amount)
            )
        }
        return sentences.joined(separator: ". ")
    }
}

/// What the route measurement on this screen depends on.
///
/// The shift's identifier answers "is this a different shift"; its recorded end
/// answers "is this the same shift measured against a different window". Both
/// have to be in the key, because correcting the end changes the second without
/// touching the first, and a measurement keyed on the identifier alone would
/// keep reporting the mileage the screen arrived with.
private struct RouteMeasurementKey: Hashable {
    let shift: UUID
    let endedAt: Date?
}

/// Which pause the editor is open on.
///
/// A case rather than an optional pause beside a boolean, so there is no state
/// in which the sheet is presented with nothing to correct, and adding a pause
/// is a first-class case rather than the absence of one.
private enum PauseEdit: Identifiable {
    case correcting(NumberedPause)
    case adding

    var pause: NumberedPause? {
        switch self {
        case let .correcting(numbered): numbered
        case .adding: nil
        }
    }

    /// The pause's own identifier, or a fixed one for the additive case.
    ///
    /// It drives `sheet(item:)` only. The stored identifier is never shown,
    /// spoken or put in an accessibility label.
    var id: String {
        switch self {
        case let .correcting(numbered): numbered.id.uuidString
        case .adding: "add"
        }
    }
}

/// One pause awaiting a deletion confirmation, with the sentences the domain
/// wrote for it.
///
/// The prompt is built when the control is pressed and carried here, so the
/// alert describes the deletion in the words the domain chose while the pause
/// itself is read again at the moment the write is attempted.
private struct PendingPauseDeletion: Identifiable {
    let pause: ShiftPause
    let prompt: ShiftPauseDeletionPrompt

    var id: UUID { pause.id }
}

/// One of the corrections a finished delivery offers from its history row.
///
/// A case rather than a closure held in a value: the row keeps deciding what
/// each control says and does, and this only says which of them are there and
/// in what order. The raw value is the accessibility identifier, applied once at
/// the grid, so the identity the grid orders by is the identity a journey looks
/// the control up by and the two cannot drift apart.
///
/// The order is the order they are read, and it is why the two corrections come
/// last: the four that record and change facts keep the places they had, and the
/// two that rewrite what the delivery's own lifecycle recorded are met after
/// them — the times first, and the one that rewrites how the delivery **ended**
/// after that.
///
/// Six of them fill three even rows of the two-column grid, where five left the
/// last cell empty. Nothing about the layout had to move to take the sixth: see
/// ``DeliveryHistoryRow/actionColumns``.
private enum DeliveryRowAction: String, Identifiable {
    case pickupPlace = "shiftDetailPickupPlaceButton"
    case pickupHistory = "shiftDetailPickupHistoryButton"
    case earnings = "shiftDetailDeliveryEarningsButton"
    case additionalTips = "shiftDetailDeliveryTipsButton"
    case correctTimes = "shiftDetailCorrectDeliveryTimesButton"
    case correctToCancelled = "shiftDetailCorrectToCancelledButton"

    var id: String { rawValue }
}

/// A `Label` whose icon sits close to its title rather than in a column of its
/// own.
///
/// The default style reserves a fixed width for the icon, which inside a
/// half-width grid cell is space taken from the words. Closing the gap gives
/// each title around fourteen more points to be written on, which is the
/// difference between `Change Pickup Place` on one line and on two, and it also
/// makes the pair read as one control rather than as a glyph beside some text.
///
/// Aligned on the first baseline, so an icon stays beside the first line of a
/// title that does wrap instead of drifting into the middle of it.
private struct DeliveryActionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon
            configuration.title
        }
    }
}

/// What one of those corrections looks like inside its grid cell.
///
/// It fills the cell rather than sizing to its own title, which is what makes
/// two controls beside each other the same width whatever they are called, and
/// what keeps the columns aligned down a list of deliveries whose actions
/// differ. The title wraps rather than truncating or shrinking: a control that
/// cannot say which delivery it changes is worse than a card one line taller.
///
/// The icon belongs to the title inside one `Label`, so the pair is one control
/// and one accessibility element rather than a picture beside a button.
private struct DeliveryActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(DeliveryActionLabelStyle())
            .font(.footnote)
            .multilineTextAlignment(.leading)
            // Wraps within the cell and takes the height it needs, rather than
            // being compressed to one line by the row around it.
            .fixedSize(horizontal: false, vertical: true)
            // The 44 points every interactive control is entitled to, kept even
            // for a one-line title, so two stacked actions cannot end up close
            // enough to tap each other by mistake.
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            // Without this the tap only lands on the glyphs themselves, which
            // is the narrow target the whole cell exists to avoid.
            .contentShape(Rectangle())
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
