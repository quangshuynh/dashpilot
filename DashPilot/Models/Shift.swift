import Foundation
import SwiftData

/// Errors raised when a shift transition would violate the model's invariants.
nonisolated enum ShiftError: Error, Equatable {
    /// The shift already has an end timestamp.
    case alreadyEnded
    /// The proposed end timestamp is earlier than the start timestamp.
    case endPrecedesStart
}

/// A single period of delivery work.
///
/// A shift is the unit every later measurement hangs from: route samples,
/// mileage, deliveries and earnings are all scoped to one shift. It is
/// deliberately narrow at this stage — recorded distance and earnings arrive
/// with the features that can actually produce them.
///
/// Route samples are the first thing to attach to it. They are collected only
/// while the shift is running; `endedAt` being set is what stops that, and
/// nothing appends to a shift that has ended.
@Model
nonisolated final class Shift {
    /// Stable identifier, used for cross-store references and future export.
    @Attribute(.unique) private(set) var id: UUID

    private(set) var startedAt: Date

    /// `nil` while the shift is still running.
    private(set) var endedAt: Date?

    /// Positions retained while this shift was running, in no guaranteed order.
    ///
    /// The delete rule is `.cascade`: a shift's route describes that shift and
    /// nothing else, so deleting the shift must take the samples with it rather
    /// than leaving a table of coordinates belonging to a shift that no longer
    /// exists. That matters more than usual here — the orphans would be exactly
    /// the sensitive data the app promises to keep accountable to a shift.
    @Relationship(deleteRule: .cascade, inverse: \RouteSample.shift)
    private(set) var routeSamples: [RouteSample] = []

    init(id: UUID = UUID(), startedAt: Date) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = nil
    }

    var isActive: Bool { endedAt == nil }

    /// Duration of a finished shift, or `nil` while it is still running.
    var completedDuration: TimeInterval? {
        endedAt.map { clampedInterval(from: startedAt, to: $0) }
    }

    /// Time covered by the shift so far, measured against `referenceDate` while running.
    func elapsed(asOf referenceDate: Date) -> TimeInterval {
        clampedInterval(from: startedAt, to: endedAt ?? referenceDate)
    }

    /// Marks the shift finished.
    ///
    /// - Throws: ``ShiftError/alreadyEnded`` if the shift is not running, or
    ///   ``ShiftError/endPrecedesStart`` if `date` is before the start.
    func end(at date: Date) throws {
        guard endedAt == nil else { throw ShiftError.alreadyEnded }
        guard date >= startedAt else { throw ShiftError.endPrecedesStart }
        endedAt = date
    }

    /// The device clock can move backwards (manual changes, NTP corrections),
    /// so a negative interval is treated as zero rather than surfaced as a
    /// negative duration in metrics.
    private func clampedInterval(from start: Date, to end: Date) -> TimeInterval {
        max(0, end.timeIntervalSince(start))
    }
}
