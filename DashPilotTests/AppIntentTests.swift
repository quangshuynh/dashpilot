import AppIntents
import Foundation
import SwiftData
import Testing
@testable import DashPilot

/// The intents themselves: performed end to end against a throwaway store, and
/// checked for the metadata that decides how they behave on a system surface.
///
/// Serialised, because every test here points the shared intent entry point at
/// its own store for the length of the test. That entry point exists only in
/// debug builds; a shipped intent has exactly one store it can reach.
@MainActor
@Suite("App intents", .serialized)
struct AppIntentTests {
    /// Performs `body` with the intents writing into a throwaway store.
    private func withStore(_ body: (ModelContext) async throws -> Void) async throws {
        let context = ModelContext(try ModelContainerFactory.makeInMemoryContainer())
        IntentLifecycleService.testContext = context
        defer { IntentLifecycleService.testContext = nil }
        try await body(context)
    }

    // MARK: Performing

    @Test("Starting a shift by intent records one")
    func startShiftIntentRecordsAShift() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()

            let shifts = try context.fetch(FetchDescriptor<Shift>())
            #expect(shifts.count == 1)
            #expect(shifts.first?.isActive == true)
        }
    }

    @Test("A second start is refused with the sentence the driver hears")
    func startShiftIntentRefusesASecond() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()

            await #expect(throws: IntentLifecycleError.self) {
                _ = try await StartShiftIntent().perform()
            }
            #expect(try context.fetch(FetchDescriptor<Shift>()).count == 1)
        }
    }

    @Test("Ending with nothing running is refused")
    func endShiftIntentRefusesWithNoShift() async throws {
        try await withStore { _ in
            await #expect(throws: IntentLifecycleError.shift(.noActiveShift)) {
                _ = try await EndShiftIntent().perform()
            }
        }
    }

    @Test("A shift started by intent is ended by intent")
    func endShiftIntentEndsTheShift() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            _ = try await EndShiftIntent().perform()

            let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
            #expect(shift.isActive == false)
            #expect(shift.endedAt != nil)
        }
    }

    @Test("A delivery started by intent advances by intent")
    func deliveryIntentsRecordTheLifecycle() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            _ = try await StartDeliveryIntent().perform()
            _ = try await RecordDeliveryProgressIntent().perform()

            let delivery = try #require(try context.fetch(FetchDescriptor<Delivery>()).first)
            #expect(delivery.state == .arrivedAtPickup)
            #expect(delivery.arrivedAtPickupAt != nil)
        }
    }

    @Test("With two deliveries running the step intent records nothing")
    func progressIntentRefusesWhenAmbiguous() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            _ = try await StartDeliveryIntent().perform()
            _ = try await StartDeliveryIntent().perform()

            await #expect(throws: IntentLifecycleError.severalDeliveriesInProgress(count: 2)) {
                _ = try await RecordDeliveryProgressIntent().perform()
            }
            let deliveries = try context.fetch(FetchDescriptor<Delivery>())
            #expect(deliveries.allSatisfy { $0.state == .accepted })
        }
    }

    @Test("A store that cannot be opened records nothing and says so")
    func refusesWithoutAStore() throws {
        // The debug seam is what the intents resolve first; with none set they
        // reach the process's own container, which is the path this suite
        // deliberately never writes to. What is asserted here is the sentence
        // the failure produces.
        #expect(IntentLifecycleError.storeUnavailable.errorDescription?.contains("nothing was recorded") == true)
    }

    // MARK: Metadata

    /// What the system reads off an intent, read the way the system reads it.
    ///
    /// Through the protocol rather than off the concrete type on purpose: a
    /// property declared with the wrong type does not become the witness, and
    /// the framework's default is used instead. That is silent, and it is
    /// exactly how an intent ships with no description.
    private struct Metadata {
        let title: String
        let description: String?
        let opensApp: Bool
        let authentication: IntentAuthenticationPolicy

        init<I: AppIntent>(_ type: I.Type) {
            title = String(localized: I.title)
            description = I.description.map { String(localized: $0.descriptionText) }
            opensApp = I.openAppWhenRun
            authentication = I.authenticationPolicy
        }
    }

    private var everyIntent: [Metadata] {
        [
            Metadata(StartShiftIntent.self),
            Metadata(EndShiftIntent.self),
            Metadata(StartDeliveryIntent.self),
            Metadata(RecordDeliveryProgressIntent.self)
        ]
    }

    @Test("No intent brings the app to the screen")
    func intentsRunWithoutOpeningTheApp() {
        for intent in everyIntent {
            #expect(intent.opensApp == false, "\(intent.title) would replace one spoken action with a screen")
        }
    }

    @Test("Every intent runs with the device locked")
    func intentsRunOnALockedDevice() {
        for intent in everyIntent {
            #expect(
                intent.authentication == .alwaysAllowed,
                "\(intent.title) would ask a driving driver to unlock the phone first"
            )
        }
    }

    @Test("Every intent names the action it performs and explains itself")
    func intentsAreNamedForTheirAction() throws {
        #expect(everyIntent.map(\.title) == [
            "Start Shift",
            "End Shift",
            "Start Delivery",
            "Record Delivery Progress"
        ])
        for intent in everyIntent {
            let description = try #require(intent.description, "\(intent.title) reaches Shortcuts with no explanation")
            #expect(!description.isEmpty)
        }
    }

    @Test("The step intent's description states the rule it refuses under")
    func progressIntentDescribesItsAmbiguityRule() throws {
        let description = try #require(Metadata(RecordDeliveryProgressIntent.self).description)

        #expect(description.contains("more than one delivery is in progress"))
        #expect(description.contains("nothing is recorded"))
    }

    @Test("The shift intent's description states that the route needs the app open")
    func startShiftDescriptionStatesTheRouteLimit() throws {
        let description = try #require(Metadata(StartShiftIntent.self).description)

        #expect(description.contains("records no mileage until you open it"))
    }

    @Test("Four shortcuts are offered, and they are the four lifecycle actions")
    func shortcutsCoverTheLifecycleActionsOnly() {
        #expect(DashPilotShortcuts.appShortcuts.count == 4)
    }
}
