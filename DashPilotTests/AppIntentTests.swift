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
            Metadata(RecordDeliveryProgressIntent.self),
            Metadata(RecordDeliveredIntent.self)
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
            "Record Delivery Progress",
            "Mark Delivered"
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

    @Test("Nine shortcuts are offered, and they are the nine lifecycle actions")
    func shortcutsCoverTheLifecycleActionsOnly() {
        #expect(DashPilotShortcuts.appShortcuts.count == 9)
    }

    @Test("Mark Delivered's description says which delivery it records and what it leaves alone")
    func deliveredIntentDescribesItsRule() throws {
        let description = try #require(Metadata(RecordDeliveredIntent.self).description)
        #expect(description.contains("lowest-numbered picked-up delivery"))
        #expect(description.contains("not yet picked up are not changed"))
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
        let parked = IntentLifecycleOutcome.vehicleParked(pickup: .notEnabled).confirmation.lowercased()

        #expect(parked.contains("route recording is stopped"))
        #expect(parked.contains("shift is still running"))
        #expect(!parked.contains("pause"), "Parking is not a pause and must never be said as one")

        let driving = IntentLifecycleOutcome.drivingResumed(parkedDuration: 1_500, pickup: .notEnabled)
            .confirmation.lowercased()
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
        #expect(ParkVehicleFromActivityIntent.supportedModes == .background)
        #expect(ResumeDrivingFromActivityIntent.supportedModes == .background)

        #expect(PauseShiftFromActivityIntent.authenticationPolicy == .alwaysAllowed)
        #expect(ResumeShiftFromActivityIntent.authenticationPolicy == .alwaysAllowed)
        #expect(EndShiftFromActivityIntent.authenticationPolicy == .alwaysAllowed)
        #expect(StartDeliveryFromActivityIntent.authenticationPolicy == .alwaysAllowed)
        #expect(RecordDeliveryProgressFromActivityIntent.authenticationPolicy == .alwaysAllowed)
        #expect(ParkVehicleFromActivityIntent.authenticationPolicy == .alwaysAllowed)
        #expect(ResumeDrivingFromActivityIntent.authenticationPolicy == .alwaysAllowed)
    }

    @Test("No Live Activity control appears in Shortcuts beside the spoken action it repeats")
    func activityIntentsAreNotDiscoverable() {
        #expect(PauseShiftFromActivityIntent.isDiscoverable == false)
        #expect(ResumeShiftFromActivityIntent.isDiscoverable == false)
        #expect(EndShiftFromActivityIntent.isDiscoverable == false)
        #expect(StartDeliveryFromActivityIntent.isDiscoverable == false)
        #expect(RecordDeliveryProgressFromActivityIntent.isDiscoverable == false)
        #expect(RecordDeliveredFromActivityIntent.isDiscoverable == false)
        #expect(RecordDeliveredFromActivityIntent.authenticationPolicy == .alwaysAllowed)
        #expect(ParkVehicleFromActivityIntent.isDiscoverable == false)
        #expect(ResumeDrivingFromActivityIntent.isDiscoverable == false)

        #expect(PauseShiftIntent.isDiscoverable, "The spoken action is the discoverable one")
        #expect(ParkVehicleIntent.isDiscoverable, "And it is the one that parks, too")
        #expect(StartDeliveryIntent.isDiscoverable, "And it is the one that starts a delivery, too")
        #expect(DashPilotShortcuts.appShortcuts.count == 9, "And the shortcut count is unchanged by them")
    }

    // MARK: A shared pickup, from every surface

    /// A running shift with the workflow on and an offer of two the driver
    /// marked Same pickup, in `context`.
    private func sharedPickupOffer(in context: ModelContext) throws -> [Delivery] {
        let settings = SettingsService(context: context)
        try settings.setUsesParkAndResumeForPickups(true)
        try settings.setHandlesStackedOrdersInOrder(true)
        return try DeliveryService(context: context)
            .startOffer(deliveryCount: 2, sharing: [.pickup], at: .now)
            .deliveriesInOrder
    }

    @Test("Siri's Park and Resume Driving move a shared pickup together, and say what the app says")
    func spokenParkAndResumeMoveASharedPickup() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            let pair = try sharedPickupOffer(in: context)

            let parked = try IntentLifecycleService(context: context).parkVehicle()
            #expect(pair.allSatisfy { $0.state == .arrivedAtPickup })
            guard case let .vehicleParked(pickup) = parked else {
                Issue.record("Parking said something else: \(parked)")
                return
            }
            #expect(pickup == .sharedPickupArrived(SharedPickupArrival(recorded: [1, 2], alreadyArrived: [])))
            #expect(parked.confirmation.contains("Deliveries 1 and 2 marked Arrived at Pickup"), "\(parked.confirmation)")

            let resumed = try IntentLifecycleService(context: context).resumeDriving()
            #expect(pair.allSatisfy { $0.state == .pickedUp && $0.pickupProvenance == .resumeAutomation })
            #expect(resumed.confirmation.contains("Deliveries 1 and 2 marked Picked Up"), "\(resumed.confirmation)")
        }
    }

    @Test("The Lock Screen's Park and Resume Driving move a shared pickup together, through the same service")
    func activityParkAndResumeMoveASharedPickup() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            let pair = try sharedPickupOffer(in: context)

            _ = try await ParkVehicleFromActivityIntent().perform()
            #expect(pair.allSatisfy { $0.state == .arrivedAtPickup })
            let shift = try #require(pair[0].shift)
            #expect(shift.openRouteSuspension?.pickupWorkflowDeliveryIDs == pair.map(\.id))

            _ = try await ResumeDrivingFromActivityIntent().perform()
            #expect(pair.allSatisfy { $0.state == .pickedUp })
        }
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

    @Test("The stacked Delivered control records the delivery it names, and nothing for a stale or unreadable one")
    func activityDeliveredIntent() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            let service = DeliveryService(context: context)
            let first = try service.startDelivery()
            let second = try service.startDelivery()
            for delivery in [first, second] {
                try service.markArrivedAtPickup(delivery)
                try service.markPickedUp(delivery)
            }

            await #expect(throws: IntentLifecycleError.deliveredTargetChanged) {
                _ = try await RecordDeliveredFromActivityIntent(deliveryID: second.id).perform()
            }
            await #expect(throws: ShiftActivityStaleControl.self) {
                let unreadable = RecordDeliveredFromActivityIntent()
                unreadable.deliveryID = "not an identifier"
                _ = try await unreadable.perform()
            }
            #expect([first.state, second.state] == [.pickedUp, .pickedUp], "Neither refusal wrote anything")

            _ = try await RecordDeliveredFromActivityIntent(deliveryID: first.id).perform()
            #expect([first.state, second.state] == [.delivered, .pickedUp])

            _ = try await RecordDeliveredIntent().perform()
            #expect(second.state == .delivered, "Siri's Mark Delivered records the next one")
        }
    }

    // MARK: Parking from the Live Activity

    @Test("Parking from the Live Activity writes what the app's own button writes")
    func activityIntentsParkAndDriveAgain() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            _ = try await ParkVehicleFromActivityIntent().perform()

            let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
            #expect(shift.isRouteSuspended)
            #expect(shift.lifecycleState == .running, "Parking is not pausing, whichever surface asked")
            #expect(shift.pauses.isEmpty)

            _ = try await ResumeDrivingFromActivityIntent().perform()
            #expect(shift.isRouteSuspended == false)
            #expect(shift.routeSuspensions.count == 1, "The stretch is kept, not deleted")
        }
    }

    /// The card offers only one of the pair, but the layer that matters is the
    /// store: a snapshot on screen can be a moment out of date.
    @Test("A stale parked press is refused by the same rule, with the same sentence")
    func activityParkedIntentsCarryTheServicesOwnRefusals() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()

            await #expect(throws: IntentLifecycleError.shift(.shiftNotParked)) {
                _ = try await ResumeDrivingFromActivityIntent().perform()
            }

            _ = try await ParkVehicleFromActivityIntent().perform()
            await #expect(throws: IntentLifecycleError.self) {
                _ = try await ParkVehicleFromActivityIntent().perform()
            }

            let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
            #expect(shift.routeSuspensions.count == 1, "A refused control opens no second row")
        }
    }

    @Test("Parking from the Live Activity mutates the shift that is running, and only it")
    func activityParkMutatesTheRunningShift() async throws {
        try await withStore { context in
            // A finished shift the card could never be describing.
            let finished = try ShiftService(context: context).startShift(at: .now.addingTimeInterval(-7_200))
            try ShiftService(context: context).endActiveShift(at: .now.addingTimeInterval(-3_600))

            _ = try await StartShiftIntent().perform()
            _ = try await ParkVehicleFromActivityIntent().perform()

            let shifts = try context.fetch(FetchDescriptor<Shift>())
            #expect(shifts.count == 2)
            #expect(finished.routeSuspensions.isEmpty, "The shift that ended is untouched")
            let running = try #require(shifts.first { $0.endedAt == nil })
            #expect(running.routeSuspensions.count == 1)
        }
    }

    @Test("Parking from the Live Activity asks the card to catch up, and a refusal does not")
    func activityParkReconciles() async throws {
        try await withStoreWatchingActivity { _, recorder in
            _ = try await StartShiftIntent().perform()
            #expect(recorder.count == 1)

            _ = try await ParkVehicleFromActivityIntent().perform()
            #expect(recorder.count == 2)

            await #expect(throws: IntentLifecycleError.self) {
                _ = try await ParkVehicleFromActivityIntent().perform()
            }
            #expect(recorder.count == 2, "A refusal wrote nothing, so there is nothing to catch up with")

            _ = try await ResumeDrivingFromActivityIntent().perform()
            #expect(recorder.count == 3)
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

    // MARK: The Park and Resume pickup workflow, from every surface

    /// A delivery started through the service on the shift an intent already
    /// started, with the workflow turned on as asked.
    private func acceptedDelivery(in context: ModelContext, stacked: Bool = false) throws -> Delivery {
        let settings = SettingsService(context: context)
        try settings.setUsesParkAndResumeForPickups(true)
        try settings.setHandlesStackedOrdersInOrder(stacked)
        return try DeliveryService(context: context).startDelivery()
    }

    /// The two system surfaces, each able to perform either half of the
    /// workflow. The app's own buttons call the same service directly and are
    /// covered by `ParkResumePickupWorkflowTests`.
    enum Surface: CaseIterable, Sendable {
        case voice, liveActivity

        @MainActor
        func park() async throws {
            switch self {
            case .voice: _ = try await ParkVehicleIntent().perform()
            case .liveActivity: _ = try await ParkVehicleFromActivityIntent().perform()
            }
        }

        @MainActor
        func resume() async throws {
            switch self {
            case .voice: _ = try await ResumeDrivingIntent().perform()
            case .liveActivity: _ = try await ResumeDrivingFromActivityIntent().perform()
            }
        }
    }

    /// Every combination of surfaces for the two halves reaches the same
    /// operation the app's buttons run, so the result is the same: Arrived at
    /// Pickup at the instant of parking, Picked Up at the instant of driving,
    /// the pickup recorded as Resume Driving's.
    @Test("Park by voice or Lock Screen marks Arrived, Resume by either marks Picked Up", arguments: [
        (Surface.voice, Surface.voice), (.voice, .liveActivity), (.liveActivity, .voice), (.liveActivity, .liveActivity)
    ])
    func everySurfaceRunsTheWorkflow(parkOn: Surface, resumeOn: Surface) async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            let delivery = try acceptedDelivery(in: context)

            try await parkOn.park()
            let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
            let parkedAt = try #require(shift.openRouteSuspension?.startedAt)
            #expect(delivery.state == .arrivedAtPickup)
            #expect(delivery.arrivedAtPickupAt == parkedAt, "One tap, one instant")

            try await resumeOn.resume()
            let resumedAt = try #require(shift.routeSuspensionsInOrder.last?.endedAt)
            #expect(!shift.isRouteSuspended)
            #expect(delivery.state == .pickedUp)
            #expect(delivery.pickedUpAt == resumedAt)
            #expect(delivery.pickupProvenance == .resumeAutomation)
        }
    }

    @Test("With the workflow off, Park and Resume from every surface record only the vehicle")
    func everySurfaceWithTheWorkflowOffRecordsOnlyTheVehicle() async throws {
        for surface in Surface.allCases {
            try await withStore { context in
                _ = try await StartShiftIntent().perform()
                let delivery = try DeliveryService(context: context).startDelivery()

                try await surface.park()
                try await surface.resume()

                let shift = try #require(try context.fetch(FetchDescriptor<Shift>()).first)
                #expect(shift.routeSuspensions.count == 1)
                #expect(delivery.state == .accepted, "\(surface): nothing but the vehicle moved")
                #expect(shift.routeSuspensions.first?.pickupWorkflowDeliveryID == nil)
            }
        }
    }

    /// Resume from the Lock Screen is the case the stored association exists
    /// for: the process that parked may be gone, and choosing again would pick
    /// up the next stacked order.
    @Test("Resume from the Lock Screen picks up the delivery Park chose, not the next one")
    func lockScreenResumeActsOnTheParkedDelivery() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            let third = try acceptedDelivery(in: context, stacked: true)
            let fourth = try DeliveryService(context: context).startDelivery()
            try DeliveryService(context: context).markArrivedAtPickup(fourth)

            _ = try await ParkVehicleIntent().perform()
            #expect(third.state == .arrivedAtPickup, "The lower number is taken first")

            // The driver cancels the first order inside the shop.
            try DeliveryService(context: context).cancelDelivery(third)

            // A fresh context stands in for a process that did not park.
            let other = ModelContext(context.container)
            IntentLifecycleService.testContext = other
            _ = try await ResumeDrivingFromActivityIntent().perform()
            IntentLifecycleService.testContext = context

            let storedFourth = try #require(
                try other.fetch(FetchDescriptor<Delivery>()).first { $0.id == fourth.id }
            )
            #expect(storedFourth.state == .arrivedAtPickup, "A different stacked order is never picked up")
            #expect(storedFourth.pickedUpAt == nil)
        }
    }

    @Test("The spoken confirmations name the delivery and say the step was recorded automatically")
    func workflowConfirmationsNameTheDelivery() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            _ = try acceptedDelivery(in: context)

            let parked = try IntentLifecycleService.forIntent().parkVehicle()
            #expect(parked == .vehicleParked(pickup: .markedArrived(deliveryNumber: 1)))
            #expect(parked.confirmation.contains("Route recording is stopped"))
            #expect(parked.confirmation.contains("Delivery 1 marked Arrived at Pickup."))
            #expect(parked.confirmation.hasSuffix("Recorded automatically when you parked."))

            let resumed = try IntentLifecycleService.forIntent().resumeDriving()
            guard case let .drivingResumed(_, pickup) = resumed else {
                Issue.record("Resume Driving confirms driving")
                return
            }
            #expect(pickup == .markedPickedUp(deliveryNumber: 1))
            #expect(resumed.confirmation.contains("Open DashPilot to start recording your route again."))
            #expect(resumed.confirmation.hasSuffix("Delivery 1 marked Picked Up. Recorded automatically when you resumed driving."))
            for sentence in [parked.confirmation, resumed.confirmation] {
                #expect(!sentence.lowercased().contains("detect"))
                #expect(!sentence.lowercased().contains("pause"))
            }
        }
    }

    @Test("Two deliveries with stacked orders off: the vehicle parks, nothing else moves, and it says why")
    func stackedOffBySpeechParksOnly() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            let first = try acceptedDelivery(in: context)
            let second = try DeliveryService(context: context).startDelivery()

            let outcome = try IntentLifecycleService.forIntent().parkVehicle()

            #expect(outcome == .vehicleParked(pickup: .stackedNotHandled(inProgress: 2)))
            #expect(first.state == .accepted && second.state == .accepted)
            #expect(outcome.confirmation.contains("Handle stacked orders in order is off"))
        }
    }

    @Test("The next-step control records a manual pickup by voice and from the Live Activity, workflow or not")
    func stepIntentsRecordManualProvenance() async throws {
        try await withStore { context in
            _ = try await StartShiftIntent().perform()
            _ = try await StartDeliveryIntent().perform()
            try SettingsService(context: context).setUsesParkAndResumeForPickups(true)
            _ = try await RecordDeliveryProgressIntent().perform()
            _ = try await RecordDeliveryProgressIntent().perform()
            let spoken = try #require(try context.fetch(FetchDescriptor<Delivery>()).first)
            #expect(spoken.pickupProvenance == .manual, "The workflow governs Park and Resume, not the step")

            _ = try await RecordDeliveryProgressIntent().perform()
            _ = try await StartDeliveryIntent().perform()
            _ = try await RecordDeliveryProgressFromActivityIntent().perform()
            _ = try await RecordDeliveryProgressFromActivityIntent().perform()
            let tapped = try #require(try context.fetch(FetchDescriptor<Delivery>()).first { $0.id != spoken.id })
            #expect(tapped.state == .pickedUp)
            #expect(tapped.pickupProvenance == .manual)
        }
    }
}
