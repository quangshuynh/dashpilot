import Foundation
import SwiftUI
import Testing
import UIKit
@testable import DashPilot

/// The Live Activity's card, laid out and measured against the height the
/// system gives it.
///
/// ## Why this is measured rather than reasoned about
///
/// A Lock Screen Live Activity is truncated by the system once its content is
/// taller than **160 points**, and what is truncated is whatever is drawn last.
/// On a real shift that was the controls: with an order in progress the card
/// grew a delivery line, a status line and a timer row, and after parking a
/// parked line as well, until Resume Driving was cut off the bottom of the card
/// while Park had been visible a moment before. That is a functional defect,
/// because the control that restarts the route was the one lost.
///
/// XCUITest cannot reach a Lock Screen, so the card's own view is laid out here,
/// in the app's test host, with the same system fonts a device uses, at the
/// width a Lock Screen card has on the widest and narrowest supported phones
/// and at every text size the card is drawn at.
@MainActor
@Suite("Live Activity card layout")
struct ShiftActivityCardLayoutTests {
    /// The height past which the system truncates a Lock Screen Live Activity.
    static let lockScreenHeightLimit: CGFloat = 160

    /// The Lock Screen card's width on a 402-point and on a 375-point screen:
    /// the screen less the system's margin either side.
    static let widths: [CGFloat] = [370, 343]

    private let asOf = Date(timeIntervalSince1970: 1_760_000_000)

    private func timer(_ number: Int, _ state: String, minutesAgo: Double) -> ShiftActivityDeliveryTimer {
        ShiftActivityDeliveryTimer(
            title: "Delivery \(number)",
            stateLabel: state,
            startedAt: asOf.addingTimeInterval(-minutesAgo * 60)
        )
    }

    private func state(
        parked: Bool = false,
        paused: Bool = false,
        deliveryStatus: String? = nil,
        timers: [ShiftActivityDeliveryTimer] = [],
        controls: [ShiftActivityControl]
    ) -> ShiftActivityAttributes.ContentState {
        ShiftActivityAttributes.ContentState(
            isPaused: paused,
            routeSuspendedNotice: parked ? "Parked · route not recording" : nil,
            workingDuration: 2 * 3600 + 14 * 60,
            asOf: asOf,
            mileageStatement: "Not enough route recorded to measure",
            partialRouteMarker: "partial route",
            activeDeliveryCount: timers.count,
            completedDeliveryCount: 5,
            deliveryStatus: deliveryStatus,
            activeDeliveryTimers: timers,
            controls: controls
        )
    }

    /// Every state the card is drawn in, named.
    private var states: [(String, ShiftActivityAttributes.ContentState)] {
        [
            ("no delivery", state(controls: [.startDelivery, .park, .pause, .end])),
            ("no delivery, workflow on", state(controls: [.park, .startDelivery, .pause, .end])),
            (
                "one accepted",
                state(
                    deliveryStatus: "Heading to the pickup",
                    timers: [timer(1, "To pickup", minutesAgo: 3)],
                    controls: [.deliveryStep(.arriveAtPickup), .startDelivery, .park]
                )
            ),
            (
                "one accepted, workflow on",
                state(
                    deliveryStatus: "Heading to the pickup",
                    timers: [timer(1, "To pickup", minutesAgo: 3)],
                    controls: [.park, .deliveryStep(.arriveAtPickup), .startDelivery]
                )
            ),
            (
                "one arrived, parked",
                state(
                    parked: true,
                    deliveryStatus: "Waiting at the pickup",
                    timers: [timer(1, "At pickup", minutesAgo: 9)],
                    controls: [.resumeDriving, .deliveryStep(.pickUp), .startDelivery]
                )
            ),
            (
                "one picked up",
                state(
                    deliveryStatus: "Heading to the customer",
                    timers: [timer(1, "To customer", minutesAgo: 14)],
                    controls: [.deliveryStep(.complete), .startDelivery, .park]
                )
            ),
            (
                "two in progress, parked",
                state(
                    parked: true,
                    timers: [timer(3, "At pickup", minutesAgo: 9), timer(4, "At pickup", minutesAgo: 9)],
                    controls: [.resumeDriving, .startDelivery]
                )
            ),
            (
                "four in progress",
                state(
                    timers: [
                        timer(1, "To customer", minutesAgo: 30), timer(2, "At pickup", minutesAgo: 12),
                        timer(3, "To pickup", minutesAgo: 4), timer(4, "To pickup", minutesAgo: 1)
                    ],
                    controls: [.startDelivery, .park]
                )
            ),
            (
                "four in progress, parked",
                state(
                    parked: true,
                    timers: [
                        timer(1, "To customer", minutesAgo: 30), timer(2, "At pickup", minutesAgo: 12),
                        timer(3, "To pickup", minutesAgo: 4), timer(4, "To pickup", minutesAgo: 1)
                    ],
                    controls: [.resumeDriving, .startDelivery]
                )
            ),
            (
                "two picked up, Delivered offered",
                state(
                    timers: [timer(3, "To customer", minutesAgo: 20), timer(4, "To customer", minutesAgo: 18)],
                    controls: [Self.delivered(3), .startDelivery, .park]
                )
            ),
            (
                "two picked up, workflow on",
                state(
                    timers: [timer(3, "To customer", minutesAgo: 20), timer(4, "To customer", minutesAgo: 18)],
                    controls: [.park, Self.delivered(3), .startDelivery]
                )
            ),
            (
                "two picked up, parked",
                state(
                    parked: true,
                    timers: [timer(3, "To customer", minutesAgo: 20), timer(4, "To customer", minutesAgo: 18)],
                    controls: [.resumeDriving, Self.delivered(3), .startDelivery]
                )
            ),
            (
                "same drop-off pair, one row, parked",
                state(
                    parked: true,
                    timers: [
                        ShiftActivityDeliveryTimer(
                            title: "Deliveries 3 and 4",
                            stateLabel: "To customer",
                            startedAt: asOf.addingTimeInterval(-20 * 60),
                            deliveryCount: 2
                        )
                    ],
                    controls: [.resumeDriving, Self.delivered(3), .startDelivery]
                )
            ),
            (
                "four in progress, Delivered 12, parked",
                state(
                    parked: true,
                    timers: [
                        timer(11, "To pickup", minutesAgo: 30), timer(12, "To customer", minutesAgo: 25),
                        timer(13, "To customer", minutesAgo: 9), timer(14, "At pickup", minutesAgo: 2)
                    ],
                    controls: [.resumeDriving, Self.delivered(12), .startDelivery]
                )
            ),
            ("paused", state(paused: true, controls: [.resume, .end]))
        ]
    }

