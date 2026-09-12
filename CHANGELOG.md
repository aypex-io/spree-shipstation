# Changelog

All notable changes to this project are documented in this file.

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
