import Foundation
import SwiftData
@testable import DashPilot

/// Measures candidate *shapes* for the route-sample write, before any of them
/// is proposed as a change to the app.
///
/// The isolation probe showed that the cost of writing one position grows with
/// the length of the `Shift.routeSamples` inverse relationship, and that
/// nothing about the context or the size of the table explains it. The question
/// that follows is what the cheapest stored shape actually is, and that cannot
/// be answered by reasoning about SwiftData: it has to be written down and
/// timed.
///
/// These models are **test-only**, in a **test-only schema**, in their own
/// throwaway store. Nothing here is part of the app's schema, nothing here is
/// migrated, and nothing here is written to a real store. They exist to answer
/// one question and are deleted with the container that held them.
///
/// Three shapes, differing only in how a sample says which shift it belongs to:
///
/// - ``ShapeLinkedSample`` is the shipping shape: a to-one relationship with
///   the matching to-many inverse on the shift. It is the control, and should
///   reproduce the curve the shipping run measured.
/// - ``ShapeOneSidedSample`` keeps the to-one relationship and declares **no
///   inverse array** on the shift.
/// - ``ShapeForeignKeySample`` keeps no relationship at all and stores the
///   shift's `UUID` as an ordinary attribute.
@Model
nonisolated final class ShapeLinkedShift {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \ShapeLinkedSample.shift)
    var samples: [ShapeLinkedSample] = []

    init(id: UUID = UUID(), startedAt: Date) {
        self.id = id
        self.startedAt = startedAt
    }
}

@Model
nonisolated final class ShapeLinkedSample {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var captureSessionID: UUID?
    var shift: ShapeLinkedShift?

    init(shift: ShapeLinkedShift, sample: LocationSample, captureSessionID: UUID?) {
        self.timestamp = sample.timestamp
        self.latitude = sample.latitude
        self.longitude = sample.longitude
        self.horizontalAccuracy = sample.horizontalAccuracy
        self.captureSessionID = captureSessionID
        self.shift = shift
    }
}

@Model
nonisolated final class ShapeOneSidedShift {
    @Attribute(.unique) var id: UUID
    var startedAt: Date

    init(id: UUID = UUID(), startedAt: Date) {
        self.id = id
        self.startedAt = startedAt
    }
}

@Model
nonisolated final class ShapeOneSidedSample {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var captureSessionID: UUID?
    var shift: ShapeOneSidedShift?

    init(shift: ShapeOneSidedShift, sample: LocationSample, captureSessionID: UUID?) {
        self.timestamp = sample.timestamp
        self.latitude = sample.latitude
        self.longitude = sample.longitude
        self.horizontalAccuracy = sample.horizontalAccuracy
        self.captureSessionID = captureSessionID
        self.shift = shift
    }
}

/// The same array inverse, with the delete rule changed, to show whether the
/// cascade is what costs rather than the array.
@Model
nonisolated final class ShapeNullifyShift {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    @Relationship(deleteRule: .nullify, inverse: \ShapeNullifySample.shift)
    var samples: [ShapeNullifySample] = []

    init(id: UUID = UUID(), startedAt: Date) {
        self.id = id
        self.startedAt = startedAt
    }
}

@Model
nonisolated final class ShapeNullifySample {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var captureSessionID: UUID?
    var shift: ShapeNullifyShift?

    init(shift: ShapeNullifyShift, sample: LocationSample, captureSessionID: UUID?) {
        self.timestamp = sample.timestamp
        self.latitude = sample.latitude
        self.longitude = sample.longitude
        self.horizontalAccuracy = sample.horizontalAccuracy
        self.captureSessionID = captureSessionID
        self.shift = shift
    }
}

@Model
nonisolated final class ShapeForeignKeySample {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var captureSessionID: UUID?
    var shiftID: UUID

    init(shiftID: UUID, sample: LocationSample, captureSessionID: UUID?) {
        self.timestamp = sample.timestamp
        self.latitude = sample.latitude
        self.longitude = sample.longitude
        self.horizontalAccuracy = sample.horizontalAccuracy
        self.captureSessionID = captureSessionID
        self.shiftID = shiftID
    }
}

@MainActor
enum RouteCaptureWriteShapes {
    enum Shape: String, CaseIterable {
        case linked
        case nullifyInverse
        case oneSided
        case foreignKey

