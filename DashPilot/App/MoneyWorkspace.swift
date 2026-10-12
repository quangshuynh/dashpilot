import SwiftUI

/// Entry points to the existing financial records and summaries. No new ledger,
/// aggregate, or historical query is constructed until a destination is opened.
struct MoneyWorkspace: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DashSpacing.md) {
                    Text("See what you've recorded")
                        .dashFont(.title)
                        .accessibilityAddTraits(.isHeader)
                    Text("Review your costs and the earnings from completed shifts.")
                        .dashFont(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, DashSpacing.md)
                .listRowBackground(ShiftActivityPalette.cloud)
            }
            Section {
                NavigationLink(value: WorkspaceDestination.expenses) {
                    Label("Recorded Expenses", systemImage: "creditcard")
                        .dashFont(.body)
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Recorded expenses")
                .accessibilityIdentifier("expensesLink")
                NavigationLink(value: WorkspaceDestination.periodSummary) {
                    Label("Period Summaries", systemImage: "calendar")
                        .dashFont(.body)
                        .frame(minHeight: 44)
                }
                .accessibilityHint("Earnings, coverage, recorded costs, and comparison with the previous period.")
                .accessibilityIdentifier("periodSummaryLink")
            } footer: {
                Text("Expenses are the costs you enter. Period summaries explain the records behind each figure.")
            }
        }
        .dashCanvas()
        .navigationTitle("Money")
        .workspaceDestinations()
    }
}
