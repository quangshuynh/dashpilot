import AppIntents
import SwiftUI

// The Live Activity's card, compiled into the app **and** the widget extension.
//
// It lives beside the snapshot it draws rather than in the extension so that the
// app's own tests can lay it out and measure it against the height the system
// gives a Lock Screen card, and so a debug build can draw it on screen for a UI
// journey. It is still only a renderer: every value comes out of
// `ShiftActivityAttributes.ContentState`, which the app derived, and every button
// runs the app's own lifecycle service. The WidgetKit-only modifiers stay in the
// extension's `ActivityConfiguration`.

/// The Lock Screen card.
///
/// ## A strict hierarchy, in a fixed height
///
/// Header, then what each order is doing, then the controls, then the recorded
/// mileage and the delivered count, with ``ShiftActivityCardLayout`` deciding
/// how many lines each state may draw so the controls always fit. The old card
/// drew a separate parked line, a mileage line, a delivery count, a status line
/// and a row per order **above** the controls, and at 240 to 300 points it was
/// truncated through the controls on a real phone. Nothing it said is lost: the
/// parked state is the header, the one order's status is its row, the in-progress
/// count is the rows themselves, and the mileage and delivered count come last.
///
/// The text size is capped at `xLarge` on this surface only: past it, two
/// control labels no longer fit side by side on the narrowest supported phone
/// and the controls would need a third row the card does not have. The app's own
/// screens are drawn at every size.
struct ShiftActivityLockScreenView: View {
    let state: ShiftActivityAttributes.ContentState

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = ShiftActivityCardLayout(
            state: state,
            surface: .lockScreen,
            textSize: dynamicTypeSize > .large ? .larger : .standard
        )
        VStack(alignment: .leading, spacing: 6) {
            ShiftActivityHeader(state: state)
            ShiftActivityDeliveryRows(layout: layout)
            ShiftActivityControls(state: state, rows: layout.controlRows)
            if layout.showsSecondaryLine {
                ShiftActivitySecondaryLine(state: state)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityIdentifier("shiftActivityCard")
    }
}

/// The Dynamic Island's expanded bottom region: what each order is doing, as
/// far as the region has room, and the controls.
///
/// The island's own header (the shift's state and clock) is drawn in its
/// centre region by the extension, so this is what remains of the same height.
/// No mileage line: it is on the Lock Screen card, and the island is a second
/// reading of the same snapshot rather than the only place a fact appears.
struct ShiftActivityIslandBottom: View {
    let state: ShiftActivityAttributes.ContentState

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = ShiftActivityCardLayout(
            state: state,
            surface: .expandedIsland,
            textSize: dynamicTypeSize > .large ? .larger : .standard
        )
        VStack(alignment: .leading, spacing: 6) {
            ShiftActivityDeliveryRows(layout: layout)
            ShiftActivityControls(state: state, rows: layout.controlRows)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}

/// The shift's state beside its working clock, on one line.
///
/// Parked is said **here**, in place of `Shift in Progress`, rather than on a
/// line of its own: the clock beside it is still counting, which is what says
/// the shift is running, and the line it used to take is the one that pushed
/// Resume Driving off the card. Where the full sentence does not fit beside the
/// clock, the shorter form is drawn rather than wrapped; VoiceOver hears the
/// whole sentence either way.
///
/// Deliberately two elements rather than one combined one. Combining them would
/// freeze the running shift's clock into a fixed spoken value, and a driver
/// would be told the working time the snapshot was built with rather than the
/// one on screen.
struct ShiftActivityHeader: View {
    let state: ShiftActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            ViewThatFits(in: .horizontal) {
                status(state.headerTitle)
                status(state.shortHeaderTitle)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.spokenHeaderTitle)

            Spacer(minLength: 8)

            ShiftActivityWorkingTime(state: state)
                .layoutPriority(1)
        }
    }

    private func status(_ title: String) -> some View {
        Label(title, systemImage: state.headerSymbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(state.isPaused || state.routeSuspendedNotice != nil ? .orange : .red)
            .lineLimit(1)
    }
}

/// The working figure.
///
/// **Counted by the system, not pushed by the app.** While the shift runs the
/// figure is drawn from an anchor instant, so it stays correct with no further
/// updates for the length of the shift; while it is paused it does not move, so
/// it is drawn once. That is the whole reason this surface needs no per-second
/// update cadence.
struct ShiftActivityWorkingTime: View {
    let state: ShiftActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.isPaused {
                // A figure that is not moving is named and read out exactly,
                // which is what the app's own panel does while paused.
                Text(state.formattedWorkingTime)
                    .accessibilityLabel("Working time, paused")
                    .accessibilityValue(state.spokenWorkingTime)
            } else {
                // Left unlabelled on purpose. The system draws and speaks this
                // one from its anchor, so any label of ours would replace a live
                // figure with the one this snapshot happened to carry.
                Text(timerInterval: state.workingTimerRange, countsDown: false)
            }
        }
        .font(.headline)
        .monospacedDigit()
        .lineLimit(1)
        .foregroundStyle(state.isPaused ? .secondary : .primary)
    }
}

