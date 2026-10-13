import SwiftData
import SwiftUI

/// Completed financial history and the next work action share a screen, never
/// a lifecycle owner. The shell still starts and routes the active shift.
struct HomeWorkspace: View {
    let activeShift: Shift?
    let start: () -> Void
    let continueShift: () -> Void
    let history: () -> Void
    let money: () -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date.now
    @State private var loader = PeriodLoadStore()
    @State private var retryRevision = 0
    @Query(PeriodDataLoader.recentShifts) private var recent: [Shift]

    private var period: ReportingPeriod? { ReportingPeriod(unit: .week, containing: now, calendar: calendar) }
    private var overview: HomePeriodSummary? {
        guard case .loaded(let snapshot) = loader.state, snapshot.overview.period == period else { return nil }
        return snapshot.overview
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DashSpacing.md) {
                    Text(activeShift == nil ? "Make every hour count." : "Your shift is here")
                        .dashFont(.title)
                        .accessibilityAddTraits(.isHeader)
                    if let activeShift {
                        activeContext(activeShift)
                    } else {
                        StartShiftPanel(start: start, compact: true)
                    }
                }
                .padding(.vertical, DashSpacing.sm)
            }

            if period == nil {
                Section { DashNotice(title: "This week is unavailable", message: "Check your calendar settings.", symbol: "calendar") }
            } else if let overview {
                weekSection(overview)
            } else if loader.state == .failed {
                PeriodLoadFailure(retry: { retryRevision += 1 })
            } else {
                Section("This Week") {
                    ProgressView("Loading completed work…")
                        .accessibilityIdentifier("homeLoading")
                }
            }

            Section {
                if _recent.fetchError != nil {
                    Text("Recent work couldn't be loaded. Open History to try again.")
                        .dashFont(.body)
                } else if recent.isEmpty {
                    Text("Your completed shifts will appear here.")
                        .dashFont(.body)
                        .foregroundStyle(.secondary)
                }
                ForEach(recent) { shift in
                    NavigationLink(value: shift) { CompletedShiftRow(shift: shift) }
                        .accessibilityIdentifier("homeRecentShiftRow")
                }
                Button(action: history) {
                    Label("View History", systemImage: "clock.arrow.circlepath")
                        .dashFont(.body)
                        .frame(minHeight: 44)
                }
                .accessibilityHint("Opens this week's History in Work, with access to older weeks.")
                .accessibilityIdentifier("homeHistoryButton")
            } header: { Text("Recent work") }

            Section {
                Button(action: money) {
                    HStack {
                        VStack(alignment: .leading, spacing: DashSpacing.xs) {
                            Label("Open Money", systemImage: "creditcard").dashFont(.emphasis)
                            Text(moneyDetail).dashFont(.supporting).foregroundStyle(Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: DashSpacing.sm)
                        Image(systemName: "chevron.right").font(.footnote).accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityHint("Recorded expenses and period summaries.")
                .accessibilityIdentifier("homeMoneyButton")
            }
        }
        .dashCanvas()
        .navigationTitle("Home")
        .workspaceDestinations()
        .navigationDestination(for: Shift.self) { CompletedShiftDetailView(shift: $0) }
        .modifier(PeriodLoading(request: period.map { PeriodLoadRequest(period: $0) },
                                store: loader, retryRevision: retryRevision))
        .onAppear { now = .now }
        .onChange(of: scenePhase) { _, phase in if phase == .active { now = .now } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in now = .now }
    }

    private var moneyDetail: String {
        guard let overview else { return "Recorded expenses and deeper financial detail" }
        return overview.expenseCount == 0
            ? "No expenses recorded this week. Review your costs."
            : "Review this week's recorded expenses and period summaries."
    }

    private func activeContext(_ shift: Shift) -> some View {
        VStack(alignment: .leading, spacing: DashSpacing.md) {
            DashStatusLabel(
                title: shift.isPaused ? "Shift paused" : shift.isRouteSuspended ? "Vehicle parked" : "Shift in progress",
                symbol: shift.isPaused ? "pause.circle.fill" : shift.isRouteSuspended ? "parkingsign.circle.fill" : "record.circle",
                tint: shift.isPaused ? DashStatusTint.paused : shift.isRouteSuspended ? DashStatusTint.parked : DashStatusTint.running
            )
            .accessibilityIdentifier("homeShiftStatus")
            Text(shift.isPaused ? "Working time is paused. Open Work to resume."
                 : shift.isRouteSuspended ? "Working time continues while you're parked."
                 : "Your active work stays in Work. This week's figures include completed shifts only.")
                .dashFont(.supporting).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: continueShift) {
                Text("Continue Shift").dashFont(.control).frame(maxWidth: .infinity)
            }
            .dashPrimaryAction().controlSize(.large)
            .accessibilityHint("Opens Work. A paused shift stays paused until you resume it.")
            .accessibilityIdentifier("continueShiftButton")
        }
    }

    private func weekSection(_ summary: HomePeriodSummary) -> some View {
        Section {
            if summary.completedShiftCount == 0 {
                DashNotice(title: "No completed shifts this week yet",
                           message: activeShift == nil ? "Start a shift to build your weekly picture." : "Your active shift joins these figures once it ends.",
                           symbol: "calendar")
                    .accessibilityIdentifier("homeEmptyWeek")
                    .listRowBackground(ShiftActivityPalette.cloud)
            } else {
                DashMetric(value: summary.earnings?.formatted(locale: locale) ?? "Earnings not recorded",
                           label: "Recorded gross earnings", detail: basis(summary.earningsCoverage),
                           isFigure: summary.earnings != nil, emphasis: .financial)
                    .padding(.vertical, DashSpacing.md)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Recorded gross earnings. \(summary.earnings?.formatted(locale: locale) ?? "Earnings not recorded"). \(basis(summary.earningsCoverage))")
                    .accessibilityIdentifier("homeEarnings")
                    .listRowBackground(ShiftActivityPalette.cloud)

                DashValueRow(title: "Working time", value: summary.workingDuration.map(DurationText.short) ?? "Not available",
                             detail: "Pauses excluded. \(basis(summary.workingCoverage))", isFigure: summary.workingDuration != nil)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Working time. \(summary.workingDuration.map(DurationText.spoken) ?? "Not available"). Pauses excluded. \(basis(summary.workingCoverage))")
                    .accessibilityIdentifier("homeWorkingTime")
                DashValueRow(title: "Gross per working hour",
                             value: summary.hourlyRate.amount.map { "\($0.formatted(locale: locale))/hr" } ?? "Not available",
                             detail: summary.hourlyRate.isAvailable ? basis(summary.hourlyRate.coverage) : "Needs recorded earnings and positive working time on the same shift.",
                             isFigure: summary.hourlyRate.isAvailable)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Gross earnings per working hour. \(summary.hourlyRate.amount?.formatted(locale: locale) ?? "Not available"). \(basis(summary.hourlyRate.coverage)). Based on shifts with recorded earnings and positive working time.")
                    .accessibilityIdentifier("homeHourlyRate")
                if let target = summary.target.statement {
                    Text(target + ". Each shift uses its own starting target.")
                        .dashFont(.supporting).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(summary.target.spokenStatement ?? target)
                        .accessibilityIdentifier("homeHourlyTarget")
                }
            }
        } header: {
            Text("This Week · Completed shifts")
        } footer: {
            Text(summary.period.rangeStatement(calendar: calendar, locale: locale))
        }
    }

    private func basis(_ coverage: MetricCoverage) -> String {
        "Based on \(coverage.statement(noun: "completed shift"))"
    }
}
