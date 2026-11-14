import Foundation
import OSLog
import SwiftData

/// Failures raised when a correction to a shift's start or end time cannot be
/// applied.
///
/// A thin layer over ``ShiftTimeCorrectionRefusal``: the domain owns which
/// corrections are truthful, and this adds only what a store can go wrong with.
nonisolated enum ShiftTimeCorrectionError: Error {
    /// The domain refused one of the proposed times.
    case invalidCorrection(ShiftTimeCorrectionRefusal)
    /// The shift is not, or is no longer, a row the store holds.
    case shiftNoLongerExists
    /// The local store could not be read or written.
    case storeUnavailable(underlying: any Error)
}

nonisolated extension ShiftTimeCorrectionError: Equatable {
    /// Two `storeUnavailable` failures compare equal regardless of the wrapped
    /// error: the underlying value is carried for diagnostics, not identity.
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.invalidCorrection(lhsRefusal), .invalidCorrection(rhsRefusal)): lhsRefusal == rhsRefusal
        case (.shiftNoLongerExists, .shiftNoLongerExists): true
        case (.storeUnavailable, .storeUnavailable): true
        default: false
        }
    }
}

nonisolated extension ShiftTimeCorrectionError: LocalizedError {
    /// Every sentence says why the time was refused and what would make it
    /// acceptable. End refusals use ``ShiftEndCorrectionError``'s sentences, so
    /// one rule is never explained two ways.
    var errorDescription: String? {
        switch self {
        case let .invalidCorrection(.start(refusal)):
            Self.sentence(for: refusal)
        case let .invalidCorrection(.end(refusal)):
            ShiftEndCorrectionError.invalidCorrection(refusal).errorDescription
        case .shiftNoLongerExists:
            "That shift is no longer in DashPilot, so nothing was changed."
        case .storeUnavailable:
            "DashPilot could not save to its local data store, so the shift was not changed."
        }
    }

    static func sentence(for refusal: ShiftStartCorrectionRefusal) -> String {
        switch refusal {
        case .inFuture:
            "That time has not happened yet. Choose a start time no later than now."
        case .notBeforeShiftEnd:
            "A shift has to start before it ended. Choose an earlier start, or correct the end time too."
        case .followsRecordedPause:
            """
            This shift records a pause that began before that time, and a pause has to be inside the \
            shift. Choose an earlier start, or correct or delete that pause first.
            """
        case .followsRecordedRouteSuspension:
            """
            This shift records a stretch parked that began before that time, and it explains a gap in \
            the shift's route. Choose an earlier start.
            """
        case let .followsRecordedDeliveryWork(event):
            """
            \(event.deliveryTitle) has \(event.eventTitle) recorded at \
            \(event.occurredAt.formatted(date: .omitted, time: .shortened)), before the proposed \
            start. Choose an earlier start, or open that delivery and correct its times.
            """
        case .followsRecordedOfferAcceptance:
            "An offer in this shift was accepted before that time. Choose an earlier start."
        case .overlapsAnotherShift:
            """
            Another shift was recorded at that time, and two shifts cannot overlap. Choose a start \
            after the previous shift ended.
            """
        }
    }
}

/// How many recorded positions a correction would delete, on each side.
nonisolated struct ShiftRouteEvidenceLoss: Equatable, Sendable {
    /// Positions fixed before the corrected start.
    let beforeStart: Int
    /// Positions fixed after the corrected end.
    let afterEnd: Int

    static let none = ShiftRouteEvidenceLoss(beforeStart: 0, afterEnd: 0)
    var total: Int { beforeStart + afterEnd }
}

