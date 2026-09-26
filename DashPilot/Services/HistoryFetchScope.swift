import Foundation
import SwiftData

/// The store reads History is drawn from.
///
/// ## Why this exists
///
/// History's root screen shows one Monday-to-Sunday week. It used to fetch every
/// completed shift the store held and discard all but that week in
/// ``HistoryWeek/partition(_:by:asOf:calendar:)``, once per use in a body that
/// used it seven times, and SwiftData re-ran the fetch whenever the store saved,
/// which while a shift runs is every route batch. Measured on an on-disk store
/// holding five years of work (3,132 shifts), that was about 80 ms of fetch and
/// 140 ms of partitioning per refresh on the main actor; the week alone is under
/// a millisecond. `HistoryFetchScopeMeasurementTests` reproduces both.
///
/// ## It adds no boundary
///
/// Every predicate is built from a ``HistoryWeek``'s own `start` and `end`, which
/// are ``ReportingPeriod``'s, so the half-open rule, the driver's time zone and
/// the 167- and 169-hour weeks are the existing implementation. Membership is
/// `startedAt`, the instant every period in the app already places a shift by,
/// and `endedAt != nil` is the app's one definition of completed, so a running
/// shift never reaches History from here.
///
/// ``currentWeek(_:)`` and ``otherWeeks(_:)`` are complements over completed
/// shifts, written from the same two bounds, so every completed shift is in
/// exactly one of them. A shift dated **after** the week (only a device clock
/// moved backwards produces one) is in the second, which is where History has
/// always listed it.
///
/// ## It is not what export reads
///
/// `Export All History` means the whole store, and ``ShiftExportService`` fetches
/// it with its own descriptor. Nothing here is handed to an export, so narrowing
/// what a screen reads cannot narrow what a file contains.
nonisolated enum HistoryFetchScope {
    /// The completed shifts that started inside `week`, newest first: the order
    /// History has always listed them in.
    ///
    /// `nil` is the permissive fallback for a calendar that cannot describe the
    /// week containing now, which no ordinary calendar reaches: every completed
    /// shift, so a driver can still find their work.
    static func currentWeek(_ week: HistoryWeek?) -> FetchDescriptor<Shift> {
        guard let week else { return allCompleted }
        let start = week.start
        let end = week.end
        return FetchDescriptor<Shift>(
            predicate: #Predicate {
                $0.endedAt != nil && $0.startedAt >= start && $0.startedAt < end
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
    }

    /// Every completed shift that did **not** start inside `week`, newest first.
    ///
    /// With no week there is nothing "other": ``currentWeek(_:)`` already holds
    /// everything.
    static func otherWeeks(_ week: HistoryWeek?) -> FetchDescriptor<Shift> {
        guard let week else {
            return FetchDescriptor<Shift>(predicate: #Predicate { _ in false })
        }
        let start = week.start
        let end = week.end
        return FetchDescriptor<Shift>(
            predicate: #Predicate {
                $0.endedAt != nil && ($0.startedAt < start || $0.startedAt >= end)
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
    }

    /// Every completed shift, newest first.
    static var allCompleted: FetchDescriptor<Shift> {
        FetchDescriptor<Shift>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
    }

    /// How many completed shifts sit outside `week`. A count: it realises no row.
    static func otherWeekShiftCount(outside week: HistoryWeek?, in context: ModelContext) throws -> Int {
        var descriptor = otherWeeks(week)
        descriptor.sortBy = []
        return try context.fetchCount(descriptor)
    }

    /// How much sits outside `week`: how many shifts, and how many distinct
    /// Monday-to-Sunday weeks they fall in.
    ///
    /// The week count needs every such shift's start, which at five years is
    /// tens of milliseconds, so this reads through its **own** context and is
    /// meant to be called off the main actor. It reads one attribute and writes
    /// nothing.
    static func otherWeeksSummary(
        outside week: HistoryWeek?,
        in container: ModelContainer,
        calendar: Calendar
    ) throws -> HistoryOtherWeeksSummary {
        let context = ModelContext(container)
        var descriptor = otherWeeks(week)
        descriptor.sortBy = []
        descriptor.propertiesToFetch = [\.startedAt]
        let starts = try context.fetch(descriptor).map(\.startedAt)
        var weeks = Set<Date>()
        for start in starts {
            // A start the calendar cannot place still counts as a shift; it is
            // not a week of its own.
            if let week = HistoryWeek(containing: start, calendar: calendar) {
                weeks.insert(week.start)
            }
        }
        return HistoryOtherWeeksSummary(weekCount: weeks.count, shiftCount: starts.count)
    }
}

nonisolated extension HistoryFetchScope {
    /// One week's summary, derived through a context of its own so that it can
    /// run off the main actor.
    ///
    /// Measuring a week means walking every route in it, which for twelve
    /// ordinary shifts is over half a second, and Older Weeks asks for it as
    /// each week scrolls into view. The derivation is exactly
    /// ``HistoryWeekSummary``'s, over the same shifts' saved facts; only the
    /// thread it runs on moves. Identifiers rather than models cross the actor
    /// boundary, and a shift that has since been deleted is simply not there.
    ///
    /// **Fetched by a predicate on the stored `id`, never through
    /// `ModelContext.model(for:)`.** That call hands back a model for an
    /// identifier whose row is gone, and reading it traps; a shift deleted
    /// while its week was being worked out would have taken the app down.
    static func weekSummary(
        of week: HistoryWeek,
        shiftIDs: [UUID],
        in container: ModelContainer
    ) -> HistoryWeekSummary {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Shift>(predicate: #Predicate { shiftIDs.contains($0.id) })
        let shifts = (try? context.fetch(descriptor)) ?? []
        return HistoryWeekSummary(
            week: week,
            records: shifts.map { $0.periodRecord(for: $0.recordedDistance()) }
        )
    }
}

/// How much History holds outside the week on screen.
nonisolated struct HistoryOtherWeeksSummary: Equatable, Sendable {
    let weekCount: Int
    let shiftCount: Int

    static let none = HistoryOtherWeeksSummary(weekCount: 0, shiftCount: 0)

    var isEmpty: Bool { shiftCount == 0 }

    /// `2 weeks · 3 shifts`, the words the root screen has always used.
    ///
    /// Neither word says *older*, because a shift a moved clock dated after this
    /// week is counted here too.
    var statement: String {
        let weekText = weekCount == 1 ? "1 week" : "\(weekCount) weeks"
        let shiftText = shiftCount == 1 ? "1 shift" : "\(shiftCount) shifts"
        return "\(weekText) · \(shiftText)"
    }
}

/// A cheap fingerprint of the recorded facts one week's summary is worked out
/// from, so the summary is worked out again exactly when one of them changes.
///
/// ## Why this exists
///
/// A week's summary is derived off the main actor and was keyed on the week
/// alone. Edits made from a shift's detail screen happened to refresh it
/// anyway, because returning makes the section reappear and SwiftUI restarts
/// its task; a change while the section stayed on screen would not have. So
/// the key now names the facts the figures are worked out from, and the
/// summary follows them rather than the navigation.
///
/// ## Cheap, and only this week's
///
/// It reads the stored columns and the small relationships a shift's summary
/// record is built from, and never a route: recorded mileage only moves when
/// the end moves (an earlier end trims the route in the same save), so the end
/// stands in for it. Built from **this week's** shifts only, so an edit to a
/// shift in another week leaves it, and that week's summary, untouched.
///
/// A shift deleted while its section is on screen is skipped rather than read:
/// a deleted model's attributes are not something to touch.
nonisolated struct HistoryWeekRevision: Hashable, Sendable {
    let value: Int

    init(_ shifts: [Shift]) {
        var hasher = Hasher()
        for shift in shifts where !shift.isDeleted && shift.modelContext != nil {
            hasher.combine(shift.id)
            hasher.combine(shift.startedAt)
            hasher.combine(shift.endedAt)
            hasher.combine(shift.grossEarnings?.amount)
            let fuel = shift.fuelAssumptions
            hasher.combine(fuel.milesPerGallon)
            hasher.combine(fuel.gasPricePerGallon?.amount)
            for pause in shift.pausesInOrder {
                hasher.combine(pause.startedAt)
                hasher.combine(pause.endedAt)
            }
            for delivery in shift.deliveriesInOrder where !delivery.isDeleted {
                hasher.combine(delivery.id)
                let record = DeliveryLifecycleRecord(delivery)
                for event in record.recordedEvents {
                    hasher.combine(event.event)
                    hasher.combine(event.occurredAt)
                }
                hasher.combine(delivery.grossEarnings?.amount)
            }
        }
        value = hasher.finalize()
    }
}
