import SwiftUI

/// A lightweight entry point. History and financial reads stay in their
/// destinations; Home observes only the unfinished shift supplied by the shell.
struct HomeWorkspace: View {
    let activeShift: Shift?
    let start: () -> Void
    let continueShift: () -> Void
    let history: () -> Void
    let money: () -> Void

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DashSpacing.md) {
                    Text(activeShift == nil ? "Ready when you are" : "Your shift is here")
                        .dashFont(.title)
                        .accessibilityAddTraits(.isHeader)
                    Text("A place for your delivery work, recorded on this device.")
                        .dashFont(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, DashSpacing.md)
                .listRowBackground(ShiftActivityPalette.cloud)
            }

            Section {
                if let activeShift {
                    VStack(alignment: .leading, spacing: DashSpacing.lg) {
                        DashStatusLabel(
                            title: activeShift.isPaused ? "Shift paused" : "Shift in progress",
                            symbol: activeShift.isPaused ? "pause.circle.fill" : "record.circle",
                            tint: activeShift.isPaused ? DashStatusTint.paused : DashStatusTint.running
                        )
                        .accessibilityIdentifier("homeShiftStatus")
                        Text(activeShift.isPaused
                             ? "Working time is paused. Open Work to resume your shift."
                             : activeShift.isRouteSuspended
                             ? "Vehicle parked. Working time continues."
                             : "Manage your deliveries and shift controls in Work.")
                            .dashFont(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(action: continueShift) {
                            Text("Continue Shift")
                                .dashFont(.control)
                                .frame(maxWidth: .infinity)
                        }
                        .dashPrimaryAction()
                        .controlSize(.large)
                        .accessibilityHint("Opens Work. A paused shift stays paused until you resume it.")
                        .accessibilityIdentifier("continueShiftButton")
                    }
                    .padding(.vertical, DashSpacing.md)
                } else {
                    StartShiftPanel(start: start)
                }
            }

            Section {
                Button(action: history) {
                    Label("View Work History", systemImage: "clock.arrow.circlepath")
                        .dashFont(.body)
                        .frame(minHeight: 44)
                }
                .accessibilityHint("Opens this week's History in Work, with access to older weeks.")
                .accessibilityIdentifier("homeHistoryButton")
                Button(action: money) {
                    Label("Open Money", systemImage: "creditcard")
                        .dashFont(.body)
                        .frame(minHeight: 44)
                }
                .accessibilityHint("Recorded expenses and period summaries.")
                .accessibilityIdentifier("homeMoneyButton")
            } header: {
                Text("Review your work")
            }
        }
        .dashCanvas()
        .navigationTitle("Home")
        .workspaceDestinations()
    }
}
