import Foundation

/// Turns the persisted models into the plain values an export is written from.
///
/// The one place a `Shift`, a `Delivery` and a `PickupPlace` are read for
/// export, and it holds **no rule of its own**: every figure it writes comes
/// from a calculation the app already defines — ``ShiftMetricsCalculator`` for
/// the rates, ``DeliveryActiveTimeCalculator`` for the unioned active time,
/// ``Delivery/pickupWait`` for the wait, ``Delivery/grossPerDeliveryHour`` for a
/// delivery's own rate. A second definition here would be a file that disagrees
/// with the screen it was exported from.
///
/// The route is passed in rather than measured here, for the reason
/// ``Shift/metrics(for:using:)`` takes it: measuring walks every position a
/// shift holds, and the caller is expected to do that once, off the main path.
nonisolated extension Shift {
    /// This shift as an export record.
    ///
    /// - Throws: ``ShiftExportError/shiftNotCompleted`` for a running shift.
    ///   The refusal lives here, at the boundary between the store and the file,
    ///   so that no scope, no screen and no future caller can put a shift that
    ///   is still growing into a document that claims to be history.
    func exportRecord(for recordedDistance: RouteDistance) throws -> ShiftExportRecord {
        guard let endedAt else { throw ShiftExportError.shiftNotCompleted }

        let activeTime = deliveryActiveTime()
        let metrics = metrics(for: recordedDistance)
        let summary = deliverySummary

        return ShiftExportRecord(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            elapsedSeconds: ExportDuration.seconds(completedDuration),
            currencyCode: Money.displayCurrencyCode,
            grossEarnings: ExportAmount.recorded(grossEarnings),
            route: ShiftRouteExport(recordedDistance),
            // The unioned figure, so two deliveries carried at once contribute
            // their shared minutes once. Absent — never zero — for a shift whose
            // deliveries describe nothing measurable.
            deliveryActiveSeconds: ExportDuration.seconds(
                activeTime.isAvailable ? activeTime.duration : nil
            ),
            nonDeliverySeconds: ExportDuration.seconds(
                activeTime.nonDeliveryDuration(inElapsed: completedDuration)
            ),
            grossPerElapsedHour: ExportAmount.recorded(metrics.grossPerElapsedHour.amount),
            grossPerDeliveryActiveHour: ExportAmount.recorded(metrics.grossPerDeliveryActiveHour.amount),
            grossPerRecordedMile: ExportAmount.recorded(metrics.grossPerRecordedMile.amount),
            deliveredCount: summary.completed,
            cancelledCount: summary.cancelled,
            deliveries: numberedDeliveries.map(DeliveryExportRecord.init)
        )
    }
}

nonisolated extension DeliveryExportRecord {
    /// One delivery as an export record, carrying the number the interface calls
    /// it by within its shift.
    ///
    /// The pickup place contributes its **display name only**. The normalised
    /// matching key never leaves the app: it is an internal rule that is allowed
    /// to improve, and publishing it would let a consumer group a driver's
    /// places by a policy this project is free to change.
    init(_ numbered: NumberedDelivery) {
        let delivery = numbered.delivery
        self.init(
            id: delivery.id,
            number: numbered.number,
            state: delivery.state,
            acceptedAt: delivery.acceptedAt,
            arrivedAtPickupAt: delivery.arrivedAtPickupAt,
            pickedUpAt: delivery.pickedUpAt,
            deliveredAt: delivery.deliveredAt,
            cancelledAt: delivery.cancelledAt,
            pickupPlaceName: delivery.pickupPlace?.displayName,
            pickupWaitSeconds: ExportDuration.seconds(delivery.pickupWait),
            acceptedToDeliveredSeconds: ExportDuration.seconds(delivery.completedDuration),
            grossEarnings: ExportAmount.recorded(delivery.grossEarnings),
            grossPerDeliveryHour: ExportAmount.recorded(delivery.grossPerDeliveryHour.amount)
        )
    }
}

/// `DeliveryState` in a file.
///
/// The raw values are already the vocabulary the app uses internally, so the
/// exported word is the domain's word rather than a second set of spellings
/// invented for the wire. Declared here rather than on the type itself because
/// being encodable is a fact about the export layer's use of it, not about the
/// lifecycle.
extension DeliveryState: Codable {}
