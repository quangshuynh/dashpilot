import SwiftUI

/// The one compact line of derived rates on a completed shift.
///
/// It renders only what ``ShiftMetrics`` says is available. A rate that could
/// not be derived leaves nothing behind — no dash, no `$0.00`, no placeholder —
/// because a shift with no amount recorded and a shift that paid nothing are
/// different facts, and so are a shift with no measurable route and one that
/// recorded zero miles. The reasons themselves are not spelled out here: the
/// line above already says what the route holds, and the row's own button
/// already offers to add an amount.
///
/// Both figures are **gross**, and the wording says what each divides by. The
/// hourly rate covers the shift's whole elapsed time, waiting included, so it is
/// never called an active or delivery hourly rate. The mileage rate divides by
/// recorded miles, which is why "recorded" is in the visible text and not only
/// in the documentation.
struct ShiftRatesLabel: View {
    let metrics: ShiftMetrics

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if !parts.isEmpty {
            content
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                // Wrap rather than truncate. Without this the row hands the
                // label its ideal width and a long rate is cut short — and the
                // first thing to disappear is the end of "recorded mi", which
                // is the word that makes the figure honest.
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(accessibilityLabel)
        }
    }

    /// Two rates share a line at ordinary text sizes. At accessibility sizes
    /// they stack: a truncated rate is worse than a second line, and a rate cut
    /// off mid-figure is worse still.
    @ViewBuilder
    private var content: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(parts, id: \.self, content: Text.init)
            }
        } else {
            Text(parts.joined(separator: " · "))
        }
    }

    /// The visible figures, in the order they are read.
    private var parts: [String] {
        var parts: [String] = []
        if let hourly = metrics.grossPerElapsedHour.amount {
            parts.append("\(hourly.formatted())/hr")
        }
        if let perMile = metrics.grossPerRecordedMile.amount {
            parts.append("\(perMile.formatted()) / recorded mi")
        }
        return parts
    }

    /// What VoiceOver says instead of the abbreviations.
    ///
    /// "per hour" and "mi" are fine to read and poor to hear, and the fact that
    /// makes the mileage rate honest — that its denominator is only the mileage
    /// DashPilot recorded — has to survive being spoken. The visible partial
    /// marker sits on the mileage line directly above this one; it is stated
    /// again here because the two lines are read as one element and a listener
    /// should not have to hold the earlier phrase in mind to interpret this one.
    private var accessibilityLabel: String {
        var sentences: [String] = []
        if let hourly = metrics.grossPerElapsedHour.amount {
            sentences.append("\(hourly.formatted()) gross earnings per shift hour")
        }
        if let perMile = metrics.grossPerRecordedMile.amount {
            sentences.append("\(perMile.formatted()) gross earnings per recorded mile")
            if metrics.isRoutePartial {
                sentences.append("Route capture was partial, so recorded miles are fewer than the miles driven")
            }
        }
        return sentences.joined(separator: ". ")
    }
}

#if DEBUG
#Preview("Both rates") {
    ShiftRatesLabel(
        metrics: PreviewSupport.metrics(
            grossEarnings: Money(minorUnits: 8625),
            elapsedDuration: 3 * 3600,
            miles: 44.7,
            isPartial: true
        )
    )
}

#Preview("Hourly only") {
    ShiftRatesLabel(
        metrics: PreviewSupport.metrics(
            grossEarnings: Money(minorUnits: 8625),
            elapsedDuration: 3 * 3600,
            miles: nil,
            isPartial: false
        )
    )
}

#Preview("No earnings recorded") {
    ShiftRatesLabel(
        metrics: PreviewSupport.metrics(
            grossEarnings: nil,
            elapsedDuration: 3 * 3600,
            miles: 44.7,
            isPartial: false
        )
    )
}
#endif
