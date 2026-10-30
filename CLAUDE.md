# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`spree-shipstation` is a Spree e-commerce extension (gem) that integrates Spree stores with [ShipStation](https://www.shipstation.com)'s **Custom Store** integration. It exposes an XML endpoint that ShipStation polls for fulfillments that are ready to ship, and a webhook endpoint that ShipStation POSTs to when a label is created (recording the tracking number and fulfilling the Spree fulfillment).

This gem targets **Spree 6.0** (`spree ~> 6.0`, Ruby >= 3.3). Its major version tracks Spree's. The Spree 5 line lives on the `5-0-stable` branch (5.0.x); `main` tracks the newest line.

This is a **public repo**: README, CHANGELOG, this file, code comments and commit messages carry generic information only. Use example values (`R1001-F1`, `int_abc123`, `shop.example.com`), never real stores, customers, hosts or prices.

### Naming

Three related but distinct names — do not "fix" one to match another:

| | Value | Why |
|---|---|---|
| Gem name | `spree-shipstation` | Dash denotes a gem under another gem's namespace |
| Require path | `spree/shipstation` | `lib/spree-shipstation.rb` is a shim so Bundler's auto-require of the gem *name* still works |
| Ruby namespace | `Spree::Shipstation` | Matches the require path |
| `engine_name` | `spree_shipstation` | Generates route helper prefixes, so it **must** be a valid Ruby identifier — a dash is illegal here |

`ENV["LIB_NAME"]` in the `Rakefile` must be the **require path** (`spree/shipstation`), not the gem name: Spree's `common:test_app` does a literal `require ENV['LIB_NAME']` and templates the same string into the generated `spec/dummy/config/application.rb`. Setting it to the gem name makes dummy-app generation fail with a `LoadError` that surfaces as the entire suite erroring.

## Commands

### Run all tests
```shell
bundle exec rake
```
The default Rake task automatically generates a dummy Rails app under `spec/dummy/` if it doesn't exist, rebuilds its database, then runs the full spec suite.

### Run against a specific Spree version
```shell
SPREE_VERSION=6.0.0 bundle update spree && bundle exec rspec   # the oldest the gemspec allows
bundle update spree && bundle exec rspec                       # the newest release
```
`Gemfile.lock` is not committed. CI runs both versions on Ruby 3.3 and 4.0.

### Generate the test dummy app (first time or after reset)
```shell
bundle exec rake test_app
```

### Run a single spec file
```shell
bundle exec rspec spec/requests/spree/shipstation_spec.rb
```

### Lint (StandardRB) and security (Brakeman)
```shell
bundle exec standardrb
bundle exec standardrb --fix
bundle exec brakeman --force --no-pager --quiet --exit-on-warn
```

Public Ruby classes and methods use YARD `##` blocks. Specs follow one
expectation per example.

## Architecture

### Integration Registration

`config/initializers/spree.rb` appends the class name string `"Spree::Integrations::Shipstation"` to `Spree.integrations` in `config.after_initialize` (Spree 6 still needs that, and the string avoids loading the model before the app has booted). The model (`app/models/spree/integrations/shipstation.rb`) extends `Spree::Integration` and keeps two preferences, `username` (`:string`) and `password` (`:password`, which Spree 6 stores encrypted in `secret_preferences`), with validations.

- The class name stays `Spree::Integrations::Shipstation`: existing rows store it as their STI type.
- Validation messages resolve with `I18n.t` at validation time (a lambda), never `Spree.t` at class load, which is deprecated and raises under Spree 6's test config.
- The dashboard lists the integration through class methods: `integration_group` (`"shipping"`), `integration_name` and the description from I18n, `logo_url` (a `data:` URI built from the bundled logo) and `docs_url`. Spree 6 builds the credentials form from the preferences, so there is no ERB form, asset manifest or `spree_extension`.

### Request Flow

`Spree::ShipstationController` is an `ActionController::Base` (an API controller renders the Builder template as an empty body and has no HTTP Basic helpers). It includes `Spree::Core::ControllerHelpers::Store` and `Pagy::Method`, and skips forgery protection on its two actions since Basic auth is the authentication.

**Routes** (`config/routes.rb`, via `Spree::Core::Engine.add_routes`):

| Route | Action | Store |
|---|---|---|
| `GET /shipstation(.xml)` | `export` | the default store (`current_store`) |
| `POST /shipstation` | `shipnotify` | the default store |
| `GET /shipstation/:integration_id(.xml)` | `export` | the store of the active integration with that `int_…` prefixed id |
| `POST /shipstation/:integration_id` | `shipnotify` | as above |

