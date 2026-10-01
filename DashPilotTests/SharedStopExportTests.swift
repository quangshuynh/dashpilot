import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// What an export says about deliveries the driver recorded as sharing a
/// pickup or a drop-off: two local grouping keys in JSON, nothing in the CSV,
/// no identity from the store, and no version bump.
///
/// Every amount, offset and name is invented.
@MainActor
@Suite("Shared stop export")
struct SharedStopExportTests {
    private let encoder = ExportDocumentEncoder()

    private func deliveries(_ fixture: ExportFixture, _ shift: Shift) throws -> [[String: Any]] {
        let document = ExportDocument(
            scope: .shift(shift.id),
            shifts: [try fixture.exportRecord(of: shift)],
            summary: nil,
            exportedAt: ExportFixture.start
        )
        let data = try encoder.json(for: document)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let first = try #require((object["shifts"] as? [[String: Any]])?.first)
        return try #require(first["deliveries"] as? [[String: Any]])
    }

    /// An offer of three where the first two share both stops and all three
    /// share the drop-off, then an independent offer of one.
    private func sharedShift(_ fixture: ExportFixture) throws -> Shift {
        let shift = try fixture.completedShift(earnings: "100.00")
        try fixture.deliveredOffer(in: shift, deliveryCount: 3, acceptedAfter: 300, earnings: [nil, nil, nil])
        try fixture.delivered(in: shift, acceptedAfter: 5_400, earnings: "6.25")
        let offer = try #require(shift.offersInOrder.first)
        let ordered = offer.deliveriesInOrder
        try OfferCorrectionService(context: fixture.context).recordSharedStops(
            pickup: [ordered[0], ordered[1]], dropOff: ordered, in: offer
        )
        return shift
    }

    @Test("Deliveries recorded as sharing a stop carry the same group, and an independent one carries null")
    func jsonCarriesTheGroups() throws {
        let fixture = try ExportFixture()
        let rows = try deliveries(fixture, try sharedShift(fixture))

        #expect(rows.map { $0["sharedPickupGroup"] as? Int } == [1, 1, nil, nil])
        #expect(rows.map { $0["sharedDropOffGroup"] as? Int } == [1, 1, 1, nil])
        #expect(rows.allSatisfy { $0.keys.contains("sharedPickupGroup") }, "Written as an explicit null, never left out")
        #expect(rows.allSatisfy { $0.keys.contains("sharedDropOffGroup") })
    }

    @Test("No stored identity, customer, address or place name for a stop reaches the file")
    func jsonCarriesNoIdentity() throws {
        let fixture = try ExportFixture()
        let shift = try sharedShift(fixture)
        let identities = shift.deliveries.flatMap { [$0.sharedPickupID, $0.sharedDropOffID] }.compactMap { $0 }
        #expect(!identities.isEmpty)

        let document = ExportDocument(
            scope: .shift(shift.id), shifts: [try fixture.exportRecord(of: shift)], summary: nil, exportedAt: ExportFixture.start
        )
        let text = try #require(String(data: try encoder.json(for: document), encoding: .utf8))
        for identity in identities {
            #expect(!text.contains(identity.uuidString), "A stored identity leaked")
            #expect(!text.lowercased().contains(identity.uuidString.lowercased()))
        }
        for word in ["customer", "address", "dropOffAddress", "sharedPickupID", "sharedDropOffID"] {
            #expect(!text.contains("\"\(word)"), "Wrote \(word)")
        }
    }

    @Test("Two separate shared pickups in one shift are numbered apart, in delivery order")
    func groupsAreNumberedWithinTheShift() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(earnings: "100.00")
        try fixture.deliveredOffer(in: shift, deliveryCount: 2, acceptedAfter: 300, earnings: [nil, nil])
        try fixture.deliveredOffer(in: shift, deliveryCount: 2, acceptedAfter: 3_000, earnings: [nil, nil])
        let corrections = OfferCorrectionService(context: fixture.context)
        for offer in shift.offersInOrder {
            try corrections.recordSharedStops(pickup: offer.deliveriesInOrder, dropOff: [], in: offer)
        }

        let rows = try deliveries(fixture, shift)
        #expect(rows.map { $0["sharedPickupGroup"] as? Int } == [1, 1, 2, 2])
        #expect(rows.allSatisfy { $0["sharedDropOffGroup"] is NSNull })
    }

    @Test("The CSV is unchanged: same width, no shared-stop column")
    func csvIsUnchanged() throws {
        let fixture = try ExportFixture()
        let shift = try sharedShift(fixture)
        let document = ExportDocument(
            scope: .shift(shift.id), shifts: [try fixture.exportRecord(of: shift)], summary: nil, exportedAt: ExportFixture.start
        )
        let text = try #require(String(data: try encoder.csv(for: document), encoding: .utf8))
        let header = try #require(text.split(separator: "\r\n").first)

        #expect(ExportDocumentEncoder.columns.count == 42)
        #expect(!header.contains("shared"))
    }

    @Test("Adding the groups did not move the format version")
    func versionUnchanged() {
        #expect(ExportFormat.version == 6)
    }
}
