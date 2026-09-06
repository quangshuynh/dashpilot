import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// What a completed shift becomes when it is written out.
///
/// These are the assertions that keep the file honest: not that a field exists,
/// but that it says the same thing the app says on screen and never a stronger
/// thing.
@Suite("Shift export records")
@MainActor
struct ShiftExportRecordTests {
    @Test("A completed shift maps to its own recorded facts")
    func completedShiftMaps() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(startedAfter: 9, lasting: 3, earnings: "86.25")
        let record = try fixture.exportRecord(of: shift)

        #expect(record.id == shift.id)
        #expect(record.startedAt == fixture.at(9))
        #expect(record.endedAt == fixture.at(12))
        #expect(record.elapsedSeconds == 3 * 3600)
        #expect(record.grossEarnings?.money == (try fixture.money("86.25")))
        #expect(record.currencyCode == "USD")
    }

    @Test("A running shift is refused rather than exported as history")
    func runningShiftRefused() throws {
        let fixture = try ExportFixture()
        let shift = fixture.runningShift()

        #expect(throws: ShiftExportError.shiftNotCompleted) {
            try shift.exportRecord(for: .none)
        }
    }

    // MARK: Earnings

    @Test("A shift with no amount exports an absence, not a zero")
    func missingShiftEarnings() throws {
        let fixture = try ExportFixture()
        let record = try fixture.exportRecord(of: try fixture.completedShift())

        #expect(record.grossEarnings == nil)
    }

    @Test("An amount recorded as zero is exported as zero")
    func explicitZeroShiftEarnings() throws {
        let fixture = try ExportFixture()
        let record = try fixture.exportRecord(of: try fixture.completedShift(earnings: "0"))

        #expect(record.grossEarnings?.money == Money.zero)
        #expect(record.grossEarnings?.string == "0.00")
    }

    @Test("Missing and explicit zero are two different exports")
    func missingIsNotZero() throws {
        let fixture = try ExportFixture()
        let missing = try fixture.exportRecord(of: try fixture.completedShift(startedAfter: 9))
        let zero = try fixture.exportRecord(of: try fixture.completedShift(startedAfter: 14, earnings: "0"))

        #expect(missing.grossEarnings == nil)
        #expect(zero.grossEarnings != nil)
    }

    @Test("A delivery's amount is its own and never taken from the shift's")
    func deliveryEarningsAreIndependent() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(earnings: "86.25")
        try fixture.delivered(in: shift, acceptedAfter: 300, earnings: "14.75")
        try fixture.delivered(in: shift, acceptedAfter: 3_000)

        let record = try fixture.exportRecord(of: shift)

        #expect(record.grossEarnings?.string == "86.25")
        #expect(record.deliveries[0].grossEarnings?.string == "14.75")
        // The second recorded none, and nothing allocated it a share of the
        // shift's amount.
        #expect(record.deliveries[1].grossEarnings == nil)
    }

    @Test("Nothing reconciles the two amounts")
    func noReconciliationField() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(earnings: "86.25")
        try fixture.delivered(in: shift, acceptedAfter: 300, earnings: "14.75")

        let json = try String(
            decoding: ExportDocumentEncoder().json(
                for: ExportDocument(
                    scope: .shift(shift.id),
                    shifts: [try fixture.exportRecord(of: shift)],
                    summary: nil,
                    exportedAt: ExportFixture.start
                )
            ),
            as: UTF8.self
        )

        for forbidden in ["unallocated", "missingEarnings", "discrepancy", "shortfall", "difference"] {
            #expect(!json.localizedCaseInsensitiveContains(forbidden), "\(forbidden) must not appear")
        }
    }

    // MARK: Lifecycle

    @Test("Every recorded lifecycle timestamp is preserved, and the absent ones stay absent")
    func lifecycleTimestamps() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        let delivery = try fixture.delivered(in: shift, acceptedAfter: 300, waitSeconds: 660)

        let record = try #require(try fixture.exportRecord(of: shift).deliveries.first)

        #expect(record.acceptedAt == delivery.acceptedAt)
        #expect(record.arrivedAtPickupAt == delivery.arrivedAtPickupAt)
        #expect(record.pickedUpAt == delivery.pickedUpAt)
        #expect(record.deliveredAt == delivery.deliveredAt)
        #expect(record.cancelledAt == nil)
        #expect(record.state == .delivered)
        #expect(record.number == 1)
    }

    @Test("A cancelled delivery keeps what happened and is never counted as completed")
    func cancelledDelivery() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        try fixture.delivered(in: shift, acceptedAfter: 300)
        try fixture.cancelled(in: shift, acceptedAfter: 3_000, earnings: "3.00")

        let record = try fixture.exportRecord(of: shift)
        let cancelled = try #require(record.deliveries.last)

        #expect(cancelled.state == .cancelled)
        #expect(cancelled.arrivedAtPickupAt != nil)
        #expect(cancelled.cancelledAt != nil)
        #expect(cancelled.deliveredAt == nil)
        // A cancelled order can pay compensation, and refusing to export it
        // would push the driver into recording it somewhere it did not happen.
        #expect(cancelled.grossEarnings?.string == "3.00")
        // No completion, so no rate over one.
        #expect(cancelled.grossPerDeliveryHour == nil)
        #expect(cancelled.acceptedToDeliveredSeconds == nil)

        #expect(record.deliveredCount == 1)
        #expect(record.cancelledCount == 1)
    }

    @Test("Deliveries are exported in the order they were accepted, with their shift numbers")
    func deliveryOrdering() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        // Inserted out of order on purpose.
        try fixture.delivered(in: shift, acceptedAfter: 5_400)
        try fixture.delivered(in: shift, acceptedAfter: 300)

        let record = try fixture.exportRecord(of: shift)

        #expect(record.deliveries.map(\.number) == [1, 2])
        #expect(record.deliveries[0].acceptedAt < record.deliveries[1].acceptedAt)
    }

    // MARK: Pickup identity

    @Test("A pickup place is exported only where one was recorded, by its display name")
    func pickupPlace() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        let noodles = try fixture.place(named: "Nowhere Noodles")
        try fixture.delivered(in: shift, acceptedAfter: 300, place: noodles)
        try fixture.delivered(in: shift, acceptedAfter: 3_000)

        let record = try fixture.exportRecord(of: shift)

        #expect(record.deliveries[0].pickupPlaceName == "Nowhere Noodles")
        #expect(record.deliveries[1].pickupPlaceName == nil)
    }

    // MARK: Pickup wait

    @Test("The exported wait is the domain's recorded wait")
    func pickupWaitMatchesTheDomain() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        let delivery = try fixture.delivered(in: shift, acceptedAfter: 300, waitSeconds: 660)

        let record = try #require(try fixture.exportRecord(of: shift).deliveries.first)

        #expect(record.pickupWaitSeconds == 660)
        #expect(record.pickupWaitSeconds.map(TimeInterval.init) == delivery.pickupWait)
    }

    @Test("A delivery cancelled before its pickup exports no wait rather than a zero")
    func cancelledBeforePickupHasNoWait() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        try fixture.cancelled(in: shift, acceptedAfter: 300)

        let record = try #require(try fixture.exportRecord(of: shift).deliveries.first)

        #expect(record.pickupWaitSeconds == nil)
    }

    // MARK: Active time

    @Test("Delivery active time is the unioned figure, not the sum of the deliveries")
    func activeTimeIsUnioned() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(startedAfter: 9, lasting: 3)
        // Two overlapping lifecycles: 300–1_800 and 900–2_400, which union to
        // 2_100 seconds and add up to 3_000.
        try fixture.delivered(in: shift, acceptedAfter: 300, waitSeconds: 300, deliveredAfterPickup: 1_020)
        try fixture.delivered(in: shift, acceptedAfter: 900, waitSeconds: 300, deliveredAfterPickup: 1_020)

        let record = try fixture.exportRecord(of: shift)

        #expect(record.deliveryActiveSeconds == 2_100)
        #expect(record.deliveryActiveSeconds == ExportDuration.seconds(shift.deliveryActiveTime().duration))
        #expect(record.nonDeliverySeconds == 3 * 3600 - 2_100)
    }

    @Test("A shift with no deliveries exports no active time, not zero")
    func noDeliveriesNoActiveTime() throws {
        let fixture = try ExportFixture()
        let record = try fixture.exportRecord(of: try fixture.completedShift())

        #expect(record.deliveryActiveSeconds == nil)
        #expect(record.nonDeliverySeconds == nil)
        #expect(record.deliveries.isEmpty)
    }

    // MARK: Route

    @Test("A measured route exports its distance, and a partial one says so")
    func partialRoute() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        fixture.attachRoute(to: shift, sessions: 2)

        let record = try fixture.exportRecord(of: shift)

        #expect(record.route.status == .measured)
        #expect(record.route.isPartial)
        #expect(record.route.segmentCount == 2)
        #expect(record.route.gapCount > 0)
        #expect(try #require(record.route.recordedDistanceMetres) > 0)
        #expect(try #require(record.route.recordedDistanceMiles) > 0)
    }

    @Test("A shift with no route exports no distance rather than zero miles")
    func noRoute() throws {
        let fixture = try ExportFixture()
        let record = try fixture.exportRecord(of: try fixture.completedShift())

        #expect(record.route.status == .noRouteRecorded)
        #expect(record.route.recordedDistanceMetres == nil)
        #expect(record.route.recordedDistanceMiles == nil)
        #expect(record.route.usableSampleCount == 0)
        // Not partial: it is missing entirely, which is a different fact.
        #expect(!record.route.isPartial)
    }

    @Test("Positions that join up into nothing are distinguished from no positions at all")
    func unmeasurableRoute() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        fixture.attachUnmeasurableRoute(to: shift)

        let record = try fixture.exportRecord(of: shift)

        #expect(record.route.status == .notEnoughRouteRecorded)
        #expect(record.route.usableSampleCount > 0)
        #expect(record.route.recordedDistanceMetres == nil)
        #expect(!record.route.isPartial)
    }

    @Test("Miles are derived from the same measurement as the metres")
    func milesAreDerived() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        fixture.attachRoute(to: shift, sessions: 1)

        let record = try fixture.exportRecord(of: shift)
        let distance = shift.recordedDistance()

        #expect(record.route.recordedDistanceMiles == ExportDistance.miles(of: distance))
        #expect(record.route.recordedDistanceMetres == ExportDistance.metres(of: distance))
    }

    // MARK: Rates

    @Test("Every rate is the one the app derives, and an unavailable one is absent")
    func ratesMatchTheDomain() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(startedAfter: 9, lasting: 3, earnings: "90.00")
        fixture.attachRoute(to: shift, sessions: 1)

        let record = try fixture.exportRecord(of: shift)
        let metrics = shift.metrics(for: shift.recordedDistance())

        // Rounded to the cents the app displays. A rate is kept at six fraction
        // digits internally so the display rounds the exact quotient once; a
        // file carrying those six digits would show a figure no screen ever did.
        #expect(record.grossPerElapsedHour?.money == metrics.grossPerElapsedHour.amount?.rounded())
        #expect(record.grossPerRecordedMile?.money == metrics.grossPerRecordedMile.amount?.rounded())
        // $90.00 over 3 hours.
        #expect(record.grossPerElapsedHour?.string == "30.00")
        // No deliveries, so there is no active-hour rate to export.
        #expect(record.grossPerDeliveryActiveHour == nil)
    }

    @Test("A shift with no amount exports no rates rather than zeros")
    func noEarningsNoRates() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        fixture.attachRoute(to: shift, sessions: 1)

        let record = try fixture.exportRecord(of: shift)

        #expect(record.grossPerElapsedHour == nil)
        #expect(record.grossPerDeliveryActiveHour == nil)
        #expect(record.grossPerRecordedMile == nil)
    }
}
