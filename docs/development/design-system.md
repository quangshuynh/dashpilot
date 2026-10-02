# Design system

DashPilot's visual rules are a small vocabulary in `DashPilot/App/DesignSystem/`, not a framework.
Screens are ordinary SwiftUI: `List` sections are the surfaces, system button styles are the
controls, and semantic colours carry light and dark mode. The vocabulary fixes the numbers between
them and answers the same questions on every screen: what state is this in, which figure is the
headline, what is the next action, and what is quieter.

This page describes version 2 of that vocabulary.

## What DashPilot should feel like

A driver reads DashPilot in a cradle, at a kerb and in a car park, often in sun and often with a
second app in front. So the app is **focused, calm, precise and slightly technical**: a working
instrument for one shift, not a dashboard and not a game. It should never look playful, neon,
trading-app-like, or like a delivery platform's own app.

Its identity comes from the thing it records, a route made of stops:

- **Numbered stop markers.** A delivery in progress is introduced by a small round marker holding
  its number, the way a stop is numbered on a route. Stacked orders are told apart by their
  markers before any sentence is read.
- **A stop track.** Under each delivery in progress, four stops on a line (accepted, at the pickup,
  picked up, delivered): filled where the delivery has been, a ring where it is now, hollow where it
  is going. It repeats the state line for the eye and is hidden from VoiceOver, which already hears
  the state.
- **Solid is recorded, dashed is estimated.** A route map draws the road travelled as a solid line
  and a planned one dashed. DashPilot uses the same convention: recorded figures sit on ordinary
  surfaces, and estimates (fuel, net after fuel) sit inside a dashed outline that is labelled as an
  estimate in words.
- **Condensed figures.** Figures are set in the system face's condensed width with tabular digits,
  which reads like an instrument and keeps a ticking value from moving sideways.

These four are the whole motif. Nothing decorative is drawn for its own sake: no route lines
across backgrounds, no illustrations, no gradients.

## Research: Caldera

