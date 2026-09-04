import CoreLocation
import Foundation
import Testing
@testable import DashPilot

@Suite("Location authorization state")
struct LocationAuthorizationTests {
    private func authorization(
        servicesEnabled: Bool = true,
        status: LocationAuthorizationStatus = .notDetermined,
        accuracy: LocationAccuracyAuthorization = .full
    ) -> LocationAuthorization {
        LocationAuthorization(servicesEnabled: servicesEnabled, status: status, accuracy: accuracy)
    }

    // MARK: Conditions

    @Test("Not determined is reported as its own condition, not as a denial")
    func notDeterminedCondition() {
        let state = authorization(status: .notDetermined)
        #expect(state.condition == .notDetermined)
        #expect(!state.isUsable)
    }

    @Test("Denied is reported as denied")
    func deniedCondition() {
        #expect(authorization(status: .denied).condition == .denied)
        #expect(!authorization(status: .denied).isUsable)
    }

    @Test("Restricted is distinct from denied")
    func restrictedCondition() {
        let restricted = authorization(status: .restricted)
        #expect(restricted.condition == .restricted)
        #expect(restricted.condition != .denied)
        #expect(!restricted.isUsable)
    }

    @Test("When In Use is authorized and usable")
    func whenInUseCondition() {
        let state = authorization(status: .authorizedWhenInUse, accuracy: .full)
        #expect(state.condition == .authorized(scope: .whenInUse, accuracy: .full))
        #expect(state.isUsable)
    }

    @Test("Always is represented separately from When In Use")
    func alwaysCondition() {
        let state = authorization(status: .authorizedAlways, accuracy: .full)
        #expect(state.condition == .authorized(scope: .always, accuracy: .full))
        #expect(state.isUsable)
        #expect(state.condition != .authorized(scope: .whenInUse, accuracy: .full))
    }

    @Test("An unrecognised platform status never reads as a grant")
    func unrecognisedStatusIsNotAGrant() {
        let state = authorization(status: .unrecognised(rawValue: 99))
        #expect(state.condition == .unrecognised(rawValue: 99))
        #expect(!state.status.grantsAccess)
        #expect(!state.isUsable)
        #expect(state.grantedAccuracy == nil)
    }

    // MARK: Services availability

    @Test("Location Services being off makes an authorized app unusable")
    func servicesDisabledOverridesAuthorization() {
        let state = authorization(servicesEnabled: false, status: .authorizedWhenInUse)
        #expect(state.condition == .servicesDisabled)
        #expect(!state.isUsable, "Authorization alone is not enough when the system switch is off")
        #expect(state.status == .authorizedWhenInUse, "The app's own grant is still recorded")
    }

    @Test("Location Services being off is reported even when the app was never asked")
    func servicesDisabledWithNotDeterminedStatus() {
        #expect(authorization(servicesEnabled: false, status: .notDetermined).condition == .servicesDisabled)
    }

    @Test("A restriction outranks Location Services being off")
    func restrictedOutranksServicesDisabled() {
        // Turning Location Services on would still leave this app without
        // permission, so the restriction is what the driver must be told about.
        let state = authorization(servicesEnabled: false, status: .restricted)
        #expect(state.condition == .restricted)
    }

    // MARK: Accuracy

    @Test("Accuracy is tracked independently of authorization")
    func reducedAccuracyIsStillAuthorized() {
        let state = authorization(status: .authorizedWhenInUse, accuracy: .reduced)
        #expect(state.isUsable, "Reduced accuracy is a granted state, not a refusal")
        #expect(state.condition == .authorized(scope: .whenInUse, accuracy: .reduced))
        #expect(state.grantedAccuracy == .reduced)
    }

    @Test("Full accuracy is exposed when granted")
    func fullAccuracyIsExposed() {
        #expect(authorization(status: .authorizedWhenInUse, accuracy: .full).grantedAccuracy == .full)
    }

    @Test("Accuracy reported before permission is granted is not treated as a grant")
    func accuracyIsSuppressedWithoutAuthorization() {
        // Core Location reports full accuracy by default before the user has
        // been asked; surfacing that would claim precision the app does not have.
        #expect(authorization(status: .notDetermined, accuracy: .full).grantedAccuracy == nil)
        #expect(authorization(status: .denied, accuracy: .full).grantedAccuracy == nil)
        #expect(authorization(status: .restricted, accuracy: .full).grantedAccuracy == nil)
    }

