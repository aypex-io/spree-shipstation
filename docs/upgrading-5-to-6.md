# Upgrading from 5.0 to 6.0

1. Bump the gem to `~> 6.0` along with your Spree 6 upgrade.
2. Run `bin/rails db:migrate`, then **`bin/rake spree:upgrade` straight away,
   before ShipStation next polls.**
3. For the default store, change nothing in ShipStation. Any other store needs
   its new URL (below).

## What happens to the data

The gem has no data migration of its own. Spree 6's migrations rename shipments
to fulfillments, keeping their ids and numbers, and copy the integration's
password into `secret_preferences` as plain text. `spree:upgrade` then:

- moves shipment statuses to fulfillment statuses: `ready` and `pending` become
  `unfulfilled`, and `shipped` becomes `fulfilled`;
- backfills the delivery-method providers that the pickup rule reads;
- recomputes the payment and fulfillment statuses of orders whose shipments were
  pending, ready or shipped. An order in another state, such as partly shipped
  or backordered, keeps its 5.x payment status until Spree next updates it;
- encrypts stored secrets, when Active Record encryption keys are configured;
- carries `auto_capture_on_dispatch` over to the store's `capture_method`.

Until it runs, the export is empty, because no fulfillment is `unfulfilled`
yet. A parcel still marked `shipped` counts as fulfilled, so a ship notice only
records its tracking.

## What changes

- **ShipStation, default store:** the same URL, credentials and `ready` status,
  and the same `OrderNumber` for parcels it has already imported.
- **ShipStation, other stores:** each must use its integration's URL,
  `/shipstation/<integration id>` (see [Setup](setup.md#more-than-one-store)).
  5.x picked the store from the request's host; Spree 6 does not, so the bare
  URL serves only the default store.
- **Numbering:** new fulfillments are numbered like `R1001-F1`.
- **Capture on dispatch** follows Spree 6's `capture_method` on the store or
  payment method (see [payment capture](configuration.md#payment-capture)).
- **Unchanged:** unpaid or backordered fulfillments stay out of ShipStation
  until they can ship, as 5.x exported only `ready` shipments.
- **Refusals:** a ship notice Spree will not apply gets a `400` with Spree's
  reason.
- **Shipped email:** Spree 6 core sends none. If your store relied on the 5.x
  email, subscribe to `fulfillment.fulfilled` (see
  [shipped emails](configuration.md#shipped-emails)).
