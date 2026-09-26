# Design system

DashPilot's visual rules are a small vocabulary in `DashPilot/App/DesignSystem/`, not a framework.
Screens are still ordinary SwiftUI: `List` sections are the surfaces, system button styles are the
controls, and semantic colours carry light and dark mode. What the vocabulary fixes is the numbers
between them and the one question every screen answers the same way: which figure is the headline,
and what is quieter.

## Scale

| Token | Value | Use |
| --- | --- | --- |
| `DashSpacing.xs` | 2 | Between a figure and the caption that qualifies it |
| `DashSpacing.sm` | 4 | Between lines of one group |
| `DashSpacing.md` | 8 | Between groups inside one surface |
| `DashSpacing.lg` | 12 | Between blocks of a panel |
| `DashSpacing.xl` | 16 | Between the major regions of a panel |
| `DashRadius.surface` | 12 | The one corner radius, for `dashInsetSurface()` |

An inset surface is for the one thing inside a list row that has to read as set apart (an undo
offer, a reminder). It is never nested, and a list section is not wrapped in one.

## Typography

`DashTypography` sets every role in **Manrope**, the one custom family the app bundles, through
`.dashFont(_:)`. Each role is a system text style and a weight, scaled with `relativeTo:`, so it
follows Dynamic Type exactly as the system font would; Bold Text moves each role one weight heavier;
a face that fails to load falls back to the system font in the same style and weight.

| Role | Style, weight | For |
| --- | --- | --- |
| `metricHero` | Large Title, Bold, tabular | The one figure a surface leads with |
| `metric` | Title 3, Bold, tabular | A figure under the headline |
| `metricLabel` | Caption, Medium | What a figure is, or a field's label |
| `title` | Title 3, Bold | A surface's heading line |
| `status` | Subheadline, SemiBold | The state a shift or delivery is in |
| `body` | Subheadline, Regular | An ordinary line |
| `emphasis` | Subheadline, SemiBold | A line that stands out from its neighbours |
| `supporting` | Caption, Regular | A quieter line under another |

Tabular figures are asked for on the two metric roles only, so a changing value keeps its width
while ordinary text stays proportional. Roles are applied screen by screen as each is redesigned:
the shift panel, the delivery card, History, Older Weeks, the completed-shift detail, Settings and
the vehicle editor use them today. The Live Activity keeps the system face, because the widget
extension bundles no font. See [The typeface and its license](building.md#the-typeface-and-its-license).

## Components

- **`DashMetric`**: a value, what it is, and an optional qualifier under it. `emphasis: .hero` for
  the headline. Where a figure does not exist the caller passes the words that say so with
  `isFigure: false`, drawn in the quieter body role, so an absence never carries the weight of a
  number.
- **`DashMetricRow`**: figures side by side where they fit, a column where they do not, and always
  a column at accessibility sizes, because three figures at the largest sizes truncate each other.
- **`DashValueRow`**: one secondary figure, title beside value, with its coverage or explanation
  under both. It stacks where the pair does not fit and always at accessibility sizes.
  `isProminent` marks the result a group arrives at, such as the net at the foot of a ledger.
- **`DashStatusLabel`**: a state said with a symbol, a word and a tint, in that order of
  importance, as one accessibility element.
- **`DashNotice`**: every empty, missing and unavailable state: a short title, an explanation, an
  optional symbol, and nothing decorative. An action, where one is useful, is the caller's own
  control after it. One accessibility element.
- **`DashValidationMessage`**: why something typed could not be saved, as a sentence beside a
  warning symbol. The symbol is hidden from assistive technologies and the identifier is on the
  sentence alone, so a UI test's `validationMessage(_:in:)` and a VoiceOver user both meet the
  sentence and never a glyph called "Warning".

## Rules every screen keeps

- **Missing is never drawn as zero.** A figure that was not recorded is words in the quieter style;
  a recorded zero is a figure.
- **Nothing shrinks to fit and nothing clips to one line.** Text wraps with
  `.fixedSize(horizontal: false, vertical: true)`, and a row that cannot hold its content stacks.
- **No state rests on colour alone.** Every state has a symbol and a word; the tint is the third
  signal.
- **Figures speak their units.** A metric is one accessibility element whose label says the unit
  and the coverage in full, because a listener has no caption in view.
- **Corrections are quieter than data.** Controls that rewrite a recorded fact sit below or apart
  from the figures they change, and destructive ones stand in a section of their own.
- **Growing content goes last.** Lists that grow with a record (deliveries, pauses) come after the
  sections that summarise it in a fixed number of lines.

## Testing the layout

Anything added above a list moves the rows below it, and a `List` renders only the rows near the
viewport. Journeys therefore scroll to what they read rather than assuming it is on screen:
`openFirstShift(in:)` and `revealHistoryRows(_:in:)` scroll to History's rows, and the scroll
helpers walk downward only, so a journey reading something above its current position goes back to
the top with `scrollToTop(reaching:in:)` first.
