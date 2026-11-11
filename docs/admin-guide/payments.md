# Payments

## What It Does

Payments lets BarnCRM take money online through **your own Stripe or PayPal account**. When
another BarnCRM module needs a payment (a paid event registration, an online gift, membership
dues), Payments sends the payer to Stripe's or PayPal's own checkout page, and records the
result when the processor reports it: paid, failed, refunded or cancelled. The money goes
straight from the payer to your account. BarnCRM never holds money and never sees or stores a
card number.

On its own, Payments takes no payments: the modules that charge (Event Management's paid
registration, Giving's online donations, memberships, donor portal payments) use it as they
arrive in later releases. Until then you can install it, enter your keys and check the setup.

## How to Turn It On

### Before You Install

- Payments is offered in **both editions** (see [Editions](editions.md)).
- It needs BarnCRM Core and nothing else.
- You need a Stripe account, a PayPal Business account, or both. BarnCRM charges nothing; the
  processor charges its usual fees to your account.
- You need a Salesforce Site, the same one public forms use (see
  [Setting Up a Site](#setting-up-a-site-once)). The processor sends its news to an address on it.

### Installing

Install it from **Module Manager** (see [Module Manager](module-manager.md)). When the install
finishes, BarnCRM gives you, the person who installed it, the **Payments Admin** permission set,
and gives everyone who already has a BarnCRM role their Payments permission set (see below).

Payments has no app of its own: its **Payments** tab joins the **BarnCRM** and **BarnCRM
Console** apps, and the **Payments Setup** and **Payment Events** tabs are for admins. A source
install puts them there itself; after a package install, add them once in App Manager (see
[The BarnCRM Apps](barncrm-app.md#a-modules-pages-in-the-barncrm-apps)).

### Roles and Permission Sets

You never assign the Payments permission sets by hand. Give people their BarnCRM role on the
[Access](access.md) page, and the module gives each role its set:

| BarnCRM role | Payments set they get | What they can do |
|---|---|---|
| Admin (anyone holding BarnCRM Admin) | Payments Admin | Everything: the settings, Payments Setup, every payment and processor event |
| Team Member, Fundraising Staff (Giving) | Payments Staff | See payments |
| Read Only | Payments Read Only | See payments |

Nobody changes a payment's status by hand: it comes only from the processor.

## Setting Up (About 20 Minutes)

### 1. Choose in BarnCRM Settings

Open **BarnCRM Settings**, **Payments**:

| Setting | Default | What it does |
|---|---|---|
| Processor | Stripe | The processor used when a module does not choose one. |
| Mode | Test | **Test** uses your processor's test keys and takes no real money. Switch to **Live** only after a test payment worked end to end. |
| Default currency | USD | The three-letter currency used when a module does not name one. |

### Setting Up a Site (Once)

If you already set up a Site for public forms, use the same one and skip to step 4. Salesforce
requires these steps in **Setup**, and no app can do them for you:

1. **Setup > Sites**: register your Sites domain, if the org has none yet.
2. Select **New**, give the Site a label and name, and save.
3. **Activate** the Site.
4. Open **Health Check** in the Settings console and select **Give Payments Webhook Guest** if it
   is listed. It gives the Site's guest user one permission: the address the processor calls.
   The guest user gets no access to any record.

### 2. Connect Stripe

1. In your Stripe Dashboard, turn on **Test mode** (while Mode is Test).
2. **Developers > API keys**: copy the **Secret key** (`sk_test_...`). A restricted key with
   write access to Checkout Sessions works too.
3. Open **Payments Setup** in BarnCRM. Copy the **Stripe address** it shows, for example
   `https://yourorg.my.salesforce-sites.com/services/apexrest/barncrm/payments/v1/stripe`.
4. In Stripe, **Developers > Webhooks > Add endpoint**: paste the address and choose these
   events: `checkout.session.completed`, `checkout.session.async_payment_succeeded`,
   `checkout.session.async_payment_failed`, `checkout.session.expired`, `charge.refunded`,
   `payment_intent.payment_failed`. Save, then reveal the **Signing secret** (`whsec_...`).
5. In **Payments Setup**, paste the secret key and the signing secret and select **Save Keys**.

### 3. Connect PayPal

1. At developer.paypal.com, **Apps & Credentials**: choose **Sandbox** (while Mode is Test) and
   create an app. Copy its **Client ID** and **Secret**.
2. In the app, **Add Webhook**: paste the **PayPal address** from **Payments Setup** and choose
   **Checkout order approved**, **Payment capture completed**, **Payment capture denied**,
   **Payment capture refunded** and **Payment capture reversed**. Save, and copy the **Webhook
   ID** PayPal shows.
3. In **Payments Setup**, paste the client id, the secret and the webhook id and select **Save
   Keys**.

### 4. Schedule Processing

Open **Health Check** and select **Schedule Payment Processing**. It runs every 15 minutes as
you, so keep your user active. It checks each processor event, records the payment's new status
and tells the module the payment belongs to.

### 5. Test, Then Go Live

Make a test payment from the module that charges (for example a paid event registration) with
Stripe's test card `4242 4242 4242 4242` or a PayPal sandbox buyer. Within 15 minutes the
payment shows **Paid** on the **Payments** tab. Refund it in the processor's dashboard: the
payment shows **Refunded** at the next run.

To go live: in the processor switch to live mode, create the live webhook the same way, enter
the live keys in **Payments Setup**, then set **Mode** to **Live**. Payments started in test
mode keep Mode **Test**, so reports can leave them out.

## The Payments Setup Page

For each processor it shows the address to give the processor and whether each key is set,
with only its last four characters. Keys are never shown again once saved: to change one, type
the new value and save. Leave a box empty to keep the key you saved before. **Clear** removes
all of one processor's keys.

## Payments and Their Status

| Status | Means |
|---|---|
| Pending | The payer was sent to the checkout page and has not paid yet. |
| Paid | The processor captured the money. **Paid At** says when. |
| Failed | The processor declined or failed the charge. The payer can try again; a later success sets Paid. |
| Refunded | The whole amount was refunded in the processor's dashboard. A partial refund keeps Paid and shows **Amount Refunded**. |
| Cancelled | The payer left the checkout page, or it expired: Stripe tells BarnCRM, and any payment still Pending after 2 days is cancelled. |

Refunds are made in Stripe or PayPal, never in BarnCRM; BarnCRM records them when the processor
reports them.

**Payment Events** lists every message the processors sent, with what was done with it
(Applied, Ignored, Rejected, Failed) and why. Each processor message is used once, however many
times it is sent.

## Health Check

| Check | What to do |
|---|---|
| Payment Keys Are Missing | Enter the keys for the processor in **Payments Setup**. |
| Stripe Key Does Not Match the Mode | A `sk_live_` key with Mode Test, or `sk_test_` with Mode Live. Enter the right key or change Mode. |
| No Active Site for Payments | Set up a Site (above). |
| A Site Guest User Can't Receive Payment News | Select **Give Payments Webhook Guest**. |
| Payment Processing Is Not Scheduled | Select **Schedule Payment Processing**. |
| Payment News Is Waiting | Processor messages have waited over an hour: check processing is scheduled, its user is active, then the Error Log. |

## For Module Builders

Other modules start a checkout and hear about status changes through one documented seam,
with no dependency on Payments: see the
[Payments module README](../../packages/payments/README.md#the-payment-seam).

## Common Mistakes

- **Test keys with Mode Live** (or the other way round): Health Check says so for Stripe;
  PayPal sandbox credentials fail to sign in when Mode is Live.
- **The webhook pointed at the Salesforce login address** instead of the Site address shown on
  Payments Setup: the processor gets an error and nothing is recorded.
- **Processing not scheduled, or scheduled by a user who was then deactivated**: payments stay
  Pending. Health Check reports both.
- **Refunding in BarnCRM**: there is no refund button; refund in the processor's dashboard.

## Other Giving Tools

Givebutter, Donorbox and similar tools are connected through Zapier, not through Payments: see
[Online Giving Through Zapier](online-giving-zapier.md).