The export is XML with or without the extension (`defaults: {format: "xml"}`). The `:integration_id` form is how a multi-store host gets one endpoint per store, since Spree 6 resolves the current store as the default store only.

**Every request** first finds the active ShipStation integration (by the path's `:integration_id`, read from `request.path_parameters` so a query-string `integration_id` on the bare URL is ignored, or else the current store's) and answers 404 if there is none, *before* authentication; then sets `Spree::Current.store` to the integration's store; then checks HTTP Basic credentials with `secure_compare` against that integration (blank stored credentials are always refused). Failure answers 401.

**Export (GET)** — ShipStation polls this endpoint to fetch fulfillments ready to ship:
1. `Spree::Shipstation::ExportQuery.new(store:, from:, to:).call` selects the rows (see below). `from`/`to` come from ShipStation's `start_date`/`end_date` (`MM/DD/YYYY HH:MM`, UTC); an unreadable date is dropped.
2. `pagy(query, limit: 50)` paginates (pagy 43 takes `limit:`, not `items:`). Pagy reads `params[:page]` itself and turns a bad one into page 1. Do not pass `page:`: an explicit page skips that coercion, and a string that is not a number then raises a 500.
3. `app/views/spree/shipstation/export.xml.builder` renders the XML through the presenters. It is validated against `spec/fixtures/shipstation_xml_schema.xsd` in tests.

`ExportQuery` returns the store's `unfulfilled` fulfillments whose order is placed (`Spree::Order.placed_orders`), paid (`paid`/`overcharged`/`partially_refunded`, or `total = 0`, or `authorized`/`partially_paid` when the *store's* `capture_method` is `on_dispatch` or `manual`; `partially_paid` is mixed tender, part captured and the rest authorized), with no backordered item and a delivery method that is not pickup or pickup point. A date window matches the fulfillment's *or* its order's `updated_at`. The order is `updated_at, id`, oldest first, replacing the `created_at` order `store.fulfillments` inherits, and the association graph is preloaded.

**Shipnotify (POST)** — ShipStation calls this when a label is created:
1. `Spree::ShipstationController#shipnotify` passes the `order_number`, `tracking_number` and `carrier` query params (nothing else), plus `order_id` from the XML body's `ShipNotice/OrderID`, to `Spree::Shipstation::ShipmentNotice.from_payload(params, store:)`. The body is parsed with Nokogiri's defaults plus `strict` (no network, no entity expansion); an empty, over-64 KB or malformed body, or a missing or non-integer `OrderID`, gives no `order_id`.
2. `ShipmentNotice#apply` resolves the fulfillment within the store. A blank number is "not found". Without an `order_id`: the stored number first (fulfillments created before Spree 6.0 keep theirs), else the derived `<order>-F<n>` number, matched against Spree's own `Fulfillment#number`. With one, the id is authoritative, because a derived number shifts when Spree destroys an earlier, drained parcel: the number only identifies the order (via a stored number, or the regex's order part even if no parcel derives that number now); the id must name a fulfillment of the store (else `ShipmentNotFoundError`, never a fallback to the number) of that same order (else `ShipmentMismatchError`). The stored-number lookup runs only while `Spree::Fulfillment.column_names` includes `number`, which Spree drops in 6.1.
3. Under `order.with_lock` (which serializes ShipStation's retries), it reloads the fulfillment and: records or corrects the tracking only when it is already fulfilled/delivered, or still carries the 5.x `shipped` status that `spree:upgrade` renames (no second fulfilment, no second event); raises for a canceled one; otherwise calls `Spree.fulfillment_fulfill_workflow` with `notify_customer: true` and the carrier when ShipStation's carrier maps to a `Spree.tracking_carriers` key. It **never passes `force:` or `items:`** — forcing would ship an unpaid or backordered parcel, and a partial list would split the parcel under a new number.
4. `Spree::Shipstation::Error` subclasses return HTTP 400 as `text/plain` with the message; success returns 200. A refusal by Spree carries Spree's own message. A gateway decline on capture (`Spree::Core::GatewayError`) is rescued *outside* the lock as `PaymentError`: the whole lock transaction rolls back, so nothing persists.

> **Note on naming:** ShipStation's webhook param is called `order_number` but its value is actually the *fulfillment* number — it mirrors the `<OrderNumber>` field from the export XML. Likewise the body's `<OrderID>` is the fulfillment's id.

### Spree 6 facts this code rests on

- Shipments became fulfillments (`unfulfilled fulfilled delivered canceled`); "ready" is no longer a status, so the XML's `OrderStatus` is the constant `ready` (merchants' ShipStation mappings key on it).
- `Fulfillment#number` is derived (`"#{order.number}-F#{position}"`) and not stored for new rows; do not re-implement the position arithmetic. The position shifts when Spree destroys an earlier parcel (all its items moved out), which is why the notice trusts `OrderID`. The stored `number` column is legacy data that Spree drops in 6.1.
- Capture on dispatch is Spree's: the fulfil workflow captures payments whose method captures on dispatch. The gem has no capture code and no `auto_capture_on_dispatch`.
- Spree 6 core sends no shipped email. The workflow publishes `fulfillment.fulfilled` with `notify_customer`; the host app's subscriber decides. On a gateway decline that event is published inside the transaction that then rolls back (core's own fulfil endpoint behaves the same).
- Spree 6's generated test config raises on missing translations and on the deprecations it disallows (among them `Spree.t` and `Product#master`). Other deprecations, such as `order.ship_total` and `option_type.presentation`, only print a warning, and the suite is kept at zero by grepping its output: `bundle exec rspec > out.txt 2>&1; grep -c "DEPRECATION WARNING" out.txt` must print 0. Avoid all four.

