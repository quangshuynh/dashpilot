import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// What an exported file must **not** contain.
///
/// Every other suite asserts that something is present and correct. This one
/// exists because the export is the moment DashPilot's data can leave the
/// device, and the failure mode is a field that appeared in the file because it
/// happened to be on the model — not because anyone decided it belonged there.
///
/// The two things guarded here are the two most sensitive: the coordinates a
/// route is made of, and the internal key the pickup catalogue matches names by.
@Suite("Shift export privacy")
@MainActor
struct ShiftExportPrivacyTests {
    private let encoder = ExportDocumentEncoder()

    /// A shift holding everything an export could accidentally leak: a measured
    /// route in two capture sessions, a named pickup place, amounts on the shift
    /// and on a delivery, and a cancellation.
    private func loadedFixture() throws -> (ExportFixture, Shift) {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(startedAfter: 9, lasting: 3, earnings: "86.25")
        fixture.attachRoute(to: shift, sessions: 2)
        let noodles = try fixture.place(named: "Nowhere Noodles")
        try fixture.delivered(in: shift, acceptedAfter: 300, place: noodles, earnings: "14.75")
        try fixture.cancelled(in: shift, acceptedAfter: 4_000, place: noodles)
        return (fixture, shift)
    }

    private func files(_ fixture: ExportFixture, _ shift: Shift) throws -> [(ExportFileFormat, String)] {
        let document = ExportDocument(
            scope: .shift(shift.id),
            shifts: [try fixture.exportRecord(of: shift)],
            summary: nil,
            exportedAt: ExportFixture.start
        )
        return try ExportFileFormat.allCases.map { format in
            (format, String(decoding: try encoder.data(for: document, as: format), as: UTF8.self))
        }
    }

    // MARK: Coordinates

    @Test("No latitude or longitude reaches a standard export")
    func noCoordinates() throws {
        let (fixture, shift) = try loadedFixture()
        // The route is real enough for the shift to report a measured distance,
        // which is what makes the absence below meaningful.
        #expect(shift.recordedDistance().isMeasured)
        #expect(shift.routeSamples.count == 24)

        // Every stored position, written out the two ways a leak would most
        // likely render it: full `Double` precision, and to the fifth decimal —
        // about a metre. Renderings shorter than eight characters are left out
        // because a coordinate that round (`40.0`) could collide with an
        // ordinary figure and would prove nothing either way.
        let forbidden = Set(
            shift.routeSamples
                .flatMap { [$0.latitude, $0.longitude] }
                .flatMap { ["\($0)", String(format: "%.5f", $0)] }
                .filter { $0.count >= 8 }
        )
        #expect(forbidden.count >= 4)

        for (format, text) in try files(fixture, shift) {
            for coordinate in forbidden {
                #expect(!text.contains(coordinate), "\(format.rawValue) contains the coordinate \(coordinate)")
            }
            // Nor any field that would invite one later.
            for key in ["latitude", "longitude", "coordinate", "routeSample", "captureSession"] {
                #expect(!text.localizedCaseInsensitiveContains(key), "\(format.rawValue) names \(key)")
            }
        }
    }

    @Test("The route is exported as a measurement and its coverage, and nothing more")
    func routeIsOnlyAMeasurement() throws {
        let (fixture, shift) = try loadedFixture()
        let record = try fixture.exportRecord(of: shift)

        // The whole of what a route contributes, so a field added to
        // `ShiftRouteExport` without a decision fails here.
        let encoded = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(record.route)
        ) as? [String: Any]
        #expect(
            Set(try #require(encoded).keys) == [
                "status", "isPartial", "recordedDistanceMetres", "recordedDistanceMiles",
                "segmentCount", "gapCount", "usableSampleCount", "usesInferredContinuity"
            ]
        )
    }

    // MARK: Pickup identity

    @Test("The normalised pickup key is never exported, only the name the driver typed")
    func noNormalizedPickupKey() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        // A spelling whose key differs visibly from its display name, so the
        // assertion below cannot pass by the two being the same string.
        let place = try fixture.place(named: "McDonald’s Nowhere")
        try fixture.delivered(in: shift, acceptedAfter: 300, place: place)

        #expect(place.normalizedName != place.displayName)

        for (format, text) in try files(fixture, shift) {
            #expect(text.contains("McDonald’s Nowhere"), "\(format.rawValue) should carry the typed name")
            #expect(
                !text.contains(place.normalizedName),
                "\(format.rawValue) must not carry the normalised key"
            )
            for key in ["normalizedName", "normalized", "comparisonKey"] {
                #expect(!text.localizedCaseInsensitiveContains(key), "\(format.rawValue) names \(key)")
            }
        }
    }

    @Test("A pickup place's catalogue bookkeeping is not exported")
    func noCatalogueBookkeeping() throws {
        let (fixture, shift) = try loadedFixture()

        for (format, text) in try files(fixture, shift) {
            for key in ["createdAt", "lastUsedAt", "pickupPlaceId", "placeId"] {
                #expect(!text.localizedCaseInsensitiveContains(key), "\(format.rawValue) names \(key)")
            }
        }
    }

    // MARK: Store internals

    @Test("No SwiftData identifier or entity name leaks into the file")
    func noPersistenceInternals() throws {
        let (fixture, shift) = try loadedFixture()

        for (format, text) in try files(fixture, shift) {
            for key in ["persistentModelID", "PersistentIdentifier", "primaryKey", "entityName", "storeIdentifier"] {
                #expect(!text.localizedCaseInsensitiveContains(key), "\(format.rawValue) names \(key)")
            }
        }
    }

    @Test("The exported identifiers are the models' own, not new ones minted for the file")
    func identifiersAreTheModelsOwn() throws {
        let (fixture, shift) = try loadedFixture()
        let record = try fixture.exportRecord(of: shift)

        #expect(record.id == shift.id)
        #expect(record.deliveries.map(\.id) == shift.deliveriesInOrder.map(\.id))
    }

    // MARK: Logging

    @Test("Nothing an export writes is the sort of value the log records")
    func exportLoggingRecordsNoContent() throws {
        // The log line the service writes is built from a scope kind, a format
        // and a count, all of which are asserted here to be free of content.
        // The values themselves cannot be read back from OSLog in a test, so the
        // guarantee is held at the source: these are the only three things
        // interpolated.
        #expect(ExportScope.allHistory.kind == "allHistory")
        #expect(ExportScope.shift(UUID()).kind == "shift")
        for format in ExportFileFormat.allCases {
            #expect(format.rawValue == format.fileExtension)
        }
    }
}
