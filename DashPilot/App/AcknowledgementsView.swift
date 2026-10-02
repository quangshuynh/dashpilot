import SwiftUI

/// Where DashPilot's parts come from, and the licenses they are under.
///
/// DashPilot's own source code is MIT. Its text is set in the system face,
/// which iOS provides, so the app bundles no typeface and carries no font
/// license; the section below says so rather than disappearing, so a driver
/// who looks for the typeface finds the answer.
struct AcknowledgementsView: View {
    var body: some View {
        List {
            Section {
                DashValueRow(title: "DashPilot source code", value: "MIT License")
                    .accessibilityElement(children: .combine)
            } footer: {
                Text("DashPilot is not affiliated with any delivery platform.")
            }

            Section {
                VStack(alignment: .leading, spacing: DashSpacing.sm) {
                    Text("San Francisco")
                        .dashFont(.emphasis)
                    Text("The system typeface, provided by iOS. DashPilot bundles no font.")
                        .dashFont(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("typefaceAcknowledgement")
            } header: {
                Text("Typeface")
            }
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview("Acknowledgements") {
    NavigationStack {
        AcknowledgementsView()
    }
}
#endif
