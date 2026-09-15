import SwiftData
import SwiftUI

/// Taking back a `Delivered` the driver did not mean, from the record of the
/// shift they are working.
///
/// ## Why it is a screen of its own
///
/// The undo offered the moment a delivery is marked delivered is the fast path,
/// and it is short lived by design: it sits beside the controls a driver is
/// using and cannot stay there. A mis-tap is often noticed a few minutes later,
/// at the next door, and by then the card is gone from the panel. This is where
/// it is still fixable, and it is deliberate rather than quick: every reopening
/// here is confirmed by a sentence that says what happens to the delivery.
///
/// ## What it shows
///
/// The deliveries of this shift that are recorded as **delivered**, named
/// exactly as they are named on the cards and in history, each with the state it
/// would go back to. Nothing else is listed: a delivery still in progress has a
/// card of its own, and a cancelled one is not what this corrects.
///
/// A delivered delivery that cannot be reopened is shown and stated rather than
/// hidden, for the reason the correction screen shows an offer holding nothing:
/// a driver looking for a row must be able to see why the app will not act on
/// it. There is no control on such a row, because a control that always refuses
/// is worse than none.
///
/// ## Only while the shift is running
///
/// Reopening a delivery on a shift that has already ended would leave an active
/// delivery under a finished shift, which nothing could then advance. The
/// refusal lives in ``DeliveryService``; this screen states it rather than
/// discovering it, so the sheet left open while a shift ends elsewhere says what
/// happened instead of offering a control that cannot work.
struct DeliveryRecoveryView: View {
    let shift: Shift

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Write-only, like the panel's: a delivery becoming active again changes
    /// what the shift's Live Activity should say, including whether it may offer
    /// a step control at all.
    @Environment(ShiftLiveActivityService.self) private var liveActivity

    /// The reopening awaiting confirmation. Nothing is written until it is
    /// confirmed, and dismissing this sheet writes nothing at all.
    @State private var pending: PendingRecovery?

    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                if shift.lifecycleState != .running {
                    unavailableSection
                } else if candidates.isEmpty {
                    emptySection
                } else {
                    ForEach(candidates, id: \.numbered.id) { candidate in
                        candidateSection(candidate)
                    }
                    explanationSection
                }

