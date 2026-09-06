import Foundation

/// What a driver says a recorded expense was for.
///
/// ## Five, and deliberately no more
///
/// This is a driver's own note about where the money went, not a chart of
/// accounts. Every category below is one a delivery driver can assign without
/// thinking about it at a fuel pump or a parking meter, and none of them is a
/// tax classification: DashPilot does not know which costs are deductible, in
/// which jurisdiction, under which rules, and inventing categories that look
/// like a tax form would imply that it does.
///
/// The set is closed on purpose. Custom categories would need naming,
/// normalisation, renaming and merging — the whole apparatus pickup places
/// needed — and would turn a four-tap record into a small filing exercise.
/// ``other`` is what carries everything the four named ones do not, and it makes
/// no claim about what the money was spent on.
///
/// ## What none of these mean
///
/// A category is a label on an amount the driver typed. It is never evidence
/// that the expense belongs to a particular shift, a particular delivery or a
/// particular vehicle, and nothing in DashPilot allocates a cost across work.
/// See ``Expense``.
nonisolated enum ExpenseCategory: String, CaseIterable, Sendable, Hashable, Identifiable, Codable {
    /// Fuel or charging.
    case fuel
    /// Parking, tolls and the like: the costs of getting the vehicle to and
    /// through the place the work happens.
    case parkingAndTolls
    /// Keeping the vehicle running: servicing, tyres, repairs, a car wash.
    case maintenance
    /// Things bought to do the work: bags, phone mounts, cables, drinks holders.
    case supplies
    /// Everything else. Claims nothing about what the money was for, which is
    /// exactly why it is the category a value this build cannot recognise reads
    /// as.
    case other

    var id: String { rawValue }

    /// The label a control shows.
    var title: String {
        switch self {
        case .fuel: "Fuel"
        case .parkingAndTolls: "Parking and tolls"
        case .maintenance: "Maintenance"
        case .supplies: "Supplies"
        case .other: "Other"
        }
    }

    /// The same word inside a spoken sentence, where a leading capital reads as
    /// the start of a new phrase.
    var spokenTitle: String {
        switch self {
        case .fuel: "fuel"
        case .parkingAndTolls: "parking and tolls"
        case .maintenance: "maintenance"
        case .supplies: "supplies"
        case .other: "other"
        }
    }

    /// The icon beside the label. Decoration only: every row states its category
    /// in words as well, because an icon is not a label to VoiceOver and is not
    /// a category to a driver who has not learned the set.
    var systemImage: String {
        switch self {
        case .fuel: "fuelpump"
        case .parkingAndTolls: "parkingsign"
        case .maintenance: "wrench.and.screwdriver"
        case .supplies: "shippingbox"
        case .other: "square.grid.2x2"
        }
    }

    /// Reads a category back out of the store.
    ///
    /// A stored string this build does not recognise reads as ``other`` rather
    /// than trapping or dropping the row. The only way to reach one is to run an
    /// older build against a store a newer one wrote, and in that situation the
    /// amount, the date and the note are still the driver's records: losing them
    /// to an unknown label would be the worse failure. ``other`` is the safe
    /// landing place precisely because it asserts nothing about what the money
    /// was for.
    static func stored(_ rawValue: String) -> ExpenseCategory {
        ExpenseCategory(rawValue: rawValue) ?? .other
    }
}
