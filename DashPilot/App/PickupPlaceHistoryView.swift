import SwiftData
import SwiftUI

/// What one pickup place's recorded waits look like, and what they do not claim.
///
/// ## Why this screen exists
///
/// A driver reviewing a finished shift can see how long *this* pickup took. The
/// question that follows is whether it was ordinary for the place, and until now
/// nothing could answer it. Reusable pickup identity gave those waits something
/// to group by; this sheet is where the grouping is read.
///
/// ## What it shows
///
/// The middle of the recorded waits, how many there were, and the shortest and
/// longest among them. No ranking against other places, no grade, no colour, no
/// arrow, no prediction of the next pickup and no advice about whether to take
/// an offer from here. It is a record, presented as one.
///
/// ## Reached from history, not from the road
///
/// The entry point is a delivery in a completed shift's log. Nothing on a
/// running shift shows a place's history: a figure offered mid-shift invites a
/// decision, and this interval deliberately builds the review surface first.
///
/// ## Where the place itself is managed
///
/// This is the one screen about a place rather than about a delivery, so
/// **Rename** and **Merge** live here. A delivery row would be the wrong home
/// for them: the controls there act on that delivery's own record, and a driver
/// tapping one beside `Delivery 2` should not be changing something every other
/// delivery reads.
struct PickupPlaceHistoryView: View {
    let place: PickupPlace

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isRenaming = false
    @State private var isMerging = false

    /// Set the moment the store accepts a merge, which deletes ``place``.
    ///
    /// The same guard ``CompletedShiftDetailView`` keeps around a deleted shift,
    /// and for the same reason: SwiftUI may evaluate this body once more while
    /// the sheet closes, and reading a property of a deleted model is not
    /// something to find out about on a driver's device.
    @State private var isMergedAway = false

    /// How many other places exist, read when the screen appears.
    ///
    /// Merge needs somewhere to merge into, and a control that cannot do
    /// anything should say so before it is tapped rather than after.
    @State private var mergeDestinationCount = 0

    /// How many individual waits are listed under the summary. Enough to see
    /// the shape of a short history without turning the sheet into a log.
    private static let listedWaitLimit = 8

    private var metrics: PickupWaitMetrics { place.pickupWaitMetrics() }

    /// Newest first, which is the order a driver reads their own history in.
    private var recentSamples: [PickupWaitSample] {
        place.pickupWaitSamples.reversed().prefix(Self.listedWaitLimit).map { $0 }
    }

    var body: some View {
        Group {
            if isMergedAway || place.isDeleted {
                // The place is gone and the sheet is closing; there is nothing
                // left to read, let alone display.
                Color.clear
            } else {
                content
            }
        }
        .sheet(isPresented: $isRenaming) {
            PickupPlaceRenameView(place: place)
        }
        .sheet(isPresented: $isMerging) {
            PickupPlaceMergeView(source: place, onMerged: handleMerge)
        }
    }

