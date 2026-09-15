import SwiftData
import SwiftUI

/// The tips one finished delivery received **outside** what the platform
/// recorded paying for it, and the controls that record, correct and remove
/// them.
///
/// Presented only from a finished delivery in a completed shift's history, for
/// the reason ``DeliveryEarningsEditor`` is: typing an amount belongs after the
/// driving, and ``Delivery/recordAdditionalTip(_:method:at:)`` refuses an
/// unfinished delivery as well, because a screen that is merely never presented
/// is not a rule.
///
/// ## Why it is a list and not a field
///
/// Tips arrive as separate events. A driver handed cash at the door and then
/// given a platform tip that evening has two facts to record, with two methods
/// and two moments, and one editable "tips" amount would make them do the
/// arithmetic themselves and would throw away which half is already in their
/// pocket. Each row here is a ``DeliveryTip``; nothing on this screen is a
/// stored total.
///
/// ## The three figures at the top, and the sentence under them
///
/// The summary states the platform amount, the tips, and what the delivery
/// therefore paid — in that order, because the third is the first two added.
/// Under it sits the only warning this feature needs: **a tip the platform
/// already included in what it paid is part of that amount and must not be
/// recorded again here.** It is stated on the screen where a tip is entered
/// rather than left to a help page, because the moment it matters is the moment
/// somebody is typing.
///
/// A delivery with tips and **no** platform amount states that instead of a
/// total, and does not offer one. It paid the tips plus an amount nobody has
/// written down, and a screen showing the tips alone under the word "Total"
/// would be inventing the rest — see ``EffectiveDeliveryEarnings``.
struct DeliveryTipsEditor: View {
    let numbered: NumberedDelivery

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    /// Which tip the entry sheet is open on, or that a new one is being
    /// recorded.
    ///
    /// A case rather than an optional tip beside a boolean, on
    /// ``CompletedShiftDetailView``'s own pattern, so there is no state in which
    /// the sheet is presented with nothing to act on and adding is a
    /// first-class case rather than the absence of one.
    @State private var edit: TipEdit?

    /// What the store said when a change was refused, stated on the screen
    /// rather than swallowed.
    @State private var message: String?

    private var delivery: Delivery { numbered.delivery }

    private var tips: [DeliveryTip] { delivery.additionalTipsInOrder }

    private var earnings: EffectiveDeliveryEarnings { delivery.effectiveEarnings }

