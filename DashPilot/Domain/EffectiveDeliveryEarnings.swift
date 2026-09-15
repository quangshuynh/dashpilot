import Foundation

/// What one delivery actually paid the driver, assembled from the two kinds of
/// recorded fact that make it up.
///
/// ## The two facts, and why they stay apart in the store
///
/// **Platform pay** is ``Delivery/grossEarnings``: the finalized amount the
/// driver recorded the platform as having paid for this delivery, whatever was
/// already inside it. If the platform folded a tip into that figure, the tip is
/// part of it and is not recorded again anywhere.
///
/// **Additional tips** are money that reached the driver *outside* that figure:
/// cash at the door, or a tip the platform added after the amount the driver
/// recorded. Each one is its own ``DeliveryTip`` row with its own amount, method
/// and timestamp, and they are never collapsed into a single mutable "tips"
/// column. Two tips on one delivery are two things that happened, and a driver
/// correcting one must not have to re-derive the other.
///
/// ## The arithmetic, and the one case it refuses
///
/// ```
/// effective = platform pay + sum(additional tips)
/// ```
///
/// with one rule that is the whole of the honesty here: **when platform pay is
/// missing there is no effective total**, and ``amount`` is `nil`. A delivery
/// carrying a `$5.00` cash tip and no recorded platform pay did not earn
/// `$5.00`; it earned `$5.00` plus an amount nobody has written down. Reading
/// the absent half as zero would put a number into a driver's earnings history
/// on the app's authority, and every aggregate downstream would then report a
/// delivery as fully recorded when half of it is not. So such a delivery
/// contributes nothing to a subtotal and counts as **not covered**, exactly as a
/// delivery with no amount at all always has. See ``MetricCoverage``.
///
/// A delivery with no tips is the ordinary case and is unchanged by all of this:
/// its effective earnings are its platform pay, to the cent.
///
/// ## What it is not
///
/// Not net, not take-home, not profit and not a payout anything confirmed.
/// Nothing for fuel, wear, insurance or tax is subtracted anywhere in DashPilot,
/// and no figure here was read from a delivery platform.
///
/// It is also **not** an expectation. ``Delivery/expectedEarnings`` is a fourth
/// independent fact and enters none of this arithmetic: nothing here reads it,
/// and recording a tip neither confirms nor consumes it.
nonisolated struct EffectiveDeliveryEarnings: Equatable, Sendable {
    /// The platform-recorded pay for the delivery, or `nil` when the driver has
    /// not recorded it. Never read as zero.
    let platformPay: Money?

    /// Every additional tip recorded against the delivery, one entry each, in
    /// the order they were recorded.
    ///
    /// Amounts rather than rows, because this type is the arithmetic and the
    /// arithmetic needs nothing else. What each tip was and when it arrived
    /// belongs to the rows themselves.
    let additionalTips: [Money]

    init(platformPay: Money?, additionalTips: [Money] = []) {
        self.platformPay = platformPay
        self.additionalTips = additionalTips
    }

    /// How many additional tips were recorded.
    var additionalTipCount: Int { additionalTips.count }

    /// Whether any additional tip was recorded at all.
    ///
    /// The question every surface asks before saying anything about tips: a
    /// delivery with none is the ordinary case, and a row reading "Additional
    /// tips $0.00" on every delivery would be noise that also states something
    /// nobody recorded.
    var hasAdditionalTips: Bool { !additionalTips.isEmpty }

    /// The additional tips added up, or `nil` when none was recorded.
    ///
    /// Absent rather than zero, by the rule that holds everywhere else here: no
    /// tip recorded is not a tip of nothing. ``amount`` treats the absence as
    /// contributing nothing, which is arithmetic rather than a claim.
    var additionalTipsTotal: Money? {
        guard hasAdditionalTips else { return nil }
        return additionalTips.reduce(Money.zero, +)
    }

    /// What the delivery paid in total, or `nil` when the platform pay is
    /// missing.
    ///
    /// See the type's own documentation for why a missing half is refused
    /// rather than filled in.
    var amount: Money? {
        guard let platformPay else { return nil }
        return platformPay + (additionalTipsTotal ?? .zero)
    }

    /// Whether the delivery has an effective total at all, which is the same
    /// question as whether its platform pay was recorded.
    var isRecorded: Bool { amount != nil }

    /// Whether the delivery records money the platform pay alone does not
    /// describe.
    ///
    /// Asked by the surfaces that decide whether to name the platform figure as
    /// one half of something rather than as the whole of what was paid.
    var hasMoneyBeyondPlatformPay: Bool { hasAdditionalTips }
}

extension Delivery {
    /// This delivery's additional tips, oldest first.
    ///
    /// The order is the order they were recorded in, with identity breaking a
    /// tie, for the reason ``Delivery/acceptedBefore(_:_:)`` breaks one: the
    /// list is numbered on screen, and two tips recorded in the same instant
    /// must not swap places between two reads.
    var additionalTipsInOrder: [DeliveryTip] { additionalTips.sorted(by: DeliveryTip.recordedBefore) }

    /// What this delivery actually paid, platform pay and additional tips
    /// together.
    ///
    /// Derived on demand and never stored, like every other total in DashPilot:
    /// a stored figure would be a second answer to a question the amount and the
    /// tip rows already answer, and it would keep the old answer after either
    /// changed.
    var effectiveEarnings: EffectiveDeliveryEarnings {
        EffectiveDeliveryEarnings(
            platformPay: grossEarnings,
            additionalTips: additionalTipsInOrder.map(\.amount)
        )
    }

    /// Whether this delivery records any money at all.
    ///
    /// Platform pay **or** a tip. Asked by the corrections that promise not to
    /// touch what the driver recorded: a delivery holding only tips has money to
    /// preserve just as surely as one holding only a platform amount.
    var hasRecordedMoney: Bool { grossEarnings != nil || !additionalTips.isEmpty }
}