/// Correcting when a shift started and, once it has finished, when it ended.
///
/// ## Why this exists
///
/// A shift's start is recorded by tapping Start, and a driver who taps it late
/// (or starts the shift from the car park twenty minutes after they began
/// waiting for offers) has a shift that is too short, so every hourly figure is
/// too high. Its end can be recorded late for the reasons
/// ``ShiftEndCorrectionService`` gives. This corrects either or both, for a
/// finished shift, and the start alone for a running one.
///
/// ## What a correction writes
///
/// **`Shift.startedAt`, `Shift.endedAt`, and the deletion of route samples that
/// the corrected times leave outside the shift.** Nothing else in the store is
/// written: no delivery, offer, pause, suspension, amount, tip, expense, fuel
/// snapshot or hourly target. A start moved later deletes the positions fixed
/// before it; an end moved earlier deletes the positions fixed after it; moving
/// either outward adds nothing, and the stretch gained counts as uncovered
/// route, exactly as for an end moved later.
///
/// **One save.** The rows are marked deleted, both times are written, and a
/// single save follows, so a refused save leaves the times and the route exactly
/// as they were. The caller must read through a fresh context after a refusal,
/// as every refused-save test here does.
///
/// ## Running shifts
///
/// Only the start, and no lifecycle transition: nothing is paused, resumed,
/// ended or restarted, Core Location is not touched, and no capture session is
/// minted or closed. The caller reconciles the Live Activity after a successful
/// save so its working-time anchor moves with the start.
///
/// Failure handling follows ``ShiftService``'s running-shift writes: a refused
/// save rolls the context back, which also discards route positions captured
/// but not yet flushed, exactly as a refused pause does.
@MainActor
struct ShiftTimeCorrectionService {
    private let context: ModelContext
    private let now: () -> Date

    /// How a change is handed to the store. Injectable so every claim about
    /// what a refused save leaves behind is testable.
    private let commit: (ModelContext) throws -> Void

    init(
        context: ModelContext,
        now: @escaping () -> Date = { .now },
        commit: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.context = context
        self.now = now
        self.commit = commit
    }

    // MARK: Correcting

    /// Rewrites when `shift` started and, when `end` is given, when it ended,
    /// and removes the route evidence the corrected times leave outside it.
    ///
    /// - Parameter end: the corrected end, or `nil` to keep the recorded one.
    ///   A running shift must pass `nil`.
    /// - Returns: what was applied.
    /// - Throws: ``ShiftTimeCorrectionError``.
    @discardableResult
    func correct(_ shift: Shift, start: Date, end: Date? = nil) throws -> ShiftTimeCorrection {
        try requireRecorded(shift)
        let correction = try proposed(on: shift, start: start, end: end)

        // Re-recording the same two times writes nothing, so it posts no save
        // and invalidates no report. Assigning an equal value would still mark
        // the row changed, so nothing is assigned at all.
        guard correction.changesAnything else { return correction }

        // Read before anything is marked deleted, so a refused read leaves the
        // context with nothing pending.
        let departing = try routeSamples(of: shift, before: correction.routeTrimStartBoundary)
            + routeSamples(of: shift, after: correction.routeTrimEndBoundary)
        for sample in departing { context.delete(sample) }

        do {
            try shift.apply(correction)
        } catch let refusal as ShiftTimeCorrectionRefusal {
            context.rollback()
            AppLog.shift.notice("Refused a shift time correction: \(refusal.logDescription, privacy: .public)")
            throw ShiftTimeCorrectionError.invalidCorrection(refusal)
        }

        try save()

        // Structural only: never the instants, the direction or the number of
        // positions, which are when and how far a driver worked.
        AppLog.shift.info(
            "A shift's times were corrected (start: \(correction.changesStart, privacy: .public), end: \(correction.changesEnd, privacy: .public), running: \(correction.isRunningShift, privacy: .public))"
        )
        if !departing.isEmpty {
            AppLog.routeCapture.info("Route recorded outside corrected shift times was removed")
        }
        return correction
    }

    // MARK: Asking without writing

    /// Why the proposed times would be refused, or `nil` if they would be
    /// accepted. The editor asks this as the pickers move, so the sentence on
    /// screen comes from the rule the write consults.
    ///
    /// A store that cannot be read reports the shift as not correctable, which
    /// withholds Save rather than offering one that is about to fail.
    func refusal(on shift: Shift, start: Date, end: Date? = nil) -> ShiftTimeCorrectionRefusal? {
        do {
            _ = try proposed(on: shift, start: start, end: end)
            return nil
        } catch ShiftTimeCorrectionError.invalidCorrection(let refusal) {
            return refusal
        } catch {
            return .end(.shiftNotCompleted)
        }
    }

    /// How many recorded positions the proposed times would delete. Counts
    /// rather than fetches, so asking does not load a route. Zero on a side
    /// that moves outward or not at all.
    func routeEvidenceLoss(on shift: Shift, start: Date, end: Date? = nil) -> ShiftRouteEvidenceLoss {
        let before = start > shift.startedAt ? count(of: shift, before: start) : 0
        var after = 0
        if let end, let recordedEnd = shift.endedAt, end < recordedEnd {
            after = shift.routeSampleCount(after: end)
        }
        return ShiftRouteEvidenceLoss(beforeStart: before, afterEnd: after)
    }

