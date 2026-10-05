import SwiftData
import SwiftUI

/// The driver's reusable preferences: the vehicles they work in, which one they
/// are working in now, what a gallon currently costs, and what parking may
/// record for them.
///
/// ## What this screen is, and the one sentence it has to get across
///
/// Everything here is a **default for the next shift**. Nothing on this screen
/// changes a shift the driver has already worked, and the footers say so in as
/// many words, because it is the one thing a driver could reasonably assume the
/// other way: typing a new gas price looks like correcting a figure, and it is
/// not.
///
/// The figures are copied onto a shift when it starts, and from that moment the
/// shift owns its copy. See ``FuelDefaults``.
///
/// ## Why it is a preferences surface rather than another delivery action
///
/// It is reached from a gear in the navigation bar, which is where a phone
/// keeps preferences, and it is deliberately not a row in the list a driver
/// opens the app to read: a setting is something they touch when they change
/// vehicle or notice the price has moved, which is a stopped-vehicle task and a
/// rare one. The bar also costs the History list no height, which every row
/// added to the main screen does.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ShiftLiveActivityService.self) private var liveActivity
    @Environment(\.locale) private var locale

    /// Oldest first: the order the driver added them, which does not move when
    /// one is renamed.
    @Query(sort: \VehicleProfile.createdAt, order: .forward)
    private var vehicles: [VehicleProfile]

    /// The settings row, if one exists yet. A driver who has never changed a
    /// setting has none, and this screen draws perfectly well without it.
    @Query private var settingsRows: [DriverSettings]

    @State private var editingVehicle: VehicleEditorSubject?
    @State private var isEditingGasPrice = false
    @State private var isEditingTarget = false
    @State private var isShowingWelcome = false
    @State private var failure: String?

    private var settings: DriverSettings? { settingsRows.first }

    private var selectedVehicleID: UUID? { settings?.selectedVehicleID }

    private var gasPrice: Money? { settings?.gasPricePerGallon }

    /// The profile new shifts copy from, resolved from the two queries this
    /// screen already holds rather than by fetching again. A selection naming a
    /// profile that no longer exists resolves to none, which is what a deleted
    /// profile means.
    private var selectedVehicle: VehicleProfile? {
        guard let selectedVehicleID else { return nil }
        return vehicles.first { $0.id == selectedVehicleID }
    }

    var body: some View {
        List {
            defaultVehicleSection
            vehiclesSection
            fuelSection
            targetSection
            pickupWorkflowSection
            aboutSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingVehicle) { subject in
            VehicleProfileEditor(vehicle: subject.vehicle)
        }
        .sheet(isPresented: $isEditingGasPrice) {
            CurrentGasPriceEditor()
        }
        .sheet(isPresented: $isEditingTarget) {
            HourlyTargetEditor()
        }
        .alert(
            "Setting Not Changed",
            isPresented: isShowingFailure,
            presenting: failure
        ) { _ in
            Button("OK", role: .cancel) { failure = nil }
        } message: { message in
            Text(message)
        }
    }

    /// Which vehicle the next shift will record, said first and on its own.
    ///
    /// "Next shift" is the whole claim: a shift already running copied its
    /// vehicle when it started and keeps it, so nothing here says or implies
    /// that changing this moves one. With nothing selected the section says what
    /// that means for the next shift rather than showing an empty card, and
    /// starting a shift is never refused over it.
    private var defaultVehicleSection: some View {
        Section {
            if let selectedVehicle {
                VStack(alignment: .leading, spacing: DashSpacing.sm) {
                    Text(selectedVehicle.name)
                        .dashFont(.title)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(economyStatement(for: selectedVehicle))
                        .dashFont(.metric)
                    Text("Used for your next shift")
                        .dashFont(.supporting)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, DashSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    """
                    Default vehicle: \(selectedVehicle.name), \(spokenEconomy(for: selectedVehicle)). \
                    Used for your next shift.
                    """
                )
                .accessibilityIdentifier("defaultVehicleSummary")
            } else {
                DashNotice(
                    title: "No vehicle selected",
                    message: "Your next shift records no miles per gallon.",
                    symbol: "car"
                )
                .accessibilityIdentifier("noDefaultVehicleNotice")
            }
        } header: {
            Text("Default Vehicle")
        }
    }

    private var vehiclesSection: some View {
        Section {
            if vehicles.isEmpty {
                DashNotice(
                    title: "No vehicles yet",
                    message: "Add the one you deliver in, so its miles per gallon is typed once."
                )
                .accessibilityIdentifier("vehiclesEmptyState")
            } else {
                ForEach(vehicles) { vehicle in
                    VehicleRow(
                        vehicle: vehicle,
                        isSelected: vehicle.id == selectedVehicleID,
                        locale: locale,
                        select: { select(vehicle) },
                        edit: { editingVehicle = .existing(vehicle) }
                    )
                }
            }

            Button {
                editingVehicle = .new
            } label: {
                Label("Add Vehicle", systemImage: "plus")
                    .dashFont(.body)
            }
            .accessibilityLabel("Add a vehicle")
            .accessibilityIdentifier("addVehicleButton")
        } header: {
            Text("Vehicles")
        } footer: {
            Text(vehiclesFooter)
        }
    }

    /// The current gas price, which is a default for shifts not yet started.
    ///
    /// A recorded price of zero is a price, and is drawn as `$0.00` with the
    /// weight of any other figure; only a price that was never set reads
    /// `Not set`.
    private var fuelSection: some View {
        Section {
            Button {
                isEditingGasPrice = true
            } label: {
                DashValueRow(
                    title: "Current gas price",
                    value: gasPriceStatement,
                    detail: "Recorded on your next shift",
                    isFigure: gasPrice != nil
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Current gas price")
            .accessibilityValue(spokenGasPrice)
            .accessibilityHint("Changes what your next shift records. Shifts you have already worked keep their own.")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("currentGasPriceRow")
        } header: {
            Text("Fuel Defaults")
        } footer: {
            Text("What you last paid per gallon. A change applies to your next shift, never to one already worked. DashPilot looks up no prices.")
        }
    }

    /// The driver's own benchmark for gross earnings per working hour, which
    /// the next shift records when it starts.
    ///
    /// `Not set` when there is none, never `$0.00`: no target is not a target
    /// of nothing, and a shift started without one is compared with nothing.
    private var targetSection: some View {
        let target = settings?.hourlyTarget
        return Section {
            Button {
                isEditingTarget = true
            } label: {
                DashValueRow(
                    title: "Target hourly earnings",
                    value: target.map { "\($0.formatted(locale: locale)) / working hour" } ?? "Not set",
                    detail: "Recorded on your next shift",
                    isFigure: target != nil
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Target hourly earnings")
            .accessibilityValue(target.map { "\($0.formatted(locale: locale)) per working hour" } ?? "Not set")
            .accessibilityHint("Changes what your next shift is compared with. Shifts you have already worked keep their own.")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("hourlyTargetRow")
        } header: {
            Text("Personal Target")
        } footer: {
            Text(
                """
                Optional. Finished shifts compare their gross earnings per working hour with the \
                target they started with. It is your benchmark, not what a shift should pay.
                """
            )
        }
    }

    /// What parking may record for the driver: a pickup through Park and
    /// Resume Driving, stacked orders in order, and driving again after a step
    /// recorded while parked.
    ///
    /// All three off until the driver turns them on, including for a driver who
    /// has never opened this screen and has no settings row at all. Each says
    /// what it does in one line under its own name, rather than one paragraph
    /// for the group, so the line a driver reads is the one beside the switch
    /// they are about to touch. The stacked-order switch depends on the
    /// workflow and is drawn under it, disabled while the workflow is off and
    /// keeping its own answer, with a line saying **why** it is unavailable; the
    /// resume switch depends on nothing and says so by being on its own.
    private var pickupWorkflowSection: some View {
        let workflowOn = settings?.usesParkAndResumeForPickups ?? false
        return Section {
            DashSettingToggle(
                isOn: usesParkAndResumeForPickups,
                title: PickupWorkflowNotice.settingName,
                detail: "Park marks Arrived at Pickup; Resume Driving marks Picked Up.",
                hint: """
                    When on, Park Vehicle marks the delivery you are picking up Arrived at Pickup, and Resume \
                    Driving marks it Picked Up.
                    """,
                identifier: "pickupWorkflowToggle"
            )

            DashSettingToggle(
                isOn: handlesStackedOrdersInOrder,
                isDependent: true,
                isAvailable: workflowOn,
                title: "Handle stacked orders in order",
                detail: workflowOn
                    ? "With several orders, Park works on the lowest-numbered one still to collect."
                    : "Needs \(PickupWorkflowNotice.settingName) on.",
                hint: workflowOn
                    ? "When on, with more than one delivery in progress, Park works on the lowest-numbered delivery still waiting for its pickup."
                    : "Unavailable until \(PickupWorkflowNotice.settingName) is on. Your choice is kept.",
                identifier: "stackedOrdersInOrderToggle"
            )

            DashSettingToggle(
                isOn: resumesDrivingAfterDeliveryProgress,
                title: ParkedProgressOutcome.settingName,
                detail: "When you record Picked Up or Delivered while parked, resume route recording once that stop has nothing left.",
                hint: """
                    When on, recording Picked Up or Delivered while the vehicle is parked resumes route recording \
                    once no order you marked Same pickup or Same drop-off, and no other order, still needs that \
                    stop. It never resumes a paused shift. Works with or without the pickup workflow.
                    """,
                identifier: "resumeAfterProgressToggle"
            )
        } header: {
            Text("Pickup & Parking")
        } footer: {
            Text(
                """
                These act on your taps; DashPilot does not know where you are. Undo, shown for a few \
                seconds, takes back what a tap recorded. Pickups Resume Driving records are left out of \
                typical pickup waits.
                """
            )
        }
    }

    /// The resume-after-progress switch, read from the row and written through
    /// the service. Nothing on the Lock Screen depends on it: Resume Driving
    /// leads the card whenever the vehicle is parked, whoever closes the
    /// stretch.
    private var resumesDrivingAfterDeliveryProgress: Binding<Bool> {
        Binding(
            get: { settings?.resumesDrivingAfterDeliveryProgress ?? false },
            set: { isEnabled in
                do {
                    try SettingsService(context: modelContext).setResumesDrivingAfterDeliveryProgress(isEnabled)
                } catch {
                    failure = (error as? any LocalizedError)?.errorDescription
                        ?? "The resume driving setting could not be changed."
                }
            }
        )
    }

    /// The workflow switch, read from the row and written through the service.
    private var usesParkAndResumeForPickups: Binding<Bool> {
        Binding(
            get: { settings?.usesParkAndResumeForPickups ?? false },
            set: { isEnabled in
                do {
                    try SettingsService(context: modelContext).setUsesParkAndResumeForPickups(isEnabled)
                } catch {
                    failure = (error as? any LocalizedError)?.errorDescription
                        ?? "The pickup workflow setting could not be changed."
                }
                // The Live Activity puts Park Vehicle first while this is on, so
                // a running shift's card follows the switch now rather than at
                // its next delivery step.
                liveActivity.reconcile()
            }
        )
    }

    /// The stacked-order switch, read from the row and written through the
    /// service.
    private var handlesStackedOrdersInOrder: Binding<Bool> {
        Binding(
            get: { settings?.handlesStackedOrdersInOrder ?? false },
            set: { isEnabled in
                do {
                    try SettingsService(context: modelContext).setHandlesStackedOrdersInOrder(isEnabled)
                } catch {
                    failure = (error as? any LocalizedError)?.errorDescription
                        ?? "The stacked orders setting could not be changed."
                }
            }
        )
    }

    /// Where DashPilot's parts come from, and the licenses they are under.
    private var aboutSection: some View {
        Section {
            Button {
                isShowingWelcome = true
            } label: {
                Label("Welcome to DashPilot", systemImage: "hand.wave")
                    .dashFont(.body)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityHint("Opens the introduction you saw when you first started DashPilot.")
            .accessibilityIdentifier("reopenOnboardingButton")
            .fullScreenCover(isPresented: $isShowingWelcome) {
                OnboardingView(context: .revisit) { isShowingWelcome = false }
            }

            NavigationLink {
                AcknowledgementsView()
            } label: {
                Label("Acknowledgements", systemImage: "doc.text")
                    .dashFont(.body)
            }
            .accessibilityIdentifier("acknowledgementsLink")
        } header: {
            Text("About")
        }
    }

    private func economyStatement(for vehicle: VehicleProfile) -> String {
        "\(MilesPerGallonInput(locale: locale).text(for: vehicle.milesPerGallon)) MPG"
    }

    private func spokenEconomy(for vehicle: VehicleProfile) -> String {
        "\(MilesPerGallonInput(locale: locale).text(for: vehicle.milesPerGallon)) miles per gallon"
    }

    /// What the vehicles section means, in the state it is actually in.
    ///
    /// Three sentences at most, and the middle one is the load-bearing one: an
    /// edit or a delete here is not a correction to anything recorded.
    private var vehiclesFooter: String {
        let stability = """
            Each shift records the default vehicle's miles per gallon when it starts. Editing or \
            deleting a vehicle changes your next shift, never one already worked.
            """
        if vehicles.isEmpty {
            return stability
        }
        return "Tap a vehicle to make it the default, and tap the default again to clear it. \(stability)"
    }

    private var gasPriceStatement: String {
        guard let gasPrice else { return "Not set" }
        return "\(gasPrice.formatted(locale: locale)) / gallon"
    }

    private var spokenGasPrice: String {
        guard let gasPrice else { return "Not set" }
        return "\(gasPrice.formatted(locale: locale)) per gallon"
    }

    private var isShowingFailure: Binding<Bool> {
        Binding(
            get: { failure != nil },
            set: { isShowing in if !isShowing { failure = nil } }
        )
    }

    /// Selects a vehicle, or clears the selection when the selected one is
    /// tapped again.
    ///
    /// Tapping the selected vehicle clearing it is deliberate: without that
    /// there is no way back to "no vehicle selected" short of deleting the
    /// profile, and a driver who has stopped using the app's estimates should
    /// not have to delete a record to say so.
    private func select(_ vehicle: VehicleProfile) {
        do {
            try SettingsService(context: modelContext)
                .selectVehicle(vehicle.id == selectedVehicleID ? nil : vehicle)
        } catch {
            failure = (error as? any LocalizedError)?.errorDescription
                ?? "That vehicle could not be selected."
        }
    }
}

/// One vehicle in the list: its name, its fuel economy, whether it is the one
/// new shifts are recorded under, and a way to correct it.
///
/// Two controls rather than one row that does both, because they answer
/// different questions and one of them is a write the driver may not have meant.
/// The row selects; the trailing control edits.
private struct VehicleRow: View {
    let vehicle: VehicleProfile
    let isSelected: Bool
    let locale: Locale
    let select: () -> Void
    let edit: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: DashSpacing.lg) {
            Button(action: select) {
                VStack(alignment: .leading, spacing: DashSpacing.xs) {
                    Text(vehicle.name)
                        .dashFont(.emphasis)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(economyStatement)
                        .dashFont(.body)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    // The default is said in words beside a symbol, never by a
                    // tint or a mark alone.
                    if isSelected {
                        DashStatusLabel(title: "Default", symbol: "checkmark.circle.fill", tint: .accentColor)
                    }
                }
                // The whole row, including the space between its lines: a plain
                // button is hit-testable only where its content draws.
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLabel)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint(
                isSelected
                    ? "Stops recording new shifts under this vehicle."
                    : "Makes this the vehicle new shifts are recorded under."
            )
            .accessibilityIdentifier("vehicleRow")

            Button(action: edit) {
                Image(systemName: "pencil")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Edit \(vehicle.name)")
            .accessibilityIdentifier("editVehicleButton")
        }
    }

    private var economyStatement: String {
        "\(MilesPerGallonInput(locale: locale).text(for: vehicle.milesPerGallon)) MPG"
    }

    /// The name, the figure with its unit spoken in full, and the selection.
    ///
    /// "MPG" is spelled out, because a metric has to say its unit to a listener
    /// who has no caption in view, and the selection is stated rather than left
    /// to a mark nobody can see.
    private var spokenLabel: String {
        let economy = MilesPerGallonInput(locale: locale).text(for: vehicle.milesPerGallon)
        let selection = isSelected ? "Selected as the default vehicle. " : ""
        return "\(selection)\(vehicle.name), \(economy) miles per gallon"
    }
}

/// Which vehicle a sheet is editing: an existing one, or one being created.
///
/// The same shape ``ExpenseListView`` uses, and for the same reason: `sheet(item:)`
/// needs one identifiable value covering both cases.
private enum VehicleEditorSubject: Identifiable {
    case new
    case existing(VehicleProfile)

    var id: String {
        switch self {
        case .new: "new"
        case let .existing(vehicle): vehicle.id.uuidString
        }
    }

    var vehicle: VehicleProfile? {
        switch self {
        case .new: nil
        case let .existing(vehicle): vehicle
        }
    }
}

#if DEBUG
#Preview("Settings with vehicles") {
    PreviewSupport.settingsView(withVehicles: true)
}

#Preview("Settings with nothing recorded") {
    PreviewSupport.settingsView(withVehicles: false)
}
#endif
