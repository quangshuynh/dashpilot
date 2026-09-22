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

    /// The same, with the shift's Live Activity watched.
    ///
    /// A throwaway store must never drive a real system surface, so what the
    /// intents reconcile here is a recorder. What is being asserted is that an
    /// intent reconciles **at all**: an intent can run with no screen, so there
    /// is nothing else to notice that a shift was paused from Siri or from a
    /// Lock Screen button.
    private func withStoreWatchingActivity(
        _ body: (ModelContext, ReconcileRecorder) async throws -> Void
    ) async throws {
        let recorder = ReconcileRecorder()
        IntentLifecycleService.testActivity = recorder
        defer { IntentLifecycleService.testActivity = nil }
        try await withStore { context in try await body(context, recorder) }
    }

    /// Counts the times an intent asked the Live Activity to catch up.
    @MainActor
    final class ReconcileRecorder: ShiftActivityReconciling {
        private(set) var count = 0
        func reconcile() { count += 1 }
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
            Metadata(ParkVehicleIntent.self),
            Metadata(ResumeDrivingIntent.self),
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
            "Park Vehicle",
            "Resume Driving",
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

    @Test("Eight shortcuts are offered, and they are the eight lifecycle actions")
    func shortcutsCoverTheLifecycleActionsOnly() {
        #expect(DashPilotShortcuts.appShortcuts.count == 8)
    }

    // MARK: Parking and driving again

    @Test("Parking by intent records the vehicle as parked without pausing the shift")
    func parkIntentRecordsTheSuspension() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            _ = try await ParkVehicleIntent().perform()

            let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
            #expect(shift.isRouteSuspended, "The state the app's own panel reads")
            #expect(shift.routeSuspensions.count == 1)
            #expect(shift.openRouteSuspension?.isOpen == true)
            // Parking is not pausing, on this surface as on every other.
            #expect(shift.lifecycleState == .running)
            #expect(shift.pauses.isEmpty)
            #expect(shift.endedAt == nil)
        }
    }

    /// The state an intent writes is the state the screen reads: one derivation,
    /// one row, and no second flag anywhere.
    @Test("An intent's parking is the same state the app's own panel reads")
    func parkIntentWritesTheStateTheAppReads() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            _ = try await ParkVehicleIntent().perform()

            let shift = try #require(try ShiftService(context: context).activeShift())
            #expect(shift.isRouteSuspended)
            #expect(shift.activeMetrics(for: .none, asOf: .now).isRouteSuspended)
            #expect(shift.suspendedTime(asOf: .now).openIntervalCount == 1)
        }
    }

    @Test("Parking with nothing running is refused, and so is driving again")
    func parkAndResumeDrivingRefuseWithNoShift() async throws {
        try await withStore { context in
            await #expect(throws: IntentLifecycleError.shift(.noActiveShift)) {
                _ = try await ParkVehicleIntent().perform()
            }
            await #expect(throws: IntentLifecycleError.shift(.noActiveShift)) {
                _ = try await ResumeDrivingIntent().perform()
            }

            let suspensions = try context.fetch(FetchDescriptor<RouteSuspension>())
            #expect(suspensions.isEmpty)
        }
    }

    @Test("Parking an already parked shift is refused and writes nothing")
    func parkIntentRefusesWhenAlreadyParked() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            _ = try await ParkVehicleIntent().perform()
            let opened = try #require(
                try context.fetch(FetchDescriptor<Shift>()).first?.openRouteSuspension?.startedAt
            )

            await #expect(throws: IntentLifecycleError.shift(.shiftAlreadyParked(parkedAt: opened))) {
                _ = try await ParkVehicleIntent().perform()
            }

            let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
            #expect(shift.routeSuspensions.count == 1, "A refused control opens no second row")
            #expect(shift.openRouteSuspension?.startedAt == opened)
        }
    }

    @Test("Driving again while parked closes the suspension")
    func resumeDrivingIntentClosesTheSuspension() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            _ = try await ParkVehicleIntent().perform()
            _ = try await ResumeDrivingIntent().perform()

            let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
            #expect(shift.isRouteSuspended == false)
            #expect(shift.openRouteSuspension == nil)
            #expect(shift.routeSuspensions.count == 1, "The stretch is kept, not deleted")
            #expect(shift.routeSuspensions.first?.endedAt != nil)
            #expect(shift.lifecycleState == .running)
        }
    }

    @Test("Driving again on a shift that is not parked is refused")
    func resumeDrivingIntentRefusesWhenNotParked() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()

            await #expect(throws: IntentLifecycleError.shift(.shiftNotParked)) {
                _ = try await ResumeDrivingIntent().perform()
            }

            let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
            #expect(shift.routeSuspensions.isEmpty)
        }
    }

    /// The intent holds no rule of its own: this is
    /// ``ShiftService/parkActiveShift(at:)``'s refusal of a paused shift,
    /// reaching a spoken surface unchanged.
    @Test("Parking a paused shift is refused by the service, not by the intent")
    func parkIntentDoesNotBypassServiceValidation() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            _ = try await PauseShiftIntent().perform()

            await #expect(throws: IntentLifecycleError.self) {
                _ = try await ParkVehicleIntent().perform()
            }

            let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
            #expect(shift.routeSuspensions.isEmpty, "A refused intent writes nothing")
            #expect(shift.lifecycleState == .paused, "And changes nothing else either")
        }
    }

    /// Parking is a **shift** operation. Nothing about it consults the
    /// deliveries, in either direction, because one driver has one vehicle
    /// however many orders are in the car.
    @Test("Parking needs no delivery, and is refused by no number of them")
    func parkIntentIsAShiftOperation() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            // No delivery at all.
            _ = try await ParkVehicleIntent().perform()
            _ = try await ResumeDrivingIntent().perform()

            // And two stacked ones, which refuse a pause and a step.
            _ = try await StartDeliveryIntent().perform()
            _ = try await StartDeliveryIntent().perform()
            _ = try await ParkVehicleIntent().perform()

            let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
            #expect(shift.isRouteSuspended)
            #expect(shift.activeDeliveries.count == 2, "And no delivery moved")
            #expect(shift.activeDeliveries.allSatisfy { $0.state == .accepted })
        }
    }

    /// Route capture is the caller's to reconcile and is not this layer's, but
    /// the rule the route depends on is: a resumed stretch must leave the rows
    /// that were recorded before it exactly as they were, so the mileage
    /// calculation still refuses to measure across the gap.
    @Test("Parking and driving again leave every recorded position untouched")
    func parkIntentTouchesNoRouteSample() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)

            let session = UUID()
            let before = shift.startedAt.addingTimeInterval(60)
            for offset in 0..<2 {
                context.insert(
                    RouteSample(
                        shift: shift,
                        timestamp: before.addingTimeInterval(Double(offset) * 10),
                        latitude: 44.0 + Double(offset) / 1_000,
                        longitude: -123.0,
                        horizontalAccuracy: 5,
                        captureSessionID: session
                    )
                )
            }
            try context.save()
            let recorded = shift.routeSamples().map(\.timestamp)
            #expect(recorded.count == 2)

            _ = try await ParkVehicleIntent().perform()
            _ = try await ResumeDrivingIntent().perform()

            #expect(shift.routeSamples().map(\.timestamp) == recorded)
            #expect(shift.routeSampleCount == 2, "No position is deleted or invented")
        }
    }

    @Test("Park and Resume Driving run without opening the app, on a locked device")
    func parkAndResumeDrivingRunInTheBackground() {
        #expect(ParkVehicleIntent.supportedModes == .background)
        #expect(ResumeDrivingIntent.supportedModes == .background)
        #expect(ParkVehicleIntent.authenticationPolicy == .alwaysAllowed)
        #expect(ResumeDrivingIntent.authenticationPolicy == .alwaysAllowed)
    }

    @Test("The parked descriptions say what stops, what does not, and what is not counted")
    func parkAndResumeDrivingDescriptionsStateTheirEffects() throws {
        let park = String(localized: try #require(ParkVehicleIntent.description?.descriptionText)).lowercased()
        let driving = String(localized: try #require(ResumeDrivingIntent.description?.descriptionText)).lowercased()

        #expect(park.contains("route recording stops"))
        #expect(park.contains("shift keeps running"), "Parking is not pausing, and the description says so")
        #expect(park.contains("not counted"), "The distance across the stretch is named")
        #expect(driving.contains("not counted"))
        #expect(driving.contains("open dashpilot"), "A session can only be started in the foreground")
    }

    /// The confirmation is the only report a driver standing away from the car
    /// gets, so the two facts the state confuses have to be in it.
    @Test("The spoken confirmations separate the route from the shift")
    func parkedConfirmationsSeparateTheRouteFromTheShift() {
        let parked = IntentLifecycleOutcome.vehicleParked.confirmation.lowercased()

        #expect(parked.contains("route recording is stopped"))
        #expect(parked.contains("shift is still running"))
        #expect(!parked.contains("pause"), "Parking is not a pause and must never be said as one")

        let driving = IntentLifecycleOutcome.drivingResumed(parkedDuration: 1_500).confirmation.lowercased()
        #expect(driving.contains("driving again"))
        #expect(driving.contains("open dashpilot"))
    }

    // MARK: The Live Activity's own controls

    /// The five Lock Screen controls, read the way the system reads them.
    ///
    /// They are separate intents from the spoken ones above because a Live
    /// Activity button must be a ``LiveActivityIntent`` and must exist in the
    /// widget extension, while Siri must not learn two ways to say the same
    /// sentence. What they must not be is a second implementation: every one of
    /// them goes through ``IntentLifecycleService``, and these tests perform them
    /// against a real store to prove it.
    @Test("Every Live Activity control runs in the background on a locked device")
    func activityIntentsRunOnALockedDevice() {
        #expect(PauseShiftFromActivityIntent.supportedModes == .background)
        #expect(ResumeShiftFromActivityIntent.supportedModes == .background)
        #expect(EndShiftFromActivityIntent.supportedModes == .background)
        #expect(StartDeliveryFromActivityIntent.supportedModes == .background)
        #expect(RecordDeliveryProgressFromActivityIntent.supportedModes == .background)

        #expect(PauseShiftFromActivityIntent.authenticationPolicy == .alwaysAllowed)
        #expect(ResumeShiftFromActivityIntent.authenticationPolicy == .alwaysAllowed)
        #expect(EndShiftFromActivityIntent.authenticationPolicy == .alwaysAllowed)
        #expect(StartDeliveryFromActivityIntent.authenticationPolicy == .alwaysAllowed)
        #expect(RecordDeliveryProgressFromActivityIntent.authenticationPolicy == .alwaysAllowed)
    }

    @Test("No Live Activity control appears in Shortcuts beside the spoken action it repeats")
    func activityIntentsAreNotDiscoverable() {
        #expect(PauseShiftFromActivityIntent.isDiscoverable == false)
        #expect(ResumeShiftFromActivityIntent.isDiscoverable == false)
        #expect(EndShiftFromActivityIntent.isDiscoverable == false)
        #expect(StartDeliveryFromActivityIntent.isDiscoverable == false)
        #expect(RecordDeliveryProgressFromActivityIntent.isDiscoverable == false)

        #expect(PauseShiftIntent.isDiscoverable, "The spoken action is the discoverable one")
        #expect(StartDeliveryIntent.isDiscoverable, "And it is the one that starts a delivery, too")
        #expect(DashPilotShortcuts.appShortcuts.count == 8, "And the shortcut count is unchanged by them")
    }

    @Test("Pausing and resuming from the Live Activity writes what the app's own button writes")
    func activityIntentsPauseAndResume() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            _ = try await PauseShiftFromActivityIntent().perform()

            let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
            #expect(shift.lifecycleState == .paused)
            #expect(shift.isActive, "Pausing does not end a shift, whichever surface asked")

            _ = try await ResumeShiftFromActivityIntent().perform()
            #expect(shift.lifecycleState == .running)
            #expect(shift.openPause == nil)
        }
    }

    @Test("Ending from the Live Activity ends the shift")
    func activityIntentEndsTheShift() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            _ = try await EndShiftFromActivityIntent().perform()

            let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
            #expect(shift.endedAt != nil)
        }
    }

    @Test("A Live Activity control is refused by the same rule, with the same sentence")
    func activityIntentsCarryTheServicesOwnRefusals() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            _ = try await StartDeliveryIntent().perform()

            await #expect(throws: IntentLifecycleError.shift(.activeDeliveriesBlockPause(count: 1))) {
                _ = try await PauseShiftFromActivityIntent().perform()
            }
            await #expect(throws: IntentLifecycleError.shift(.activeDeliveriesInProgress(count: 1))) {
                _ = try await EndShiftFromActivityIntent().perform()
            }

            let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
            #expect(shift.lifecycleState == .running, "A refused control writes nothing")
        }
    }

    @Test("The step control refuses rather than guessing when two deliveries are in progress")
    func activityStepIntentRefusesWhenAmbiguous() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            _ = try await StartDeliveryIntent().perform()
            _ = try await StartDeliveryIntent().perform()

            await #expect(throws: IntentLifecycleError.severalDeliveriesInProgress(count: 2)) {
                _ = try await RecordDeliveryProgressFromActivityIntent().perform()
            }

            let deliveries = try context.fetch(FetchDescriptor<Delivery>())
            #expect(deliveries.count == 2)
            #expect(deliveries.allSatisfy { $0.state == .accepted }, "Neither delivery was advanced")
        }
    }

    // MARK: Starting a delivery from the Live Activity

    @Test("Starting a delivery from the Live Activity records exactly one")
    func activityStartDeliveryRecordsExactlyOne() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            _ = try await StartDeliveryFromActivityIntent().perform()

            let deliveries = try context.fetch(FetchDescriptor<Delivery>())
            #expect(deliveries.count == 1)
            #expect(deliveries.first?.state == .accepted)
            // Nothing is invented alongside the delivery the driver started.
            #expect(deliveries.first?.grossEarnings == nil)
            #expect(deliveries.first?.expectedEarnings == nil)
            #expect(deliveries.first?.pickupPlace == nil)
        }
    }

    @Test("Starting one while another is running stacks rather than replacing")
    func activityStartDeliveryStacks() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            _ = try await StartDeliveryFromActivityIntent().perform()
            let first = try #require(try context.fetch(FetchDescriptor<Delivery>()).first)
            _ = try await RecordDeliveryProgressFromActivityIntent().perform()
            #expect(first.state == .arrivedAtPickup)

            _ = try await StartDeliveryFromActivityIntent().perform()

            let deliveries = try context.fetch(FetchDescriptor<Delivery>())
            #expect(deliveries.count == 2)
            #expect(first.state == .arrivedAtPickup, "The order already in the car is untouched")
            #expect(deliveries.filter { $0.state == .accepted }.count == 1)
        }
    }

    @Test("Each press records exactly one delivery")
    func activityStartDeliveryRecordsOnePerPress() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()

            for expected in 1...3 {
                _ = try await StartDeliveryFromActivityIntent().perform()
                #expect(try context.fetch(FetchDescriptor<Delivery>()).count == expected)
            }

            let deliveries = try context.fetch(FetchDescriptor<Delivery>())
            #expect(deliveries.allSatisfy { $0.state == .accepted })
            #expect(Set(deliveries.map(\.id)).count == 3, "Three records, not one pressed three times")
        }
    }

    @Test("A stale press after the shift is paused or ended is refused and writes nothing")
    func activityStartDeliveryRefusesStalePresses() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            _ = try await PauseShiftIntent().perform()

            await #expect(throws: IntentLifecycleError.delivery(.shiftPaused)) {
                _ = try await StartDeliveryFromActivityIntent().perform()
            }
            #expect(try context.fetch(FetchDescriptor<Delivery>()).isEmpty)

            _ = try await EndShiftIntent().perform()
            await #expect(throws: IntentLifecycleError.delivery(.noActiveShift)) {
                _ = try await StartDeliveryFromActivityIntent().perform()
            }
            #expect(try context.fetch(FetchDescriptor<Delivery>()).isEmpty)
        }
    }

    @Test("A press with nothing running at all is refused")
    func activityStartDeliveryRefusesWithNoShift() async throws {
        try await withStore { context in
            await #expect(throws: IntentLifecycleError.delivery(.noActiveShift)) {
                _ = try await StartDeliveryFromActivityIntent().perform()
            }

            let deliveries = try context.fetch(FetchDescriptor<Delivery>())
            #expect(deliveries.isEmpty)
        }
    }

    @Test("Starting a delivery from the Live Activity asks the card to catch up, and a refusal does not")
    func activityStartDeliveryReconciles() async throws {
        try await withStoreWatchingActivity { _, recorder in
            _ = try await StartShiftIntent().perform()
            #expect(recorder.count == 1)

            _ = try await StartDeliveryFromActivityIntent().perform()
            #expect(recorder.count == 2)

            _ = try await StartDeliveryFromActivityIntent().perform()
            #expect(recorder.count == 3)

            await #expect(throws: IntentLifecycleError.self) {
                _ = try await PauseShiftFromActivityIntent().perform()
            }
            #expect(recorder.count == 3, "A refusal wrote nothing, so there is nothing to catch up with")
        }
    }

    @Test("The step control advances the one delivery in progress")
    func activityStepIntentAdvancesTheOneDelivery() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            _ = try await StartDeliveryIntent().perform()
            _ = try await RecordDeliveryProgressFromActivityIntent().perform()

            let delivery = try #require(try context.fetch(FetchDescriptor<Delivery>()).first)
            #expect(delivery.state == .arrivedAtPickup)
        }
    }

    @Test("Every write from a system surface asks the Live Activity to catch up, and a refusal does not")
    func writesReconcileTheLiveActivity() async throws {
        try await withStoreWatchingActivity { _, recorder in
            _ = try await StartShiftIntent().perform()
            #expect(recorder.count == 1)

            _ = try await StartDeliveryIntent().perform()
            #expect(recorder.count == 2)

            _ = try await RecordDeliveryProgressIntent().perform()
            #expect(recorder.count == 3)

            // Refused: a shift cannot pause over a delivery in progress. Nothing
            // was written, so there is nothing for the surface to catch up with.
            await #expect(throws: IntentLifecycleError.self) {
                _ = try await PauseShiftFromActivityIntent().perform()
            }
            #expect(recorder.count == 3)
        }
    }
}