### Key Files

| File | Purpose |
|------|---------|
| `app/controllers/spree/shipstation_controller.rb` | Both endpoints; integration lookup (404), store selection, Basic auth (constant-time `secure_compare`) |
| `config/routes.rb` | The four routes, with the XML default for the export |
| `app/models/spree/integrations/shipstation.rb` | Integration record: credential preferences, validations, dashboard listing |
| `lib/spree/shipstation/export_query.rb` | `ExportQuery`: which fulfillments are exported, date window, order, preloads |
| `lib/spree/shipstation/shipment_notice.rb` | Plain Ruby object that applies a ship notification through Spree's fulfil workflow |
| `lib/spree/shipstation/errors.rb` | Error hierarchy (`ShipmentNotFoundError`, `ShipmentMismatchError`, `MissingTrackingNumberError`, `FulfillmentCanceledError`, `FulfillmentRefusedError`, `PaymentError`) |
| `lib/spree/shipstation/engine.rb` | Engine only (no decorators remain); `engine_name` is `spree_shipstation` |
| `lib/spree-shipstation.rb` | Bundler auto-require shim; only does `require "spree/shipstation"` |
| `app/presenters/spree/shipstation/export/` | `OrderPresenter`, `ItemPresenter`, `Weight`: shape a fulfillment into the XML's values |
| `app/helpers/spree/shipstation/export_helper.rb` | Helper methods for building address XML nodes |
| `app/views/spree/shipstation/export.xml.builder` | XML template for ShipStation export |
| `config/locales/en.yml` | Integration description, brand name and validation messages |

### Testing

- The `spec/dummy` app is generated by Spree 6's `rake test_app` and is git-ignored; `spec/spec_helper.rb` loads it plus `spree_dev_tools`' RSpec setup, with a 90% line coverage floor.
- Endpoint behaviour is tested by **request specs** (`spec/requests/spree/shipstation_spec.rb`) through the real routes with Basic auth; there are no controller specs. Ship notices fulfil through the real Spree workflow — only ShipStation's side is simulated.
- `spec/lib/spree/shipstation/export_query_spec.rb` covers each export-filter case (paid, unpaid, backordered, free, deferred capture, partially paid, pickup, canceled, draft, partially refunded) and the date window, on the default store so the factory's rate refresh selects a standard delivery method; `shipment_notice_spec.rb` covers resolution (by number, and by `OrderID` including a parcel Spree dissolved), retries, the legacy `shipped` status, refusals and capture.
- `spec/support/xsd.rb` — provides the `pass_validation(xsd_path)` RSpec matcher for XML schema validation.
- `lib/spree/shipstation/testing_support/factories/shipstation_integration.rb` — FactoryBot factory for `Spree::Integrations::Shipstation`, loaded via `require "spree/shipstation/factories"` in `spec/spec_helper.rb`.
- `spree_dev_tools` is constrained (`~> 1.0`) in the **Gemfile**: the gemspec no longer declares it, and Bundler 2 would otherwise resolve 0.6.3, which is broken on Spree 6.
