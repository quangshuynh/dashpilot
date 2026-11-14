import SwiftUI

/// The financial figures of a ``PeriodComparison``, one readable row each.
///
/// Shared by Money and Insights so both say a comparison the same way.
/// ``PeriodComparisonCalculator`` decides every value, change, basis and
/// refusal; this only lays them out. Change is omitted while the selected
/// period is in progress, as the calculator's own in-progress statement says.
struct FinancialComparisonRows: View {
    let comparison: PeriodComparison
    var identifierPrefix: String?
    @Environment(\.locale) private var locale

    /// Money's figures only. Mileage, deliveries and active time need a load
    /// that reads deliveries and routes, so they stay in the full report.
    static let metrics: [PeriodComparisonMetric] = [.recordedGrossEarnings, .workingTime, .rate(.perWorkingHour), .recordedExpenses]

    var body: some View {
        ForEach(comparison.entries.filter { Self.metrics.contains($0.metric) }) { entry in
            VStack(alignment: .leading, spacing: DashSpacing.sm) {
                Text(entry.metric.title).dashFont(.emphasis)
                Text(entry.valuesStatement(locale: locale)).monospacedDigit()
                if !comparison.isCurrentPeriodInProgress, let change = entry.changeStatement(locale: locale) {
                    Text([change, entry.percentStatement(locale: locale)].compactMap { $0 }.joined(separator: " · "))
                        .monospacedDigit()
                }
                if let basis = entry.basisStatement { Text(basis).dashFont(.supporting) }
                if let refusal = entry.refusalStatement(noun: comparison.periodNoun), entry.percentageRefusal != .currentPeriodInProgress {
                    Text(refusal).dashFont(.supporting).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(identifierPrefix.map { "\($0).\(entry.metric.id)" } ?? "")
        }
    }
}