                if let message {
                    failureSection(message)
                }
            }
            .navigationTitle("Reopen a Delivery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", role: .cancel) { dismiss() }
                        .accessibilityIdentifier("closeDeliveryRecoveryButton")
                }
            }
        }
        // An alert rather than a confirmation dialog, for the reason the
        // grouping correction uses one: a dialog is a popover in some layouts,
        // where iOS drops the explicit Cancel button, and a correction that puts
        // a delivery back into the shift's running work must always show both
        // choices.
        .alert(
            pending.map { Text($0.prompt.title) } ?? Text("Reopen a Delivery"),
            isPresented: isConfirming,
            presenting: pending
        ) { recovery in
            Button(recovery.prompt.confirmTitle) { apply(recovery) }
                .accessibilityIdentifier("confirmReopenDeliveryButton")
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { recovery in
            Text(recovery.prompt.detail)
        }
    }

    // MARK: What can be reopened

    /// One delivered delivery, and what reopening it would leave behind.
    ///
    /// The state is derived once, here, by the same rule the model applies when
    /// the write is attempted, so the row states what will happen rather than a
    /// screen's own guess at it.
    private struct Candidate {
        let numbered: NumberedDelivery
        let restored: DeliveryState?
        let refusal: DeliveryRecoveryRefusal?

        init(_ numbered: NumberedDelivery) {
            self.numbered = numbered
            do {
                restored = try DeliveryRecovery(
                    reopening: DeliveryLifecycleRecord(numbered.delivery)
                ).restoredState
                refusal = nil
            } catch let error as DeliveryRecoveryRefusal {
                restored = nil
                refusal = error
            } catch {
                restored = nil
                refusal = .notDelivered
            }
        }
    }

    /// The shift's deliveries that are recorded as delivered, under the numbers
    /// they have everywhere else.
    private var candidates: [Candidate] {
        // A closure rather than `map(Candidate.init)`: the initializer is
        // isolated to this actor, and passing it as a value hands a
        // main-actor-isolated function to a nonisolated `map`.
        shift.numberedDeliveries
            .filter { $0.delivery.state == .delivered }
            .map { Candidate($0) }
    }

    @ViewBuilder
    private func candidateSection(_ candidate: Candidate) -> some View {
        Section {
            deliveryRow(candidate)

            if let restored = candidate.restored {
                Button(candidate.numbered.reopenActionTitle) {
                    pending = PendingRecovery(
                        deliveryID: candidate.numbered.id,
                        prompt: .reopen(
                            candidate.numbered,
                            restoredTo: restored,
                            keepsRecordedMoney: candidate.numbered.delivery.hasRecordedMoney
                        )
                    )
                }
                .accessibilityLabel(candidate.numbered.spokenReopenLabel(restoredTo: restored))
                .accessibilityIdentifier("reopenDeliveryRowButton")
            } else if let refusal = candidate.refusal {
                Text(Self.refusalStatement(refusal))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("deliveryRecoveryRefusedRow")
            }
        }
    }

    /// Which delivery this is, when it was recorded delivered, and where it goes
    /// back to.
    ///
    /// The state is stated in words beside a symbol rather than shown by tint
    /// alone, for the reason every delivery state in the app is: a row read in
    /// bright sun, or by someone who does not see the colour, has to carry the
    /// same fact.
    private func deliveryRow(_ candidate: Candidate) -> some View {
        let delivery = candidate.numbered.delivery

        return VStack(alignment: .leading, spacing: 2) {
            Label(
                "\(candidate.numbered.title) · \(DeliveryState.delivered.historyDescription)",
                systemImage: DeliveryState.delivered.symbolName
            )
            .font(.subheadline.weight(.semibold))

            if let place = delivery.pickupPlace {
                Text(place.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let deliveredAt = delivery.deliveredAt {
                LabeledContent("Delivered") {
                    Text(deliveredAt, format: .dateTime.hour().minute())
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let restored = candidate.restored {
                Label(
                    "Goes back to \(restored.statusDescription.lowercased())",
                    systemImage: restored.symbolName
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenRow(candidate))
        .accessibilityIdentifier("deliveryRecoveryRow")
    }

    private func spokenRow(_ candidate: Candidate) -> String {
        var sentences = ["\(candidate.numbered.title), recorded as delivered"]
        if let place = candidate.numbered.delivery.pickupPlace {
            sentences.append("Picked up from \(place.displayName)")
        }
        if let deliveredAt = candidate.numbered.delivery.deliveredAt {
            sentences.append("Delivered at \(deliveredAt.formatted(date: .omitted, time: .shortened))")
        }
        if let restored = candidate.restored {
            sentences.append("Reopening it makes it active again, \(restored.statusDescription.lowercased())")
        }
        return sentences.joined(separator: ". ")
    }

    /// Why one delivered row cannot be acted on, in one sentence.
    ///
    /// Every case here describes a store the app cannot produce, apart from the
    /// cancellation, which this version has deliberately not decided how to take
    /// back. The wording states the fact and claims nothing about repairing it.
    private static func refusalStatement(_ refusal: DeliveryRecoveryRefusal) -> String {
        switch refusal {
        case .notDelivered:
            "This delivery is not recorded as delivered, so there is nothing to reopen."
        case .cancelled:
            "This delivery was cancelled. Only a delivery recorded as delivered can be reopened."
        case .pickedUpWithoutArrival:
            """
            This delivery records being picked up with no arrival at the pickup before it, so \
            DashPilot cannot tell which state to return it to.
            """
        case .timestampsOutOfOrder:
            """
            The times recorded for this delivery run backwards, so DashPilot cannot tell which state \
            to return it to.
            """
        }
    }

    // MARK: The list's own sections

    private var explanationSection: some View {
        Section {
            Text(
                """
                Reopening removes the delivered time and nothing else. The delivery becomes one you \
                are still working, back at the last step you recorded before it, and it appears \
                again among the cards on the running shift. Everything else stays as it is: the \
                times you recorded, the pickup place, any expected pay, and any gross earnings you \
                recorded against it. The shift cannot be ended again until the delivery is \
                delivered or cancelled.
                """
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("deliveryRecoveryExplanation")
        }
    }

    private var emptySection: some View {
        Section {
            Text("No delivery in this shift is recorded as delivered")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("deliveryRecoveryUnavailable")
        } footer: {
            Text("This is where a delivery you marked delivered by mistake is put back among the ones you are working.")
        }
    }

    /// A shift that is no longer running, which is the one state this screen
    /// cannot act in.
    private var unavailableSection: some View {
        Section {
            Text("A delivery can only be reopened while its shift is running")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("deliveryRecoveryShiftNotRunning")
        } footer: {
            Text(
                """
                A shift cannot end while a delivery is still in progress, so reopening one on a \
                shift that has finished would leave a delivery nothing could complete. Resume a \
                paused shift to reopen a delivery in it.
                """
            )
        }
    }

    private func failureSection(_ message: String) -> some View {
        Section {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("deliveryRecoveryMessage")
        }
    }

    // MARK: Applying

    /// A reopening the driver has chosen and not yet confirmed.
    ///
    /// It carries the delivery's identity and the sentences the alert shows, so
    /// the alert can describe the correction after the row that raised it has
    /// gone, and so the delivery is read back out of the shift at the moment the
    /// write is attempted rather than captured when the alert was raised.
    private struct PendingRecovery: Identifiable {
        let deliveryID: UUID
        let prompt: DeliveryRecoveryPrompt

        var id: UUID { deliveryID }
    }

    private var isConfirming: Binding<Bool> {
        Binding(
            get: { pending != nil },
            set: { isShowing in if !isShowing { pending = nil } }
        )
    }

    private func apply(_ recovery: PendingRecovery) {
        pending = nil
        message = nil

        do {
            guard let delivery = shift.deliveries.first(where: { $0.id == recovery.deliveryID }) else {
                message = "That delivery is no longer in DashPilot, so nothing was changed."
                return
            }
            try DeliveryService(context: modelContext).reopenDelivered(delivery)
        } catch {
            message = (error as? any LocalizedError)?.errorDescription
                ?? "That delivery could not be reopened."
        }

        // After every outcome, refused or not, for the reason the panel
        // reconciles after every one of its own: reconciling reads the store, so
        // a refusal costs one pass that finds nothing changed.
        liveActivity.reconcile()
    }
}

#if DEBUG
#Preview("A shift holding a delivered delivery") {
    PreviewSupport.rootView(container: PreviewSupport.activeDeliveryContainer())
}
#endif