    private static func delivered(_ number: Int) -> ShiftActivityControl {
        .nextDelivered(number: number, deliveryID: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(number % 10)")!)
    }

    /// The card's height at `width` and `size`, laid out by SwiftUI itself.
    private func height(
        of state: ShiftActivityAttributes.ContentState,
        width: CGFloat,
        size: DynamicTypeSize
    ) -> CGFloat {
        let host = UIHostingController(
            rootView: ShiftActivityLockScreenView(state: state).environment(\.dynamicTypeSize, size)
        )
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    /// Every text size, including the accessibility sizes the card caps.
    static let textSizes: [DynamicTypeSize] = [.xSmall, .large, .xLarge, .xxLarge, .xxxLarge, .accessibility5]

    /// Measured before the redesign, at `large` and 370 points: 201 with nothing
    /// in progress, 242 with one order, 266 with one order parked, 296 with four
    /// parked. Measured after: 134, 154, 154 and 131. The limit below keeps a
    /// few points in hand, because a device's own rendering of a bordered
    /// button is the one metric here not taken on a device.
    @Test("Every state fits the Lock Screen, with room to spare, at every width and text size")
    func everyStateFits() {
        for (name, state) in states {
            for width in Self.widths {
                for size in Self.textSizes {
                    let measured = height(of: state, width: width, size: size)
                    #expect(
                        measured <= Self.lockScreenHeightLimit - 4,
                        "\(name) at \(Int(width)) pt, \(size): \(Int(measured.rounded())) pt"
                    )
                }
            }
        }
    }

    @Test("Text past xLarge is drawn at xLarge on the card, so it measures the same")
    func textSizeIsCapped() {
        for (name, state) in states {
            let capped = height(of: state, width: 370, size: .xLarge)
            for size in [DynamicTypeSize.xxLarge, .xxxLarge, .accessibility3, .accessibility5] {
                #expect(height(of: state, width: 370, size: size) == capped, "\(name) at \(size)")
            }
        }
    }

    @Test("The Dynamic Island's expanded bottom region stays within what the island leaves it")
    func islandFits() {
        for (name, state) in states {
            for size in Self.textSizes {
                let host = UIHostingController(
                    rootView: ShiftActivityIslandBottom(state: state).environment(\.dynamicTypeSize, size)
                )
                let measured = host.sizeThatFits(in: CGSize(width: 330, height: CGFloat.greatestFiniteMagnitude)).height
                #expect(measured <= 100, "\(name) at \(size): \(Int(measured.rounded())) pt")
            }
        }
    }

    // MARK: The plan

    @Test("Controls are drawn in the app's order, in rows of two, and never more than two rows")
    func controlRows() {
        for (name, state) in states {
            let layout = ShiftActivityCardLayout(state: state, surface: .lockScreen, textSize: .standard)
            #expect(layout.controlRows.flatMap { $0 } == state.controls, "\(name)")
            #expect(layout.controlRows.count <= 2, "\(name)")
            #expect(layout.controlRows.allSatisfy { $0.count <= 2 }, "\(name)")
        }
    }

    @Test("One order: its row and the mileage line at the default size, its row alone once text is larger")
    func oneOrder() throws {
        let one = try #require(states.first { $0.0 == "one arrived, parked" }?.1)

        let standard = ShiftActivityCardLayout(state: one, surface: .lockScreen, textSize: .standard)
        #expect(standard.deliveryRows.map(\.title) == ["Delivery 1"])
        #expect(standard.footnote == nil)
        #expect(standard.showsSecondaryLine)

        let larger = ShiftActivityCardLayout(state: one, surface: .lockScreen, textSize: .larger)
        #expect(larger.deliveryRows.map(\.title) == ["Delivery 1"], "The order outranks the mileage")
        #expect(!larger.showsSecondaryLine)
    }

    @Test("Stacked orders: rows as far as they fit, then one line for the rest and the withheld step")
    func stackedOrders() throws {
        let four = try #require(states.first { $0.0 == "four in progress, parked" }?.1)
        let layout = ShiftActivityCardLayout(state: four, surface: .lockScreen, textSize: .standard)

        #expect(layout.deliveryRows.map(\.title) == ["Delivery 1", "Delivery 2"])
        #expect(layout.footnote == "2 more · Open DashPilot for steps")
        #expect(layout.spokenFootnote?.contains("2 more deliveries also active") == true)
        #expect(layout.spokenFootnote?.contains("Open DashPilot to record a step") == true)
        #expect(!layout.showsSecondaryLine, "Orders and the step outrank the mileage")

        let two = try #require(states.first { $0.0 == "two in progress, parked" }?.1)
        let pair = ShiftActivityCardLayout(state: two, surface: .lockScreen, textSize: .standard)
        #expect(pair.deliveryRows.count == 2)
        #expect(pair.footnote == "Open DashPilot to record a step")
    }

    @Test("Stacked with Delivered offered: both rows at the default size, nothing claiming a step is withheld")
    func stackedWithDelivered() throws {
        let pair = try #require(states.first { $0.0 == "two picked up, parked" }?.1)

        let standard = ShiftActivityCardLayout(state: pair, surface: .lockScreen, textSize: .standard)
        #expect(standard.deliveryRows.map(\.title) == ["Delivery 3", "Delivery 4"])
        #expect(standard.footnote == nil)
        #expect(standard.controlRows == [[.resumeDriving, Self.delivered(3)], [.startDelivery]])

        // One line at xLarge: no row fits beside its sibling, so the count is
        // stated, and it does not say "more" over rows that were not drawn.
        let larger = ShiftActivityCardLayout(state: pair, surface: .lockScreen, textSize: .larger)
        #expect(larger.deliveryRows.isEmpty)
        #expect(larger.footnote == "2 in progress")
        #expect(larger.spokenFootnote == "2 deliveries in progress. Open DashPilot for their timers.")

        let merged = try #require(states.first { $0.0 == "same drop-off pair, one row, parked" }?.1)
        let one = ShiftActivityCardLayout(state: merged, surface: .lockScreen, textSize: .larger)
        #expect(one.deliveryRows.map(\.title) == ["Deliveries 3 and 4"], "A merged row still fits at xLarge")
    }

    @Test("The island never draws the mileage line, and draws no order row beside two rows of controls")
    func island() throws {
        for (name, state) in states {
            let layout = ShiftActivityCardLayout(state: state, surface: .expandedIsland, textSize: .standard)
            #expect(!layout.showsSecondaryLine, "\(name)")
            if layout.controlRows.count == 2 {
                #expect(layout.deliveryRows.isEmpty && layout.footnote == nil, "\(name)")
            }
        }
    }

    @Test("The mileage is never drawn without its qualifier, and the delivered count gives way first")
    func secondaryLine() throws {
        let state = try #require(states.first?.1)
        #expect(state.secondaryLine == "Not enough route recorded to measure · partial route · 5 delivered")
        #expect(state.secondaryLine.hasPrefix(state.mileageLine))
        #expect(state.spokenSecondaryLine.contains("Partial route"))
        #expect(state.spokenSecondaryLine.hasSuffix("5 deliveries delivered"))
    }

    @Test("Parked is the header, never a paused one, and speaks both halves")
    func parkedHeader() throws {
        let parked = try #require(states.first { $0.0 == "one arrived, parked" }?.1)
        #expect(parked.headerTitle == "Parked · route not recording")
        #expect(parked.shortHeaderTitle == "Parked")
        #expect(parked.headerSymbolName == "parkingsign.circle.fill")
        #expect(parked.spokenHeaderTitle.contains("your shift is still running"))
        #expect(!parked.headerTitle.lowercased().contains("pause"))

        let running = try #require(states.first?.1)
        #expect(running.headerTitle == "Shift in Progress")
        let paused = try #require(states.last?.1)
        #expect(paused.headerTitle == "Shift Paused")
    }

    /// The island's compact and minimal glyph is what a driver sees with
    /// another app in front. A forgotten Resume Driving must not look like
    /// recording there.
    @Test("The island's glyph is the parking sign while parked, never the recording dot")
    func compactGlyph() throws {
        let parked = try #require(states.first { $0.0 == "one arrived, parked" }?.1)
        #expect(parked.compactStatus == .parked)
        #expect(parked.headerSymbolName != parked.statusSymbolName, "Not the record dot")

        let running = try #require(states.first?.1)
        #expect(running.compactStatus == .running)
        #expect(running.headerSymbolName == "record.circle")

        let paused = try #require(states.last?.1)
        #expect(paused.compactStatus == .paused)
        #expect(paused.headerSymbolName == "pause.circle.fill")
    }
}
