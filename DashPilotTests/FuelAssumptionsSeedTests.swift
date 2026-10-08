import Foundation
import Testing
@testable import DashPilot

/// What a finished shift's fuel editor opens on, and how Settings states the
/// current gas price.
///
/// Both were decided inside SwiftUI views and read only by UI journeys
/// (`testFuelAssumptionsSeedTheNextShiftAndItsNetNamesMissingEarnings`,
/// `testDefaultsAreRecordedAtStartAndNeverReachARecordedShift` and
/// `testSettingsStatesItsDefaultsAndRecordsTheGasPrice`). They are rules, so
/// they are pinned here instead. That a seeded field records nothing until
/// saved is `FuelAssumptionTests`; that the stored price keeps zero apart from
/// missing is `VehicleSettingsTests`.
///
/// Every figure here is invented.
@Suite("Fuel editor seed and gas price wording")
struct FuelAssumptionsSeedTests {
    private let locale = Locale(identifier: "en_US")
    private let recorded = FuelAssumptions(milesPerGallon: 30, gasPricePerGallon: Money(minorUnits: 289))
    private let defaults = FuelDefaults(vehicleName: "Test car", milesPerGallon: 34, gasPricePerGallon: Money(minorUnits: 319))
    private let recent = FuelAssumptions(milesPerGallon: 22, gasPricePerGallon: Money(minorUnits: 405))

    @Test("A shift's own recorded pair is what its editor opens on, and is not a suggestion")
    func recordedWins() {
        var askedForRecent = false
        let seed = FuelAssumptionsSeed.choose(recorded: recorded, currentDefaults: defaults) {
            askedForRecent = true
            return recent
        }
        #expect(seed == FuelAssumptionsSeed(assumptions: recorded, isSuggestion: false))
        #expect(!askedForRecent, "The store is not read for a suggestion nobody needs")
    }

    @Test("One recorded half is still the shift's own record")
    func oneRecordedHalfWins() {
        let half = FuelAssumptions(milesPerGallon: nil, gasPricePerGallon: Money(minorUnits: 299))
        let seed = FuelAssumptionsSeed.choose(recorded: half, currentDefaults: defaults) { recent }
        #expect(seed == FuelAssumptionsSeed(assumptions: half, isSuggestion: false))
    }

    @Test("With nothing recorded, the current defaults come before an older shift's pair")
    func defaultsBeforeHistory() {
        let seed = FuelAssumptionsSeed.choose(recorded: .none, currentDefaults: defaults) { recent }
        #expect(seed == FuelAssumptionsSeed(assumptions: defaults.assumptions, isSuggestion: true))
    }

    @Test("With no defaults either, the most recent shift's pair is suggested")
    func mostRecentLast() {
        let seed = FuelAssumptionsSeed.choose(recorded: .none, currentDefaults: .none) { recent }
        #expect(seed == FuelAssumptionsSeed(assumptions: recent, isSuggestion: true))
    }

    @Test("Nothing anywhere opens an empty editor that claims no suggestion")
    func nothingAnywhere() {
        let seed = FuelAssumptionsSeed.choose(recorded: .none, currentDefaults: .none) { .none }
        #expect(seed == FuelAssumptionsSeed(assumptions: .none, isSuggestion: false))
    }

    @Test("A recorded zero price is a seed like any other, never treated as missing")
    func zeroPriceIsRecorded() {
        let zero = FuelAssumptions(milesPerGallon: nil, gasPricePerGallon: .zero)
        let seed = FuelAssumptionsSeed.choose(recorded: zero, currentDefaults: defaults) { recent }
        #expect(seed.assumptions == zero)
        #expect(!seed.isSuggestion)
    }

    @Test("No gas price is Not set, a recorded zero is $0.00, and both say their unit aloud")
    func gasPriceWording() {
        #expect(CurrentGasPriceWording.statement(nil, locale: locale) == "Not set")
        #expect(CurrentGasPriceWording.spoken(nil, locale: locale) == "Not set")
        #expect(CurrentGasPriceWording.statement(.zero, locale: locale) == "$0.00 / gallon")
        #expect(CurrentGasPriceWording.spoken(.zero, locale: locale) == "$0.00 per gallon")
        #expect(CurrentGasPriceWording.statement(Money(minorUnits: 319), locale: locale) == "$3.19 / gallon")
        #expect(CurrentGasPriceWording.spoken(Money(minorUnits: 335), locale: locale) == "$3.35 per gallon")
    }
}
