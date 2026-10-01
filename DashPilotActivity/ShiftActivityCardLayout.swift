import Foundation

/// Which lines the Live Activity's card draws for one snapshot, and in what
/// order, so that the controls are never the thing the system cuts off.
///
/// ## The defect it exists for
///
/// A Lock Screen Live Activity taller than 160 points is truncated from the
/// bottom, and the controls were drawn last. With one order in progress the card
/// measured about 240 points at the default text size, and about 265 once the
/// vehicle was parked, so on a real shift Resume Driving was cut off the card
/// while Park had been visible before it. Measured in
/// `ShiftActivityCardLayoutTests`.
///
/// ## The hierarchy, and what gives way
///
/// 1. The header: whether the shift is running, paused or parked, beside the
///    working clock. Always drawn, one line.
/// 2. What each order in progress is doing, one line each.
/// 3. The controls, in the order the app chose. Always drawn, whole.
/// 4. Secondary details: the recorded mileage with its qualifier, and how many
///    deliveries are done.
///
/// Each state gets a **fixed budget of lines** between the header and the
/// controls, decided here from the number of control rows, the surface and the
/// text size, never by measuring at run time. The order lines take it in is the
/// order above: orders first, then the sentence explaining a withheld step,
/// then the secondary line. Whatever does not fit is **not drawn** rather than
/// drawn and cut: a count of the orders that have no line of their own takes
/// the last line instead, and the mileage is never drawn without its qualifier.
/// The controls are drawn before the secondary line, so even a card the system
/// lays out taller than planned loses the least important line first.
///
/// ## It decides presentation only
///
/// Which controls exist, their order and which one is emphasised are the app's
/// decisions, carried in the snapshot. This type only arranges them. It holds no
/// rule about deliveries, parking or the pickup workflow.
nonisolated struct ShiftActivityCardLayout: Equatable, Sendable {
    /// Where the card is drawn.
    enum Surface: Equatable, Sendable {
        /// The Lock Screen card, 160 points tall at most.
        case lockScreen
        /// The Dynamic Island's expanded presentation, whose bottom region is
        /// what remains of the same height once the island's own header is
        /// drawn.
        case expandedIsland
    }

    /// The card's text size, in the two buckets its budget is measured for.
    ///
    /// The card is drawn at **`xLarge` at most**: past it,
    /// two control labels no longer fit side by side on the narrowest supported
    /// phone, and a third row of controls does not fit the card. The app itself
    /// is drawn at every size.
    enum TextSize: Equatable, Sendable {
        /// `large`, the default, and every smaller size.
        case standard
        /// `xLarge`, which every larger size is drawn at.
        case larger
    }

    /// The orders drawn with a line each, in the order the app listed them.
    let deliveryRows: [ShiftActivityDeliveryTimer]

    /// The line under the orders, or `nil`: how many orders have no line of
    /// their own, and why no step is offered, whichever apply.
    let footnote: String?

    /// The same line for VoiceOver, where nothing is abbreviated.
    let spokenFootnote: String?

    /// Whether the mileage and delivered line is drawn.
    let showsSecondaryLine: Bool

    /// The controls, in the app's order, in rows of at most two.
    let controlRows: [[ShiftActivityControl]]

    init(state: ShiftActivityAttributes.ContentState, surface: Surface, textSize: TextSize) {
        controlRows = stride(from: 0, to: state.controls.count, by: 2).map { start in
            Array(state.controls[start..<min(start + 2, state.controls.count)])
        }
        var lines = Self.lineBudget(controlRows: controlRows.count, surface: surface, textSize: textSize)

        let timers = state.activeDeliveryTimers
        let withheldStep = state.controlNotice != nil
        var rows: [ShiftActivityDeliveryTimer] = []
        var needsFootnote = false

        if !timers.isEmpty, lines > 0 {
            if !withheldStep, timers.count <= lines {
                rows = timers
                lines -= rows.count
            } else {
                // The footnote takes the last line: the orders without a line,
                // the withheld step, or both.
                rows = Array(timers.prefix(lines - 1))
                needsFootnote = true
                lines = 0
            }
        }

        let overflow = timers.count - rows.count
        deliveryRows = rows
        footnote = needsFootnote ? Self.footnote(overflow: overflow, withheldStep: withheldStep) : nil
        spokenFootnote = needsFootnote ? Self.spokenFootnote(overflow: overflow, withheldStep: withheldStep) : nil
        showsSecondaryLine = surface == .lockScreen && lines > 0
    }

    /// Lines available between the header and the controls.
    ///
    /// Measured, not reasoned: at `large` a line is about 20 points with its
    /// spacing, a control row 28 and the header 20; at `xLarge`, 23, 31 and 23.
    /// Each budget leaves the tallest state it allows at least a few points
    /// under the limit at both supported widths, which
    /// `ShiftActivityCardLayoutTests` asserts for every state.
    static func lineBudget(controlRows: Int, surface: Surface, textSize: TextSize) -> Int {
        switch (surface, textSize, controlRows) {
        case (.lockScreen, .standard, ...1): 3
        case (.lockScreen, .standard, _): 2
        case (.lockScreen, .larger, ...1): 3
        case (.lockScreen, .larger, _): 1
        case (.expandedIsland, _, ...1): 1
        case (.expandedIsland, _, _): 0
        }
    }

    private static func footnote(overflow: Int, withheldStep: Bool) -> String {
        switch (overflow > 0, withheldStep) {
        case (true, true): "\(overflow) more · Open DashPilot for steps"
        case (true, false): "\(overflow) more also active"
        case (false, _): "Open DashPilot to record a step"
        }
    }

    private static func spokenFootnote(overflow: Int, withheldStep: Bool) -> String {
        var sentences: [String] = []
        if overflow > 0 {
            let noun = overflow == 1 ? "delivery" : "deliveries"
            sentences.append("\(overflow) more \(noun) also active. Open DashPilot for their timers")
        }
        if withheldStep {
            sentences.append("Several deliveries are in progress. Open DashPilot to record a step")
        }
        return sentences.joined(separator: ". ") + "."
    }
}
