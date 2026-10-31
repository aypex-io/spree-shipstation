# spree-shipstation

![CI](https://github.com/aypex-io/spree-shipstation/workflows/CI/badge.svg)
![Standard Rb](https://github.com/aypex-io/spree-shipstation/workflows/Standard%20Rb/badge.svg)

Connects a Spree store to [ShipStation](https://www.shipstation.com) as a
**Custom Store**. ShipStation pulls the fulfillments that are ready to ship, and
when it creates a label, the gem records the tracking number and fulfils the
fulfillment in Spree.

| spree-shipstation | Spree | Ruby |
|---|---|---|
| 6.0.x | 6.x | 3.3 or newer |
| 5.0.x, on [`5-0-stable`](https://github.com/aypex-io/spree-shipstation/tree/5-0-stable) | 5.x | 3.1 or newer |

## Install

```ruby
gem "spree-shipstation", "~> 6.0"
```

Run `bundle install` and restart. There is nothing else to run. Then connect
ShipStation from the dashboard under **Settings → Integrations** by following
[Setup](docs/setup.md).

## Documentation

- [Install](docs/install.md): adding the gem, its routes, and a production
  checklist
- [Setup](docs/setup.md): connecting ShipStation, for store staff
- [Configuration](docs/configuration.md): payment capture, fulfillment
  providers, shipped emails
- [How it works](docs/how-it-works.md): what is exported, what a ship notice
  does, error messages
- [Upgrading from 5.0](docs/upgrading-5-to-6.md)
- [Development](docs/development.md): tests, linting, releasing
- [Changelog](CHANGELOG.md)

## License

Copyright (c) 2021-2026 Matthew Kennedy, released under the MIT License.

Everyone interacting in this project's codebases, issue trackers and
communication channels is expected to follow the
[code of conduct](CODE_OF_CONDUCT.md).
