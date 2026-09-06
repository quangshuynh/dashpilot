import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// The canonical machine-readable file.
///
/// The suite reads the encoded bytes two ways on purpose: as text, because some
/// of the contract is about what the file *says* (an explicit `null`, a quoted
/// amount, a key that must never appear), and decoded back into the same value
/// types, because the rest of it is about nothing being lost on the way out.
@Suite("Shift export JSON")
@MainActor
struct ShiftExportJSONTests {
    private let encoder = ExportDocumentEncoder()

    private func document(
        _ fixture: ExportFixture,
        scope: ExportScope,
        shifts: [Shift],
        summary: PeriodExportSummary? = nil
    ) throws -> ExportDocument {
        ExportDocument(
            scope: scope,
            shifts: try shifts.map(fixture.exportRecord),
            summary: summary,
            exportedAt: ExportFixture.start
        )
    }

    private func text(_ document: ExportDocument) throws -> String {
        String(decoding: try encoder.json(for: document), as: UTF8.self)
    }

    private func object(_ document: ExportDocument) throws -> [String: Any] {
        let parsed = try JSONSerialization.jsonObject(
            with: try encoder.json(for: document),
            options: [.fragmentsAllowed]
        )
        return try #require(parsed as? [String: Any])
    }

    // MARK: Metadata

    @Test("The file states its own format version, which is not the schema version")
    func formatVersion() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        let object = try object(try document(fixture, scope: .shift(shift.id), shifts: [shift]))

