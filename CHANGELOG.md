# Changelog

All notable changes to this project are documented in this file.

## 6.0.4

### Changed

- The dashboard's **Setup guide** link opens a setup page for store staff
  (`docs/setup.md`) instead of the README.
- The README is now a short overview. Install, setup, configuration, how it
  works, upgrading from 5.0 and development each have their own page under
  `docs/`, which the gem's RubyGems page links as its documentation.

## 6.0.3

### Changed

- The dashboard icon is ShipStation's gear alone, cropped edge to edge on a
  transparent background, so the dashboard's own tile supplies the padding and
  white background. 6.0.2's icon was a green square that sat oddly inside that
  tile.

## 6.0.2

### Changed

- The integrations dashboard shows ShipStation's square app icon instead of the
  wide wordmark, which was too small to read in the dashboard's icon tile. The
  icon is a 3 KB PNG, down from the 17 KB WebP.

## 6.0.1

### Fixed

- The export no longer fails with a 500 (`undefined method 'attachment_path'`)
  for an order whose items have an image.
- `ImageUrl` is now an absolute URL on the host ShipStation polls, so ShipStation
  can fetch item images (#21).

## 6.0.0

Spree 6 support. The major version tracks Spree's, so `spree-shipstation` 6.x
supports Spree 6, and Spree 5 stays on the 5.0.x releases (the `5-0-stable`
branch).

**Nothing ShipStation or the merchant has configured has to change** for the
default store. The `/shipstation` URL, the credentials, the XML, the `ready`
status and the `OrderNumber` of every fulfillment ShipStation already holds stay
as they were. A store other than the default moves to its integration's URL
(below).

**Run `bin/rake spree:upgrade` right after `db:migrate`, before ShipStation next
polls.** Spree's upgrade tasks move 5.x shipment statuses to fulfillment statuses
(`ready` and `pending` become `unfulfilled`, `shipped` becomes `fulfilled`),
backfill the delivery-method providers the pickup rule reads, recompute the
statuses of orders whose shipments were pending, ready or shipped, encrypt stored
secrets, and carry `auto_capture_on_dispatch` over to the store's
`capture_method`. Until then the export is empty. See
[Upgrading from 5.0](docs/upgrading-5-to-6.md).

**Requirements:** Spree `~> 6.0`, Ruby 3.3 or newer, pagy 43.6 or newer. The 5.x
releases do not install on Spree 6.

### Changed

- **Orders are exported per fulfillment**, since Spree 6 replaced shipments with
  fulfillments. `OrderID` is the fulfillment's id and `OrderNumber` its number:
  the number a fulfillment already had before Spree 6, or `R1001-F1` style
  (order number, `-F`, position) for new ones. Totals stay order-level, as before.
- **Only fulfillments Spree will let ship are exported**: placed, still
  unfulfilled, paid, with nothing backordered, and not a pickup. "Paid" means
  paid, overcharged or partially refunded; or nothing owed; or, on a store whose
  capture method is `on_dispatch` or `manual`, authorized, or partially paid with
  the rest authorized (mixed tender, such as store credit plus a card). As before,
  unpaid or backordered fulfillments do not appear in ShipStation until they can
  ship: 5.x exported only `ready` shipments. Results are ordered by last update,
  oldest first.
- **Ship notices fulfil through Spree 6's fulfil workflow.** When Spree refuses
  (an unpaid order, backordered items, a canceled fulfillment) the notice is
  answered with `400` and Spree's reason, and nothing is recorded. It is never
  answered `200` for a fulfillment Spree did not ship.
- **Ship notices are retry-safe.** A notice for a fulfillment that is already
  fulfilled or delivered only records or corrects the tracking number: it does
  not fulfil the parcel or publish the event again. A retry that names a tracking
  number already on another delivery of the same fulfillment is refused with
  `400` ("Tracking number has already been taken"). Concurrent retries are
  serialized under the order's row lock. A parcel still marked `shipped` from 5.x,
  before Spree's upgrade task renames the status, is treated the same way.
- **A notice without an order number is refused** with `400`. New fulfillments
  store no number, so a blank one would otherwise match any of them.
- **Capture on dispatch follows Spree 6's `capture_method`**, set on the store or
  overridden per payment method. A declined capture answers `400` ("Could not
  capture payment: ...") and keeps nothing: the fulfillment stays unfulfilled,
  the payment stays pending and the tracking written during the attempt is rolled
  back, so the retry starts from the same place.
- **Shipped notifications are the host app's to send.** Spree 6 core sends no
  shipped email itself. The fulfil workflow publishes `fulfillment.fulfilled` with
  `notify_customer` set, and your application's subscriber decides whether, and
  how, to tell the customer. On a declined capture core publishes that event
  inside the transaction that is then rolled back, so a subscriber that notifies
  at once can announce a shipment that did not happen (Spree's own fulfil endpoint
  behaves the same).
- `ImageUrl` uses the media's still image, so a video thumbnail exports its
  poster. It is still a root-relative path.
- The export returns **50 fulfillments per page**, as documented. (pagy 43, which
  Spree 6 requires, ignores the option the gem used to set this and would have
  given 25.) A `page` that is not a number is read as page 1.
- The integration appears in Spree 6's dashboard under the shipping group, with a
  description, logo and link to the README. Its form is generated from the
  username and password preferences. Spree 6's migration copies the password into
  `secret_preferences` as plain text, and `bin/rake spree:upgrade` encrypts it
  when Active Record encryption keys are configured.
- Both endpoints now run on a plain `ActionController::Base` controller, since
  Spree 6 removed the base controller and helper the 5.x one used.

### Added

- **`/shipstation/<integration id>`** (`GET` and `POST`, with or without `.xml`)
  serves the store of the active ShipStation integration with that `int_` prefixed
  id. Spree 6 no longer picks the store from the request's host, so a multi-store
  host points each store's ShipStation at its own integration's URL. The bare
  `/shipstation` path is unchanged and belongs to the default store.
- **Ship notices are matched on ShipStation's `OrderID`** when the notice's XML
  body carries it. A new fulfillment's number is its place in its order, so when
  Spree deletes a parcel whose items were all moved out, the parcels after it
  take new numbers; the `OrderID` (the fulfillment's id) does not change. A notice
  whose `OrderID` belongs to another order is refused with `400` ("Shipment ...
  does not match order id ..."), and one for a parcel Spree has deleted since
  ShipStation imported it is refused with `400` instead of fulfilling the sibling
  that now has its number; re-import the order from ShipStation. A notice without
  an `OrderID` is matched on its number.
- **The `carrier` ShipStation sends** is recorded on the delivery when it matches
  one of Spree's `tracking_carriers` (for example `UPS` or `Royal Mail`). Otherwise
  Spree detects the carrier from the tracking number.
- `GET /shipstation` without the `.xml` extension answers with XML.
- An integration whose stored username or password is blank refuses every request.

### Removed

- The gem's own payment-capture code and its use of **`auto_capture_on_dispatch`**.
  Spree 6's `capture_method` replaces that setting, and Spree's upgrade task
  carries it over to the store's `capture_method`.
- The `Spree::Shipment` decorator and its `exportable` and `between` scopes. The
  gem no longer patches core models; `Spree::Shipstation::ExportQuery` selects what
  is exported.
- The ERB admin form, the asset manifest and the `spree_extension` dependency.

### Internal

- Specs run against the real routes and Spree's real fulfil workflow, with only
  ShipStation's side simulated. The suite runs with no deprecation warnings.
- CI tests the oldest and newest Spree 6 the gem allows (6.0.0 and the latest
  release) on Ruby 3.3 and 4.0, weekly as well as on pushes.

## 5.0.1

### Fixed

- Export the correct `<Quantity>` for lines ordered more than once. Spree 5 stores
  a quantity on each `Spree::InventoryUnit` rather than creating one unit row per
  item, so counting rows reported every line as a quantity of 1 and ShipStation
  under-picked multi-quantity orders. The quantity is now summed across the
  line's inventory units, which also keeps a line split across shipments
  reporting only the units in its own shipment.

## 5.0.0

First public release on RubyGems, as `spree-shipstation`.

This gem was developed under the working name `spree_shipstation` but was never
published under it — that name is held on RubyGems by an unrelated, abandoned
2014 project. Releasing as `spree-shipstation` also lets the gem name, the require
path, and the Ruby namespace agree with each other, per the RubyGems convention
that a dash denotes a gem living under another gem's namespace.

**Versioning:** the major version tracks Spree's major version — `spree-shipstation`
5.x supports Spree 5.x. This release therefore starts at 5.0.0 rather than 1.0.0,
and continues the repository's existing tag lineage (which reached `v3.0.0` before
the rename).

If you tracked this repository from git before 5.0.0, note:

- **Gem name** is `spree-shipstation`. `gem "spree-shipstation"` is all a host app
  needs — `Bundler.require` resolves through a shim at `lib/spree-shipstation.rb`.
- **Require path** is now `spree/shipstation` (was `spree_shipstation`).
- **Ruby namespace** is now `Spree::Shipstation` (was `SpreeShipstation`). This
  affects `Spree::Shipstation::ShipmentNotice`, the error hierarchy
  (`Spree::Shipstation::Error` and subclasses), `Spree::Shipstation::ExportHelper`,
  and `Spree::Shipstation::Export::{OrderPresenter,ItemPresenter,Weight}`.
- **Test factories** are loaded with `require "spree/shipstation/factories"`.
- **Unchanged:** the `Spree::Integrations::Shipstation` integration model,
  `Spree::ShipstationController`, both `/shipstation` routes, the admin form
  partial, and all i18n keys. Existing installations need no data or config
  changes.

### Features

- XML export endpoint (`GET /shipstation`) for ShipStation to poll ready shipments,
  paginated at 50 per page and validated against ShipStation's XML schema.
- Shipnotify webhook (`POST /shipstation`) that applies tracking numbers and ships
  shipments, capturing pending payments first when `auto_capture_on_dispatch` is on.
- HTTP Basic Auth against per-store credentials, compared in constant time.
- Registers with Spree's integration framework; no migrations or generators to run.
- Tested against Spree 5.2, 5.3, and 5.4.
