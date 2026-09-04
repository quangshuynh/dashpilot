import SwiftUI

/// Shown when the local store could not be opened.
///
/// The app deliberately does not offer to erase and recreate the store here:
/// recorded shifts cannot be re-entered from memory, so destroying them must
/// never be a one-tap recovery path.
struct PersistenceUnavailableView: View {
    let error: Error

    var body: some View {
        ContentUnavailableView {
            Label("Local Data Unavailable", systemImage: "externaldrive.badge.xmark")
        } description: {
            Text("DashPilot could not open its local data store, so no shift data can be read or recorded. Restarting the app may resolve this.")
        } actions: {
            Text(error.localizedDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#if DEBUG
#Preview {
    PersistenceUnavailableView(
        error: NSError(domain: "DashPilotPreview", code: 1, userInfo: [NSLocalizedDescriptionKey: "The data store could not be opened."])
    )
}
#endif