    private var content: some View {
        NavigationStack {
            Form {
                summarySection
                if !recentSamples.isEmpty {
                    recordedWaitsSection
                }
                managementSection
                explanationSection
            }
            .navigationTitle(place.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("closePickupPlaceHistoryButton")
                }
            }
        }
        .onAppear { mergeDestinationCount = otherPlaceCount }
    }

    // MARK: Managing the place

    /// The two ways a place's identity can be corrected.
    ///
    /// Below the history rather than above it: this sheet is opened to read what
    /// was recorded, and correcting the name is the occasional thing a driver
    /// does once they have seen it. Both are explicit, both name the place, and
    /// neither is offered anywhere a driver could reach it in traffic.
    private var managementSection: some View {
        Section {
            Button {
                isRenaming = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .accessibilityLabel("Rename pickup place, \(place.displayName)")
            .accessibilityIdentifier("renamePickupPlaceButton")

            Button {
                isMerging = true
            } label: {
                Label("Merge", systemImage: "arrow.triangle.merge")
            }
            .disabled(mergeDestinationCount == 0)
            .accessibilityLabel("Merge pickup place, \(place.displayName)")
            .accessibilityIdentifier("mergePickupPlaceButton")
        } header: {
            Text("This place")
        } footer: {
            Text(managementExplanation)
        }
    }

    /// What each control does, and why Merge may be unavailable.
    ///
    /// The two are described as the different intentions they are. Rename fixes
    /// a spelling; merge puts two places together and removes one of them, which
    /// is said in those words rather than as "combine".
    private var managementExplanation: String {
        let merge = mergeDestinationCount == 0
            ? """
            Merge puts this place's deliveries under another place and removes this one. It needs a \
            second pickup place, and this is the only one recorded so far.
            """
            : """
            Merge moves every delivery recorded here to another pickup place you choose, and then \
            removes this one. The deliveries and their recorded times are kept.
            """
        return """
            Rename changes what this place is called, everywhere. Its deliveries and their recorded \
            waits are unaffected. \(merge) DashPilot never combines two places on its own — it does \
            no name matching beyond treating capitalisation and spacing as the same.
            """
    }

    /// Every place except this one, counted rather than listed: the sheet that
    /// lists them reads them itself when it opens.
    private var otherPlaceCount: Int {
        (try? PickupPlaceService(context: modelContext).mergeDestinations(for: place).count) ?? 0
    }

    /// The merge succeeded, so this screen is showing a place the store no
    /// longer holds. It stops reading it and closes.
    private func handleMerge() {
        isMergedAway = true
        isMerging = false
        dismiss()
    }

    // MARK: Summary

    /// The headline, in whichever of the three states this place is in.
    ///
    /// All three say the sample count, and only one of them uses the word
    /// *typical*. The whole section is one accessibility element so a figure is
    /// never heard without the count it came from.
    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                if let typical = metrics.typicalDuration {
                    LabeledContent(PickupWaitMetrics.typicalTitle) {
                        Text(DurationText.short(typical))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                    }
                } else if let recorded = metrics.medianDuration {
                    // Exactly one wait: shown as the fact it is, without being
                    // named as the place's typical wait.
                    LabeledContent("Recorded wait") {
                        Text(DurationText.short(recorded)).monospacedDigit()
                    }
                }

                Text(metrics.basisStatement)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let explanation = metrics.insufficientHistoryExplanation {
                    Text(explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let spread = metrics.spreadStatement {
                    Text(spread)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(spokenSummary)
            .accessibilityIdentifier("pickupPlaceHistorySummary")
        } header: {
            Text("Pickup wait")
        }
    }

    /// One sentence per claim, so VoiceOver never hears a duration on its own.
    private var spokenSummary: String {
        [metrics.spokenStatement, metrics.spokenSpreadStatement]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    // MARK: The individual waits

    /// The waits themselves, newest first.
    ///
    /// The summary is derived from these, so listing them is what makes it
    /// checkable: a driver who doubts the middle value can see the numbers it
    /// sits among.
    private var recordedWaitsSection: some View {
        Section {
            ForEach(recentSamples, id: \.pickedUpAt) { sample in
                LabeledContent {
                    Text(DurationText.short(sample.duration)).monospacedDigit()
                } label: {
                    Text(sample.pickedUpAt, format: .dateTime.month().day().hour().minute())
                }
                .font(.footnote)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(DurationText.spoken(sample.duration)) on "
                        + sample.pickedUpAt.formatted(date: .abbreviated, time: .shortened)
                )
                .accessibilityIdentifier("pickupPlaceHistoryWaitRow")
            }
        } header: {
            Text("Recorded waits")
        } footer: {
            Text(Self.listedWaitsExplanation(of: metrics.sampleCount, listed: recentSamples.count))
        }
    }

    private static func listedWaitsExplanation(of total: Int, listed: Int) -> String {
        listed < total
            ? "The \(listed) most recent of \(total) recorded waits, newest first."
            : "Every recorded wait at this place, newest first."
    }

    // MARK: What this is

    private var explanationSection: some View {
        Section {
            Text(Self.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("pickupPlaceHistoryExplanation")
        }
    }

    /// Said in full rather than implied, because a number on a screen is read as
    /// a forecast unless it says otherwise.
    private static let explanation = """
        A wait is the time between arriving at a pickup and marking the order picked up, \
        measured only from those two events. Deliveries that recorded one of them, or \
        neither, are left out. Nothing is discarded for being unusually long, and none of \
        this predicts how long the next pickup here will take.
        """
}

#if DEBUG
#Preview("Several recorded waits") {
    PreviewSupport.pickupPlaceHistory(.severalRecordedWaits)
}

#Preview("One recorded wait") {
    PreviewSupport.pickupPlaceHistory(.oneRecordedWait)
}

#Preview("No recorded waits") {
    PreviewSupport.pickupPlaceHistory(.noRecordedWaits)
}
#endif
