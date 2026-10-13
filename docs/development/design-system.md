# Design system

DashPilot's third visual foundation prepares for the working name **Worklane** while keeping the
public app name, icon, and technical identifiers unchanged. It adapts the existing
`Dash*` components rather than introducing a second component library.

## Workspace navigation

Home, Work, and Money use the native tab bar with an independent navigation stack per workspace.
Home pairs a quiet blue welcome surface with the existing next-shift panel or a Continue Shift
action. Work preserves the operational hierarchy and pinned delivery entry. Money offers two
clear routes into the existing records and summaries. A shared toolbar Settings route appears on
all three roots. Labels, symbols, native selected-tab semantics, and headings identify each place.

The system lays out the tab bar, delivery-entry bar, and transient Undo using safe areas. No device
height or inset is hardcoded. The existing entry-bar accessibility1 text cap remains; the rest of
the Work list can grow to AX5 and scroll. Home and Money introduce no custom animation.

## Character

The signature is an open financial figure on a quiet cloud-blue surface, followed immediately by
its meaning and coverage. Ordinary records stay on native list surfaces. Estimates keep their
labelled dashed boundary. This gives facts, supporting actions, and estimates distinct treatments
without shadows, gradients, or a dashboard made of nested cards.

Two complementary densities share the same vocabulary:

- **Business clarity:** open-width financial headlines, tabular digits, a little more space between
  the value and its explanation, and soft blue summary rows. Used in completed-shift summaries,
  period earnings and expenses, and the current week's earnings headline.
- **Operational clarity:** condensed tabular timers and compact metrics, the existing control order,
  numbered deliveries, and a four-stop progress track. Driving controls retain their position,
  native feedback, and large targets. Visual breathing room must not bury the next action.

