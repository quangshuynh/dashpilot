import SwiftData
import SwiftUI

/// Which deliveries in progress share a pickup or a drop-off, corrected while
/// the shift runs, across the offers they were recorded in.
///
/// ## Why it exists
///
/// On a real shift (October 3 2026) two deliveries had been started one at a
/// time, and only once parked did the driver see they were collected at one
/// counter. The only correction was to cancel both and record them again as
/// one offer, which threw away their acceptance times and cost a stop's worth
/// of tapping. This sheet says it instead: choose the deliveries, then Same
/// Pickup or Same Drop-off.
///
/// ## What it writes, and what it never does
///
/// Each action is one write through
/// ``OfferCorrectionService/editSharedStops(_:_:of:on:)``: the deliveries'
/// shared-stop identities and nothing else. No delivery is cancelled,
/// recreated or renumbered, no offer changes, no lifecycle event is recorded
/// and no amount moves. Marking a delivery that was already picked up as
/// sharing a pickup says where it was collected; it records nothing for the
/// other one.
///
/// ## Where it sits
///
/// Behind one small control under the cards, shown only while two or more
/// deliveries are in progress, so the cards themselves stay as quiet as they
/// were and the next lifecycle step stays the most prominent thing on them.
/// Every row and action is at least 44 points tall and names its subject.
struct StackEditorView: View {
    let shift: Shift

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selection: Set<UUID> = []
    @State private var message: String?
    @State private var isRefusal = false

    private var inProgress: [NumberedDelivery] { shift.numberedActiveDeliveries }

    private var chosen: [NumberedDelivery] { inProgress.filter { selection.contains($0.id) } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(inProgress) { numbered in
                        row(numbered)
                    }
                } header: {
                    Text("Deliveries in Progress")
                } footer: {
                    Text("Choose the deliveries a change applies to.")
                }

                actions(.pickup)
                actions(.dropOff)

                if let message {
                    Section {
                        if isRefusal {
                            DashValidationMessage(message: message, identifier: "stackEditMessage")
                        } else {
                            // The symbol is hidden and the identifier is on the
                            // sentence alone: a `Label` mirrors an identifier
                            // onto its icon, which is the trap
                            // `DashValidationMessage` describes.
                            HStack(alignment: .firstTextBaseline, spacing: DashSpacing.md) {
                                Image(systemName: "checkmark.circle")
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityHidden(true)
                                Text(message)
                                    .dashFont(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("stackEditMessage")
                            }
                        }
                    }
                }

                Section {
                    Text(
                        """
                        Only what you choose is recorded. Nothing is marked arrived, picked up or delivered, \
                        no delivery is cancelled or renumbered, and no offer changes. With Pick up orders with \
                        Park & Resume on, the next Park moves deliveries marked Same pickup together.
                        """
                    )
                    .dashFont(.supporting)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle("Edit Stack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("doneEditingStackButton")
                }
            }
        }
    }

    /// One delivery: its name and state, what it already shares, and whether
    /// it is chosen, in words as well as a mark.
    private func row(_ numbered: NumberedDelivery) -> some View {
        let isChosen = selection.contains(numbered.id)
        let shared = numbered.sharedStops
        return Button {
            if isChosen { selection.remove(numbered.id) } else { selection.insert(numbered.id) }
            message = nil
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: DashSpacing.md) {
                Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isChosen ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DashSpacing.xs) {
                    Text(numbered.title)
                        .dashFont(.emphasis)
                    Text(numbered.delivery.state.statusDescription)
                        .dashFont(.supporting)
                        .foregroundStyle(.secondary)
                    if let caption = shared.caption {
                        Label(caption, systemImage: "link")
                            .labelStyle(DashCompactLabelStyle())
                            .dashFont(.supporting)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [numbered.title, numbered.delivery.state.statusDescription, shared.spokenCaption]
                .compactMap { $0 }
                .joined(separator: ". ")
        )
        .accessibilityValue(isChosen ? "Chosen" : "Not chosen")
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("stackDeliveryRow")
    }

    /// The two things a driver can say about one kind of stop for the chosen
    /// deliveries: that they share it, or that they do not.
    private func actions(_ kind: SharedStopKind) -> some View {
        let canJoin = chosen.count > 1
        let canSeparate = chosen.contains { $0.delivery.sharedStopID(kind) != nil }
        return Section {
            Button {
                apply(.join, kind)
            } label: {
                Label("Mark \(kind.title)", systemImage: "link")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .disabled(!canJoin)
            .accessibilityHint(canJoin ? "" : "Choose two or more deliveries first")
            .accessibilityIdentifier(kind == .pickup ? "markSamePickupButton" : "markSameDropOffButton")

            Button {
                apply(.separate, kind)
            } label: {
                Label("Not \(kind.title)", systemImage: "personalhotspot.slash")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .disabled(!canSeparate)
            .accessibilityIdentifier(kind == .pickup ? "separatePickupButton" : "separateDropOffButton")
        } header: {
            Text(kind.title)
        }
    }

    private func apply(_ edit: SharedStopEdit, _ kind: SharedStopKind) {
        let names = SharedStopDescription.list(chosen.map(\.title))
        do {
            try OfferCorrectionService(context: modelContext).editSharedStops(
                edit, kind, of: chosen.map(\.delivery), on: shift
            )
            isRefusal = false
            message = switch edit {
            case .join: "\(names) marked \(kind.title.lowercased())."
            case .separate: "\(names) no longer marked \(kind.title.lowercased())."
            }
            selection = []
        } catch {
            isRefusal = true
            message = (error as? any LocalizedError)?.errorDescription ?? "That could not be saved."
        }
    }
}

#if DEBUG
#Preview("Edit stack") {
    PreviewSupport.stackEditor()
}
#endif
