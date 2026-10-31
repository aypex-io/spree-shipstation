# Set up ShipStation

Connect ShipStation to your Spree store in three steps. You need admin access
to both. If ShipStation is listed under **Settings → Integrations** in the Spree
dashboard, the extension is installed and you can start.

## 1. Create credentials in Spree

1. In the Spree dashboard, go to **Settings → Integrations** and open the
   **Shipping** tab.
2. On the **ShipStation** card, choose **Configure**.
3. Choose a username and password for ShipStation to sign in with. Use them for
   nothing else.
   - **Username:** 10 to 30 characters, using letters, numbers and `. _ @ + -`.
   - **Password:** 20 to 60 characters, including an uppercase letter, a number
     and one of `! @ # $ % ^ & * ( ) , . ? " : { } | < >`.
4. Save, and check the card's switch is on and shows **Active**.

## 2. Add a Custom Store in ShipStation

1. In ShipStation, go to **Settings → Selling Channels → Stores → Add Store**
   and choose **Custom Store**.
2. Enter:
   - **Username** and **Password:** the ones you chose in step 1.
   - **URL to custom page:** your store's address followed by
     `/shipstation.xml`, for example `https://shop.example.com/shipstation.xml`.

### More than one store

That URL is for your **default** store. Every other store has its own ShipStation
integration and its own URL, which ends in the integration's ID (it starts with
`int_`):

```
https://shop.example.com/shipstation/int_abc123.xml
```

Use the username and password set on that store's integration. Your developer
can [look up the ID](install.md#finding-an-integrations-id).

## 3. Map the order status

In the Custom Store's status mapping, enter `ready` for **Awaiting Shipment**.
It is the only status Spree sends: only parcels that can ship now are sent, and
ShipStation marks each one shipped itself once its label exists.

## What to expect

- **Each parcel is its own ShipStation order.** Spree calls parcels
  *fulfillments* and numbers them after the order, for example `R1001-F1`. An
  order sent in two parcels appears twice, each copy showing the order's totals.
- **A parcel appears once it can ship:** its order is paid, nothing in it is
  backordered, and it is not a pickup. See
  [what ShipStation pulls](how-it-works.md#what-shipstation-pulls).
- **Creating a label fulfils the parcel in Spree** and records its tracking
  number. If Spree refuses, ShipStation shows the reason; see
  [error messages](how-it-works.md#error-messages).
- **Don't empty a parcel ShipStation has already imported.** Moving all its
  items to another parcel makes Spree delete it, and ShipStation's copy can no
  longer ship. [Why](how-it-works.md#why-the-orderid-comes-first).
