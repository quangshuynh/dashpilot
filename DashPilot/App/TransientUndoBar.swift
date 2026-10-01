import SwiftUI

/// The short-lived line, and its Undo, that a Delivered or a step recorded
/// while parked leaves on the running shift's screen.
///
/// Screen state rather than a stored fact, for the reason
/// ``PickupWorkflowFeedback`` is: the store holds what happened, and this is
/// the sentence saying the tap did it, with an offer that lasts
/// ``DeliveryControlPanel/undoSeconds``.
struct TransientUndo: Identifiable {
    /// What the Undo takes back.
    enum Offer {
        /// The Delivered just recorded, through the reopening the deliberate
        /// control also uses.
        case delivered(deliveryID: UUID, spokenLabel: String)
        /// The step recorded while parked and the driving it resumed, together.
        case parkedProgress(ParkedProgressAction)
    }

    let id = UUID()
    var title: String
    var detail: String?
    var spokenLabel: String
    var symbolName: String
    /// The accessibility identifier of the sentence: `undoDeliveredBanner` for a
    /// plain Delivered, `parkedProgressNotice` for what the parked setting did.
    var identifier: String
    /// `nil` once taken, or when there is nothing to take back.
    var offer: Offer?
}

extension TransientUndo {
    /// A Delivered, with whatever the parked setting added beside it when it
    /// did not resume driving.
    static func delivered(_ numbered: NumberedDelivery, restoredTo state: DeliveryState, parked: PickupWorkflowNotice?) -> Self {
        TransientUndo(
            title: numbered.deliveredStatement,
            detail: parked?.detail,
            spokenLabel: [numbered.deliveredStatement, parked?.spokenLabel].compactMap { $0 }.joined(separator: ". "),
            symbolName: DeliveryState.delivered.symbolName,
            identifier: "undoDeliveredBanner",
            offer: .delivered(
                deliveryID: numbered.id,
                spokenLabel: numbered.spokenUndoDeliveredLabel(restoredTo: state)
            )
        )
    }

    /// What the parked setting did, with the Undo of step and driving together
    /// when it resumed driving.
    static func parked(_ notice: PickupWorkflowNotice, action: ParkedProgressAction?) -> Self {
        TransientUndo(
            title: notice.title,
            detail: notice.detail,
            spokenLabel: notice.spokenLabel,
            symbolName: notice.symbolName,
            identifier: "parkedProgressNotice",
            offer: action.map(Offer.parkedProgress)
        )
    }

    /// The same line once its Undo has been taken.
    func undone(_ notice: PickupWorkflowNotice) -> Self {
        var copy = self
        copy.title = notice.title
        copy.detail = notice.detail
        copy.spokenLabel = notice.spokenLabel
        copy.symbolName = notice.symbolName
        copy.offer = nil
        return copy
    }
}

/// Draws ``TransientUndo`` **below the list**, as an inset over its bottom
/// edge, rather than inside the delivery panel.
///
/// ## Why it is not at the top of the panel any more
///
/// It used to sit above the delivery cards. Appearing pushed them down and,
/// twenty seconds later, disappearing pulled every card up by its height, at
/// whatever moment that happened to be: a driver reaching for the next
/// delivery's button could press the one that had just moved under their
/// thumb, and CI run 36324925828 did exactly that. Inset at the bottom it takes
/// space from the scroll view's edge instead of from the panel, so arriving and
/// leaving move no card. Content scrolls clear of it, so it covers nothing it
/// cannot also reveal, and it leaves no permanent blank area: the inset goes
/// with it.
struct TransientUndoBar: View {
    let undo: TransientUndo
    let perform: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: DashSpacing.md) {
            // A symbol and a sentence, never a tint alone. The sentence is the
            // one element a listener hears, carrying the whole statement; the
            // printed detail is part of it rather than a second stop.
            Image(systemName: undo.symbolName)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DashSpacing.xs) {
                Text(undo.title)
                    .dashFont(.body)
                    .accessibilityLabel(undo.spokenLabel)
                    .accessibilityIdentifier(undo.identifier)
                if let detail = undo.detail {
                    Text(detail)
                        .dashFont(.body)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if let offer = undo.offer {
                Button("Undo", action: perform)
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityLabel(Self.spokenLabel(offer))
                    .accessibilityIdentifier(Self.identifier(offer))
            }
        }
        .padding(DashSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DashRadius.surface))
        .padding(.horizontal, DashSpacing.lg)
        .padding(.bottom, DashSpacing.sm)
    }

    private static func spokenLabel(_ offer: TransientUndo.Offer) -> String {
        switch offer {
        case let .delivered(_, label): label
        case let .parkedProgress(action): action.spokenUndoLabel
        }
    }

    private static func identifier(_ offer: TransientUndo.Offer) -> String {
        switch offer {
        case .delivered: "undoDeliveredButton"
        case .parkedProgress: "undoParkedProgressButton"
        }
    }
}
