# spree-shipstation

![CI](https://github.com/aypex-io/spree-shipstation/workflows/CI/badge.svg)
![Standard Rb](https://github.com/aypex-io/spree-shipstation/workflows/Standard%20Rb/badge.svg)

The spree-shipstation integration connects your Spree stores with [ShipStation](https://www.shipstation.com), allowing ShipStation to pull the fulfillments that are ready to ship from your store, and when one is sent, update the order with a tracking number and mark it as fulfilled.

## Requirements

- Spree 6 (`~> 6.0`)
- Ruby 3.3 or newer

Spree 5 stores stay on the 5.0.x releases, which live on the [`5-0-stable`](https://github.com/aypex-io/spree-shipstation/tree/5-0-stable) branch:

```ruby
gem "spree-shipstation", "~> 5.0"
```

## Installation

1. Add this extension to your Gemfile with this line:

    ```ruby
    gem "spree-shipstation", "~> 6.0"
    ```

2. Install the gem using Bundler

    ```shell
    bundle install
    ```

The extension registers itself with Spree's integration framework automatically — there are no migrations or generators to run.

### Step 1: Configuring Spree

Visit the **Integrations** section of your Spree dashboard and configure the ShipStation integration (listed with the shipping integrations) by creating a unique username and password. The username is 10 to 30 characters of letters, numbers and `. _ @ + -`; the password is 20 to 60 characters and needs an uppercase letter, a number and a special character, one of `! @ # $ % ^ & * ( ) , . ? " : { } | < >`. Other characters such as `-`, `_`, `+` and `=` may appear but do not count as the special character.

### Step 2: Configuring ShipStation

Create a new ShipStation store by visiting: **Settings** -> **Selling Channels** -> **Stores** -> **Add Store**, then selecting the **Custom Store** option.

Enter the following details:

- **Username**: The username you created in Step 1.
- **Password**: The password you created in Step 1.
- **URL to custom page**: `https://shop.example.com/shipstation.xml`.

That URL belongs to your **default store**. Any other store (a multi-store setup) must use the URL that names its ShipStation integration:

```
https://shop.example.com/shipstation/int_abc123.xml
```

`int_abc123` stands for the integration's prefixed ID, which starts with `int_`. In a Rails console, `Spree::Integrations::Shipstation.all.map(&:prefixed_id)` lists them. The credentials are always the ones set on that integration. The `.xml` is optional on both URLs.

### Order status

Every order the gem sends has the status `ready`, so in ShipStation's Custom Store settings map `ready` to **Awaiting Shipment**. ShipStation's other statuses are never sent: the gem exports only fulfillments that can ship now, and ShipStation marks one as shipped itself once the label exists.

ShipStation description | ShipStation status | Sent by the gem
------------------------|--------------------|----------------
Awaiting Shipment       | `paid`             | `ready`
Anything else           | —                  | never; only `ready` is exported

## What ShipStation pulls

Spree 6 splits an order into fulfillments (parcels), and the gem exports one ShipStation order per fulfillment. An order with several fulfillments therefore appears once for each, every copy carrying the order's totals.

A fulfillment is exported when all of these hold:

- it belongs to the store and is still **unfulfilled**;
- its order is **placed**, so drafts and canceled orders are left out;
- its order is **paid**: paid, overcharged or partially refunded; or it owes nothing (a total of zero); or, on a store whose capture method is `on_dispatch` or `manual`, it is only authorized, or partially paid with the rest authorized (mixed tender, such as store credit plus a card) (see [Payment capture](#payment-capture));
- **none of its items is backordered**;
- it is **not a pickup**: fulfillments collected in person (pickup or pickup point delivery methods) are not shipped.

Apart from the pickup rule, these are most of the checks Spree makes again when the parcel is fulfilled, so ShipStation is rarely offered a parcel Spree would refuse. When it is fulfilled, Spree also checks that the stock location has the units on hand, and the limits under [Payment capture](#payment-capture) apply. A parcel refused then gets a `400` with Spree's reason.

ShipStation's `start_date` and `end_date` (`MM/DD/YYYY HH:MM`, UTC) limit the export to fulfillments whose own or whose order's last update falls in that window. A date the gem cannot read is ignored. Results are ordered by last update, oldest first.

`OrderID` is the fulfillment's id and `OrderNumber` its number. Fulfillments created on Spree 6 are numbered after their order, for example `R1001-F1`; fulfillments created before 6.0 keep the number they already had, so what ShipStation already holds does not change.

## What happens on a ship notice

When a label is created, ShipStation posts to the same URL with `order_number` (the `OrderNumber` it was given), `tracking_number` and `carrier` in the query string, and the notice again as an XML body that carries the `OrderID` it was given. The gem finds that fulfillment in the store, by its `OrderID` when the body carries one and by its number otherwise, and:

- **fulfils it** through Spree's own fulfil workflow, recording the tracking number, and answers `200`;
- records the carrier when ShipStation's carrier name matches one of Spree's `tracking_carriers` (for example `UPS`, `USPS`, `FedEx` or `Royal Mail`); otherwise Spree detects it from the tracking number;
- if the fulfillment is **already fulfilled or delivered**, only records or corrects the tracking number and answers `200`. ShipStation retries, and a retry does not fulfil the parcel or publish the event again. The one exception is a tracking number that is already on a different delivery of the same fulfillment, which is refused (below);
- otherwise answers `400` with a plain-text reason and changes nothing. ShipStation shows the reason to the warehouse. The reasons include:
  - `Could not find shipment with number …`, for an unknown or blank number, or an `OrderID` whose fulfillment no longer exists;
  - `Shipment … does not match order id …`, when the `OrderID` belongs to a fulfillment of another order;
  - `Tracking number is required`;
  - `Shipment … is canceled`;
  - Spree's own message when it refuses to fulfil, for example `This order is not paid for yet`, or its message about backordered units;
  - `Could not capture payment: …`, when the gateway declines a capture on dispatch;
  - `Tracking number has already been taken`, when a retry for a fulfilled parcel names a tracking number that already belongs to another delivery of the same fulfillment.

The gem never forces a fulfilment past Spree's paid and backordered checks, and never splits a fulfillment.

### Why the `OrderID` comes first

A new fulfillment's number is its place in its order: `R1001-F2` is the second parcel. When every item is moved out of a parcel (with the dashboard's split or change-location actions, say), Spree deletes it, and the parcels after it move up a place and take new numbers. A fulfillment's id never changes, so the gem trusts the `OrderID` over the number. A notice for a renumbered parcel still fulfils the right one, and a notice for a parcel Spree deleted after ShipStation imported it is refused with a `400` rather than fulfilling a sibling that now has its number. Re-import the order from ShipStation to pick up its parcels as they now are.

So, in an order with several parcels, avoid moving every item out of a parcel ShipStation has already imported: that parcel is no longer valid in ShipStation.

## Configuration

### Payment capture

The gem has no capture setting of its own. Capture on dispatch follows Spree 6's `capture_method`, set on the store and optionally overridden by each payment method:

- `checkout` (the default) charges as the order is placed. Authorized orders are not yet paid, so they are not exported.
- `on_dispatch` authorizes at checkout and charges when the fulfillment is fulfilled. The gem exports authorized orders, and partially paid ones whose rest is authorized, and Spree captures the payment as the ship notice is applied. If the gateway declines, ShipStation gets a `400` ("Could not capture payment: …") and nothing is kept: the fulfillment stays unfulfilled, the payment stays pending and any tracking number written during the attempt is rolled back. The next retry, or the merchant's fix to the payment, fulfils it.
- `manual` authorizes at checkout and leaves charging to your staff. The gem exports authorized and partially paid orders, and Spree lets them ship without charging them.

Two limits:

- Whether an authorized or partially paid order is exported depends on the **store's** capture method only. A store that captures at checkout but has a payment method that overrides it to `on_dispatch` never exports that method's authorized orders, and does so silently. To export them, set the store's capture method to `on_dispatch` or `manual`, bearing in mind that this changes it for every payment method that has no setting of its own. In the reverse case, a store set to `on_dispatch` with a payment method overridden to capture at checkout, an authorized order is exported and the ship notice is then refused with Spree's reason.
- A partially refunded order is exported, because the rest of it may still ship, but Spree compares the net captured amount (after refunds) with what the order was due, so the ship notice may still be refused with Spree's reason. Likewise a partially paid order ships only while the rest is authorized on payment methods that defer capture.

### Fulfillment providers

Give the delivery methods whose parcels ShipStation ships Spree's **Manual** fulfillment provider. On a ship notice, Spree's fulfil workflow also buys a label and tells the delivery method's provider that the parcel has shipped; for Manual, both do nothing. A provider that buys labels or hands parcels to a 3PL would act a second time for a parcel ShipStation has already shipped. A declined capture on dispatch does not undo those calls either, even though everything Spree wrote is rolled back.

### Telling the customer

Spree core does not send a shipped email by itself (as of Spree 6.0.1). When a fulfillment is fulfilled, Spree publishes the `fulfillment.fulfilled` event, and the gem asks for the customer to be notified (`notify_customer: true`). Your application decides whether, and how, to tell the customer, by subscribing to `fulfillment.fulfilled`. Without a subscriber, no shipped email goes out.

One caveat: when a capture on dispatch is declined, Spree publishes `fulfillment.fulfilled` synchronously inside the transaction that is then rolled back. A subscriber that notifies at once, rather than after the transaction commits, can tell a customer their order has shipped when the attempt was declined and nothing was kept. Spree's own fulfil endpoint behaves the same way, so if that matters to you, make your subscriber send only after the transaction has committed.

### Pagination

The export endpoint returns up to **50 fulfillments per page**. ShipStation handles pagination automatically using the `page` query parameter; a `page` that is not a number is read as the first page.

## Upgrading from 5.0

- Bump the gem to `~> 6.0` alongside your upgrade to Spree 6.
- The gem has no data migration of its own. Spree 6's migrations rename shipments to fulfillments, keeping their ids and numbers, and move the integration's password into `secret_preferences`, encrypted when Active Record encryption is configured.
- **Run `bin/rake spree:upgrade` right after `db:migrate`, before ShipStation next polls.** Spree's upgrade tasks move 5.x shipment statuses to fulfillment statuses (`ready` and `pending` become `unfulfilled`, `shipped` becomes `fulfilled`), backfill the delivery-method providers the pickup rule reads, recompute orders' payment and fulfillment statuses, and carry settings such as `auto_capture_on_dispatch` over to the store's `capture_method`. Until then the export is empty, since no fulfillment is `unfulfilled` yet. Meanwhile a parcel still marked `shipped` is treated as fulfilled: a ship notice only records its tracking.
- **ShipStation needs no changes** for the default store: same URL, same credentials, same `OrderNumber` for parcels it has already imported, same `ready` status.
- New fulfillments are numbered like `R1001-F1`. A store other than the default must use `/shipstation/<integration id>` (see Step 2): 5.x picked the store from the request's host, and Spree 6 does not, so the bare URL serves only the default store.
- Capture on dispatch now follows Spree 6's `capture_method` setting (on the store or the payment method). Spree's upgrade task carries `auto_capture_on_dispatch` over to the store's `capture_method`.
- As before, unpaid or backordered fulfillments do not appear in ShipStation until they can ship: 5.x exported only `ready` shipments.
- A ship notice for something Spree will not ship is answered with `400` and Spree's reason.
- Spree 6 core sends no shipped email on its own, so subscribe to `fulfillment.fulfilled` if your store relied on the 5.x email (see [Telling the customer](#telling-the-customer)).

## Security considerations

- **Serve the endpoints over HTTPS.** Both `/shipstation` endpoints authenticate with HTTP Basic Auth, which transmits the configured username and password (base64-encoded) on every request. Always terminate these requests over TLS in production so the credentials are not exposed in transit. Credentials are compared in constant time to avoid timing attacks, and an integration whose stored username or password is blank refuses every request.
- **Consider rate limiting.** The gem does not throttle authentication attempts. If you want brute-force protection, add it at the application or edge layer (for example, [`rack-attack`](https://github.com/rack/rack-attack) or Rails' `rate_limit`). The enforced credential length (10–30 character username, 20–60 character complex password) already makes guessing impractical.
- **Response codes.** When no active ShipStation integration is configured, the endpoints respond with `404` before authentication is checked; a configured-but-unauthenticated request responds with `401`. This is intentional, but be aware it reveals whether the integration is configured. An integration that is switched off is the same as none.

## Performance

The export query eager-loads its association graph to avoid N+1 queries. It selects unfulfilled fulfillments, joins their orders and filters by payment status, and orders and windows by `updated_at`. The gem ships no migrations of its own. Spree 6's schema indexes `spree_fulfillments.status` and `spree_orders.payment_status`, but not `spree_fulfillments.updated_at` or `spree_orders.updated_at`; on large stores, consider indexing those two in your application's database.

## Usage

There's nothing you need to do. Once properly configured, the integration just works!

### Compatibility

spree-shipstation | Spree | Ruby
------------------|-------|------
6.0.x             | 6.x (`~> 6.0`) | 3.3 or newer
5.0.x, on [`5-0-stable`](https://github.com/aypex-io/spree-shipstation/tree/5-0-stable) | 5.x | 3.1 or newer

### Testing

First bundle your dependencies:

```shell
bundle
```

To run the tests use:

```shell
bundle exec rake
```

CI runs the suite against Spree 6.0.0 and the newest 6.x release. To test against a specific Spree version locally:

```shell
SPREE_VERSION=6.0.0 bundle update spree
bundle exec rake
```

### Code Formatting

To check your code formatting with [Standard Rb](https://github.com/testdouble/standard) run:

```shell
bundle exec standardrb
```

To fix basic code formatting issues run:

```shell
bundle exec standardrb --fix
```

## Releasing

Bump `Spree::Shipstation::VERSION` in `lib/spree/shipstation/version.rb`, add the release to the changelog, and merge. Pushing a `v*` tag publishes the gem to RubyGems through the Release workflow.

## License

Copyright (c) 2021-2026 Matthew Kennedy, released under the MIT License.

## Code of Conduct

Everyone interacting in this project's codebases, issue trackers, and
communication channels is expected to follow the [code of
conduct](CODE_OF_CONDUCT.md).