The [Bevel reference](https://styles.refero.design/style/c0717d1a-b446-4166-a445-6497fe287fea)
informed the restrained blue surfaces, readable hierarchy, and approachable tone. Its marketing
layouts, assets, fixed display sizes, and web spacing were not copied.

## Semantic color roles

`DashPilotActivity/ShiftActivityPalette.swift` supplies the app and Live Activity's shared roles.
The extension has no asset catalog; the app's `AccentColor` asset mirrors the foreground accent.
A contrast test checks the catalog and shared value in both appearances and contrast settings.

| Role | Light | Dark | Use |
| --- | --- | --- | --- |
| Foreground accent | `#315FCC` | `#8EADFF` | Links, selected controls, delivery progress |
| Foreground accent, Increase Contrast | `#244B9F` | `#B7CAFF` | Same meanings, stronger separation |
| Filled action | `#315FCC` | `#315FCC` | Prominent actions and enabled switch fill |
| Filled action, Increase Contrast | `#244B9F` | `#244B9F` | Stronger white-text pairing |
| On action | White | White | Text and delivery numbers on the explicit fill |
| Canvas | `#F5F7FB` | `#161A22` | Principal lists, financial editors, onboarding |
| Cloud | `#EBF0F8` | `#222D40` | Financial summary rows, inset supporting actions |
| Quiet outline | `#CBD5E5` | `#475773` | Inset surface boundaries |
| Strong outline | `#65758E` | `#99ABC9` | Estimates, and inset boundaries with Increase Contrast |
| Muted marker fill | `#566174` | `#566174` | Cancelled delivery markers with white text |

Primary and secondary text remain the system's semantic text colors. Native List/Form rows,
separators, sheet behavior, destructive controls, and materials retain platform rendering.

The proposed brand blue `#4375E8` is not the action fill: white on it measures about 4.24:1.
White on `#315FCC` measures about 5.77:1. The candidate earnings green `#43B98B` is not used for
ordinary text on white (about 2.46:1), or as a blanket financial success signal. A recorded amount
is not evidence of profitability. Future uses need a concrete meaning and a tested text pair.

The darker filled action is intentionally separate from the lighter dark-mode foreground accent.
A bright dark-mode link color must not become the background for white button text.

### Status is separate from brand

The established system colors remain: red for running/recording, orange for paused, blue for
parked, green for completed, and red for destructive/error roles. Every state is also named and
has its own symbol. Parked still means working time continues while route capture stops. Paused
still means working time stops. Neither meaning depends on a blue or orange pixel.

Validation retains its warning symbol and explanatory words. Estimates are labelled explicitly;
there is no new green/red judgment of earnings, targets, or historical performance.

## Typography

### Why the system face

SF Pro remains the only family. No font is bundled. All roles use semantic Dynamic Type styles.
The system face keeps native text scaling, familiar glyphs, and consistent app/Live Activity typography.

| Role | Text style | Weight | Width / figures |
| --- | --- | --- | --- |
| `metricHero` | Large Title | Bold | Condensed, tabular; operational timer |
| `financialHero` | Large Title | Semibold | Standard, tabular; financial headline |
| `metric` | Title 3 | Semibold | Condensed, tabular; compact metrics |
| `metricLabel` | Footnote | Medium | Standard |
| `eyebrow` | Footnote | Semibold | Standard; existing short operational labels |
| `title` | Title 3 | Bold | Standard |
| `status` | Subheadline | Semibold | Standard |
| `body` | Subheadline | Regular | Standard |
| `emphasis` | Subheadline | Semibold | Standard |
| `supporting` | Caption | Regular | Standard |
| `control` | Headline | Semibold | Standard |

`DashMetric.Emphasis.financial` selects the financial role explicitly. Nothing guesses whether a
formatted string is money. A missing amount remains ordinary explanatory text, never a financial
headline displaying zero. Metric values, labels, and coverage wrap rather than shrinking.

The stop marker no longer scales its number down to fit. It has a scaled minimum size and can grow
horizontally for longer delivery numbers. The full delivery title remains the accessible name.

## Surfaces and spacing

The existing 2, 4, 8, 12, 16, and 24-point rhythm remains. There is no global spacing increase on
the active-work screen. Financial metric captions use a four-point gap; History and completed-shift
summary rows gain modest vertical breathing room.

- **Native rows:** ordinary records and controls. List/Form still own grouping and outer shape.
- **Cloud summary rows:** financial highlights, applied with `listRowBackground`; no nested card.
- **Supporting inset:** `dashInsetSurface()`, cloud fill with a one-point outline and 16-point radius.
  Used for an Undo offer or reminder, not around every block.
- **Estimate inset:** `dashEstimateSurface()`, no fill and a dashed strong outline with a 16-point
  radius. The title and spoken explanation carry its meaning independently of the outline.
- **State banner:** existing symbol, title, detail, and state-tinted fill; same 16-point inset radius.
- **Canvas:** `dashCanvas()` hides the scroll background and supplies an opaque blue-tinted canvas.
  The pinned entry bar uses the same canvas and retains its separating rule.

Small-radius tokens remain available at eight points. Prominent actions use `dashPrimaryAction()`,
a thin modifier over the native bordered-prominent style with the explicit fill/foreground pair.
The system still owns pressed and disabled feedback. No custom gesture or animation is added.

## Components retained

`DashMetric`, `DashMetricRow`, `DashValueRow`, `DashNotice`, `DashValidationMessage`,
`DashStatusLabel`, `DashStateBanner`, `DashSettingToggle`, `DashStopMarker`, and `DashStopTrack`
remain the shared vocabulary. Native stacks, lists, forms, sheets, alerts, and button styles remain
in charge of interaction. The visual foundation introduces no chart, financial rule, or persistence field.

The Live Activity adopts the shared foreground accent without changing its snapshot, control order,
layout budget, intents, or existing text-size cap. The app's entry bar also retains its existing
accessibility-size cap; those established constraints are not expanded by this visual interval.

Onboarding uses the shared canvas and filled action treatment. Its four illustrations, pages, skip,
completion key, VoiceOver focus, and Reduce Motion behavior remain intact. The artwork is retained,
so this interval does not constitute a full illustration rebrand.

## Accessibility and verification

Use [Apple's accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility)
and the [WCAG contrast benchmark](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)
when evaluating the rendered result. Automated palette checks cover explicit text pairs, not every
translucent system control or every physical lighting condition.

Verify light and dark appearances, default and AX5 text, Bold Text, Increase Contrast, Reduce Motion,
iPhone and iPad. Inspect stacked deliveries, Park versus Pause, Undo and entry bars, financial
coverage, onboarding, empty states, and validation. A screenshot proves only the captured state;
VoiceOver interaction and outdoor readability also require device evaluation.

Keep at least 44-point controls and larger primary driving actions. Do not remove labels or coverage
to make a screenshot cleaner. Preserve the existing accessible summaries and semantic control roles.
The native system continues to handle keyboard, sheet, back-navigation, and interaction feedback.

## Future W-monogram exploration

These are concepts, not approved or generated assets:

1. **Continuous W:** one rounded stroke with two broad valleys. Strongest starting candidate for a
   small app icon and monochrome use. Distinct proportions are needed to avoid a waveform reading.
2. **Converging lanes:** several rounded paths meeting into a W, suggesting income streams joining.
   The meaning is clear, but narrow gaps may disappear at small sizes.
3. **Folded ribbon W:** a broad silhouette formed through positive and negative space. Works without
   color, but folds must avoid a corporate or overly dimensional treatment.

Explore the Continuous W first with a readable lowercase `worklane` wordmark. Check light, dark,
tinted, monochrome, and small sizes. Do not depend on gradients or fine linework. The current
DashPilot icon and public name remain unchanged until a separately approved rebrand and name review.
