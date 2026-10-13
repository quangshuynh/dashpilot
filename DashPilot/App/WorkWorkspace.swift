import SwiftUI

/// Presentation only. All shift actions and session services belong to the shell.
struct WorkWorkspace: View {
    let activeShift: Shift?
    let routeReading: ActiveRouteReading
    let pickupWorkflow: PickupWorkflowFeedback?
    let currentWeek: HistoryWeek?
    let now: Date
    let focusRequest: WorkFocusRequest?
    @Binding var transientUndo: TransientUndo?
    @Binding var pendingEarningsConfirmation: PendingDeliveryEarningsConfirmation?
    let startShift: () -> Void
    let resumeShift: () -> Void
    let park: () -> Void
    let resumeDriving: () -> Void
    let pauseShift: () -> Void
    let endShift: () -> Void
    let undoPickupWorkflowStep: () -> Void
    let takeBackTransientUndo: () -> Void
    let exportAllHistory: () -> Void

    @Environment(LocationTrackingService.self) private var routeCapture
    @State private var handledFocusRequest: WorkFocusRequest?
    @State private var activeReview: ActiveDeliveryReview?

    var body: some View {
        ScrollViewReader { proxy in
            List {
                #if DEBUG
                if let activeShift, LaunchArgument.isPresent(LaunchArgument.liveActivityPreview) {
                    LiveActivityPreviewSection(shift: activeShift)
                }
                #endif

                Section {
                    if let activeShift {
                        ActiveShiftPanel(
                            shift: activeShift,
                            routeReading: routeReading,
                            resume: resumeShift,
                            park: park,
                            resumeDriving: resumeDriving,
                            pickupWorkflow: pickupWorkflow.flatMap { $0.describes(activeShift) ? $0 : nil },
                            undoPickupWorkflowStep: undoPickupWorkflowStep
                        )
                    } else {
                        StartShiftPanel(start: startShift)
                    }
                }
                .id(WorkFocusRequest.Destination.activeShift)

                if let activeShift {
                    Section {
                        // A paused shift is one the driver has said they are not
                        // working, and a delivery started on it would be time
                        // the app is simultaneously reporting as not worked. The
                        // control is replaced by the reason rather than removed,
                        // so the section does not silently vanish.
                        if activeShift.isPaused {
                            Text("Deliveries are not recorded while the shift is paused. Resume the shift to start one.")
                                .dashFont(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("pausedDeliveryNotice")
                        } else {
                            DeliveryControlPanel(
                                shift: activeShift,
                                transientUndo: $transientUndo,
                                pendingEarningsConfirmation: $pendingEarningsConfirmation,
                                review: { activeReview = $0 }
                            )
                        }
                    } header: {
                        Text("Deliveries")
                    } footer: {
                        Text("DashPilot records only what you tap. It is not connected to any delivery platform.")
                    }

                    // Below the deliveries: Pause and End are tapped once a
                    // shift, and the vehicle and capture lines are context.
                    Section {
                        ActiveShiftControlsPanel(
                            shift: activeShift,
                            routeReading: routeReading,
                            captureState: routeCapture.state,
                            pause: pauseShift,
                            end: endShift
                        )
                    } header: {
                        Text("Shift")
                    }
                }

                Section {
                    LocationAuthorizationPanel()
                } header: {
                    Text("Location")
                }

                CurrentWeekHistorySection(week: currentWeek, now: now) {
                    exportAllHistory()
                }
                .id(WorkFocusRequest.Destination.history)
            }

            .safeAreaInset(edge: .bottom) {
                if let transientUndo, activeShift?.lifecycleState == .running {
                    TransientUndoBar(undo: transientUndo, perform: takeBackTransientUndo)
                }
            }
            .safeAreaBar(edge: .bottom) {
                if let activeShift, activeShift.lifecycleState == .running {
                    DeliveryEntryBar(shift: activeShift)
                }
            }
            .dashCanvas()
            .navigationTitle("Work")
            .workspaceDestinations()
            .navigationDestination(for: Shift.self) { shift in
                CompletedShiftDetailView(shift: shift)
            }
            .onChange(of: focusRequest) { _, _ in revealRequestedSection(using: proxy) }
            .onAppear { revealRequestedSection(using: proxy) }
        }
        // Keep review state outside the List's recycled row. A row refresh
        // must not discard navigation or the correction awaiting confirmation.
        .sheet(item: $activeReview) { review in
            if let activeShift {
                switch review {
                case .grouping: OfferCorrectionView(shift: activeShift)
                case .stack: StackEditorView(shift: activeShift)
                case .recovery: DeliveryRecoveryView(shift: activeShift)
                }
            }
        }
    }

    private func revealRequestedSection(using proxy: ScrollViewProxy) {
        guard let focusRequest, focusRequest != handledFocusRequest else { return }
        proxy.scrollTo(focusRequest.destination, anchor: .top)
        handledFocusRequest = focusRequest
    }
}

nonisolated enum ActiveDeliveryReview: String, Identifiable {
    case grouping, stack, recovery

    var id: String { rawValue }
}
