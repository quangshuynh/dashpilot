import SwiftData
import SwiftUI

/// Shared lifecycle for bounded report reads. Saves carry invalidation only;
/// session orchestration stays in RootView and its existing services.
struct PeriodLoading: ViewModifier {
    let request: PeriodLoadRequest?
    let store: PeriodLoadStore
    var retryRevision = 0
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var revision = 0
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .task(id: PeriodLoadStore.Key(request: isVisible ? request : nil, revision: revision + retryRevision)) {
                guard isVisible, let request else { return }
                let container = context.container
                await store.load(key: .init(request: isVisible ? request : nil, revision: revision + retryRevision)) {
                    try PeriodDataLoader.load(request, in: container)
                }
            }
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { notification in
                if PeriodSaveInvalidation.affectsPeriods(notification) { revision += 1 }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { revision += 1 }
            }
    }
}

struct PeriodLoadFailure: View {
    let retry: () -> Void

    var body: some View {
        Section {
            DashNotice(title: "Couldn't load your records", message: "Try again to see your completed work.",
                       symbol: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
            Button("Try Again", action: retry)
                .frame(minHeight: 44)
                .accessibilityLabel("Try loading your records again")
                .accessibilityIdentifier("retryPeriodLoadButton")
        }
        .accessibilityIdentifier("periodLoadFailure")
    }
}
