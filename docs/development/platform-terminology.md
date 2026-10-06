# Platform-neutral terminology audit

DashPilot is meant to serve any delivery driver, not only restaurant delivery: DoorDash, Uber Eats,
Grubhub, Amazon Flex, Walmart Spark and courier or package work. This page records where the code
and the interface already say that, and where they assume restaurant food delivery. It is a
starting point for a later interval. **Nothing here has been renamed or migrated.**

Each term is classified as:

- **A. Already generic**: correct for every platform as it stands.
- **B. Wording only**: an interface or documentation string; changing it changes no meaning.
- **C. Domain-model assumption**: a rule in the model that fits restaurant delivery and not every
  platform.
- **D. Future migration**: changing it would move stored or exported names.

## Findings

| Term | Where | Class | Notes |
| --- | --- | --- | --- |
| Delivery | `Delivery`, cards, export `deliveries[]` | A | One drop-off with its own lifecycle. A package is a delivery too. |
| Pickup, pickup place | `PickupPlace`, `Arrived at Pickup`, `Picked Up`, export `pickupPlace` | A | A store, a restaurant, a warehouse and a delivery station are all pickups. |
| Customer, drop-off | `To customer`, `Heading to the customer`, `Same drop-off` | A | The person or door an order goes to, on every platform. |
| Offer | `Offer`, `Start Offer`, export `offerNumber` | A, with a C caveat | One acceptance of one or more deliveries. Amazon Flex accepts a **block**: a scheduled window paid as a whole, with many packages. See below. |
| Restaurant | Code comments and a few documentation pages | B | No interface string says restaurant. The Settings footer did ("which restaurant you are at") and now says "where you are"; that is the only string changed. Documentation examples use it where a pickup is meant. |
| Food, meal | One documentation phrase ("how long until I got the food") | B | A quoted example in the pickup-wait page. |
| Merchant | Documentation only (no scoring, no merchant field) | B | Already phrased as something DashPilot does not do. |
| DoorDash, Uber, Amazon, Walmart | README, documentation and the welcome's last screen, always as "not connected" | A | Named only to disclaim an integration. |
| The app's name | `DashPilot`, `DashDesign`, bundle identifiers | D | A product name, not a domain claim. Renaming it is a separate decision. |
| Per-delivery lifecycle | `accepted`, `arrivedAtPickup`, `pickedUp`, `delivered`, `cancelled` | C | Fits one pickup per delivery. A Flex block has **one** pickup for dozens of drop-offs; today that would be dozens of deliveries each recording the same arrival and pickup, which `Same pickup` can express (now across offers, from Edit Stack) but which the UI bounds (the new-offer stepper stops at 10). |
| Delivery pay | `grossEarningsAmount`, expected pay, tips | C | Per-delivery pay fits app-based food delivery. Flex and Spark pay per block or per batch; that is what shift gross already records, so the model holds it, but per-delivery figures would be missing for every such delivery. |
| Pickup wait | Per pickup place, median of waits | A | A station's line-up wait is a pickup wait. |
| Live Activity rows | Up to three order rows, within a per-state line budget | C (presentation) | Fine for two or three stacked orders; a route of 40 packages would be a row or two and "N more also active". |
| Export field names | `deliveries`, `pickupPlace`, `offerNumber`, `pickupRecordedBy`, `sharedPickupGroup` | A | Generic as written. Any rename to platform terms would be a format-version bump (D). |

## What a platform-neutral interval would need to decide

1. Whether a **block or route** (many drop-offs, one pickup, pay for the whole) is a new kind of
   offer, or an offer with a flag, and how its pay relates to shift gross.
2. Whether a route's drop-offs need a lighter lifecycle than four taps each.
3. How the Live Activity and History summarise dozens of deliveries without listing them.
4. Which of the above moves stored or exported names, and therefore needs a migration and an export
   version.

None of these is answered by renaming words, which is why this interval renamed nothing.
