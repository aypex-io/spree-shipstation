# Configuration

Apart from its credentials, the integration has no settings. It follows these
Spree settings.

## Payment capture

Capture follows Spree 6's `capture_method`, set on the store and optionally
overridden by a payment method:

| `capture_method` | Exported | On the ship notice |
|---|---|---|
| `checkout` (default) | Paid orders only | Nothing to capture |
| `on_dispatch` | Also orders that are authorized, or partially paid with the rest authorized | Spree captures the payment |
| `manual` | As `on_dispatch` | Ships without charging; your staff capture later |

If the gateway declines a capture on dispatch, ShipStation gets a `400`
(`Could not capture payment: …`) and nothing is kept: the fulfillment stays
unfulfilled, the payment stays pending, and any tracking number written during
the attempt is rolled back. ShipStation's next retry, or a fix to the payment,
fulfils it.

Two limits:

- **Only the store's capture method decides what is exported.** If the store
  captures at checkout and a payment method is overridden to `on_dispatch`, that
  method's authorized orders are never exported, and nothing says so. To export
  them, set the store to `on_dispatch` or `manual`, which also changes every
  payment method without a setting of its own. The reverse case, a store on
  `on_dispatch` with a payment method set to capture at checkout, exports the
  authorized order, and the ship notice is then refused with Spree's reason.
- **Refunds and split payments can still be refused.** A partially refunded
  order is exported, since the rest may still ship, but Spree compares the net
  captured amount with what the order owes and may refuse the ship notice. A
  partially paid order ships only while the rest is authorized on a payment
  method that defers capture.

## Fulfillment providers

Give the delivery methods that ShipStation ships Spree's **Manual** fulfillment
provider. On a ship notice, Spree's fulfil workflow also buys a label and tells
the provider the parcel has shipped, and Manual does nothing for either. A
provider that buys labels or hands parcels to a 3PL would act a second time on a
parcel ShipStation has already shipped, and a declined capture does not undo
those calls.

## Shipped emails

Spree 6 core sends no shipped email (as of 6.0.1). On a ship notice, Spree
publishes `fulfillment.fulfilled` with `notify_customer: true`. To tell the
customer, subscribe to that event in your application. Without a subscriber, no
email goes out.

Send only after the transaction commits. When a capture on dispatch is declined,
Spree publishes the event inside the transaction that it then rolls back, so a
subscriber that sends at once can announce a shipment that never happened.
Spree's own fulfil endpoint behaves the same way.

## Pagination

The export returns 50 fulfillments per page, and ShipStation requests the next
page itself with `page`. A `page` that is not a number is read as page 1.
