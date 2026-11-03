import Foundation

/// The few figures worth reading the moment a shift has ended.
///
/// **Nothing here is calculated afresh.** Every figure is one the shift's own
/// detail screen already shows, read through the same calculators:
/// ``ShiftMetricsCalculator`` for working time and gross per working hour,
/// ``RouteQuality`` for recorded mileage and its qualifications, and
/// ``FuelEstimateCalculator`` for the estimate. The recap only chooses five of
/// them and words their absence.
///
/// Recorded expenses are deliberately absent: they are dated independently of
/// shifts, and putting them beside an estimated fuel cost would invite adding
/// the two together. Delivery earnings are absent too: shift gross and delivery
/// gross are independent facts, and neither is inferred from the other here.
nonisolated struct PostShiftRecap: Equatable, Sendable {
    let shiftID: UUID
    let grossEarnings: Money?
    let workingDuration: TimeInterval?
    let grossPerWorkingHour: ShiftRate
    let route: RouteQuality
    let fuelEstimate: FuelEstimate

    /// `nil` for a shift that has not ended: a recap describes completed work,
    /// and a running shift has no working time or rate yet.
    init?(shift: Shift, recordedDistance: RouteDistance) {
        guard shift.endedAt != nil else { return nil }
        let metrics = shift.metrics(for: recordedDistance)
        shiftID = shift.id
        grossEarnings = metrics.grossEarnings
        workingDuration = metrics.workingDuration
        grossPerWorkingHour = metrics.grossPerWorkingHour
        route = RouteQuality(recordedDistance, suspendedTime: shift.completedSuspendedTime ?? .none)
        fuelEstimate = shift.fuelEstimate(for: recordedDistance)
    }

    // MARK: Wording

    /// A missing amount is "Not recorded", never `$0.00`. A recorded zero is the
    /// zero it is.
    func grossStatement(locale: Locale = .autoupdatingCurrent) -> String {
        grossEarnings?.formatted(locale: locale) ?? "Not recorded"
    }

    var workingTimeStatement: String {
        workingDuration.map(DurationText.short) ?? "Not available"
    }

    var spokenWorkingTime: String {
        workingDuration.map(DurationText.spoken) ?? "not available"
    }

    func rateStatement(locale: Locale = .autoupdatingCurrent) -> String {
        grossPerWorkingHour.amount.map { "\($0.formatted(locale: locale))/hr" } ?? "Not available"
    }

    /// Why the rate is missing, in the detail screen's own words.
    var rateDetail: String? {
        grossPerWorkingHour.unavailability?.explanation
    }

    func mileageStatement(locale: Locale = .autoupdatingCurrent) -> String {
        route.isMeasured ? route.distance.formattedMiles(locale: locale) : "Not recorded"
    }

    /// The qualification a recorded figure never appears without.
    var mileageDetail: String {
        guard route.isMeasured else { return route.mileageStatement() }
        return route.partialMarker.map { "Recorded mileage, \($0)" } ?? "Recorded mileage"
    }

    func spokenMileage(locale: Locale = .autoupdatingCurrent) -> String {
        route.spokenMileageStatement(locale: locale)
    }

    func fuelStatement(locale: Locale = .autoupdatingCurrent) -> String {
        fuelEstimate.cost?.formatted(locale: locale) ?? "Not available"
    }

    /// Always says "estimated", and says why where there is no estimate.
    var fuelDetail: String {
        switch fuelEstimate {
        case let .available(consumption):
            consumption.isRoutePartial
                ? "Estimated from a partial route, so likely low. Not a recorded expense."
                : "Estimated from recorded mileage. Not a recorded expense."
        case let .unavailable(reason):
            reason.explanation
        }
    }
}
