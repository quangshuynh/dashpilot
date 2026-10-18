# Accessibility

DashPilot uses native SwiftUI navigation, controls and semantic colors. Accessibility is part of
completion, including the meaning and coverage of a figure, not just whether its text fits.

## Reading and operating

- Home, Work and Money are native tabs with separate navigation stacks and Settings toolbar access.
- Onboarding has scrolling pages, decorative artwork hidden from VoiceOver, a spoken step count,
  reachable Skip or Close, and focus on the title after a page change. Reduce Motion disables its
  animated button transitions. Completion remains version 1 under `onboarding.completedVersion`.
- Important financial elements identify their metric, amount or unavailable state, units and
  contributing coverage. Missing shift gross in detail names the metric rather than just saying
  that no amount was recorded. USD is fixed; locale affects formatting, not currency.
- Money and Insights stack values at accessibility text sizes. Home uses the same bounded fitting
  for monetary figures so cents stay attached to the amount. Qualifiers retain Dynamic Type.
- Insights has exact selected-week values and **Read All Weekly Values**. At accessibility text
  sizes these replace charts. Native week controls do not require chart gestures; vertical
  scrolling is not chart selection. Zero, missing and partial coverage also have text explanations.
- Park and Pause retain different labels and effects. Delivery controls name their subject, stacked
  deliveries remain separate, and destructive changes use native confirmations. Undo remains
  available across workspace tabs for its existing active-scene window.

See the [design system](design-system.md), [financial semantics](../product/earnings-and-metrics.md)
and [Insights](../product/insights.md) for the shared behavior.

## Verification matrix

Use synthetic records only. Capture diagnostics outside tracked documentation assets. Retain the
40-journey essential suite; extend relevant journeys instead of adding a screenshot-only suite.

| Configuration | Inspect |
| --- | --- |
| iPhone default light and dark | All welcome pages, Home, active Work, Money, Insights, Settings and a historical detail |
| Narrow iPhone at AX5 | Scroll all welcome pages, reach Back and finish, keep exact amounts readable, operate week controls and corrections |
| Bold Text and Increase Contrast | Financial labels, blue actions, unavailable text, selection and focus indicators |
| Reduce Motion | Button-driven welcome transitions and unchanged navigation usability |
| iPad | Width, native tab placement, sheets, readable values and welcome controls |
| VoiceOver on physical hardware | Reading order, focus after navigation, spoken units and coverage, lifecycle controls and confirmation recovery |

XCTest label and hit-target assertions are useful evidence, but do not establish actual spoken
VoiceOver behavior or physical driving usability. Simulator screenshots do not prove contrast in
sunlight, battery cost, route continuity or chart frame performance. Keep these limits explicit in
any verification report.

## Known limits

The Live Activity caps Dynamic Type at xLarge. The pinned delivery-entry bar caps it at
accessibility1. These constraints need a focused hardware usability review before release.
Route measurement in completed-shift detail still runs on the main actor; addressing it requires a
separate bounded performance interval. No physical-device VoiceOver certification is claimed.
