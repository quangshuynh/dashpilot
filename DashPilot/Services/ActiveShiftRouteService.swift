import Foundation
import OSLog
import SwiftData

/// Reads the part of a running shift's route that a live measurement has not
/// seen yet.
///
/// The only type in the app that queries route rows for a shift **in progress**.
/// It owns no rule about distance, continuity or gaps — those are
/// ``RouteMileageAccumulator``'s, through ``ActiveRouteMeasurement`` — and it
/// owns no rule about when to ask, which is the caller's. All it does is turn a
/// plan into the smallest query that satisfies it.
///
/// ## It writes nothing
///
/// Unlike the other services here it is read-only, and deliberately so: a live
/// figure is a reading of stored rows, and the moment it were written down it
/// would become a second answer to a question the store can already answer. See
/// ``ActiveRouteMeasurement`` for the correctness model, and `AGENTS.md` on
/// derived data.
///
/// ## The query
///
/// Two queries at most per reading, and usually one:
///
/// 1. A **count** of the shift's route rows. It is an aggregate rather than a
///    fetch, so it costs the same whether the shift holds ten positions or
///    thirty thousand, and it is what catches rows that have disappeared.
/// 2. A **fetch of the rows after the last one already measured**, and only when
///    the count says there are some. On a shift being recorded at one position a
///    second, read every few seconds, that is a handful of rows.
///
/// Neither loads `shift.routeSamples`, which would fault in the entire route to
/// look at the end of it.
@MainActor
struct ActiveShiftRouteService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// The shift's live route measurement, extending `previous` when it can.
    ///
    /// A `previous` measuring a different shift, or none at all, starts a new
    /// measurement over the whole stored route. So does one whose rows the store
    /// no longer holds.
    ///
    /// - Throws: whatever the store raised. The caller keeps the figure it had
    ///   rather than showing a wrong one: a route that could not be read is not
    ///   a route of zero miles.
    func measurement(extending previous: ActiveRouteMeasurement?, of shift: Shift) throws -> ActiveRouteMeasurement {
        var measurement = previous?.shiftID == shift.id
            ? previous ?? ActiveRouteMeasurement(shiftID: shift.id)
            : ActiveRouteMeasurement(shiftID: shift.id)

        let storedRowCount = try rowCount(of: shift)

        switch measurement.plan(againstStoredRowCount: storedRowCount) {
        case .upToDate:
            return measurement
        case .remeasure:
            AppLog.routeCapture.info("Live route measurement restarted; stored positions no longer match it")
            measurement = ActiveRouteMeasurement(shiftID: shift.id)
            let read = try points(of: shift, after: nil)
            measurement.extend(with: read, rowsRead: read.count, storedRowCount: storedRowCount)
        case .extend(let after):
            let read = try points(of: shift, after: after)
            measurement.extend(with: read, rowsRead: read.count, storedRowCount: storedRowCount)
        }

        return measurement
    }

    /// How many route rows the store holds for this shift.
    private func rowCount(of shift: Shift) throws -> Int {
        let shiftID = shift.id
        return try context.fetchCount(
            FetchDescriptor<RouteSample>(predicate: #Predicate { $0.shift?.id == shiftID })
        )
    }

    /// The shift's retained positions recorded after `instant`, oldest first.
    ///
    /// Sorted by timestamp and then by coordinate, which is the order the walk
    /// itself imposes: timestamp alone is not a total order, so two positions
    /// fixed at the same instant would otherwise arrive in whatever order the
    /// store happened to return them.
    private func points(of shift: Shift, after instant: Date?) throws -> [RoutePoint] {
        let shiftID = shift.id
        var predicate = #Predicate<RouteSample> { $0.shift?.id == shiftID }
        if let instant {
            predicate = #Predicate<RouteSample> { $0.shift?.id == shiftID && $0.timestamp > instant }
        }

        let descriptor = FetchDescriptor<RouteSample>(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\.timestamp),
                SortDescriptor(\.latitude),
                SortDescriptor(\.longitude)
            ]
        )
        return try context.fetch(descriptor).map(\.routePoint)
    }
}
