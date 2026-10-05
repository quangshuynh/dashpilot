import SwiftData
import SwiftUI

/// Which deliveries of one offer the driver says share a pickup, and which
/// share a drop-off.
///
/// ## Why it lives under Correct Grouping
///
/// It is the same kind of correction as the rest of that screen: it restates a
/// relationship between deliveries already recorded, moves no lifecycle event,
/// and is reached from one small control rather than from every card. The offer
/// sheet asks the same two questions for a whole offer at the moment it is
/// recorded; this is where a driver says it for **some** of an offer, or takes
/// it back.
///
/// ## What it writes, and when
///
/// Nothing until Save, and then both answers in one write through
/// ``OfferCorrectionService/recordSharedStops(pickup:dropOff:in:)``. Each list
/// needs two deliveries or none; one alone is refused on screen before it can
/// be refused by the model. A stretch the driver has already parked for keeps
/// the deliveries it stored, so changing this while parked changes the next
/// Park and not the Resume that follows this one.
///
/// Every row is a 44-point control that names its delivery and says whether it
/// is chosen, so it can be answered by touch or by VoiceOver without reading the
/// rest of the screen.
struct SharedStopEditor: View {
    let offer: NumberedOffer

    /// Called once the answers are saved, so the list can return to itself.
    let saved: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var pickup: Set<UUID>
    @State private var dropOff: Set<UUID>
    @State private var message: String?

    private let recordedPickup: Set<UUID>
    private let recordedDropOff: Set<UUID>

    init(offer: NumberedOffer, saved: @escaping () -> Void) {
        self.offer = offer
        self.saved = saved
        let pickup = Self.sharing(.pickup, in: offer)
        let dropOff = Self.sharing(.dropOff, in: offer)
        recordedPickup = pickup
        recordedDropOff = dropOff
        _pickup = State(initialValue: pickup)
        _dropOff = State(initialValue: dropOff)
    }

    var body: some View {
        List {
            section(.pickup, selection: $pickup) {
                Text(
                    """
                    Collected at the same pickup. With Pick up orders with Park & Resume on, Park and \
                    Resume Driving mark these arrived and picked up together.
                    """
                )
            }
            section(.dropOff, selection: $dropOff) {
                Text(
                    """
                    Taken to the same drop-off. This only shows they belong together: two orders for \
                    one drop-off can still come from two pickups.
                    """
                )
            }

            Section {
                Button("Save", action: save)
                    .disabled(!canSave)
                    .accessibilityIdentifier("saveSharedStopsButton")
                if let message = message ?? oneChosenHint {
                    DashValidationMessage(message: message, identifier: "sharedStopsMessage")
                }
            } footer: {
                Text(
                    """
                    Choose two or more, or none. DashPilot stores no customer, address or place for this. \
                    Deliveries of different offers are marked with Edit Stack while the shift runs.
                    """
                )
            }
        }
        .navigationTitle("Same Pickup or Drop-off")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(
        _ kind: SharedStopKind,
        selection: Binding<Set<UUID>>,
        @ViewBuilder footer: () -> some View
    ) -> some View {
        Section {
            ForEach(offer.deliveries) { numbered in
                let isChosen = selection.wrappedValue.contains(numbered.id)
                Button {
                    if isChosen {
                        selection.wrappedValue.remove(numbered.id)
                    } else {
                        selection.wrappedValue.insert(numbered.id)
                    }
                    message = nil
                } label: {
                    HStack {
                        Text(numbered.title)
                            .dashFont(.body)
                        Spacer()
                        Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isChosen ? Color.accentColor : Color.secondary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(numbered.title), \(kind.title.lowercased())")
                .accessibilityValue(isChosen ? "Chosen" : "Not chosen")
                .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier(kind == .pickup ? "sharedPickupRow" : "sharedDropOffRow")
            }
        } header: {
            Text(kind.title)
        } footer: {
            footer()
        }
    }

    /// Why Save is not available yet, when the reason is one chosen alone.
    private var oneChosenHint: String? {
        let alone = [(SharedStopKind.pickup, pickup), (.dropOff, dropOff)].filter { $0.1.count == 1 }.map(\.0)
        guard let kind = alone.first else { return nil }
        return "Choose one more delivery for \(kind.title), or none."
    }

    /// Changed, and neither list names exactly one delivery.
    private var canSave: Bool {
        (pickup != recordedPickup || dropOff != recordedDropOff) && pickup.count != 1 && dropOff.count != 1
    }

    private func save() {
        let deliveries = Dictionary(uniqueKeysWithValues: offer.deliveries.map { ($0.id, $0.delivery) })
        do {
            func chosen(_ selection: Set<UUID>) -> [Delivery] {
                offer.deliveries.filter { selection.contains($0.id) }.compactMap { deliveries[$0.id] }
            }
            try OfferCorrectionService(context: modelContext).recordSharedStops(
                pickup: pickup == recordedPickup ? nil : chosen(pickup),
                dropOff: dropOff == recordedDropOff ? nil : chosen(dropOff),
                in: offer.offer
            )
            saved()
        } catch {
            message = (error as? any LocalizedError)?.errorDescription ?? "That could not be saved."
        }
    }

    /// The deliveries of `offer` that share a `kind` of stop with another of
    /// them, which is what the switches start from.
    private static func sharing(_ kind: SharedStopKind, in offer: NumberedOffer) -> Set<UUID> {
        let identities = offer.deliveries.compactMap { $0.delivery.sharedStopID(kind) }
        let shared = Set(identities.filter { identity in identities.filter { $0 == identity }.count > 1 })
        return Set(offer.deliveries.filter { $0.delivery.sharedStopID(kind).map(shared.contains) == true }.map(\.id))
    }
}
