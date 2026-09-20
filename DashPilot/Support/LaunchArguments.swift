import Foundation

/// Launch arguments the app recognises.
///
/// The UI test target cannot link the app target, so it repeats these string
/// values rather than importing them. Keep the two in step.
nonisolated enum LaunchArgument {
    /// Runs against a throwaway in-memory store.
    ///
    /// UI tests need a known empty starting state and must not write shifts
    /// into the store a real driver's data would live in. Debug builds only.
    static let inMemoryStore = "-dashpilot-in-memory-store"

    /// Runs against a throwaway store already holding synthetic completed
    /// shifts.
    ///
    /// Some of what the history row shows cannot be produced by tapping through
    /// the app: a UI test cannot drive a simulator into recording a route, so a
    /// measured, partial route and the rates derived from it would otherwise be
    /// untestable end to end. The data is the same synthetic fixture the
    /// previews use — invented amounts and coordinates in open country, never a
    /// real driver's history. Debug builds only, and in memory, so it can never
    /// touch a real store.
    static let seededHistory = "-dashpilot-seeded-history"

    /// Runs against a throwaway store already holding a running shift with two
    /// deliveries in progress at different points in their lifecycles.
    ///
    /// A UI test cannot terminate and relaunch the app into a store it wrote
    /// earlier — the in-memory store the other journeys use disappears with the
    /// process. Seeding stacked active deliveries at launch reproduces the state
    /// a relaunch recovers into, which is the only way to assert end to end that
    /// the interface restores *every* running delivery with its own next step
    /// rather than collapsing them into one. That recovery is proved against a
    /// real reopened store in `DeliveryPersistenceTests`. Debug builds only, and
    /// in memory, so it can never touch a real store.
    static let seededActiveDelivery = "-dashpilot-seeded-active-delivery"

    /// Runs against a throwaway store already holding one completed shift whose
    /// deliveries give two pickup places different amounts of recorded history.
    ///
    /// The general seeded-history fixture is pinned by the journeys that assert
    /// exact active-time and rate figures over its three deliveries, so it
    /// cannot also be the place a median, a sample count and the
    /// insufficient-history wording are reached from. Debug builds only, and in
    /// memory, so it can never touch a real store.
    static let seededPickupHistory = "-dashpilot-seeded-pickup-history"

    /// Runs against a throwaway store already holding a week of synthetic
    /// completed shifts and three synthetic expenses, anchored to today.
    ///
    /// The period summary shows the day and week the driver is actually in, so
    /// the epoch-pinned fixtures above would open it on an empty period. This
    /// one keeps its offsets fixed and moves only its anchor, which is what lets
    /// a journey assert a subtotal and its coverage end to end. Debug builds
    /// only, and in memory, so it can never touch a real store.
    static let seededPeriodSummary = "-dashpilot-seeded-period-summary"

    /// Runs against a throwaway store holding three consecutive days of
    /// synthetic completed shifts, anchored to today.
    ///
    /// The period summary fixture above is pinned by the journeys that assert
    /// its exact day and week figures, and it holds nothing before this week, so
    /// it cannot also be where a period is read beside the one before it. This
    /// one gives today an incomplete record and a shift still to be paid for,
    /// yesterday and the day before a complete one each, and the day before
    /// those nothing at all — which is the three cases a comparison has to tell
    /// apart. Debug builds only, and in memory, so it can never touch a real
    /// store.
    static let seededPeriodComparison = "-dashpilot-seeded-period-comparison"

    /// Runs against a throwaway store holding a running shift with two
    /// deliveries waiting at their pickups, one of which records what it is
    /// expected to pay.
    ///
    /// Expected pay is the one delivery fact that can only be entered while the
    /// delivery is in progress, so every journey through it starts from a
    /// running delivery. Two of them, identical apart from the expectation, is
    /// what lets one launch cover all three cases the feature has: entering an
    /// amount on a delivery carrying none, completing a delivery that carries
    /// one and meeting the confirmation, and completing one that does not and
    /// meeting nothing. Seeding them at the pickup rather than already picked up
    /// keeps a lifecycle step in front of the completion, which is how a journey
    /// can assert that the confirmation belongs to the delivered event alone.
    ///
    /// The amounts, times and place are invented, like every other fixture here.
    /// Debug builds only, and in memory, so it can never touch a real store.
    static let seededExpectedPay = "-dashpilot-seeded-expected-pay"

    /// Runs against a throwaway store holding a running shift with one offer of
    /// two deliveries and a second, later offer of one.
    ///
    /// Grouping is the one thing a journey cannot reach by tapping: recording an
    /// offer of two is a single write, and what has to be asserted is what the
    /// screen looks like **afterwards**: which cards carry a heading, which
    /// carry none, and that a heading never becomes a control. The add-on offer
    /// is in the fixture for the same reason: two offers on one screen is the
    /// shape that proves the heading belongs to one of them rather than to the
    /// panel.
    ///
    /// The two deliveries of the first offer are left at different lifecycle
    /// points, so a journey can advance one and watch its sibling stay where it
    /// was.
    ///
    /// Every time is invented. Debug builds only, and in memory, so it can never
    /// touch a real store.
    static let seededStackedOffer = "-dashpilot-seeded-stacked-offer"

    /// Opens on a running shift holding one offer of two deliveries **and an
    /// offer holding none**.
    ///
    /// The empty offer is a row the app cannot produce: an offer is recorded
    /// with its deliveries in one write, and a correction that empties one
    /// removes it in the same write. It exists in a store only through a fault
    /// or a migration this build has not met, and the claim under test is that
    /// the correction screen reads such a store, states what the row is, and
    /// still corrects the offers around it rather than falling over.
    ///
    /// It is accepted **after** the real offer, so the real one is still
    /// `Offer 1` and the journeys about grouping read what they always did.
    ///
    /// Every time is invented. Debug builds only, and in memory.
    static let seededMalformedOffer = "-dashpilot-seeded-malformed-offer"

    /// Runs against a throwaway store holding one **completed** shift that was
    /// paused twice, with one delivery recorded between the two pauses.
    ///
    /// The completed-shift detail's `Paused` and `Working` rows, its list of
    /// recorded pauses and every correction offered there were reachable from no
    /// fixture and from no sequence of taps: a journey would have to pause a
    /// live shift, wait a measurable number of minutes and end it, which
    /// measures the clock rather than the screen. The shape is chosen for what
    /// the corrections are checked against — two pauses, a delivery between
    /// them, and a stretch at the end with neither.
    ///
    /// Every time and amount is invented. Debug builds only, and in memory, so
    /// it can never touch a real store.
    static let seededPausedHistory = "-dashpilot-seeded-paused-history"

    /// Runs against a throwaway store holding one **completed** shift whose
    /// recorded end is twenty minutes later than the driver actually stopped,
    /// with a capture session recorded in those twenty minutes.
    ///
    /// The end-time correction's most important claim is that recorded route
    /// after the corrected end is **deleted** and the mileage measured again
    /// from what remains, and no fixture and no sequence of taps reaches that
    /// shape: ending a shift records the clock, and a UI test cannot drive a
    /// simulator into recording a route. The shift also holds a delivery
    /// finishing ten minutes before the corrected end, so the refusal a
    /// correction meets when it would swallow recorded work is reachable too.
    ///
    /// Every time, amount and coordinate is invented. Debug builds only, and in
    /// memory, so it can never touch a real store.
    static let seededLateEndHistory = "-dashpilot-seeded-late-end-history"

    /// Runs against a throwaway store holding one **completed** shift whose
    /// delivery recorded its completion two hours after the order was actually
    /// handed over, and whose own end is late as well.
    ///
    /// The real recovery case: DashPilot became unreachable near the end of a
    /// shift, the driver kept delivering, and the remaining lifecycle events
    /// landed in the app only once a new build was installed. No fixture and no
    /// sequence of taps reaches that shape, because recording a completion
    /// records the clock. It is what lets one journey drive the whole recovery
    /// end to end: an end correction refused and naming the blocking delivery
    /// and event, the delivery's times corrected, and the same end correction
    /// then accepted.
    ///
    /// The shift, its route and its recorded amount are the late-end fixture's,
    /// so the figures a corrected end produces are the ones those journeys
    /// already pin.
    ///
    /// Every time, amount and coordinate is invented. Debug builds only, and in
    /// memory, so it can never touch a real store.
    static let seededLateDeliveryHistory = "-dashpilot-seeded-late-delivery-history"

    /// Runs against a throwaway store holding completed shifts in three
    /// different weeks: one in the current one, one in the week before it and
    /// two in the week three back.
    ///
    /// History is scoped to the current Monday-to-Sunday week, and every other
    /// fixture sits inside one week on purpose. A journey cannot tap its way to
    /// a shift dated last month either, because ending a shift records the
    /// clock. This is what lets the scope itself be asserted end to end: which
    /// rows the default list holds, that a shift outside the week is genuinely
    /// absent from it, and that it is one tap away under View Older Weeks.
    ///
    /// Every time and amount is invented. Debug builds only, and in memory, so
    /// it can never touch a real store.
    static let seededOlderWeeks = "-dashpilot-seeded-older-weeks"

    /// The fixture above **without** its current-week shift, which is the empty
    /// current week.
    ///
    /// A separate argument rather than a separate fixture: the two launches
    /// describe the same store minus one row, so a journey asserting that
    /// History says the week holds nothing is asserting the absence of exactly
    /// the row the other launch shows.
    ///
    /// Debug builds only, and in memory.
    static let seededOlderWeeksOnly = "-dashpilot-seeded-older-weeks-only"

    /// Runs with Core Location replaced by the stub the tests and previews use,
    /// reporting When In Use with full accuracy and producing no positions.
    ///
    /// A UI test cannot grant location permission or feed a route, so without
    /// this the running shift's status line is only ever reachable in its
    /// "permission required" state, and the journeys that matter here cannot be
    /// written: what a driver reads while a route is being recorded, and whether
    /// leaving the app and returning still says the same thing.
    ///
    /// It stubs permission and the position feed and nothing else. The scene
    /// phase, ``RootView``'s reaction to it and ``LocationTrackingService``'s own
    /// decisions are the real ones, which is the whole point of reaching them
    /// from a journey rather than a unit test. Debug builds only.
    static let stubbedLocation = "-dashpilot-stubbed-location"

    /// Runs with Core Location replaced by a synthetic vehicle driving in a
    /// straight line, so a journey can watch a live figure move.
    ///
    /// ``stubbedLocation`` grants permission and produces no positions, which is
    /// enough to reach every capture *state* but not enough to reach a recorded
    /// *distance*. A live mileage figure cannot be seeded either: what has to be
    /// asserted is that it grows while positions are accepted, that it stops the
    /// moment the driver pauses, and that resuming does not add the distance
    /// covered during the break. All three are statements about capture running.
    ///
    /// It implies ``stubbedLocation``'s permission stub, because a fed route
    /// with no grant would be rejected before the filter ever saw it.
    /// ``SimulatedRouteLocationProvider`` is the whole of what it replaces; the
    /// filter, the capture sessions, the store writes and the measurement are
    /// the shipping ones. Debug builds only.
    static let simulatedRoute = "-dashpilot-simulated-route"

    static func isPresent(_ argument: String, in processInfo: ProcessInfo = .processInfo) -> Bool {
        processInfo.arguments.contains(argument)
    }

    /// Every argument that replaces the driver's own store with a throwaway one.
    ///
    /// Listed once, so that anything which must not act on synthetic data has a
    /// single question to ask. Adding a fixture means adding it here too.
    static let throwawayStoreArguments = [
        inMemoryStore,
        seededHistory,
        seededActiveDelivery,
        seededPickupHistory,
        seededPeriodSummary,
        seededPeriodComparison,
        seededExpectedPay,
        seededStackedOffer,
        seededMalformedOffer,
        seededPausedHistory,
        seededLateEndHistory,
        seededLateDeliveryHistory,
        seededOlderWeeks,
        seededOlderWeeksOnly
    ]

    /// Whether this launch is running over synthetic, in-memory data.
    ///
    /// Asked by anything whose effects reach **outside** the store, because those
    /// effects outlive the process and a fixture's data must not produce them.
    /// The Live Activity is the first such surface: a card requested from a
    /// throwaway store would sit on a real Lock Screen describing a shift that
    /// never happened.
    static func isUsingThrowawayStore(in processInfo: ProcessInfo = .processInfo) -> Bool {
        throwawayStoreArguments.contains { isPresent($0, in: processInfo) }
    }
}
