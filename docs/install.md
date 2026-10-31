# Install

Requires Spree 6 (`~> 6.0`) and Ruby 3.3 or newer. Spree 5 stores stay on the
5.0.x releases from the
[`5-0-stable`](https://github.com/aypex-io/spree-shipstation/tree/5-0-stable)
branch (`gem "spree-shipstation", "~> 5.0"`).

1. Add the gem to your Gemfile:

   ```ruby
   gem "spree-shipstation", "~> 6.0"
   ```

2. Run `bundle install` and restart the app.

There are no migrations, generators or initializers. The gem registers
ShipStation with Spree's integrations, so it appears in the dashboard under
**Settings → Integrations**, and adds these routes:

| Route | Does | For |
|---|---|---|
| `GET /shipstation(.xml)` | Export | The default store |
| `POST /shipstation` | Ship notice | The default store |
| `GET /shipstation/:integration_id(.xml)` | Export | That integration's store |
| `POST /shipstation/:integration_id` | Ship notice | That integration's store |

Then connect ShipStation by following [Setup](setup.md).

## Finding an integration's ID

Only a store other than the default needs it. In a Rails console:

```ruby
Spree::Integrations::Shipstation.all.map(&:prefixed_id) # => ["int_abc123", ...]
```

## Production checklist

- **Serve the endpoints over HTTPS.** They use HTTP Basic Auth, which sends the
  username and password with every request.
- **Let ShipStation reach them.** If the host sits behind an access proxy or
  single sign-on, exempt the `/shipstation` paths.
- **Add rate limiting if you want it.** The gem does not throttle sign-in
  attempts; use [`rack-attack`](https://github.com/rack/rack-attack) or Rails'
  `rate_limit`. The credential rules already make guessing impractical, and
  credentials are compared in constant time.
- **Index `updated_at` on large stores.** The export filters and sorts by
  `spree_fulfillments.updated_at` and `spree_orders.updated_at`, which Spree 6
  does not index. Add those two indexes in your application.

When no active ShipStation integration matches the URL, the endpoints answer
`404` before checking credentials, so a `404` reveals that the integration is
not set up. See [response codes](how-it-works.md#response-codes).
