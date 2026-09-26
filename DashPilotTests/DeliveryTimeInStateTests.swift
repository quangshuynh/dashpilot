import Foundation
import Testing
@testable import DashPilot

/// How long a delivery in progress has been at its current step, which the
/// running card shows and the reminder's evidence reads.
///
/// One definition, taken from the recorded instants and nothing else: no
/// location, no guess at when an unrecorded step happened, and no figure for a
/// chain whose instants contradict each other.
@Suite("Delivery time in state")
struct DeliveryTimeInStateTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    private func record(
        accepted: Double = 0,
        arrived: Double? = nil,
        pickedUp: Double? = nil,
        delivered: Double? = nil,
        cancelled: Double? = nil
    ) -> DeliveryLifecycleRecord {
        DeliveryLifecycleRecord(
            acceptedAt: at(accepted),
            arrivedAtPickupAt: arrived.map(at),
            pickedUpAt: pickedUp.map(at),
            deliveredAt: delivered.map(at),
            cancelledAt: cancelled.map(at)
        )
    }

    @Test("Each active state is measured from its own recorded instant")
    func measuresFromTheStatesOwnInstant() {
        #expect(record().timeInCurrentState(asOf: at(12)) == TimeInterval(12 * 60))
        #expect(record(arrived: 5).timeInCurrentState(asOf: at(12)) == TimeInterval(7 * 60))
        #expect(record(arrived: 5, pickedUp: 9).timeInCurrentState(asOf: at(27)) == TimeInterval(18 * 60))
    }

    @Test("A contradictory chain has no clock, rather than a wrong one")
    func contradictoryChainsHaveNoClock() {
        #expect(record(arrived: 10, pickedUp: 4).timeInCurrentState(asOf: at(30)) == nil)
        #expect(record(pickedUp: 4).currentStateStartedAt == nil, "A pickup with no arrival")
    }

    @Test("A clock reading before the instant is not shown as zero")
    func aMovedClockIsNotZero() {
        #expect(record(arrived: 20).timeInCurrentState(asOf: at(10)) == nil)
    }

    @Test("The reminder's evidence is the same span the card shows")
    func reminderAgreesWithTheCard() throws {
        let delivery = AssistedDelivery(id: UUID(), number: 2, record: record(arrived: 5))
        let now = at(40)
        let suggestion = try #require(DeliveryProgressAssistance().suggestion(for: delivery, asOf: now))
        #expect(suggestion.stillRecordingNothingNewerFor == delivery.record.timeInCurrentState(asOf: now))
    }
}
