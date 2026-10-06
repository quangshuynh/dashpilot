import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// The parked-history fixture read through the vocabulary the shift detail
/// speaks, without a simulator.
///
/// The fixture is the one the interface previews and the debug launch argument
/// open: a finished shift with 25 minutes recorded parked between two capture
/// sessions. What a driver hears about its short route is assembled from
/// ``RouteQuality``; the detail screen only places these sentences beside the
/// figure they qualify.
@MainActor
@Suite("Parked history route")
struct ParkedHistoryRouteTests {
    @Test("A parked shift's short route says the driver parked, and how long, and claims no extra driving")
    func aParkedShiftExplainsItsShortRoute() throws {
        let container = try PreviewSupport.seededParkedHistoryContainer()
        let context = ModelContext(container)
        let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
        let end = try #require(shift.endedAt)

        let quality = RouteQuality(
            shift.recordedDistance(),
            suspendedTime: shift.completedSuspendedTime ?? .none
        )
        let locale = Locale(identifier: "en_US")

        #expect(quality.mileageStatement(locale: locale) == "4.5 mi recorded")
        #expect(quality.segmentStatement == "2 capture segments")

        let suspension = try #require(quality.suspensionExplanation)
        #expect(suspension.contains("1 stretch parked"), "\(suspension)")
        #expect(suspension.contains("25 min"), "\(suspension)")

        let partial = try #require(quality.partialExplanation)
        #expect(partial.contains("time you recorded as parked"), "\(partial)")
        #expect(
            !partial.contains("more miles were driven than were recorded"),
            "Untrue of a vehicle that spent the stretch in a parking space"
        )

        #expect(shift.pauses.isEmpty, "Parking records no pause")
        #expect(
            shift.workingDuration(asOf: end) == end.timeIntervalSince(shift.startedAt),
            "Shopping is working: nothing subtracts the stretch parked"
        )
    }
}