/// What each order in progress is doing and how long it has been open, one
/// line each, as many as the layout allows, and the footnote that says what
/// has no line.
///
/// ## One line per delivery, and the system counts each of them
///
/// `Delivery 1 · At pickup · 18:04`, drawn from that delivery's own acceptance
/// instant. **Counted by the system, not pushed by the app**, for exactly the
/// reason the shift's own clock is. Deliveries the driver recorded as sharing a
/// stop, in the same state since the same acceptance, arrive from the app as one
/// row (`Deliveries 3 and 4`), because one clock is then true of both.
///
/// Nothing is added together. Two stacked orders are two lifecycles running
/// over the same minutes, and one combined figure would be longer than the
/// shift and would belong to neither of them.
///
/// ## Two elements per row, deliberately
///
/// The label and the figure are separate, like the shift's clock and its
/// header. Combining them would freeze the count into whatever this snapshot
/// was built at, and a listener would be told a duration that stopped moving.
struct ShiftActivityDeliveryRows: View {
    let layout: ShiftActivityCardLayout

    var body: some View {
        if !layout.deliveryRows.isEmpty || layout.footnote != nil {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(layout.deliveryRows, id: \.self) { timer in
                    row(for: timer)
                }
                if let footnote = layout.footnote {
                    Text(footnote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityLabel(layout.spokenFootnote ?? footnote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(for timer: ShiftActivityDeliveryTimer) -> some View {
        HStack(spacing: 4) {
            // The subject, and the one element carrying a spoken label. The
            // middle dot is hidden from VoiceOver for the reason it is
            // everywhere else in this app: it is punctuation, not a word.
            Text(timer.title)
                .accessibilityLabel(timer.spokenLabel)
            Text(verbatim: "·")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            // Hidden from VoiceOver because the element above already speaks it.
            // It gives way first when the row is too narrow, which is why it
            // carries no layout priority and the figure does.
            if let state = timer.stateLabel {
                Text(state)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(verbatim: "·")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            // Left unlabelled on purpose. The system draws and speaks this one
            // from the anchor, so any label of ours would replace a live figure
            // with the one this snapshot happened to carry.
            Text(timerInterval: timer.timerRange, countsDown: false)
                .monospacedDigit()
                .layoutPriority(1)
        }
        .font(.caption)
        .lineLimit(1)
    }
}

/// The recorded mileage with its qualifier, and how many deliveries are done:
/// the least important line on the card, drawn last and only when the layout
/// has a line for it.
///
/// **Never drawn without its qualifier.** If the whole line does not fit on one
/// line, the delivered count is dropped; if the mileage and its marker still do
/// not fit, nothing is drawn rather than a figure cut short of `partial route`.
struct ShiftActivitySecondaryLine: View {
    let state: ShiftActivityAttributes.ContentState

    var body: some View {
        ViewThatFits(in: .horizontal) {
            line(state.secondaryLine)
            line(state.mileageLine)
            EmptyView()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recorded mileage")
        .accessibilityValue(state.spokenSecondaryLine)
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

/// The controls the app said this shift may offer, in its order, in rows of at
/// most two.
///
/// One row where they all fit and rows of two where they do not, rather than
/// truncating a label: a button whose words are cut short is a button a driver
/// has to guess at, which on this surface is how the wrong thing gets recorded.
/// The layout budgets for the rows of two, so the card never needs a third.
struct ShiftActivityControls: View {
    let state: ShiftActivityAttributes.ContentState
    let rows: [[ShiftActivityControl]]

    var body: some View {
        if !state.controls.isEmpty {
            ViewThatFits(in: .horizontal) {
                row(of: state.controls)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, line in
                        row(of: line)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(of controls: [ShiftActivityControl]) -> some View {
        HStack(spacing: 6) {
            ForEach(controls, id: \.self) { control in
                ShiftActivityControlButton(
                    control: control,
                    isEmphasised: control == ShiftActivityControl.emphasised(in: state.controls)
                )
            }
        }
    }
}

/// One control.
///
/// The intent is chosen by a switch rather than by a lookup returning an
/// existential, because a button has to name a concrete intent type. Each of
/// them is performed in the **app's** process and refused there by the app's own
/// rules, so a button shown against a snapshot that is a moment out of date
/// costs a refusal sentence rather than a wrong write.
struct ShiftActivityControlButton: View {
    let control: ShiftActivityControl

    /// Whether this is the one control on the card that carries the emphasis.
    ///
    /// Decided for the list rather than for the control, by
    /// ``ShiftActivityControl/emphasised(in:)``: the first control in the app's
    /// order that can take emphasis, so the order the app chose is also what the
    /// card makes prominent.
    let isEmphasised: Bool

    var body: some View {
        Group {
            switch control {
            case .pause:
                Button(intent: PauseShiftFromActivityIntent()) { label }
            case .resume:
                Button(intent: ResumeShiftFromActivityIntent()) { label }
            case .end:
                Button(intent: EndShiftFromActivityIntent()) { label }
            case .startDelivery:
                Button(intent: StartDeliveryFromActivityIntent()) { label }
            case .park:
                Button(intent: ParkVehicleFromActivityIntent()) { label }
            case .resumeDriving:
                Button(intent: ResumeDrivingFromActivityIntent()) { label }
            case .deliveryStep:
                Button(intent: RecordDeliveryProgressFromActivityIntent()) { label }
            }
        }
        .buttonStyle(.bordered)
        .tint(tint)
        .accessibilityLabel(control.spokenLabel)
        .accessibilityIdentifier(control.accessibilityIdentifier)
    }

    private var label: some View {
        Label(control.title, systemImage: control.symbolName)
            .font(.caption.weight(isEmphasised ? .semibold : .regular))
            .lineLimit(1)
    }

    /// Red only on End, which is the one action here a driver cannot undo from
    /// this surface.
    private var tint: Color {
        switch control {
        case .end: .red
        case .pause, .resume, .startDelivery, .park, .resumeDriving, .deliveryStep: .accentColor
        }
    }
}
