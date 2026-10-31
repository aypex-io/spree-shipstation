# How it works

ShipStation polls the store's URL for orders to ship (`GET`) and posts to the
same URL when it creates a label (`POST`). Both requests sign in with the
integration's username and password.

## What ShipStation pulls

The export sends one ShipStation order per **fulfillment** (parcel). An order
with several fulfillments appears once for each, and every copy carries the
order's totals.

A fulfillment is exported when all of these hold:

- it belongs to the store and is **unfulfilled**;
- its order is **placed**, so drafts and canceled orders are left out;
- its order is **paid**: paid, overcharged, partially refunded or owing nothing;
  or, on a store that captures on dispatch or manually, authorized, or partially
  paid with the rest authorized (see
  [payment capture](configuration.md#payment-capture));
- **none of its items is backordered**;
- it is **not a pickup** (a pickup or pickup point delivery method).

Spree repeats most of these checks when it fulfils the parcel, and also checks
that the stock location has the units on hand, so ShipStation is rarely offered
a parcel Spree would refuse.

Other details of the export:

- ShipStation's `start_date` and `end_date` (`MM/DD/YYYY HH:MM`, UTC) limit it
  to fulfillments whose own or whose order's last update falls in that window.
  A date the gem cannot read is ignored. The oldest update comes first.
- `OrderID` is the fulfillment's id and `OrderNumber` its number. Fulfillments
  created on Spree 6 are numbered after their order (`R1001-F1`). Fulfillments
  created before 6.0 keep their old number, so what ShipStation already holds
  does not change.
- Every order has the status `ready`.

## What a ship notice does

ShipStation sends `order_number`, `tracking_number` and `carrier` in the query
string, and an XML body that carries the `OrderID`. The gem finds the
fulfillment in the store by its `OrderID`, or by its number when the body has
none, and then does one of three things:

- **Fulfils it** through Spree's fulfil workflow with the tracking number, and
  answers `200`. The carrier is recorded when ShipStation's name for it matches
  one of Spree's `tracking_carriers` (such as `UPS`, `USPS`, `FedEx` or
  `Royal Mail`). Otherwise Spree works it out from the tracking number.
- **Updates the tracking** when the fulfillment is already fulfilled or
  delivered, and answers `200`. ShipStation retries, and a retry never fulfils
  the parcel or publishes the event a second time.
- **Refuses** with a `400` and a plain-text reason, and changes nothing.

The gem never forces a fulfillment past Spree's paid and backordered checks, and
never splits one.

## Error messages

ShipStation shows the reason for a `400` to the warehouse:

| Message | Cause |
|---|---|
| `Could not find shipment with number …` | The number is unknown or blank, or the `OrderID`'s fulfillment no longer exists |
| `Shipment … does not match order id …` | The `OrderID` belongs to a fulfillment of another order |
| `Tracking number is required` | ShipStation sent no tracking number |
| `Shipment … is canceled` | The fulfillment was canceled in Spree |
| Spree's own message, such as `This order is not paid for yet` | Spree refused to fulfil it, for example because it is unpaid or has backordered units |
| `Could not capture payment: …` | The gateway declined a capture on dispatch, and nothing was kept |
| `Tracking number has already been taken` | A retry for a fulfilled parcel names a tracking number already on another delivery of the same fulfillment |

## Why the `OrderID` comes first

A new fulfillment's number is its place in its order: `R1001-F2` is the second
parcel. When every item is moved out of a parcel, for example with the
dashboard's split or change-location actions, Spree deletes it, and the parcels
after it move up a place and take new numbers. A fulfillment's id never changes,
so the gem trusts the `OrderID` over the number. A notice for a renumbered
parcel still fulfils the right one, and a notice for a deleted parcel gets a
`400` instead of fulfilling the sibling that now has its number. Re-import the
order in ShipStation to pick up its parcels as they are now.

So don't empty a parcel ShipStation has already imported: its copy in
ShipStation can no longer ship.

## Response codes

| Code | When |
|---|---|
| `200` | The export, or a ship notice that was applied |
| `400` | A ship notice was refused (see [error messages](#error-messages)) |
| `401` | Wrong credentials, or the integration's stored credentials are blank |
| `404` | No active ShipStation integration matches the URL, checked before credentials. A switched-off integration counts as none |