    var body: some View {
        NavigationStack {
            Form {
                summarySection
                tipsSection

                if let message {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            // A `Label` is a glyph and a text under one
                            // identifier, so VoiceOver would otherwise read the
                            // glyph's name. The sentence is what a listener
                            // needs.
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(message)
                            .accessibilityIdentifier("deliveryTipsMessage")
                    }
                }
            }
            .navigationTitle("Additional Tips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("closeDeliveryTipsButton")
                }
            }
        }
        .sheet(item: $edit) { edit in
            DeliveryTipEntryEditor(numbered: numbered, tip: edit.tip)
        }
    }

    // MARK: What the delivery paid

    @ViewBuilder
    private var summarySection: some View {
        Section {
            LabeledContent(platformPayTitle) {
                Text(earnings.platformPay?.formatted(locale: locale) ?? "Not recorded")
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(spokenPlatformPay)
            .accessibilityIdentifier("deliveryTipsPlatformPay")

            if let total = earnings.additionalTipsTotal {
                LabeledContent("Additional tips") {
                    Text(total.formatted(locale: locale))
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    numbered.spokenAdditionalTips(
                        total.formatted(locale: locale),
                        tipCount: earnings.additionalTipCount
                    )
                )
                .accessibilityIdentifier("deliveryTipsAdditionalTotal")
            }

            if let effective = earnings.amount, earnings.hasAdditionalTips {
                LabeledContent("Total recorded") {
                    Text(effective.formatted(locale: locale))
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(numbered.spokenEffectiveEarnings(effective.formatted(locale: locale)))
                .accessibilityIdentifier("deliveryTipsEffectiveTotal")
            }

            // Said only where the absence is real, and said out loud rather than
            // left as a missing row: a list of tips with no total above it would
            // otherwise read as though the tips were the total.
            if earnings.platformPay == nil, earnings.hasAdditionalTips {
                Text(
                    """
                    No platform pay is recorded for \(numbered.title), so there is no total to show. \
                    The tips below are what has been recorded.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(numbered.spokenNoPlatformPayBesideTips)
                .accessibilityIdentifier("deliveryTipsNoPlatformPayNotice")
            }
        } header: {
            Text("What \(numbered.title) Paid")
        } footer: {
            Text(
                """
                A tip belongs here only if it reached you outside what the platform recorded paying \
                for this delivery. If the platform already included it in that amount, it is part of \
                it: recording it here as well would count it twice.
                """
            )
        }
    }

    private var platformPayTitle: String {
        // The platform amount is called `Gross earnings` everywhere it stands
        // alone. On this screen it never stands alone, so it is named for the
        // half of the total it is.
        "Platform pay"
    }

    private var spokenPlatformPay: String {
        guard let platformPay = earnings.platformPay else {
            return "No platform pay recorded for \(numbered.title)"
        }
        let amount = platformPay.formatted(locale: locale)
        return earnings.hasAdditionalTips
            ? numbered.spokenPlatformPayBesideTips(amount)
            : numbered.spokenEarnings(amount)
    }

    // MARK: The tips themselves

    @ViewBuilder
    private var tipsSection: some View {
        Section {
            ForEach(Array(tips.enumerated()), id: \.element.id) { index, tip in
                // The recorded facts, read as one element, with an explicit
                // control under them — the shape a shift's recorded pauses
                // already have on ``CompletedShiftDetailView``.
                //
                // The whole row was a `Button` first, and it is worth knowing
                // why it is not: inside a `Form` a plain-styled button wrapping
                // a row of text reports as a button and takes a tap without
                // running its action, so the sheet never opened. That
                // reproduced on an idle machine. A named control is also the
                // better surface: a listener hears what pressing it does rather
                // than a row that happens to be interactive.
                VStack(alignment: .leading, spacing: 6) {
                    tipRow(number: index + 1, tip: tip)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(spokenTip(number: index + 1, tip: tip))
                        .accessibilityIdentifier("deliveryTipRow")

                    Button {
                        message = nil
                        edit = .correcting(tip)
                    } label: {
                        Label("Edit Tip", systemImage: "pencil")
                            .font(.footnote)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Edit tip \(index + 1) for \(numbered.title)")
                    .accessibilityIdentifier("editDeliveryTipButton")
                }
            }

            Button {
                message = nil
                edit = .adding
            } label: {
                Label("Add a Tip", systemImage: "plus.circle")
            }
            .accessibilityIdentifier("addDeliveryTipButton")
            .accessibilityLabel("Add an additional tip to \(numbered.title)")
        } header: {
            Text("Recorded Tips")
        } footer: {
            Text(
                tips.isEmpty
                    ? """
                    Nothing recorded. A delivery with no tips recorded is not a delivery that \
                    received none.
                    """
                    : """
                    Each tip is its own record. Correcting one leaves the others exactly as they \
                    are, and what the platform paid is never changed by anything on this screen.
                    """
            )
        }
    }

    /// One tip as it is printed: what it was, how it arrived, and when it was
    /// recorded.
    ///
    /// The number is a position in this list rather than anything stored, and it
    /// is not stable — removing a tip renumbers the rest. Every control acts on
    /// the row itself, never on the number, which is the rule ``NumberedPause``
    /// keeps for the same reason.
    private func tipRow(number: Int, tip: DeliveryTip) -> some View {
        // Plain stacks rather than a `LabeledContent`, which inside a button's
        // label is a row shape that reads as a control of its own.
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tip \(number)")
                Text(methodAndTime(of: tip))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Text(tip.amount.formatted(locale: locale))
                .monospacedDigit()
        }
    }

    private func methodAndTime(of tip: DeliveryTip) -> String {
        let method = tip.method?.title ?? "Method not recorded"
        let recorded = tip.recordedAt.formatted(date: .omitted, time: .shortened)
        return "\(method) · recorded \(recorded)"
    }

    private func spokenTip(number: Int, tip: DeliveryTip) -> String {
        NumberedDelivery.spokenTip(
            number: number,
            amount: tip.amount.formatted(locale: locale),
            method: tip.method,
            recordedAt: tip.recordedAt.formatted(date: .omitted, time: .shortened)
        )
    }
}

/// Which tip the entry sheet is open on.
///
/// The identifier drives `sheet(item:)` only. A stored `UUID` is never shown,
/// spoken or put in an accessibility label.
private enum TipEdit: Identifiable {
    case adding
    case correcting(DeliveryTip)

    var tip: DeliveryTip? {
        switch self {
        case .adding: nil
        case let .correcting(tip): tip
        }
    }

    var id: String {
        switch self {
        case .adding: "add"
        case let .correcting(tip): tip.id.uuidString
        }
    }
}

/// Records one additional tip, or corrects and removes one already recorded.
///
/// One sheet for all three, on ``ShiftPauseEditor``'s pattern: the typed text
/// and the chosen method are a **draft**, the store is written once when Save or
/// Remove is pressed, and cancelling leaves everything exactly as it was.
///
/// The refusals are written by ``DeliveryLifecycleError`` and ``MoneyInput``
/// rather than by this view, so the sentence a driver reads and the rule the
/// write consults cannot drift apart.
///
/// **It records no time of its own.** A tip takes the moment it is recorded, and
/// correcting one leaves that moment alone: a picker here would look like the
/// time the money changed hands, which is a fact DashPilot has never asked for
/// and does not hold.
struct DeliveryTipEntryEditor: View {
    let numbered: NumberedDelivery

    /// The tip being corrected, or `nil` when one is being recorded.
    let tip: DeliveryTip?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var text = ""
    @State private var method: DeliveryTipMethod = .cash
    @State private var message: String?
    @FocusState private var isAmountFocused: Bool

    private var isCorrecting: Bool { tip != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // A decimal pad, for the reason every other amount field in
                    // the app uses one: the field holds a number, and a full
                    // keyboard offers keys that can only produce a validation
                    // message.
                    TextField(placeholder, text: $text)
                        .keyboardType(.decimalPad)
                        .focused($isAmountFocused)
                        .font(.title2)
                        .monospacedDigit()
                        .accessibilityIdentifier("deliveryTipAmountField")
                        .accessibilityLabel("Additional tip for \(numbered.title)")
                        .onChange(of: text) { _, _ in
                            // The message describes the text that produced it,
                            // so it goes as soon as the text does.
                            message = nil
                        }
                } header: {
                    Text("Amount")
                } footer: {
                    Text(
                        """
                        What you received on top of what the platform recorded paying for \
                        \(numbered.title). It has to be more than nothing: a delivery that received \
                        no tip simply has none recorded.
                        """
                    )
                }

                Section {
                    // Segmented rather than a wheel: two choices, both visible,
                    // and no overlay covering the rest of the form.
                    Picker("How it reached you", selection: $method) {
                        ForEach(DeliveryTipMethod.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("deliveryTipMethodPicker")
                } header: {
                    Text("How It Reached You")
                } footer: {
                    Text(method.explanation)
                }

                if let message {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(message)
                            .accessibilityIdentifier("deliveryTipValidationMessage")
                    }
                }

                if isCorrecting {
                    Section {
                        Button("Remove This Tip", role: .destructive, action: remove)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("removeDeliveryTipButton")
                            .accessibilityLabel("Remove this additional tip from \(numbered.title)")
                    } footer: {
                        Text(
                            """
                            Removes the record entirely, which says this tip never arrived. What the \
                            platform paid for \(numbered.title) is not changed.
                            """
                        )
                    }
                }
            }
            .navigationTitle(isCorrecting ? "Edit Tip" : "Add a Tip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityIdentifier("cancelDeliveryTipButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .accessibilityIdentifier("saveDeliveryTipButton")
                }
            }
        }
        .onAppear {
            if let tip {
                text = MoneyInput(locale: locale).text(for: tip.amount)
                // A stored method this build cannot name leaves the control on
                // its default rather than inventing one; saving then records the
                // method the driver actually chose.
                method = tip.method ?? .cash
            }
            isAmountFocused = true
        }
    }

    private var placeholder: String { MoneyInput(locale: locale).placeholder }

    private func save() {
        do {
            let amount = try MoneyInput(locale: locale).amount(from: text)
            let service = DeliveryService(context: modelContext)
            if let tip {
                try service.updateAdditionalTip(tip, amount: amount, method: method)
            } else {
                try service.addAdditionalTip(amount, method: method, on: numbered.delivery)
            }
            dismiss()
        } catch let error as MoneyInputError {
            // The sheet stays open with the text the driver typed: an amount
            // that could not be saved is not a reason to make them type it
            // again.
            message = error.message(for: .additionalTip)
            isAmountFocused = true
        } catch {
            message = (error as? any LocalizedError)?.errorDescription ?? "That tip could not be saved."
            isAmountFocused = true
        }
    }

    private func remove() {
        guard let tip else { return }
        do {
            try DeliveryService(context: modelContext).deleteAdditionalTip(tip)
            dismiss()
        } catch {
            message = (error as? any LocalizedError)?.errorDescription ?? "That tip could not be removed."
        }
    }
}

#if DEBUG
#Preview("Two tips recorded") {
    PreviewSupport.deliveryTipsEditor(withRecordedTips: true)
}

#Preview("No tips recorded") {
    PreviewSupport.deliveryTipsEditor(withRecordedTips: false)
}

#Preview("Add a tip") {
    PreviewSupport.deliveryTipEntryEditor(correctingExisting: false)
}

#Preview("Edit a tip") {
    PreviewSupport.deliveryTipEntryEditor(correctingExisting: true)
}
#endif