        var label: String {
            switch self {
            case .linked: "Shape: to-one relationship with the to-many array inverse (the shipping shape)"
            case .nullifyInverse: "Shape: the same array inverse with a nullify delete rule"
            case .oneSided: "Shape: to-one relationship with no inverse array"
            case .foreignKey: "Shape: the shift's identifier as a plain attribute"
            }
        }
    }

    static func run(
        _ shape: Shape,
        positions: Int,
        start: Date,
        bucketSize: Int = 900,
        metresPerSecond: Double = 20
    ) async throws -> RouteCaptureWriteProbe.Run {
        let schema = Schema([
            ShapeLinkedShift.self,
            ShapeLinkedSample.self,
            ShapeNullifyShift.self,
            ShapeNullifySample.self,
            ShapeOneSidedShift.self,
            ShapeOneSidedSample.self,
            ShapeForeignKeySample.self
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-shape-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: url)
        )
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }

        RouteCaptureWriteProbe.openTable(label: shape.label, cadence: .perRunLoopTurn)

        let context = ModelContext(container)
        let linkedShift = ShapeLinkedShift(startedAt: start)
        let nullifyShift = ShapeNullifyShift(startedAt: start)
        let oneSidedShift = ShapeOneSidedShift(startedAt: start)
        context.insert(linkedShift)
        context.insert(nullifyShift)
        context.insert(oneSidedShift)
        try context.save()
        let foreignKey = UUID()

        let session = UUID()
        let startFootprint = RouteCaptureWriteProbe.footprint()
        let wallClockStart = DispatchTime.now().uptimeNanoseconds
        var buckets: [RouteCaptureWriteProbe.Bucket] = []
        var index = 0

        while index < positions {
            let upper = min(index + bucketSize, positions)
            var bucket = RouteCaptureWriteProbe.Bucket(range: index..<upper)

            for step in index..<upper {
                let sample = SyntheticRoute.sample(
                    at: start.addingTimeInterval(Double(step) + 1),
                    northMetres: Double(step + 1) * metresPerSecond
                )

                let elapsed = autoreleasepool {
                    RouteCaptureWriteProbe.time {
                        switch shape {
                        case .linked:
                            context.insert(
                                ShapeLinkedSample(shift: linkedShift, sample: sample, captureSessionID: session)
                            )
                        case .nullifyInverse:
                            context.insert(
                                ShapeNullifySample(shift: nullifyShift, sample: sample, captureSessionID: session)
                            )
                        case .oneSided:
                            context.insert(
                                ShapeOneSidedSample(shift: oneSidedShift, sample: sample, captureSessionID: session)
                            )
                        case .foreignKey:
                            context.insert(
                                ShapeForeignKeySample(shiftID: foreignKey, sample: sample, captureSessionID: session)
                            )
                        }
                        if (step + 1).isMultiple(of: 10) {
                            try? context.save()
                        }
                    }
                }
                await Task.yield()

                if (step + 1).isMultiple(of: 10) {
                    bucket.flushSamples.append(elapsed)
                } else {
                    bucket.insertSamples.append(elapsed)
                }
            }

            bucket.footprint = RouteCaptureWriteProbe.footprint()
            buckets.append(bucket)
            RouteCaptureWriteProbe.emit(bucket)
            index = upper
        }

        try context.save()
        let wallClock = Double(DispatchTime.now().uptimeNanoseconds - wallClockStart) / 1e9
        let reader = ModelContext(container)
        let stored: Int
        switch shape {
        case .linked: stored = try reader.fetchCount(FetchDescriptor<ShapeLinkedSample>())
        case .nullifyInverse: stored = try reader.fetchCount(FetchDescriptor<ShapeNullifySample>())
        case .oneSided: stored = try reader.fetchCount(FetchDescriptor<ShapeOneSidedSample>())
        case .foreignKey: stored = try reader.fetchCount(FetchDescriptor<ShapeForeignKeySample>())
        }

        let run = RouteCaptureWriteProbe.Run(
            label: shape.label,
            buckets: buckets,
            startFootprint: startFootprint,
            wallClockSeconds: wallClock,
            storedRowCount: stored
        )
        RouteCaptureWriteProbe.closeTable(run)
        return run
    }
}
