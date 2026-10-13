import SwiftData
import SwiftUI

struct StartShiftPanel: View {
    let start: () -> Void
    var compact = false

    @Environment(\.locale) private var locale

    // Observed rather than read once, so a driver who changes vehicle in
    // Settings and comes back sees the new one without anything to refresh.
    // Reading them writes nothing: no settings row is created by looking.
    @Query private var vehicles: [VehicleProfile]
    @Query private var settingsRows: [DriverSettings]

    /// What the next shift will record, through the same rule the start copies.
    private var nextVehicle: NextShiftVehicleContext {
        NextShiftVehicleContext(
            defaults: SettingsService.fuelDefaults(settings: settingsRows.first, vehicles: vehicles)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? DashSpacing.md : DashSpacing.xl) {
            // The state, said once and quietly: there is nothing running.
            DashStatusLabel(title: "No shift in progress", symbol: "circle.dashed", tint: .secondary)

            // What starting now would record, as the block the button sits
            // under rather than a caption beside it.
            nextVehicleBlock

            Button(action: start) {
                Text("Start Shift")
                    .dashFont(.control)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .dashPrimaryAction()
            .controlSize(.large)
            .accessibilityIdentifier("startShiftButton")

            if !compact {
                Text("DashPilot records a shift's start and end times on this device.")
                    .dashFont(.supporting)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, compact ? 0 : DashSpacing.md)
    }

    /// The vehicle the shift about to be started will record.
    ///
    /// Titled for what it is, `Next shift records`, so the name under it reads
    /// as the assumption about to be copied rather than as a setting. With
    /// nothing selected it says so in the quieter role and blocks nothing: a
    /// shift started with nothing to copy records no assumptions, as it always
    /// has. A separate element from the button, so `Start Shift` stays the
    /// plain action it was.
    private var nextVehicleBlock: some View {
        let vehicle = nextVehicle

        return HStack(alignment: .firstTextBaseline, spacing: DashSpacing.md) {
            Image(systemName: "car.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DashSpacing.xs) {
                Text("Next shift records")
                    .dashFont(.eyebrow)
                    .foregroundStyle(.secondary)

                Text(vehicle.title)
                    .dashFont(vehicle.hasVehicle ? .title : .body)
                    // Secondary where none is selected, because an absence
                    // should not read with the weight of a fact.
                    .foregroundStyle(vehicle.hasVehicle ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = vehicle.detail(locale: locale) {
                    Text(detail)
                        .dashFont(.supporting)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(vehicle.spokenLabel)
        .accessibilityValue(vehicle.spokenValue(locale: locale))
        .accessibilityHint("Recorded on the shift when you start it. Change it in Settings.")
        .accessibilityIdentifier("nextShiftVehicle")
    }
}
