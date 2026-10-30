# spree-shipstation: Spree 6 port — design

## Intent

`spree-shipstation` connects a Spree store to ShipStation's **Custom Store** integration:

- ShipStation **pulls** orders that are ready to ship from `GET /shipstation(.xml)`, an XML export.
- When a label is created, ShipStation **posts** a ship notice to `POST /shipstation`. The gem records the tracking number and marks the parcel shipped in Spree.

Both endpoints authenticate with HTTP Basic, using credentials held on a per-store `Spree::Integrations::Shipstation` record.

The gem is 5.x only (`spree >= 5.0, < 6.0`) and does not work on Spree 6:

- It won't install.
- Its controller base and helper are gone.
- Its "ready" filter matches nothing, so the export comes back empty.
- Shipment numbers are no longer stored, so every ship notice would fail to find its parcel.
- `ship!` returns a failure instead of raising, so a straight port would answer 200 to ShipStation without shipping anything.

This port makes the gem a Spree 6 extension (gem version **6.0.0**, tracking Spree's major) **without changing anything ShipStation or the merchant has configured**: the URL, the credentials, the XML, the numbers ShipStation already holds, and the status strings it maps.

The API mapping this design relies on, with file:line evidence from Spree 6.0.1 and runtime probes, was compiled during design. Its conclusions are restated below wherever they drive a decision.

## Goals

1. Install and run on Spree `~> 6.0`, with Ruby ≥ 3.3, and with zero deprecation warnings under Spree 6's generated test config.
2. Keep the ShipStation contract byte-compatible for an existing store:
   - same paths (`/shipstation`, `/shipstation.xml`);
   - same Basic-auth credentials (the integration's STI class name stays `Spree::Integrations::Shipstation`, so existing rows load);
   - XML that still validates against ShipStation's schema (`spec/fixtures/shipstation_xml_schema.xsd`);
   - `OrderStatus` still `ready`;
   - `OrderID`/`OrderNumber` for a parcel exported under 5.x unchanged.
3. Export exactly the parcels Spree will let the warehouse ship: placed orders, unfulfilled, paid, nothing backordered, and not collected in person.
4. A ship notice either fulfils the parcel or answers ShipStation with a 4xx and the reason. It never answers 200 for a parcel Spree didn't ship.
5. Retry-safe ship notices: ShipStation retries, and a retry for an already-shipped parcel succeeds without shipping it or publishing `fulfillment.fulfilled` twice.
6. Same CI quality bar as this org's other gems:
   - a matrix of Spree 6.0.0 and the newest release, each on Ruby 3.3 and 4.0, run weekly;
   - StandardRB, Brakeman and bundler-audit kept;
   - a trusted-publishing release that survives `rubygems/release-gem`'s preload (the fix from `spree-paypal_merchant`).

## Non-goals

- A ShipStation API (push) integration, a Spree `FulfillmentProvider`, shipping labels or rates. The Custom Store pull model stays.
- A dashboard plugin, for example one showing the URL to paste into ShipStation. Spree 6's dashboard builds the credentials form from the preferences; the README tells merchants the URL.
- Partial shipments from ShipStation (splitting a parcel). The gem ships the whole fulfillment ShipStation names.
- Telling ShipStation about cancellations through the export (5.x didn't either).
- Throttling in the gem. Hosts use rack-attack or Rails `rate_limit` at the app or edge; the README keeps that advice.

## Anti-goals

These would be failures even if the tests pass:

- Exporting an unpaid or backordered parcel, so the warehouse ships goods Spree won't release.
- Answering 200 to a ship notice when Spree did not mark the parcel shipped.
- Forcing fulfilment (`force: true`) past Spree's paid and backordered guards.
- Changing the `OrderNumber`, `OrderID` or `OrderStatus` of a parcel ShipStation already imported. That creates duplicates, or orphans its ship notice.
- Monkey-patching core models. The 5.x `ShipmentDecorator` goes.

## Constraints

- **Public repo.** All code, docs, commits and PR text are generic: no store, customer, host or incident details. Commits are authored `Matthew Kennedy <m.kennedy@me.com>`, and the user pushes release tags.
- **Spree 6.0 facts** this design rests on:
  - `Spree::Fulfillment` replaces `Shipment`. Statuses are `unfulfilled fulfilled delivered canceled`, and "ready" is no longer a status.
  - `Fulfillment#number` is derived, `"#{order.number}-F#{position}"`, and never stored for new rows. Rows created before 6.0 keep their stored number.
  - Fulfilling goes through `Spree.fulfillment_fulfill_workflow.call(fulfillment:, tracking:, tracking_carrier:, notify_customer:, force:)`:
    - it returns a `Result`, whose error is a plain string;
    - it is not idempotent;
    - it refuses unpaid, backordered, draft, canceled and already-fulfilled parcels;
    - it captures on-dispatch payments itself;
    - a gateway decline raises `Spree::Core::GatewayError`, after tracking has been written.
  - `Spree::BaseController` and `Spree::IntegrationsHelper` are gone. `Spree::Core::ControllerHelpers::Store#current_store` always resolves the store marked default.
  - `Spree.t` is deprecated (and raises in tests). `Spree::Image` is gone (now `Spree::Media`). `product.master` is deprecated (and raises). `order.ship_total` and `option_type.presentation` warn.
  - pagy 43 ignores `items:`, so today's export pages are 25, not the documented 50.

## Design

### 1. Endpoints and controller

`Spree::ShipstationController < ActionController::Base`. `ActionController::API` renders the Builder template as an empty body and has no HTTP Basic helpers. The controller:

- includes `Spree::Core::ControllerHelpers::Store` and `Pagy::Method`;
- uses `skip_forgery_protection`, since Basic auth is the authentication and there is no session.

**Routes** (`Spree::Core::Engine.add_routes`):

| Route | Action | Store |
|---|---|---|
| `GET /shipstation(.xml)` | `export` | `current_store` (the default store), as today |
| `POST /shipstation` | `shipnotify` | `current_store` |
| `GET /shipstation/:integration_id(.xml)` | `export` | the store of the active integration with that prefixed id (`int_…`) |
| `POST /shipstation/:integration_id` | `shipnotify` | as above |

The `:integration_id` form is new. It restores multi-store support, which 5.x got from host-based store resolution and Spree 6 no longer has. It is the same idiom Spree 6's own inbound webhooks use: the record names the store. The bare path is unchanged, so existing ShipStation setups keep working.

**Request order:**

1. Find the active ShipStation integration, either by `:integration_id` or as the current store's (`store.integrations.active.find_by(type:)`). If there is none, answer 404, before authentication, as today.
2. Set `Spree::Current.store` to the integration's store.
3. Check HTTP Basic credentials with `secure_compare` against that integration's `preferred_username`/`preferred_password`. If they don't match, answer 401.

### 2. Which parcels are exported

A query object, `Spree::Shipstation::ExportQuery.new(store:, from:, to:)`, replaces the decorator's scopes. It returns a relation in which a parcel is exported when:

- it is one of the store's fulfillments (`store.fulfillments`, so the order is joined and scoped to the store), with status `unfulfilled`;
- its order is placed: `Spree::Order.placed_orders`, which excludes drafts and canceled orders;
- its order is paid, meaning any of:
  - `payment_status` is `paid`, `overcharged` or `partially_refunded`;
  - `total = 0` (a free order has `payment_status = 'none'`, and Spree still ships it);
  - `payment_status` is `authorized` and the store's capture method is `on_dispatch` or `manual`. On those stores Spree captures at dispatch, as 5.x's `auto_capture_on_dispatch` did.
  - `payment_status` is `partially_paid` on those same stores: mixed tender, part captured at checkout and the rest authorized. Spree's fulfil check lets it through when every pending payment defers capture.
- none of its items is backordered (`id NOT IN` the backordered fulfillment items);
- its delivery method is not pickup or pickup point. Those parcels are collected, not shipped, and have no ship address. Digital fulfillments are already fulfilled at placement.
- **Date window:** when `start_date`/`end_date` are given, the parcel's `updated_at` *or* its order's `updated_at` falls in the window, as today. The order table is already joined.
- **Order:** `reorder(spree_fulfillments.updated_at, spree_fulfillments.id)`. `store.fulfillments` inherits a `created_at` order that must be replaced.
- **Preloads:** order, addresses, fulfillment items with line item, variant, product, media and option values, plus the order's fulfillments, so the derived number isn't an N+1.

`partially_refunded` is included because a partial refund before shipping (one line refunded) still leaves the rest to ship. Leaving it out would silently strand the parcel. If the order is in fact not paid enough, the ship notice is refused with Spree's reason (§4), which the warehouse sees.

**Pagination:** `pagy(query, limit: 50)`, with pagy reading `page` from the params itself. The README's 50 per page becomes true.

### 3. The export XML

The template, `export.xml.builder`, keeps every element and its order. Field sources change as follows (presenters stay; the `Shipment` name in their docs becomes fulfillment):

| XML | 5.x source | 6.0 source |
|---|---|---|
| `OrderID` | `shipment.id` | `fulfillment.id`. The table was renamed in place, so ids carry over. |
| `OrderNumber` | `shipment.number` | `fulfillment.number`: the stored number for parcels created before 6.0, `R1001-F1` for new ones |
| `OrderStatus` | `shipment.state` (`ready`) | the constant `ready`. Every exported parcel is ready by definition, and merchants' ShipStation status mappings key on `ready` (README table). |
| `OrderDate` / `LastModified` | `order.completed_at`, `shipment.updated_at` | unchanged |
| `ShippingMethod` | `shipment.shipping_method.name` | `fulfillment.delivery_method&.name` |
| `ShippingAmount` | `order.ship_total` | `order.delivery_total` |
| `OrderTotal`, `TaxAmount`, `CustomField1` (order number), `CustomerCode` | order | unchanged. Totals stay order-level, as in 5.x. |
| Address fields | `zipcode`, `country.iso`, `state.abbr \|\| state_name`, `name`/`full_name` | `postal_code`, `country_code`, `state_code.presence \|\| state_name`, `full_name` |
| `Item` grouping | `inventory_units.group_by(&:line_item)`, quantity summed | `fulfillment_items.group_by(&:line_item)`, quantity summed |
| `ImageUrl` | `variant.images.first \|\| product.master.images.first`, then `url_for(attachment)` | `variant.thumbnail` (the variant's primary media, else the product's), then `url_for(media.attachment)` |
| `Weight`/`WeightUnits` | variant weight and unit | unchanged. The unit falls back to the variant's store. |
| `Options` | `option_type.presentation`, `option_value.name` | `option_type.label`, `option_value.name`. The value stays the same string ShipStation already shows. |

The XML must still validate against the bundled XSD, and the specs keep that check.

### 4. Ship notice

`Spree::Shipstation::ShipmentNotice` keeps its role and its `from_payload(params, store:)` entry. `params` are `order_number` (ShipStation's name, holding our `OrderNumber`), `tracking_number` and `carrier`.

**Resolve the fulfillment** within the store:

1. `store.fulfillments.find_by(number:)` for parcels created before 6.0, which keep their stored number.
2. Otherwise parse `\A(?<order>.+)-F(?<position>\d+)\z`. Find the store's order by number, then pick the fulfillment whose derived `number` equals the given string. The match uses Spree's own derivation rather than re-implementing the position arithmetic.
3. If neither finds it, raise `ShipmentNotFoundError` and answer 400, as today.

When the notice's XML body carries `OrderID` (the fulfillment's id, as exported), it is authoritative: a derived number shifts when Spree destroys an earlier parcel, the id does not. The number then only identifies the order; an id outside the store is `ShipmentNotFoundError`, never a fallback to the number, and an id from another order is `ShipmentMismatchError` (400).

**Apply**, under `order.with_lock`. This is the pattern Spree 6's admin API uses, and it serializes ShipStation retries.

- **Blank tracking:** `MissingTrackingNumberError`, 400 (as today).
- **Already fulfilled or delivered:** `Spree.delivery_upsert_primary_service.call(fulfillment:, tracking:)`. This records or corrects the tracking without fulfilling it or publishing `fulfillment.fulfilled` again, then answers 200. This makes retries and re-labels safe.
- **Canceled:** `FulfillmentCanceledError`, 400. It is checked before the workflow, which would otherwise say "cannot be fulfilled", the same text as for already-fulfilled.
- **Otherwise**, call `Spree.fulfillment_fulfill_workflow`:
  - with `fulfillment:`, `tracking:`, and `tracking_carrier:` when ShipStation's `carrier` maps to a key in `Spree.tracking_carriers` (otherwise Spree detects the carrier from the number);
  - with `notify_customer: true`. The workflow publishes `fulfillment.fulfilled` with that flag, and the host app's subscriber decides whether to tell the customer; Spree 6 core sends no shipped email itself;
  - never with `force:`, and never with `items:`. A partial list would split the parcel and ship a new fulfillment with a different number.
  - **On failure**, raise `FulfillmentRefusedError` carrying Spree's message ("This order is not paid for yet", "…backordered units…") and answer 400.
- **`Spree::Core::GatewayError`**, from an on-dispatch capture decline, becomes `PaymentError` and a 400. On a decline the whole lock transaction rolls back, so nothing persists; the retry, or the merchant's fix, fulfils it.

The gem's own `capture_pending_payments!` and `Spree::Config.auto_capture_on_dispatch` go. Spree 6 captures on dispatch inside the workflow, configured by the store's or payment method's `capture_method`.

The controller still rescues `Spree::Shipstation::Error` into `400 text/plain` with the message, as today. The new errors subclass it.

### 5. The integration record

- **Class:** `Spree::Integrations::Shipstation < Spree::Integration`. The name is unchanged because existing rows store it as their STI type. It is registered in `config.after_initialize`, as today; Spree 6 still requires that.
- **Preferences:** unchanged (`username :string`, `password :password`), so the dashboard's generated form shows a secret field for the password. Spree 6 stores password preferences in the encrypted `secret_preferences` column, and its own migration moves existing rows.
- **Validations:** the same length and character rules. Messages resolve with `I18n.t` at validation time (a lambda), not `Spree.t` at class load, which would raise at boot under Spree 6's test config.
- **Admin listing:**
  - `integration_group` becomes `"shipping"` (lowercase), the dashboard's group key, shared with core's shipping integrations;
  - `integration_name` comes from I18n;
  - `description` comes from `spree.integrations.shipstation.description`;
  - `logo_url` is a `data:` URI built from the gem's existing logo file;
  - `docs_url` is the README.
- **Removed:**
  - `icon_path` (gone in 6.0);
  - the ERB admin form;
  - the asset manifest and the engine's assets initializer;
  - `spree_extension` (a generator-only gem, no longer a Spree dependency).

### 6. Dependencies, harness, CI, release

**Gemspec:**

- `spree ~> 6.0` and `pagy >= 43.6, < 45` (Spree 6's floor);
- `required_ruby_version >= 3.3`;
- version `6.0.0`;
- `spree_extension` dropped.

**Gemfile:**

- `spree_dev_tools '>= 1.0.0.beta2'` must be written in the Gemfile. Bundler 2 lets an unconstrained Gemfile entry override the gemspec's constraint and resolves 0.6.3, which can't load on Spree 6.
- `spree` is pinned by `SPREE_VERSION` when it is set.
- Appraisals, `gemfiles/*`, `spree_admin` and `propshaft` are dropped.

**Test app:** regenerated by Spree 6's `rake test_app`, which raises on deprecations and missing translations.

Specs:

- Controller specs become **request specs** through the real routes, with Basic auth.
- Ship notices fulfil through the real Spree workflow. Only ShipStation's side is simulated.

**CI:**

- One test job: a matrix of `spree: ['6.0.0', '']` × `ruby: ['3.3', '4.0']`, on sqlite as today, plus a weekly schedule.
- A `Tests` summary job is added so branch protection can require one stable name.
- StandardRB, Brakeman and bundler-audit stay.
- **Branch protection** on `main` today requires the three `sqlite (3.4, spree_5_x)` jobs, which will never report again. `6-0-stable` has no protection. Before the PR can merge, the user requires `Tests`, `standard`, `brakeman` and `bundler-audit` on both branches.

**Release:**

- `release.yml` gains the step from `spree-paypal_merchant` that installs, system-wide, the locked versions of the gems `rubygems/release-gem` preloads (zlib, openssl).

**Branches** (the user's decision):

- `5-0-stable` holds the 5.x line. It already existed and was fast-forwarded to `main`, so it includes 5.0.1.
- `6-0-stable` was created from `main`. The port's PR targets `6-0-stable`, and `v6.0.0` is tagged there.
- After the release, `main` is fast-forwarded to `6-0-stable`, so `main` always holds the newest line.

### 7. Upgrading an existing store

This goes in the README's "Upgrading from 5.0" section:

- Bump the gem to `~> 6.0` alongside the Spree 6 upgrade.
- There is no data migration of the gem's own. Spree 6's migrations rename shipments to fulfillments, keeping their ids and numbers, and move the password into `secret_preferences`.
- Run `bin/rake spree:upgrade` right after `db:migrate`, before ShipStation next polls: until Spree's upgrade tasks move 5.x statuses (`ready`/`pending` to `unfulfilled`, `shipped` to `fulfilled`), the export is empty.
- ShipStation needs no changes for the default store: same URL, same credentials, same `OrderNumber` for parcels already imported, same `ready` status.
- New parcels are numbered `R1001-F1`. A store other than the default must use `/shipstation/<integration id>`, since Spree 6 no longer picks the store from the host.
- Capture on dispatch now follows Spree 6's `capture_method` setting (store or payment method); Spree's upgrade task carries `auto_capture_on_dispatch` over to it.
- As before, unpaid or backordered parcels do not appear in ShipStation until they can ship (5.x exported only `ready` shipments).

## Left to the builder

- File layout for the query object and errors (`lib/spree/shipstation/…` next to `ShipmentNotice`), and whether presenters take the fulfillment or a wrapper.
- How the carrier mapping normalises ShipStation carrier codes (`UPS`, `USPS`, `FedEx`, `royal_mail`…) to `Spree.tracking_carriers` keys. Unknown codes are omitted.
- Spec fixtures for each export-filter case: paid, unpaid, backordered, free, deferred-capture, pickup, canceled, draft, partially refunded.
