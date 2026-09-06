import Foundation

/// Turns an ``ExportDocument`` into the bytes of a file.
///
/// Two encoders behind one call, and neither of them reads the store: the
/// document is already a tree of plain values by the time it arrives here, which
/// is what lets every byte of both formats be asserted in a test with no
/// container, no context and no rendered view.
///
/// ## Determinism
///
/// The same document produces the same bytes, every time, on every device. JSON
/// keys are sorted, so the file does not reorder itself between two exports of
/// the same shift; dates and amounts go through the one canonical formatter each
/// (``ExportTimestamp``, ``ExportAmount``) rather than through anything
/// locale-aware; and the CSV's column order is the fixed list below.
nonisolated struct ExportDocumentEncoder: Equatable, Sendable {
    init() {}

    /// The file's bytes, in the chosen format.
    ///
    /// - Throws: ``ShiftExportError/encodingFailed``.
    func data(for document: ExportDocument, as format: ExportFileFormat) throws -> Data {
        switch format {
        case .json: try json(for: document)
        case .csv: try csv(for: document)
        }
    }

    // MARK: JSON

    /// The canonical machine-readable form.
    ///
    /// Pretty-printed as well as sorted, because "portable" in this project
    /// means a driver can open the file and read it. The size cost is
    /// irrelevant at the scale of a week of shifts.
    func json(for document: ExportDocument) throws -> Data {
        do {
            return try Self.encoder.encode(document)
        } catch {
            // The document holds only plain values, so this is unreachable
            // short of a Foundation failure. It is surfaced as a clean error
            // rather than trapped: an export failing is not a reason to lose a
            // driver's session.
            throw ShiftExportError.encodingFailed
        }
    }

    /// Reads a document back. Used by the tests that prove the file is lossless,
    /// and by nothing in the app — DashPilot does not import.
    func document(from data: Data) throws -> ExportDocument {
        try Self.decoder.decode(ExportDocument.self, from: data)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        // The one timestamp rule, shared with the CSV writer, so the two files
        // cannot disagree about what a moment looks like.
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ExportTimestamp.string(date))
        }
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            guard let date = ExportTimestamp.date(string) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Expected an ISO 8601 timestamp in UTC, such as \"2026-09-05T13:04:05Z\"."
                    )
                )
            }
            return date
        }
        return decoder
    }()

    // MARK: CSV

    /// The flat, spreadsheet-friendly form: **one row per recorded delivery**,
    /// with its shift's own columns repeated across it.
    ///
    /// ## Why one table and not two files
    ///
    /// A shifts table and a deliveries table would be cleaner to normalise and
    /// would need a container to travel in. Packaging one is real work — a ZIP
    /// writer, or a directory the share sheet handles inconsistently — for a
    /// gain a driver opening a spreadsheet does not get. One delivery-oriented
    /// table opens in one window, sorts and filters, and repeats a handful of
    /// shift columns to do it.
    ///
    /// ## A shift with no deliveries
    ///
    /// Gets one row of its own, with every delivery column empty. It is a shift
    /// that happened, and dropping it because nothing was recorded inside it
    /// would make the file's shift count disagree with the JSON's.
    ///
    /// ## What is not in it
    ///
    /// The period summary. Every figure in one is paired with the count of
    /// shifts behind it, and a flat table has nowhere to keep that pairing —
    /// a `2.18` in a spreadsheet cell with its "4 of 6 shifts" left behind is
    /// exactly the claim this project spends its effort refusing to make. The
    /// summary is in the JSON export, and the sheet says so before the driver
    /// chooses.
    ///
    /// Recorded expenses, for a reason that comes from the model rather than
    /// from the format. This table's unit is a delivery, and an expense belongs
    /// to a **date** rather than to a delivery or a shift — so there is no row
    /// it can occupy, and putting it on the delivery that happens to be nearest
    /// would manufacture the attribution ``Expense`` exists to avoid. Appending
    /// a second table of expenses under the first was the alternative and was
    /// rejected: a file whose row shape changes half way down is one most
    /// parsers read as a corrupt table, and the row count would stop agreeing
    /// with the JSON's shift count. Expenses are in the JSON export, and the
    /// format picker says so before the driver chooses.
    ///
    /// Identifiers are also absent. They are of no use in a spreadsheet and
    /// would push the columns a driver actually reads off the first screen.
    func csv(for document: ExportDocument) throws -> Data {
        var writer = CSVWriter()
        writer.appendRow(Self.columns)

        for shift in document.shifts {
            guard !shift.deliveries.isEmpty else {
                writer.appendRow(Self.shiftFields(shift) + Self.emptyDeliveryFields)
                continue
            }
            for delivery in shift.deliveries {
                writer.appendRow(Self.shiftFields(shift) + Self.deliveryFields(delivery))
            }
        }

        guard let data = writer.text.data(using: .utf8) else { throw ShiftExportError.encodingFailed }
        return data
    }

    /// The column order, fixed. Shift columns first so a sorted file groups by
    /// shift, then the delivery's own.
    ///
    /// Every name states what the figure is rather than what it might be taken
    /// for: `shiftRecordedDistanceMiles`, never `milesDriven`;
    /// `deliveryPickupWaitSeconds`, never `wait`.
    static let columns = [
        "shiftStartedAt",
        "shiftEndedAt",
        "shiftElapsedSeconds",
        "currencyCode",
        "shiftGrossEarnings",
        "shiftDeliveryActiveSeconds",
        "shiftNonDeliverySeconds",
        "shiftRecordedDistanceMetres",
        "shiftRecordedDistanceMiles",
        "shiftRouteStatus",
        "shiftRouteIsPartial",
        "shiftRouteSegmentCount",
        "shiftRouteGapCount",
        "shiftRouteUsableSampleCount",
        "shiftRouteUsesInferredContinuity",
        "shiftGrossPerElapsedHour",
        "shiftGrossPerDeliveryActiveHour",
        "shiftGrossPerRecordedMile",
        "shiftDeliveredCount",
        "shiftCancelledCount",
        "deliveryNumber",
        "deliveryState",
        "deliveryAcceptedAt",
        "deliveryArrivedAtPickupAt",
        "deliveryPickedUpAt",
        "deliveryDeliveredAt",
        "deliveryCancelledAt",
        "deliveryPickupPlaceName",
        "deliveryPickupWaitSeconds",
        "deliveryAcceptedToDeliveredSeconds",
        "deliveryGrossEarnings",
        "deliveryGrossPerDeliveryHour"
    ]

    /// An absent value.
    ///
    /// **An empty cell, never `0`.** A shift with no amount recorded and a shift
    /// recorded as paying nothing are different facts, and `0` in a column a
    /// spreadsheet will happily sum is the single most damaging way to lose that
    /// distinction.
    private static let empty = ""

    private static let emptyDeliveryFields = Array(repeating: empty, count: 12)

    private static func shiftFields(_ shift: ShiftExportRecord) -> [String] {
        [
            ExportTimestamp.string(shift.startedAt),
            ExportTimestamp.string(shift.endedAt),
            integer(shift.elapsedSeconds),
            shift.currencyCode,
            amount(shift.grossEarnings),
            integer(shift.deliveryActiveSeconds),
            integer(shift.nonDeliverySeconds),
            number(shift.route.recordedDistanceMetres, scale: ExportDistance.metresScale),
            number(shift.route.recordedDistanceMiles, scale: ExportDistance.milesScale),
            shift.route.status.rawValue,
            boolean(shift.route.isPartial),
            String(shift.route.segmentCount),
            String(shift.route.gapCount),
            String(shift.route.usableSampleCount),
            boolean(shift.route.usesInferredContinuity),
            amount(shift.grossPerElapsedHour),
            amount(shift.grossPerDeliveryActiveHour),
            amount(shift.grossPerRecordedMile),
            String(shift.deliveredCount),
            String(shift.cancelledCount)
        ]
    }

    private static func deliveryFields(_ delivery: DeliveryExportRecord) -> [String] {
        [
            String(delivery.number),
            delivery.state.rawValue,
            ExportTimestamp.string(delivery.acceptedAt),
            timestamp(delivery.arrivedAtPickupAt),
            timestamp(delivery.pickedUpAt),
            timestamp(delivery.deliveredAt),
            timestamp(delivery.cancelledAt),
            // The one field a driver typed, and the reason `CSVWriter` guards
            // against spreadsheet formulas at all.
            delivery.pickupPlaceName ?? empty,
            integer(delivery.pickupWaitSeconds),
            integer(delivery.acceptedToDeliveredSeconds),
            amount(delivery.grossEarnings),
            amount(delivery.grossPerDeliveryHour)
        ]
    }

    private static func amount(_ value: ExportAmount?) -> String {
        value?.string ?? empty
    }

    private static func integer(_ value: Int?) -> String {
        value.map(String.init) ?? empty
    }

    private static func timestamp(_ value: Date?) -> String {
        value.map(ExportTimestamp.string) ?? empty
    }

    private static func boolean(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    /// A measurement, written to a fixed number of fraction digits in
    /// `en_US_POSIX` so the separator is a full stop wherever the device is set.
    private static func number(_ value: Double?, scale: Int) -> String {
        guard let value, value.isFinite else { return empty }
        return value.formatted(
            .number
                .precision(.fractionLength(scale))
                .grouping(.never)
                .locale(Locale(identifier: "en_US_POSIX"))
        )
    }
}
