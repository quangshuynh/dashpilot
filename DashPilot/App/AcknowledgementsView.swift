import SwiftUI

/// Where DashPilot's parts come from, and the licenses they are under.
///
/// Two licenses and they are different on purpose: DashPilot's own source code
/// is MIT, and the one typeface it bundles, Manrope, is under the SIL Open Font
/// License 1.1. The OFL asks for its text to travel with the font, so the
/// license is bundled beside the font files and shown here in full, read from
/// the bundle rather than typed into the app a second time.
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
                    Text("Manrope")
                        .dashFont(.emphasis)
                    Text("Copyright 2019 The Manrope Project Authors")
                        .dashFont(.body)
                        .foregroundStyle(.secondary)
                    Text("SIL Open Font License, Version 1.1")
                        .dashFont(.body)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("manropeAcknowledgement")

                if let license = Self.fontLicense {
                    Text(license)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("manropeLicenseText")
                } else {
                    DashNotice(
                        title: "License text unavailable",
                        message: "The license file was not found in this build. It is published at openfontlicense.org."
                    )
                }
            } header: {
                Text("Typeface")
            } footer: {
                Text("The typeface is bundled unmodified and is not sold on its own.")
            }
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The bundled `OFL.txt`, or `nil` where the file is missing from the build.
    private static var fontLicense: String? {
        Bundle.main.url(forResource: "OFL", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
}

#if DEBUG
#Preview("Acknowledgements") {
    NavigationStack {
        AcknowledgementsView()
    }
}
#endif