    @Test("An unrecognised accuracy value is preserved rather than guessed at")
    func unrecognisedAccuracy() {
        let state = authorization(status: .authorizedWhenInUse, accuracy: .unrecognised(rawValue: 7))
        #expect(state.grantedAccuracy == .unrecognised(rawValue: 7))
        #expect(state.condition == .authorized(scope: .whenInUse, accuracy: .unrecognised(rawValue: 7)))
    }

    // MARK: Requesting

    @Test("Permission may only be requested while the status is not determined")
    func onlyNotDeterminedCanBeRequested() {
        #expect(authorization(status: .notDetermined).canRequestAuthorization)

        for status: LocationAuthorizationStatus in [
            .denied, .restricted, .authorizedWhenInUse, .authorizedAlways, .unrecognised(rawValue: 42)
        ] {
            #expect(
                !authorization(status: status).canRequestAuthorization,
                "iOS shows the prompt once; \(status) must not offer to ask again"
            )
        }
    }

    @Test("A not-determined status can still be requested while Location Services is off")
    func requestableEvenWithServicesOff() {
        // The prompt is gated on the app's own status, not the system switch.
        #expect(authorization(servicesEnabled: false, status: .notDetermined).canRequestAuthorization)
    }

    // MARK: Recovery

    @Test("Not determined recovers by asking for permission")
    func notDeterminedRecovery() {
        #expect(authorization(status: .notDetermined).recovery == .requestAuthorization)
    }

    @Test("Denied recovers through the app's Settings page")
    func deniedRecovery() {
        #expect(authorization(status: .denied).recovery == .openSettings)
    }

    @Test("Restricted offers no recovery, because the driver has none")
    func restrictedRecovery() {
        #expect(authorization(status: .restricted).recovery == .none)
        #expect(authorization(servicesEnabled: false, status: .restricted).recovery == .none)
    }

    @Test("Services disabled points at Location Services rather than the app's own page")
    func servicesDisabledRecovery() {
        // Opening the app's Settings page would not show the system-wide switch.
        let state = authorization(servicesEnabled: false, status: .denied)
        #expect(state.recovery == .enableLocationServices)
        #expect(state.recovery != .openSettings)
    }

    @Test("An authorized app is offered no recovery action")
    func authorizedRecovery() {
        #expect(authorization(status: .authorizedWhenInUse).recovery == .none)
        #expect(authorization(status: .authorizedWhenInUse, accuracy: .reduced).recovery == .none)
        #expect(authorization(status: .authorizedAlways).recovery == .none)
    }

    @Test("An unrecognised status offers no recovery action")
    func unrecognisedRecovery() {
        #expect(authorization(status: .unrecognised(rawValue: 99)).recovery == .none)
    }

    // MARK: Core Location mapping

    @Test(
        "Core Location statuses map onto the app's states",
        arguments: [
            (CLAuthorizationStatus.notDetermined, LocationAuthorizationStatus.notDetermined),
            (.denied, .denied),
            (.restricted, .restricted),
            (.authorizedWhenInUse, .authorizedWhenInUse),
            (.authorizedAlways, .authorizedAlways)
        ]
    )
    func statusMapping(platform: CLAuthorizationStatus, expected: LocationAuthorizationStatus) {
        #expect(LocationAuthorizationStatus(platform) == expected)
    }

    @Test(
        "Core Location accuracy maps onto the app's states",
        arguments: [
            (CLAccuracyAuthorization.fullAccuracy, LocationAccuracyAuthorization.full),
            (.reducedAccuracy, .reduced)
        ]
    )
    func accuracyMapping(platform: CLAccuracyAuthorization, expected: LocationAccuracyAuthorization) {
        #expect(LocationAccuracyAuthorization(platform) == expected)
    }

    @Test("Only the two authorized Core Location statuses grant access")
    func onlyAuthorizedStatusesGrantAccess() {
        let granting: [CLAuthorizationStatus] = [.authorizedWhenInUse, .authorizedAlways]
        let withholding: [CLAuthorizationStatus] = [.notDetermined, .denied, .restricted]

        for status in granting {
            #expect(LocationAuthorizationStatus(status).grantsAccess)
        }
        for status in withholding {
            #expect(!LocationAuthorizationStatus(status).grantsAccess)
        }
    }
}
