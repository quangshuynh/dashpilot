import Foundation

/// Turns the persisted models into the plain values an export is written from.
///
/// The one place a `Shift`, a `Delivery` and a `PickupPlace` are read for
/// export, and it holds **no rule of its own**: every figure it writes comes
/// from a calculation the app already defines — ``ShiftMetricsCalculator`` for
/// the rates, ``DeliveryActiveTimeCalculator`` for the unioned active time,
/// ``Delivery/pickupWait`` for the wait, ``Delivery/effectiveEarningsPerDeliveryHour`` for a
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
        let pausedTime = completedPausedTime ?? .none
        let metrics = metrics(for: recordedDistance)
        let summary = deliverySummary

        return ShiftExportRecord(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            elapsedSeconds: ExportDuration.seconds(completedDuration),
            pausedSeconds: ExportDuration.seconds(pausedTime.duration),
            workingSeconds: ExportDuration.seconds(completedWorkingDuration),
            pauseCount: pausedTime.intervalCount,
            currencyCode: Money.displayCurrencyCode,
            grossEarnings: ExportAmount.recorded(grossEarnings),
            route: ShiftRouteExport(recordedDistance),
            // The assumptions as recorded, never the estimate derived from
            // them: the file states what the driver entered, and a reader
            // reproduces the arithmetic from the recorded mileage above.
            fuelMilesPerGallon: ExportDecimal.recorded(fuelAssumptions.milesPerGallon),
            fuelGasPricePerGallon: ExportAmount.recorded(fuelAssumptions.gasPricePerGallon),
            // The unioned figure, so two deliveries carried at once contribute
            // their shared minutes once. Absent — never zero — for a shift whose
            // deliveries describe nothing measurable.
            deliveryActiveSeconds: ExportDuration.seconds(
                activeTime.isAvailable ? activeTime.duration : nil
            ),
            // Within working time rather than elapsed, so a pause does not
            // reappear as time the driver spent not delivering.
            nonDeliverySeconds: ExportDuration.seconds(
                activeTime.nonDeliveryDuration(inElapsed: completedWorkingDuration)
            ),
            grossPerWorkingHour: ExportAmount.recorded(metrics.grossPerWorkingHour.amount),
            grossPerDeliveryActiveHour: ExportAmount.recorded(metrics.grossPerDeliveryActiveHour.amount),
            grossPerRecordedMile: ExportAmount.recorded(metrics.grossPerRecordedMile.amount),
            deliveredCount: summary.completed,
            cancelledCount: summary.cancelled,
            // The offer numbers are worked out once for the shift and handed to
            // each record, rather than each record asking the shift again: the
            // numbering is over the whole shift, so a record cannot derive it
            // from the delivery alone.
            deliveries: numberedDeliveries.map { numbered in
                DeliveryExportRecord(numbered, offerNumber: offerNumbersByDelivery[numbered.id])
            }
        )
    }

    /// Which offer of this shift each delivery arrived in, by delivery.
    ///
    /// A delivery that records no offer is simply absent, which becomes an
    /// explicit `null` in the file rather than an invented group.
    private var offerNumbersByDelivery: [UUID: Int] {
        var numbers: [UUID: Int] = [:]
        for offer in numberedOffers {
            for delivery in offer.deliveries {
                numbers[delivery.id] = offer.number
            }
        }
        return numbers
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
    /// - Parameter offerNumber: which offer of the delivery's shift it arrived
    ///   in, or `nil` for a delivery that records none. Supplied by the caller
    ///   because the numbering runs over the shift rather than over the
    ///   delivery.
    init(_ numbered: NumberedDelivery, offerNumber: Int?) {
        let delivery = numbered.delivery
        let effective = delivery.effectiveEarnings
        self.init(
            id: delivery.id,
            number: numbered.number,
            // The grouping key, and nothing else about the offer: it holds no
            // money and no time, so there is nothing else of it to export.
            offerNumber: offerNumber,
            state: delivery.state,
            acceptedAt: delivery.acceptedAt,
            arrivedAtPickupAt: delivery.arrivedAtPickupAt,
            pickedUpAt: delivery.pickedUpAt,
            deliveredAt: delivery.deliveredAt,
            cancelledAt: delivery.cancelledAt,
            pickupPlaceName: delivery.pickupPlace?.displayName,
            pickupWaitSeconds: ExportDuration.seconds(delivery.pickupWait),
            acceptedToDeliveredSeconds: ExportDuration.seconds(delivery.completedDuration),
            // The platform-recorded amount alone, unchanged and meaning exactly
            // what it always has. Tips are beside it rather than inside it.
            grossEarnings: ExportAmount.recorded(delivery.grossEarnings),
            // Written from its own column, and read by nothing else in this
            // file. There is no expected-per-hour figure, no expected subtotal
            // and no expected summary anywhere in the format, deliberately: a
            // rate over an expectation would be a claim about what the driver
            // would have earned.
            expectedEarnings: ExportAmount.recorded(delivery.expectedEarnings),
            // The individual facts, in the order the app numbers them. The two
            // derived figures below come from the same
            // `EffectiveDeliveryEarnings` the screen reads, so a file and the
            // history it was exported from cannot disagree.
            additionalTips: delivery.additionalTipsInOrder.map(DeliveryTipExportRecord.init),
            additionalTipsTotal: ExportAmount.recorded(effective.additionalTipsTotal),
            effectiveEarnings: ExportAmount.recorded(effective.amount),
            effectiveEarningsPerDeliveryHour: ExportAmount.recorded(
                delivery.effectiveEarningsPerDeliveryHour.amount
            )
        )
    }
}

nonisolated extension DeliveryTipExportRecord {
    /// One recorded tip as an export record.
    ///
    /// The method is carried as the domain's own word, or as an absence for a
    /// stored value this build cannot name. See ``DeliveryTip/method``.
    init(_ tip: DeliveryTip) {
        self.init(id: tip.id, amount: ExportAmount(tip.amount), method: tip.method, recordedAt: tip.recordedAt)
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
