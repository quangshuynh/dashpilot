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
    ///
    /// ``AppIntent/supportedModes`` replaced ``AppIntent/openAppWhenRun``,
    /// which iOS 26 deprecated. ``IntentModes/background`` states the same fact
    /// the old `false` did, and reading it here rather than the deprecated
    /// property is what proves the intents still declare it themselves instead
    /// of falling back on whatever the framework defaults to.
    private struct Metadata {
        let title: String
        let description: String?
        let modes: IntentModes
        let authentication: IntentAuthenticationPolicy

        init<I: AppIntent>(_ type: I.Type) {
            title = String(localized: I.title)
            description = I.description.map { String(localized: $0.descriptionText) }
            modes = I.supportedModes
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
            #expect(
                intent.modes == .background,
                "\(intent.title) would replace one spoken action with a screen"
            )
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

    // MARK: Pausing and resuming

    @Test("Pausing by intent pauses the shift without ending it")
    func pauseShiftIntentPausesTheShift() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            _ = try await PauseShiftIntent().perform()

            let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
            #expect(shift.lifecycleState == .paused)
            #expect(shift.endedAt == nil, "A pause is not an end")
            #expect(shift.pauses.count == 1)
        }
    }

    @Test("Resuming by intent closes the pause")
    func resumeShiftIntentResumesTheShift() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            _ = try await PauseShiftIntent().perform()
            _ = try await ResumeShiftIntent().perform()

            let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
            #expect(shift.lifecycleState == .running)
            #expect(shift.openPause == nil)
            #expect(shift.pauses.count == 1)
        }
    }

    /// The intents hold no rule of their own: this is ``ShiftService``'s
    /// refusal, reaching a system surface unchanged.
    @Test("Pausing by intent is refused while a delivery is in progress")
    func pauseShiftIntentRefusesOverAnOpenDelivery() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            _ = try await StartDeliveryIntent().perform()

            await #expect(throws: IntentLifecycleError.shift(.activeDeliveriesBlockPause(count: 1))) {
                _ = try await PauseShiftIntent().perform()
            }

            let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
            #expect(shift.pauses.isEmpty)
            #expect(shift.lifecycleState == .running)
        }
    }

    @Test("Pausing an already paused shift is refused, and resuming a running one is too")
    func pauseAndResumeIntentsRefuseTheirOwnNoOps() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()

            await #expect(throws: IntentLifecycleError.shift(.shiftNotPaused)) {
                _ = try await ResumeShiftIntent().perform()
            }

            _ = try await PauseShiftIntent().perform()

            await #expect(throws: IntentLifecycleError.self) {
                _ = try await PauseShiftIntent().perform()
            }

            let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
            #expect(shift.pauses.count == 1)
        }
    }

    @Test("Pausing or resuming with nothing running is refused")
    func pauseAndResumeRefuseWithNoShift() async throws {
        try await withStore { _ in
            await #expect(throws: IntentLifecycleError.shift(.noActiveShift)) {
                _ = try await PauseShiftIntent().perform()
            }
            await #expect(throws: IntentLifecycleError.shift(.noActiveShift)) {
                _ = try await ResumeShiftIntent().perform()
            }
        }
    }

    @Test("A delivery started by intent is refused while the shift is paused")
    func startDeliveryIntentRefusesWhilePaused() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            _ = try await PauseShiftIntent().perform()

            await #expect(throws: IntentLifecycleError.delivery(.shiftPaused)) {
                _ = try await StartDeliveryIntent().perform()
            }

            #expect(try context.fetch(FetchDescriptor<Delivery>()).isEmpty)
        }
    }

    @Test("Ending a paused shift by intent ends it and closes the pause")
    func endShiftIntentEndsAPausedShift() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            _ = try await PauseShiftIntent().perform()
            _ = try await EndShiftIntent().perform()

            let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
            #expect(shift.lifecycleState == .ended)
            #expect(shift.openPause == nil)
        }
    }

    /// The pair run in the background and on a locked phone, like the four that
    /// came before them: a driver pausing at a kerb must not have to unlock the
    /// phone first, or they will not record the break at all.
    @Test("Pause and Resume run without opening the app, on a locked device")
    func pauseAndResumeRunInTheBackground() {
        #expect(PauseShiftIntent.supportedModes == .background)
        #expect(ResumeShiftIntent.supportedModes == .background)
        #expect(PauseShiftIntent.authenticationPolicy == .alwaysAllowed)
        #expect(ResumeShiftIntent.authenticationPolicy == .alwaysAllowed)
    }

    @Test("The pause description says what stops, and the resume description what restarts")
    func pauseAndResumeDescriptionsStateTheirEffects() throws {
        let pause = String(localized: try #require(PauseShiftIntent.description?.descriptionText))
        let resume = String(localized: try #require(ResumeShiftIntent.description?.descriptionText))

        #expect(pause.lowercased().contains("not counted as working time"))
        #expect(pause.lowercased().contains("route recording stops"))
        #expect(resume.lowercased().contains("not counted"), "The distance across the pause is named")
        #expect(resume.lowercased().contains("open dashpilot"), "A session can only be started in the foreground")
    }

    @Test("Six shortcuts are offered, and they are the six lifecycle actions")
    func shortcutsCoverTheLifecycleActionsOnly() {
        #expect(DashPilotShortcuts.appShortcuts.count == 6)
    }
}
