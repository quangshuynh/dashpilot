import SwiftData
import SwiftUI

/// A short, dismissible look at a shift that has just ended.
///
/// Shown only after the end has been written, and never over a running shift.
/// Five figures from ``PostShiftRecap`` and two ways out; anything more belongs
/// on the shift's detail screen, which View Shift Details opens.
struct PostShiftRecapView: View {
    let shiftID: UUID
    let done: () -> Void
    let viewDetails: (Shift) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @State private var shift: Shift?
    @State private var recap: PostShiftRecap?
    @State private var isUnavailable = false

    var body: some View {
        NavigationStack {
            List {
                if let recap {
                    figures(recap)
                } else if isUnavailable {
                    Section {
                        Text("This shift's summary is unavailable. It is in History.")
                    }
                } else {
                    Section { ProgressView("Measuring the recorded route…") }
                }
                if let shift {
                    Section {
                        Button {
                            viewDetails(shift)
                        } label: {
                            Label("View Shift Details", systemImage: "list.bullet.rectangle")
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("recapViewDetails")
                    }
                }
            }
            .dashCanvas()
            .navigationTitle("Shift Ended")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: done)
                        .accessibilityIdentifier("recapDone")
                }
            }
        }
        .task(id: shiftID) { load() }
    }

    private func figures(_ recap: PostShiftRecap) -> some View {
        Section {
            DashValueRow(title: "Recorded gross earnings", value: recap.grossStatement(locale: locale),
                         isFigure: recap.grossEarnings != nil, isProminent: true, keepsFigureTogether: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Recorded gross earnings, \(recap.grossEarnings?.formatted(locale: locale) ?? "not recorded")")
                .accessibilityIdentifier("recapGross")
            DashValueRow(title: "Working time", value: recap.workingTimeStatement, detail: "Pauses excluded",
                         isFigure: recap.workingDuration != nil, keepsFigureTogether: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Working time, \(recap.spokenWorkingTime). Pauses excluded.")
                .accessibilityIdentifier("recapWorkingTime")
            DashValueRow(title: "Gross per working hour", value: recap.rateStatement(locale: locale),
                         detail: recap.rateDetail, isFigure: recap.grossPerWorkingHour.isAvailable,
                         keepsFigureTogether: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Gross per working hour, \(recap.rateStatement(locale: locale)). \(recap.rateDetail ?? "")")
                .accessibilityIdentifier("recapRate")
            DashValueRow(title: "Recorded miles", value: recap.mileageStatement(locale: locale),
                         detail: recap.mileageDetail, isFigure: recap.route.isMeasured, keepsFigureTogether: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Recorded miles, \(recap.spokenMileage(locale: locale))")
                .accessibilityIdentifier("recapMileage")
            DashValueRow(title: "Estimated fuel cost", value: recap.fuelStatement(locale: locale),
                         detail: recap.fuelDetail, isFigure: recap.fuelEstimate.isAvailable, keepsFigureTogether: true)
                .dashEstimateSurface()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Estimated fuel cost, \(recap.fuelStatement(locale: locale)). \(recap.fuelDetail)")
                .accessibilityIdentifier("recapFuel")
        } footer: {
            Text("Gross before expenses. Recorded expenses are listed in Money by their own dates.")
        }
    }

    private func load() {
        let id = shiftID
        var descriptor = FetchDescriptor<Shift>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let found = try? modelContext.fetch(descriptor).first, found.endedAt != nil else {
            isUnavailable = true
            return
        }
        shift = found
        // The same walk the detail screen makes, once, for a shift that has
        // just ended and so holds no more positions than one shift's worth.
        recap = PostShiftRecap(shift: found, recordedDistance: found.recordedDistance())
    }
}