        #expect(object["formatVersion"] as? Int == 2)
        #expect(object["producer"] as? String == "DashPilot")
        // The store is at v7 and the file is at 2. If a future change ever made
        // these the same number by accident, this is where it would show.
        #expect(ExportFormat.version != 7)
    }

    @Test("Metadata says what the file covers and how much of it there is")
    func metadata() throws {
        let fixture = try ExportFixture()
        let first = try fixture.completedShift(startedAfter: 9)
        let second = try fixture.completedShift(startedAfter: 14)
        let object = try object(try document(fixture, scope: .allHistory, shifts: [first, second]))

        #expect(object["exportedAt"] as? String == "2026-06-17T00:00:00Z")
        #expect(object["shiftCount"] as? Int == 2)
        let scope = try #require(object["scope"] as? [String: Any])
        #expect(scope["kind"] as? String == "allHistory")
        #expect(scope["periodStart"] is NSNull)
        #expect(scope["periodEndExclusive"] is NSNull)
    }

    @Test("A period scope carries its half-open span")
    func periodScope() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        let period = try #require(
            ReportingPeriod(unit: .day, containing: ExportFixture.start, calendar: ExportFixture.calendar)
        )
        let object = try object(try document(fixture, scope: .period(period), shifts: [shift]))
        let scope = try #require(object["scope"] as? [String: Any])

        #expect(scope["kind"] as? String == "day")
        #expect(scope["periodStart"] as? String == "2026-06-17T00:00:00Z")
        #expect(scope["periodEndExclusive"] as? String == "2026-06-18T00:00:00Z")
    }

    @Test("Nothing about the device or the driver is in the metadata")
    func metadataIsAnonymous() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        let object = try object(try document(fixture, scope: .shift(shift.id), shifts: [shift]))

        #expect(Set(object.keys) == ["formatVersion", "producer", "exportedAt", "scope", "shiftCount", "shifts", "summary"])
    }

    // MARK: Shape

    @Test("Keys are sorted, so the same records produce the same bytes")
    func deterministicOutput() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(earnings: "86.25")
        fixture.attachRoute(to: shift, sessions: 2)
        try fixture.delivered(in: shift, acceptedAfter: 300, place: try fixture.place(named: "Nowhere Noodles"))

        let document = try document(fixture, scope: .shift(shift.id), shifts: [shift])

        #expect(try encoder.json(for: document) == (try encoder.json(for: document)))
        // Sorted rather than declaration order, and asserted at the top level so
        // a change to the encoder's formatting is noticed here.
        let text = try text(document)
        let versionIndex = try #require(text.range(of: "\"formatVersion\""))
        let producerIndex = try #require(text.range(of: "\"producer\""))
        #expect(versionIndex.lowerBound < producerIndex.lowerBound)
    }

    @Test("A missing value is an explicit null, never an omitted key and never a zero")
    func explicitNulls() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        let object = try object(try document(fixture, scope: .shift(shift.id), shifts: [shift]))
        let encoded = try #require((object["shifts"] as? [[String: Any]])?.first)

        for key in [
            "grossEarnings", "deliveryActiveSeconds", "nonDeliverySeconds",
            "grossPerElapsedHour", "grossPerDeliveryActiveHour", "grossPerRecordedMile"
        ] {
            #expect(encoded[key] is NSNull, "\(key) should be an explicit null")
        }
        #expect(object["summary"] is NSNull)

        let route = try #require(encoded["route"] as? [String: Any])
        #expect(route["recordedDistanceMetres"] is NSNull)
        #expect(route["recordedDistanceMiles"] is NSNull)
    }

    @Test("Every delivery record has the same keys, whatever it recorded")
    func deliveryRecordsAreTheSameShape() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        try fixture.delivered(
            in: shift,
            acceptedAfter: 300,
            place: try fixture.place(named: "Nowhere Noodles"),
            earnings: "14.75"
        )
        try fixture.cancelled(in: shift, acceptedAfter: 3_000)

        let object = try object(try document(fixture, scope: .shift(shift.id), shifts: [shift]))
        let encoded = try #require((object["shifts"] as? [[String: Any]])?.first)
        let deliveries = try #require(encoded["deliveries"] as? [[String: Any]])

        #expect(deliveries.count == 2)
        #expect(Set(deliveries[0].keys) == Set(deliveries[1].keys))
    }

    // MARK: Money

    @Test("Money is a decimal string, so no parser turns it into a binary double")
    func moneyIsAString() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(earnings: "86.25")
        let text = try text(try document(fixture, scope: .shift(shift.id), shifts: [shift]))

        #expect(text.contains("\"grossEarnings\" : \"86.25\""))
        // Not a bare number, which is the mistake this rule exists to prevent.
        #expect(!text.contains("\"grossEarnings\" : 86.25"))
    }

    @Test(
        "An amount survives the round trip exactly, including the ones a double loses",
        arguments: ["0.00", "0.01", "0.10", "0.20", "0.30", "8.15", "86.25", "1234567.89", "99999.99"]
    )
    func moneyRoundTrips(amount: String) throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(earnings: amount)
        let document = try document(fixture, scope: .shift(shift.id), shifts: [shift])
        let decoded = try encoder.document(from: try encoder.json(for: document))

        let recorded = try #require(decoded.shifts.first?.grossEarnings?.money)
        #expect(recorded == (try fixture.money(amount)))
        // Exact decimal identity, not approximate equality: the whole point of
        // keeping money out of `Double`.
        #expect(recorded.amount == (try fixture.money(amount)).amount)
    }

    @Test("The currency is stated rather than implied, and no symbol is in the figure")
    func currency() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(earnings: "86.25")
        let text = try text(try document(fixture, scope: .shift(shift.id), shifts: [shift]))

        #expect(text.contains("\"currencyCode\" : \"USD\""))
        #expect(!text.contains("$"))
    }

    // MARK: Dates

    @Test("Timestamps are ISO 8601 in UTC, whatever the device is set to")
    func timestamps() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift(startedAfter: 9, lasting: 3)
        let object = try object(try document(fixture, scope: .shift(shift.id), shifts: [shift]))
        let encoded = try #require((object["shifts"] as? [[String: Any]])?.first)

        #expect(encoded["startedAt"] as? String == "2026-06-17T09:00:00Z")
        #expect(encoded["endedAt"] as? String == "2026-06-17T12:00:00Z")
    }

    @Test("A timestamp survives the round trip to the second")
    func timestampsRoundTrip() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        let document = try document(fixture, scope: .shift(shift.id), shifts: [shift])
        let decoded = try encoder.document(from: try encoder.json(for: document))

        #expect(decoded.shifts.first?.startedAt == shift.startedAt)
        #expect(decoded.shifts.first?.endedAt == shift.endedAt)
    }

    // MARK: Round trip

    @Test("A document with several shifts, stacked deliveries and a cancellation decodes back unchanged")
    func fullRoundTrip() throws {
        let fixture = try ExportFixture()
        let noodles = try fixture.place(named: "Nowhere Noodles")

        let first = try fixture.completedShift(startedAfter: 9, lasting: 3, earnings: "86.25")
        fixture.attachRoute(to: first, sessions: 2)
        try fixture.delivered(in: first, acceptedAfter: 300, place: noodles, earnings: "14.75")
        try fixture.delivered(in: first, acceptedAfter: 900, earnings: "0")
        try fixture.cancelled(in: first, acceptedAfter: 4_000, place: noodles)

        let second = try fixture.completedShift(startedAfter: 14, lasting: 2)
        fixture.attachUnmeasurableRoute(to: second)

        let document = try document(fixture, scope: .allHistory, shifts: [first, second])
        let decoded = try encoder.document(from: try encoder.json(for: document))

        #expect(decoded == document)
    }

    @Test("A Unicode pickup name encodes and decodes intact")
    func unicodePickupName() throws {
        let fixture = try ExportFixture()
        let shift = try fixture.completedShift()
        let place = try fixture.place(named: "Nowhere Noodles 🍜 Café")
        try fixture.delivered(in: shift, acceptedAfter: 300, place: place)

        let document = try document(fixture, scope: .shift(shift.id), shifts: [shift])
        let decoded = try encoder.document(from: try encoder.json(for: document))

        #expect(decoded.shifts.first?.deliveries.first?.pickupPlaceName == "Nowhere Noodles 🍜 Café")
        #expect(try text(document).contains("Nowhere Noodles 🍜 Café"))
    }

    // MARK: Period summary

    @Test("A period export carries every figure with the counts behind it")
    func periodSummaryCoverage() throws {
        let fixture = try ExportFixture()
        let period = try #require(
            ReportingPeriod(unit: .day, containing: ExportFixture.start, calendar: ExportFixture.calendar)
        )

        // Two shifts, one with an amount and a route and one with neither: the
        // shape that makes every coverage figure visibly incomplete.
        let paid = try fixture.completedShift(startedAfter: 9, lasting: 3, earnings: "90.00")
        fixture.attachRoute(to: paid, sessions: 1)
        try fixture.delivered(in: paid, acceptedAfter: 300, waitSeconds: 660, earnings: "14.75")
        try fixture.delivered(in: paid, acceptedAfter: 3_000, waitSeconds: 360)
        let unpaid = try fixture.completedShift(startedAfter: 14, lasting: 2)

        let records = [paid, unpaid].map { $0.periodRecord(for: $0.recordedDistance()) }
        let metrics = PeriodMetricsCalculator().metrics(of: records, in: period)
        let summary = PeriodExportSummary(metrics)

        let object = try object(
            try document(fixture, scope: .period(period), shifts: [paid, unpaid], summary: summary)
        )
        let encoded = try #require(object["summary"] as? [String: Any])

        #expect(encoded["completedShiftCount"] as? Int == 2)

        let earnings = try #require(encoded["earnings"] as? [String: Any])
        #expect(earnings["recordedGrossEarnings"] as? String == "90.00")
        #expect(earnings["contributingShiftCount"] as? Int == 1)
        #expect(earnings["totalShiftCount"] as? Int == 2)

        // A rate's own paired subset, which is not the same count as the
        // earnings coverage above it.
        let perMile = try #require(encoded["grossPerRecordedMile"] as? [String: Any])
        #expect(perMile["amount"] is String)
        #expect(perMile["contributingShiftCount"] as? Int == 1)
        #expect(perMile["totalShiftCount"] as? Int == 2)

        // Route partiality survives as its own count.
        let route = try #require(encoded["route"] as? [String: Any])
        #expect(route["measuredShiftCount"] as? Int == 1)
        #expect(route["unmeasurableShiftCount"] as? Int == 1)
        #expect(route["totalShiftCount"] as? Int == 2)

        let deliveries = try #require(encoded["deliveries"] as? [String: Any])
        #expect(deliveries["deliveredCount"] as? Int == 2)
        #expect(deliveries["pickupWaitSampleCount"] as? Int == 2)
        #expect(deliveries["medianPickupWaitSeconds"] as? Int == 510)

        // The delivery subtotal is counted over deliveries, never over shifts.
        let deliveryEarnings = try #require(encoded["deliveryEarnings"] as? [String: Any])
        #expect(deliveryEarnings["recordedTotal"] as? String == "14.75")
        #expect(deliveryEarnings["contributingDeliveryCount"] as? Int == 1)
        #expect(deliveryEarnings["totalDeliveryCount"] as? Int == 2)
    }

    @Test("A period rate no shift could contribute to is null with its counts intact")
    func unavailablePeriodRate() throws {
        let fixture = try ExportFixture()
        let period = try #require(
            ReportingPeriod(unit: .day, containing: ExportFixture.start, calendar: ExportFixture.calendar)
        )
        // An amount, but no route at all: the per-mile rate has no denominator.
        let shift = try fixture.completedShift(earnings: "90.00")

        let metrics = PeriodMetricsCalculator().metrics(
            of: [shift.periodRecord(for: shift.recordedDistance())],
            in: period
        )
        let object = try object(
            try document(
                fixture,
                scope: .period(period),
                shifts: [shift],
                summary: PeriodExportSummary(metrics)
            )
        )
        let summary = try #require(object["summary"] as? [String: Any])
        let perMile = try #require(summary["grossPerRecordedMile"] as? [String: Any])

        #expect(perMile["amount"] is NSNull)
        #expect(perMile["contributingShiftCount"] as? Int == 0)
        #expect(perMile["totalShiftCount"] as? Int == 1)
    }

    @Test("A period summary round-trips")
    func periodSummaryRoundTrips() throws {
        let fixture = try ExportFixture()
        let period = try #require(
            ReportingPeriod(unit: .week, containing: ExportFixture.start, calendar: ExportFixture.calendar)
        )
        let shift = try fixture.completedShift(earnings: "86.25")
        fixture.attachRoute(to: shift, sessions: 2)

        let metrics = PeriodMetricsCalculator().metrics(
            of: [shift.periodRecord(for: shift.recordedDistance())],
            in: period
        )
        let document = try document(
            fixture,
            scope: .period(period),
            shifts: [shift],
            summary: PeriodExportSummary(metrics)
        )
        let decoded = try encoder.document(from: try encoder.json(for: document))

        #expect(decoded == document)
    }
}
