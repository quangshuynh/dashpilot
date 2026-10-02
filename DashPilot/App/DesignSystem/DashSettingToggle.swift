import SwiftUI

/// A switch with its name, what it changes in one line, and, for a switch that
/// depends on another, a glyph and an indent that say so before the words do.
///
/// At accessibility sizes the description moves under the switch at full
/// width: beside the switch it was squeezed to a word a line. The identifier,
/// hint, availability and on/off value stay on the switch itself, so a query
/// for the switch still finds exactly one element; the description is then a
/// line of its own that VoiceOver reads after it.
struct DashSettingToggle: View {
    let isOn: Binding<Bool>
    var isDependent = false
    var isAvailable = true
    let title: String
    let detail: String
    let hint: String
    let identifier: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: DashSpacing.sm) {
                toggle(showingDetail: false)
                Text(detail)
                    .dashFont(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            toggle(showingDetail: true)
        }
    }

    private func toggle(showingDetail: Bool) -> some View {
        Toggle(isOn: isOn) {
            DashSettingLabel(isDependent: isDependent, title: title, detail: showingDetail ? detail : nil)
        }
        .disabled(!isAvailable)
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
    }
}

/// A switch's name, what it changes in one line, and, for a switch that
/// depends on another, a glyph and an indent that say so before the words do.
struct DashSettingLabel: View {
    /// Whether this switch only works while the one above it is on.
    var isDependent = false
    let title: String
    let detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DashSpacing.md) {
            if isDependent {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: DashSpacing.xs) {
                Text(title)
                    .dashFont(.emphasis)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .dashFont(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
