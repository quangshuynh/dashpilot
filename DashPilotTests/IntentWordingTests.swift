import Foundation
import Testing
@testable import DashPilot

/// The sentences a driver hears back when they never look at the screen.
///
/// A voice confirmation is the whole report of what was recorded, so these are
/// asserted as carefully as the figures on a screen: what was recorded, in the
/// same words the app prints, with nothing claimed that was not written.
@MainActor
@Suite("Intent wording")
struct IntentWordingTests {
    private let start = Date(timeIntervalSince1970: 1_756_000_000)

    /// Every sentence the outcome type can produce, for the sweeps below.
    private var everyConfirmation: [String] {
        [
            IntentLifecycleOutcome.shiftStarted(at: start),
            .shiftEnded(duration: 5_400),
            .shiftEnded(duration: nil),
            .deliveryStarted(number: 1, inProgress: 1),
            .deliveryStarted(number: 2, inProgress: 2),
            .deliveryStarted(number: nil, inProgress: nil),
            .deliveryEventRecorded(number: 1, state: .arrivedAtPickup),
            .deliveryEventRecorded(number: 1, state: .pickedUp),
            .deliveryEventRecorded(number: 2, state: .delivered)
        ].map(\.confirmation)
    }

    // MARK: Shift

    @Test("Starting a shift says when it started and that the route needs the app open")
    func shiftStartNamesTheTimeAndTheRouteLimit() {
        let confirmation = IntentLifecycleOutcome.shiftStarted(at: start).confirmation

        #expect(confirmation.hasPrefix("Shift started at "))
        #expect(confirmation.contains(start.formatted(date: .omitted, time: .shortened)))
        #expect(
            confirmation.contains("records your route only while the app is open"),
            "A shift started without opening the app records no route, and the driver has no screen to notice it on"
        )
    }

    @Test("Ending a shift says how long it ran, in the spoken duration wording")
    func shiftEndNamesTheDuration() {
        #expect(
            IntentLifecycleOutcome.shiftEnded(duration: 5_400).confirmation
                == "Shift ended after \(DurationText.spoken(5_400))."
        )
    }

    @Test("A shift with no recorded length reports no length rather than zero")
    func shiftEndWithoutADurationSaysLess() {
        #expect(IntentLifecycleOutcome.shiftEnded(duration: nil).confirmation == "Shift ended.")
    }

    // MARK: Delivery

    @Test("A started delivery is named and counted in the interface's own words")
    func deliveryStartNamesAndCounts() {
        #expect(
            IntentLifecycleOutcome.deliveryStarted(number: 1, inProgress: 1).confirmation
                == "Delivery 1 started. 1 delivery in progress."
        )
        #expect(
            IntentLifecycleOutcome.deliveryStarted(number: 2, inProgress: 2).confirmation
                == "Delivery 2 started. 2 deliveries in progress."
        )
    }

    @Test("An unknown number or count is left out rather than invented")
    func unknownFactsAreNotFilledIn() {
        #expect(IntentLifecycleOutcome.deliveryStarted(number: nil, inProgress: 2).confirmation
            == "Delivery started. 2 deliveries in progress.")
        #expect(IntentLifecycleOutcome.deliveryStarted(number: 2, inProgress: nil).confirmation
            == "Delivery 2 started.")
        #expect(IntentLifecycleOutcome.deliveryStarted(number: nil, inProgress: nil).confirmation
            == "Delivery started.")
        #expect(IntentLifecycleOutcome.deliveryEventRecorded(number: nil, state: .delivered).confirmation
            == "Delivery recorded as delivered.")
    }

    @Test("A recorded event is named as history names it")
    func eventIsNamedAsHistoryNamesIt() {
        #expect(IntentLifecycleOutcome.deliveryEventRecorded(number: 1, state: .arrivedAtPickup).confirmation
            == "Delivery 1 recorded as arrived at the pickup.")
        #expect(IntentLifecycleOutcome.deliveryEventRecorded(number: 1, state: .pickedUp).confirmation
            == "Delivery 1 recorded as picked up.")
        #expect(IntentLifecycleOutcome.deliveryEventRecorded(number: 3, state: .delivered).confirmation
            == "Delivery 3 recorded as delivered.")
    }

    @Test("A delivery is called the same thing aloud as it is on screen")
    func deliveryIsNamedOnceForBothSurfaces() {
        let numbered = NumberedDelivery(number: 2, delivery: Delivery(shift: Shift(startedAt: start), acceptedAt: start))

        #expect(IntentLifecycleOutcome.deliveryStarted(number: 2, inProgress: nil).confirmation
            .hasPrefix(numbered.title))
    }

    // MARK: What no confirmation says

    @Test("No confirmation states an amount, a distance or a rate")
    func confirmationsClaimNoFigures() {
        for confirmation in everyConfirmation {
            let lowercased = confirmation.lowercased()
            for word in ["earn", "$", "mile", "profit", "per hour", "rate", "total"] {
                #expect(!lowercased.contains(word), "\(confirmation) claims something an intent did not record")
            }
        }
    }

    @Test("Every confirmation is one or two finished sentences")
    func confirmationsAreSpeakable() {
        for confirmation in everyConfirmation {
            #expect(confirmation.hasSuffix("."))
            #expect(!confirmation.contains(" · "), "A middle dot is not spoken")
            #expect(confirmation.count <= 130, "\(confirmation) is too long to hear at a junction")
        }
    }

    // MARK: Refusals

    @Test("A refusal the services already word is repeated, not rewritten")
    func serviceRefusalsAreCarriedThrough() {
        #expect(
            IntentLifecycleError.shift(.noActiveShift).errorDescription
                == ShiftLifecycleError.noActiveShift.errorDescription
        )
        #expect(
            IntentLifecycleError.shift(.activeDeliveriesInProgress(count: 2)).errorDescription
                == ShiftLifecycleError.activeDeliveriesInProgress(count: 2).errorDescription
        )
        #expect(
            IntentLifecycleError.delivery(.noActiveShift).errorDescription
                == DeliveryLifecycleError.noActiveShift.errorDescription
        )
    }

    @Test("The refusals that only exist off-screen say what to do instead")
    func offScreenRefusalsExplainThemselves() throws {
        let nothingRunning = try #require(IntentLifecycleError.noDeliveryInProgress.errorDescription)
        #expect(nothingRunning.contains("No delivery is in progress"))
        #expect(nothingRunning.contains("Start one"))

        let ambiguous = try #require(IntentLifecycleError.severalDeliveriesInProgress(count: 2).errorDescription)
        #expect(ambiguous.hasPrefix("2 deliveries are in progress"), "The count is named rather than left vague")
        #expect(ambiguous.contains("cannot tell which one"))
        #expect(ambiguous.contains("Open DashPilot"), "The refusal names the screen that can say it unambiguously")

        let unavailable = try #require(IntentLifecycleError.storeUnavailable.errorDescription)
        #expect(unavailable.contains("nothing was recorded"))
    }

    @Test("A refusal reaches the system surface as its own sentence")
    func refusalsDescribeThemselvesToTheSystem() {
        let error = IntentLifecycleError.severalDeliveriesInProgress(count: 2)

        #expect(String(localized: error.localizedStringResource) == error.errorDescription)
    }
}