Version 2 studied the [Caldera reference on Refero](https://styles.refero.design/style/fe8cdcf9-c850-4d52-be07-5ad269bf9ebf)
as design research, not as a template.

**Principles borrowed:**

- **Hierarchy carried by type and tone, not by boxes.** Caldera separates content with flat tonal
  steps and no shadows. DashPilot keeps `List`'s flat grouped surfaces, uses no shadows, and stops
  wrapping groups inside a row in extra rectangles.
- **One accent with one job.** Caldera spends its single vivid colour on primary actions and the
  most important figures. DashPilot's accent marks the primary action, active progress and what is
  selected, and nothing else.
- **Figures as structure.** Caldera lets heavy, condensed display type carry the page. DashPilot
  applies the idea to the numbers a driver glances at: condensed, heavy, tabular figures with quiet
  labels under them.
- **A small, fixed shape vocabulary.** Caldera uses a few radii consistently. DashPilot uses two.
- **Medium weight for small labels**, so a label stays legible beside a heavy figure.

**Principles rejected as wrong for DashPilot:**

- Architectural display sizes and fixed pixel type. DashPilot's type follows Dynamic Type at every
  size, and a figure must still fit a phone at the largest accessibility setting.
- Decorative signature artwork (halftone fields, gradients, illustration). A driving screen has no
  room for decoration.
- Very large corner radii and pill-shaped everything. DashPilot keeps the platform's own control
  shapes, which drivers already recognise.
- Generous editorial spacing. A shift screen is dense on purpose; the next action has to be on the
  first screen.
- A warm tinted canvas and a vivid orange accent. DashPilot's statuses already use red and orange
  for meaning, so an orange accent would collide with them.

**Made deliberately different:** the typeface (the system face, not a custom display family), the
colours (a teal route accent, system semantic colours elsewhere), the shapes (system controls and
list cells), and the motif (stops and routes rather than halftone).

## Typography

Every role is set in **SF Pro, the system face**, through `.dashFont(_:)`. The app bundles no font.

### Why the system face

Version 2 compared the families actually available on `main` (Manrope, bundled until then, and the
system face with its width variants) on DashPilot's own content: `$127.43`, `$24.61/hr`, `3h 48m`,
a ticking `1:30:04`, `Delivery 3`, `Arrived at pickup`, `Resume Driving`, `Estimated net after fuel`,
a Settings explanation, a week's summary line, and a delivery card at the largest accessibility
size. DM Sans, IBM Plex Sans and Space Grotesk were removed from the repository earlier and were not
restored for the study.

| | Manrope | SF Pro | SF Pro, condensed figures |
| --- | --- | --- | --- |
| `$127.43`, 34 pt bold, tabular | 137 pt wide | 143 pt | **113 pt** |
| `$24.61/hr`, 34 pt bold, tabular | 166 pt | 164 pt | **131 pt** |
| Tabular `1:11:11` | wide gaps around each 1 | even | even |
| Bold Text | needs a manual weight step; Bold cannot get heavier | native | native |
| Dynamic Type | scaled through `relativeTo:` | native | native |
| Matches the Live Activity | no (the widget uses the system face) | yes | yes |
| Ships a file and a license | yes | no | no |

Both faces draw `I` and `l` alike; neither wins on that. SF Pro Rounded was also tried and read as
playful, which DashPilot should not be.

The decision is **one family, the system face**, with the **condensed width for figures only**. It
gives figures a denser, more instrument-like character than Manrope did, about a fifth narrower so a
row of three fits at larger sizes, while body text keeps the face iOS tunes for reading at small
sizes. The app and its Live Activity now share one face.

### Roles

Each role is a text style, a weight and, for figures, a width. Nothing outside
`DashTypography.swift` names a point size.

| Role | Style, weight | For |
| --- | --- | --- |
| `metricHero` | Large Title, Bold, condensed, tabular | The one figure a surface leads with |
| `metric` | Title 3, Semibold, condensed, tabular | A figure under the headline |
| `metricLabel` | Footnote, Medium | What a figure is |
| `eyebrow` | Footnote, Semibold | A short label above a group, such as `Next` |
| `title` | Title 3, Bold | A surface's heading line, such as `Delivery 3` |
| `status` | Subheadline, Semibold | The state a shift or delivery is in |
| `body` | Subheadline, Regular | An ordinary line |
| `emphasis` | Subheadline, Semibold | A line that stands out from its neighbours |
| `supporting` | Caption, Regular | A short qualifier under another line |
| `control` | Headline, Semibold | The title of a large action button |

Tabular digits are asked for on the metric roles, so a changing value keeps its width. A figure
inside an ordinary line (`DashValueRow`'s value, a row's amount) adds `.monospacedDigit()` itself.

## Spacing

| Token | Value | Use |
| --- | --- | --- |
| `DashSpacing.xs` | 2 | Between a figure and the caption that qualifies it |
| `DashSpacing.sm` | 4 | Between lines of one group |
| `DashSpacing.md` | 8 | Between groups inside one block |
| `DashSpacing.lg` | 12 | Between blocks of a panel |
| `DashSpacing.xl` | 16 | Between the major regions of a panel |
| `DashSpacing.xxl` | 24 | Between panels that share one list row |

A value outside the scale needs a reason in a comment beside it (a 44-point target is one).

## Surfaces and radii

| Surface | Use | Treatment |
| --- | --- | --- |
| Page | Behind everything | The system grouped background |
| Grouped | A list section: the normal container | The system cell |
| Inset | The one thing in a row that must read as set apart (an Undo, a reminder) | `dashInsetSurface()`: tertiary grouped fill |
| Status | A state that changes what the screen means (paused, parked) | `DashStateBanner`: the state's tint at low opacity, plus symbol and words |
| Estimate | Estimated figures beside recorded ones | `dashEstimateSurface()`: no fill, dashed outline, titled as an estimate |
| Destructive | Deleting a record | A section of its own, a red text button, a confirmation |

Inset surfaces are never nested, and a list section is never wrapped in one.

| Radius | Value | Use |
| --- | --- | --- |
| `DashRadius.small` | 8 | Markers' neighbours: chips and small badges |
| `DashRadius.surface` | 12 | Inset, status and estimate surfaces |

Cells and buttons keep the system's own shapes.

## Colour

The palette is semantic colours plus **one accent**, defined in the asset catalog:

| Token | Light | Dark | Purpose |
| --- | --- | --- | --- |
| Accent (`AccentColor`) | `#0F766E` | `#1E9C8B` | Primary actions, the active stop, route recording, a selected choice |

The light accent holds 5.5:1 against white button text and 4.9:1 as text on the grouped
background; the dark accent holds 5.0:1 as text on a dark cell and 3.4:1 under white bold button
titles (the large-text threshold), the same trade the system blue makes in dark mode.

The accent is not decoration. A heading, an icon beside a fact, or a figure is never tinted with
it. Every other hue is a status colour from the table below, and none of them is ever the only
signal.

## Status language

| State | Symbol | Words | Tint |
| --- | --- | --- | --- |
| Shift running | `record.circle` | `Shift in Progress` | red |
| Shift paused | `pause.circle.fill` | `Paused`, and `working time stopped` | orange |
| Vehicle parked | `parkingsign.circle.fill` | `Parked`, and `working time still counting` | blue |
| No shift | `circle.dashed` | `No shift in progress` | secondary |
| Delivery in progress | its stage's symbol | the stage and how long | accent |
| Delivered / completed | `checkmark.circle.fill` | `Delivered` | green |
| Partial route | `circle.lefthalf.filled` | `partial route` | secondary |
| Estimated | dashed outline | `Estimated` in the title | none |
| Warning or refusal | `exclamationmark.triangle.fill` | the sentence | red or orange |

**Paused and parked never look alike.** Paused stops working time and is orange with a pause
symbol; parked keeps working time running, stops only the route, and is blue with the parking
sign. Each banner says which clock is still running, so the difference does not depend on colour.
Parked is blue in the app and on the Live Activity alike.

## Metrics

- **Primary metric**: `metricHero`, one per surface (working time on a running shift, earnings on a
  week or a period).
- **Supporting metrics**: `metric`, side by side in a `DashMetricRow`, a column at accessibility
  sizes.
- **Labels and units**: under the figure in `metricLabel`. A unit that is part of the formatted
  value (`mi`, `/hr`) stays in the figure.
- **Coverage and provenance**: `supporting`, directly under the figure it qualifies (`1 of 2
  shifts`, `partial route`). Never only in a footer.
- **Absence**: words in the quieter body role (`No amount recorded`), never a zero and never a
  dash.

## Controls

| Role | Treatment | Example |
| --- | --- | --- |
| Primary | `borderedProminent`, large, full width, accent | Start Shift, a delivery's next step, Resume Driving |
| Secondary | `bordered`, large, full width | Park for a Pickup, Pause Shift, Start Delivery beside cards |
| Quiet | borderless, body role, 44-point row | Add Pickup Place, Correct Grouping |
| Destructive | bordered and red for a lifecycle end (End Shift); red text in its own section for a delete; borderless red for a cancel | End Shift, Delete Shift, Cancel Delivery 3 |
| Workflow progression | Primary, under the `Next` eyebrow, one per delivery | Arrived at Pickup |

A screen has one primary action at a time. On a running shift it is each delivery's next step; when
nothing is in progress it is Start Delivery; while paused it is Resume Shift; while parked it is
Resume Driving.

## Components

- **`DashMetric`**: a value, what it is, and an optional qualifier. `emphasis: .hero` for the
  headline. An absence is passed as words with `isFigure: false`.
- **`DashMetricRow`**: figures side by side where they fit, a column where they do not, always a
  column at accessibility sizes.
- **`DashValueRow`**: one secondary figure, title beside value, with its coverage under both;
  stacks where the pair does not fit. `isProminent` marks the result a group arrives at.
- **`DashStatusLabel`**: a state as symbol, word and tint, in that order of importance.
- **`DashStateBanner`**: a status surface for a state that changes what the screen means.
- **`DashStopMarker`** and **`DashStopTrack`**: the numbered stop marker and the four-stop track.
- **`DashNotice`**: every empty, missing and unavailable state, as one accessibility element.
- **`DashValidationMessage`**: why something could not be saved, with the identifier on the
  sentence alone.
- **`dashInsetSurface()`**, **`dashEstimateSurface()`**: the two surface modifiers.

## Rules every screen keeps

- **Missing is never drawn as zero.**
- **Nothing shrinks to fit and nothing clips to one line.** Text wraps; a row that cannot hold its
  content stacks.
- **No state rests on colour alone.** Every state has a symbol and a word.
- **Figures speak their units** and their coverage, as one accessibility element.
- **Estimates are set apart from recorded figures**, in words first and then by the dashed
  surface or a section of their own.
- **Explanation follows the figure.** A section shows its figures first; general explanation goes
  after them, and on Period Summaries it gathers in one section at the end.
- **Corrections are quieter than data**, and destructive actions stand apart.
- **Growing content goes last.**

## Dark mode

Every colour is semantic or has a dark variant, so nothing is checked by eye per screen. Two traps
are worth knowing: `secondarySystemBackground` is the grouped cell's own colour in dark mode, so an
inset surface uses `tertiarySystemGroupedBackground`; and a status tint at low opacity must still
sit under a full-strength symbol and words.

## Live Activity

The Lock Screen card and the Dynamic Island share the vocabulary's words, symbols and status tints
(parked is blue there too) but not its implementation: the widget extension has its own measured
layout, keeps the system face (which is now the app's face as well), and bundles no font.

## Testing the layout

Anything added above a list moves the rows below it, and a `List` renders only rows near the
viewport. Journeys scroll to what they read rather than assuming it is on screen, and reach a
control by searching for it (`reachShiftControl`, `scrollUntilHittable`) rather than by a fixed
number of swipes. `DashTypographyTests` pins the roles; `FontBundleInvariantTests` pins that the app
and the widget bundle no font.