    /// The shifts either side of `proposedStart`, for the picker bounds and the
    /// overlap rule.
    func neighbours(of shift: Shift, proposedStart: Date) throws -> ShiftTimeNeighbours {
        let shiftID = shift.id
        let recordedStart = shift.startedAt
        do {
            var previous = FetchDescriptor<Shift>(
                predicate: #Predicate { $0.startedAt < proposedStart && $0.id != shiftID },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            previous.fetchLimit = 1
            let earlier = try context.fetch(previous).first
            return ShiftTimeNeighbours(
                previous: earlier.map { RecordedShiftSpan(startedAt: $0.startedAt, endedAt: $0.endedAt) },
                nextStartedAt: try firstStart(atOrAfter: proposedStart, excluding: shiftID),
                nextAfterRecordedStartStartedAt: try firstStart(atOrAfter: recordedStart, excluding: shiftID)
            )
        } catch {
            AppLog.shift.error("Failed to read the shifts around the one being corrected: \(error)")
            throw ShiftTimeCorrectionError.storeUnavailable(underlying: error)
        }
    }

    // MARK: Reading

    private func proposed(on shift: Shift, start: Date, end: Date?) throws -> ShiftTimeCorrection {
        let neighbours = try neighbours(of: shift, proposedStart: start)
        do {
            return try shift.timeCorrection(start: start, end: end, now: now(), neighbours: neighbours)
        } catch let refusal as ShiftTimeCorrectionRefusal {
            AppLog.shift.notice("Refused a shift time correction: \(refusal.logDescription, privacy: .public)")
            throw ShiftTimeCorrectionError.invalidCorrection(refusal)
        }
    }

    private func firstStart(atOrAfter instant: Date, excluding shiftID: UUID) throws -> Date? {
        var descriptor = FetchDescriptor<Shift>(
            predicate: #Predicate { $0.startedAt >= instant && $0.id != shiftID },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.startedAt
    }

    private func count(of shift: Shift, before boundary: Date) -> Int {
        let shiftKey = shift.persistentModelID
        do {
            return try context.fetchCount(
                FetchDescriptor<RouteSample>(
                    predicate: #Predicate { $0.shift?.persistentModelID == shiftKey && $0.timestamp < boundary }
                )
            )
        } catch {
            AppLog.routeCapture.error("Could not count the head of a shift's stored route: \(error)")
            return 0
        }
    }

    /// Positions fixed strictly before `boundary`, or none without one.
    ///
    /// Fetched through the context, and a failed read refuses the correction:
    /// these rows are about to be deleted, and silently finding none would
    /// leave a shift claiming a start its own route reaches past.
    private func routeSamples(of shift: Shift, before boundary: Date?) throws -> [RouteSample] {
        guard let boundary else { return [] }
        let shiftKey = shift.persistentModelID
        return try fetchRoute(
            FetchDescriptor<RouteSample>(
                predicate: #Predicate { $0.shift?.persistentModelID == shiftKey && $0.timestamp < boundary }
            )
        )
    }

    /// Positions fixed strictly after `boundary`, or none without one.
    private func routeSamples(of shift: Shift, after boundary: Date?) throws -> [RouteSample] {
        guard let boundary else { return [] }
        let shiftKey = shift.persistentModelID
        return try fetchRoute(
            FetchDescriptor<RouteSample>(
                predicate: #Predicate { $0.shift?.persistentModelID == shiftKey && $0.timestamp > boundary }
            )
        )
    }

    private func fetchRoute(_ descriptor: FetchDescriptor<RouteSample>) throws -> [RouteSample] {
        do {
            return try context.fetch(descriptor)
        } catch {
            AppLog.routeCapture.error("Failed to read the route a shift time correction would remove: \(error)")
            throw ShiftTimeCorrectionError.storeUnavailable(underlying: error)
        }
    }

    // MARK: Writing

    private func save() throws {
        do {
            try commit(context)
        } catch {
            // Times and route together: the interface must not show a shift the
            // store does not hold.
            context.rollback()
            AppLog.shift.error("Failed to correct a shift's times: \(error)")
            throw ShiftTimeCorrectionError.storeUnavailable(underlying: error)
        }
    }

    private func requireRecorded(_ shift: Shift) throws {
        guard shift.modelContext != nil, !shift.isDeleted else {
            AppLog.shift.notice("Refused a shift time correction: the shift is not in the store")
            throw ShiftTimeCorrectionError.shiftNoLongerExists
        }
    }
}
