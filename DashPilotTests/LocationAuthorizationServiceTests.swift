import Foundation
import Testing
import UIKit
@testable import DashPilot

@MainActor
@Suite("Location authorization service")
struct LocationAuthorizationServiceTests {
    private func makeService(
        servicesEnabled: Bool = true,
        status: LocationAuthorizationStatus = .notDetermined,
        accuracy: LocationAccuracyAuthorization = .full
    ) -> (LocationAuthorizationService, StubLocationAuthorizationProvider) {
        let provider = StubLocationAuthorizationProvider(
            servicesEnabled: servicesEnabled,
            status: status,
            accuracy: accuracy
        )
        return (LocationAuthorizationService(provider: provider), provider)
    }

    // MARK: Initial state

    @Test("The service starts from whatever the platform already reports")
    func adoptsInitialAuthorization() {
        let (service, _) = makeService(status: .authorizedWhenInUse, accuracy: .reduced)

        #expect(service.authorization.status == .authorizedWhenInUse)
        #expect(service.authorization.grantedAccuracy == .reduced)
        #expect(service.authorization.isUsable)
    }

    @Test("A denied app starts denied and offers Settings")
    func adoptsDeniedState() {
        let (service, provider) = makeService(status: .denied)

        #expect(service.authorization.condition == .denied)
        #expect(service.authorization.recovery == .openSettings)
        #expect(provider.requestCount == 0, "Nothing is asked for merely by observing state")
    }

    @Test("A restricted app starts restricted with no recovery offered")
    func adoptsRestrictedState() {
        let (service, _) = makeService(status: .restricted)

        #expect(service.authorization.condition == .restricted)
        #expect(service.authorization.recovery == .none)
    }

    @Test("Location Services being off is reported even for an authorized app")
    func adoptsServicesDisabledState() {
        let (service, _) = makeService(servicesEnabled: false, status: .authorizedAlways)

        #expect(service.authorization.condition == .servicesDisabled)
        #expect(!service.authorization.isUsable)
    }

    @Test("An unrecognised platform status is carried through rather than flattened")
    func adoptsUnrecognisedState() {
        let (service, _) = makeService(status: .unrecognised(rawValue: 88))

        #expect(service.authorization.condition == .unrecognised(rawValue: 88))
        #expect(!service.authorization.isUsable)
    }

    // MARK: Requesting

    @Test("Requesting while not determined asks the platform exactly once")
    func requestsWhenNotDetermined() {
        let (service, provider) = makeService(status: .notDetermined)

        service.requestAuthorization()

        #expect(provider.requestCount == 1)
    }

    @Test("A denied app never re-asks, because iOS would not show the prompt")
    func doesNotRequestWhenDenied() {
        let (service, provider) = makeService(status: .denied)

        service.requestAuthorization()
        service.requestAuthorization()

        #expect(provider.requestCount == 0)
    }

    @Test(
        "Requesting is refused in every state that cannot show the prompt",
        arguments: [
            LocationAuthorizationStatus.denied,
            .restricted,
            .authorizedWhenInUse,
            .authorizedAlways,
            .unrecognised(rawValue: 5)
        ]
    )
    func doesNotRequestOutsideNotDetermined(status: LocationAuthorizationStatus) {
        let (service, provider) = makeService(status: status)

        service.requestAuthorization()

        #expect(provider.requestCount == 0)
    }

    @Test("A second request after the prompt has been answered is refused")
    func doesNotRequestTwiceAcrossAnAnswer() {
        let (service, provider) = makeService(status: .notDetermined)
        provider.authorizationAfterRequest = LocationAuthorization(
            servicesEnabled: true,
            status: .authorizedWhenInUse,
            accuracy: .full
        )

        service.requestAuthorization()
        service.requestAuthorization()

        #expect(provider.requestCount == 1)
        #expect(service.authorization.status == .authorizedWhenInUse)
    }

    @Test("Location Services being off does not block the first permission prompt")
    func requestsEvenWhenServicesDisabled() {
        // The system decides what to show; the app's rule is only that the
        // status is still undetermined.
        let (service, provider) = makeService(servicesEnabled: false, status: .notDetermined)

        service.requestAuthorization()

        #expect(provider.requestCount == 1)
    }

    // MARK: Change propagation

    @Test("Granting permission propagates to the service")
    func propagatesAGrant() {
        let (service, provider) = makeService(status: .notDetermined)

        provider.update(status: .authorizedWhenInUse)

        #expect(service.authorization.status == .authorizedWhenInUse)
        #expect(service.authorization.isUsable)
        #expect(service.authorization.recovery == .none)
    }

    @Test("Revoking permission propagates to the service")
    func propagatesARevocation() {
        let (service, provider) = makeService(status: .authorizedWhenInUse)

        provider.update(status: .denied)

        #expect(service.authorization.condition == .denied)
        #expect(!service.authorization.isUsable)
        #expect(service.authorization.recovery == .openSettings)
    }

    @Test("An accuracy change propagates without changing authorization")
    func propagatesAnAccuracyChange() {
        let (service, provider) = makeService(status: .authorizedWhenInUse, accuracy: .full)

        provider.update(accuracy: .reduced)

        #expect(service.authorization.status == .authorizedWhenInUse, "Still authorized")
        #expect(service.authorization.grantedAccuracy == .reduced)
        #expect(service.authorization.isUsable)
    }

    @Test("Location Services being switched off propagates to the service")
    func propagatesServicesBeingDisabled() {
        let (service, provider) = makeService(status: .authorizedWhenInUse)
        #expect(service.authorization.isUsable)

        provider.update(servicesEnabled: false)

        #expect(service.authorization.condition == .servicesDisabled)
        #expect(!service.authorization.isUsable)
    }

    @Test("The service follows a full sequence of platform changes")
    func propagatesASequenceOfChanges() {
        let (service, provider) = makeService(status: .notDetermined)

        provider.update(status: .authorizedWhenInUse, accuracy: .reduced)
        #expect(service.authorization.condition == .authorized(scope: .whenInUse, accuracy: .reduced))

        provider.update(accuracy: .full)
        #expect(service.authorization.condition == .authorized(scope: .whenInUse, accuracy: .full))

        provider.update(servicesEnabled: false)
        #expect(service.authorization.condition == .servicesDisabled)

        provider.update(servicesEnabled: true)
        #expect(service.authorization.condition == .authorized(scope: .whenInUse, accuracy: .full))

        provider.update(status: .denied)
        #expect(service.authorization.condition == .denied)
    }

    // MARK: Refresh

    @Test("Refreshing asks the provider to re-read platform state")
    func refreshReachesTheProvider() {
        let (service, provider) = makeService()
        #expect(provider.refreshCount == 0)

        service.refresh()

        #expect(provider.refreshCount == 1)
    }

    @Test("Refreshing does not request permission")
    func refreshDoesNotRequest() {
        let (service, provider) = makeService(status: .notDetermined)

        service.refresh()

        #expect(provider.requestCount == 0, "Returning to the app must never trigger the prompt")
    }

    // MARK: Settings recovery

    @Test("The Settings recovery offered for a denied app resolves to a real URL")
    func settingsURLIsUsable() {
        let (service, _) = makeService(status: .denied)
        #expect(service.authorization.recovery == .openSettings)
        #expect(URL(string: UIApplication.openSettingsURLString) != nil)
    }
}
