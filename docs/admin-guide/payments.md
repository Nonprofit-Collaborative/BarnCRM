# Payments

## What It Does

Payments lets BarnCRM take money online through **your own Stripe or PayPal account**. When
another BarnCRM module needs a payment (a paid event registration, an online gift, membership
dues), Payments sends the payer to Stripe's or PayPal's own checkout page, and records the
result when the processor reports it: paid, failed, refunded or cancelled. The money goes
straight from the payer to your account. BarnCRM never holds money and never sees or stores a
card number.

On its own, Payments takes no payments: the modules that charge (Event Management's paid
registration, Fundraising's online donations, memberships, donor portal payments) use it as they
arrive in later releases. Until then you can install it, connect your processor and check the
setup.

Your processor's secrets (the Stripe secret key, the PayPal client id and secret) are entered in
Salesforce **Setup**, on External Credentials that Payments ships empty. Salesforce keeps them
encrypted and adds them to each call to the processor; BarnCRM's code never reads, shows or
stores them.

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
| Team Member, Fundraising Staff (Fundraising) | Payments Staff | See payments |
| Read Only | Payments Read Only | See payments |

Nobody changes a payment's status by hand: it comes only from the processor.

Payments Staff, Payments Admin and Payments Webhook Guest also give access to the processor
credentials (never their values), so the people and public pages that start checkouts can call
the processor. Payments Read Only does not.

## Setting Up (About 20 Minutes)

### 1. Choose in BarnCRM Settings

Open **BarnCRM Settings**, **Payments**:

| Setting | Default | What it does |
|---|---|---|
| Processor | Stripe | The processor used when a module does not choose one. |
| Mode | Test | **Test** uses your processor's test keys and takes no real money. Switch to **Live** only after a test payment worked end to end. |
| Default currency | USD | The three-letter currency used when a module does not name one. |
| Automatic Recurring Payments | Off | When on, a donor who pays a recurring gift online sets up automatic payments: the processor saves the card and charges it each period, and the donor can update the card from the donor portal. See [Automatic Recurring Payments](#automatic-recurring-payments). |

### Setting Up a Site (Once)

If you already set up a Site for public forms, use the same one and skip to step 4. Salesforce
requires these steps in **Setup**, and no app can do them for you:

1. **Setup > Sites**: register your Sites domain, if the org has none yet.
2. Select **New**, give the Site a label and name, and save.
3. **Activate** the Site.
4. Open **Health Check** in the Settings console and select **Give Payments Webhook Guest** if it
   is listed. It gives the Site's guest user the address the processor calls and access to the
   processor credentials (never their values), so public pages on the Site can start checkouts.
   The guest user gets no access to any record.

### Entering a Secret in Setup

Each processor's card on **Payments Setup** names its External Credential, principal and
parameters, with the steps. In general:

1. **Setup > Named Credentials**, then the **External Credentials** tab.
2. Open the credential (**BarnCRM Stripe** or **BarnCRM PayPal**).
3. Under **Principals**, edit the principal (`Barn_Stripe_Key` or `Barn_PayPal_App`).
4. Add each **Authentication Parameter**, named exactly as the card says, with its value, and
   save. To change a secret later, edit the parameter's value the same way.
5. Back on **Payments Setup**, select **Check Connection**.

With a namespaced package install, the names on the card carry the package prefix; use them as
shown.

### 2. Connect Stripe

1. In your Stripe Dashboard, turn on **Test mode** (while Mode is Test).
2. **Developers > API keys**: copy the **Secret key** (`sk_test_...`). A restricted key with
   write access to Checkout Sessions and read access to Events and Balance works too.
3. In Setup, on the **BarnCRM Stripe** External Credential, principal `Barn_Stripe_Key`, add the
   parameter `SecretKey` with that key (see [Entering a Secret in Setup](#entering-a-secret-in-setup)).
4. Open **Payments Setup** in BarnCRM and select **Check Connection** on the Stripe card. It
   reads **Connected** and says which mode the key is for.
5. Copy the **Stripe address** Payments Setup shows, for example
   `https://yourorg.my.salesforce-sites.com/services/apexrest/barncrm/payments/v1/stripe?token=...`.
   Copy all of it: the random token after the question mark is what lets Stripe's posts in, and
   a post without it is refused and stores nothing.
6. In Stripe, **Developers > Webhooks > Add endpoint**: paste the address and choose these
   events: `checkout.session.completed`, `checkout.session.async_payment_succeeded`,
   `checkout.session.async_payment_failed`, `checkout.session.expired`, `charge.refunded`,
   `payment_intent.payment_failed`, and, for automatic recurring payments, `invoice.paid`,
   `invoice.payment_failed` and `customer.subscription.deleted`. Save. You do not need the
   signing secret: BarnCRM fetches each event back from Stripe with your secret key and uses only
   Stripe's own copy, so a forged message is never applied.

### 3. Connect PayPal

1. At developer.paypal.com, **Apps & Credentials**: choose **Sandbox** (while Mode is Test) and
   create an app. Copy its **Client ID** and **Secret**.
2. In Setup, on the **BarnCRM PayPal** External Credential, principal `Barn_PayPal_App`, add the
   parameters `ClientId` and `ClientSecret`. One app's credentials serve the mode you are in:
   **BarnCRM PayPal Sandbox** is used in Test mode and **BarnCRM PayPal Live** in Live mode.
3. In the app, **Add Webhook**: paste the **PayPal address** from **Payments Setup** and choose
   **Checkout order approved**, **Payment capture completed**, **Payment capture denied**,
   **Payment capture refunded** and **Payment capture reversed**, and, for automatic recurring
   payments, **Payment sale completed**, **Billing subscription payment failed** and **Billing
   subscription cancelled**. Save, and copy the **Webhook ID** PayPal shows.
4. In **Payments Setup**, paste the webhook id and select **Save Webhook ID**, then select
   **Check Connection** on the PayPal card.

### 4. Schedule Processing

**Payments Setup** says whether processing is scheduled. If it is not, select **Schedule
Processing** there (or **Schedule Payment Processing** in Health Check). Nothing is scheduled
until you choose to. It runs every 15 minutes as you, so keep your user active. It checks each processor event, records the payment's new status
and tells the module the payment belongs to.

### 5. Test, Then Go Live

Make a test payment from the module that charges (for example a paid event registration) with
Stripe's test card `4242 4242 4242 4242` or a PayPal sandbox buyer. Within 15 minutes the
payment shows **Paid** on the **Payments** tab. Refund it in the processor's dashboard: the
payment shows **Refunded** at the next run.

To go live: in the processor switch to live mode, create the live webhook the same way, replace
the secrets on the External Credential in Setup with the live ones (and, for PayPal, save the
live webhook id), set **Mode** to **Live**, then select **Check Connection** again. Payments
started in test mode keep Mode **Test**, so reports can leave them out.

## The Payments Setup Page

It shows the address to give each processor and, for each processor, a card with:

- **Connected** or **Not connected**: whether **Check Connection** last succeeded.
- The External Credential, principal and parameter names to fill in Setup, with the steps.
- **Check Connection**: one call to the processor through its Named Credential, as you
  (Stripe: reads your balance, which also says whether the key is live; PayPal: signs in, in the
  current mode). Success marks the processor connected; failure says why, marks it not
  connected and writes the detail to the Error Log. Checkouts start only for a connected
  processor.
- For PayPal, the **PayPal Webhook ID** box and **Save Webhook ID**.
- **Regenerate Token** (under the addresses, after a confirmation): BarnCRM made the token in
  the addresses the first time you opened this page. Regenerating replaces it, so the addresses
  already given to Stripe and PayPal stop working until you paste in the new ones. Use it if an
  address may have been shared.
- **Disconnect**: after you confirm, marks the processor not connected (and, for PayPal, clears the webhook id).
  The secrets stay on the External Credential until you remove them in Setup.

BarnCRM never shows a secret: it cannot read one.

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
times it is sent. A Stripe message is fetched back from Stripe before it is used: if Stripe has
no event with that id in your account, the message is **Rejected** ("Stripe has no event with
this ID"); if Stripe cannot be reached, it stays **Received**, the Error Log says why, and it is
tried again at the next run. A run reads up to 20 messages and stops early after a minute of waiting on
PayPal, leaving the rest **Received** for the next run. A message whose processor could not be
reached stays **Received** and is tried again at the next run. Abandoned checkouts are cancelled
50 at a time in a job of their own.

## Automatic Recurring Payments

With **Automatic Recurring Payments** on (PAY-04, D-196), a donor who chooses **Pay Online** on
a recurring gift in the donor portal sets up automatic payments for the gift's amount and how
often it comes (weekly, every two weeks, monthly, quarterly, twice a year or yearly), on your
Stripe or PayPal page. From then on:

- **The processor charges each period** from the saved card or PayPal account and retries a
  failed charge on its own schedule. Each charge it reports paid becomes a **Paid** payment with
  the same **Subscription Id** as the first, and a **Received** gift on the recurring gift.
- **The recurring gift keeps its health.** The gift gets **Processor Subscription Id** and
  **Processor Customer Id**, and each failed charge, renewed charge, card update and
  cancellation becomes a Recurring Gift Event, so **Failed Charges**, **Card Expires** and
  **Cancelled at Processor** stay current on the Recurring Donor Health page.
- **The donor updates the card** with **Update Card** in the donor portal: an email with a link
  to your processor's own page (Stripe's card form, valid 24 hours, or PayPal's automatic
  payments page). BarnCRM never sees the card. Stripe retries a failed charge on the new card.
- **Pay Online is refused** on a recurring gift that is charged automatically, so nobody pays
  twice.
- **PayPal plans are shared** (D-198). BarnCRM makes one PayPal product (named after your
  organization, "... recurring payments") and one billing plan per amount, currency and schedule
  ("25.00 USD every month"), and reuses them: two donors giving 25.00 monthly share one plan,
  each with a subscription of their own, so renewals, failures, cancellations and Update Card
  still reach the right recurring gift. The payment's **Plan Id** shows the plan. If you
  deactivate a plan in PayPal, or connect another PayPal account, the next checkout makes a new
  plan (and product) and uses it from then on. Donors see the plan name on PayPal's page, not
  the gift's description. Stripe makes no product or plan of its own to reuse.

Before you turn it on, add the subscription events to your processor's webhook (steps 2 and 3
above). To stop a donor's automatic payments, cancel the subscription in your processor's
dashboard: BarnCRM records **Cancelled at Processor** and never changes the gift's Status.
Recurring gifts set up outside BarnCRM (for example through a Zapier recipe) keep working as
before; for Stripe ones, fill **Processor Customer Id** (`cus_...`) on the recurring gift to let
the donor use Update Card.

## Health Check

| Check | What to do |
|---|---|
| Payment Processor Is Not Connected | Enter the processor's secrets on its External Credential in Setup, then select **Check Connection** on **Payments Setup** (PayPal also needs its webhook id). |
| Payment Processor Connection Failed | Stripe is connected but a test call now fails (Health Check calls Stripe each time it runs). Check the secret on the External Credential principal and your permission sets, then **Check Connection**. |
| Stripe Key Does Not Match the Mode | A live key with Mode Test, or a test key with Mode Live. Enter the right key in Setup or change Mode. |
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
- **The address pasted without its token**, or an old address after **Regenerate Token**: the
  receiver answers 404 and stores nothing. Copy the full address from Payments Setup again.
- **The hourly limit**: each processor's address stores at most 500 events an hour and refuses
  the rest (the processor sends them again later). The first refusal each hour writes one
  Warning to the Error Log and Health Check shows `Payment Receiver Hit Its Hourly Limit` for a
  day. If the volume is not yours, regenerate the token.
- **The webhook created before the processor is connected**: until **Check Connection** has
  succeeded (and, for PayPal, the webhook id is saved), the processor's address refuses every
  message and stores nothing. Stripe and PayPal retry, so connect soon after adding the webhook.
  Event types the module does not use are acknowledged and not stored.
- **Secrets entered without Check Connection**: the processor stays **Not connected** and no
  checkout starts until you select it.
- **Someone without a Payments permission set starting a checkout**: the call to the processor
  fails, because only the Payments sets give access to the credential. Give them a BarnCRM role
  on the Access page.
- **Processing not scheduled, or scheduled by a user who was then deactivated**: payments stay
  Pending. Health Check reports both.
- **Refunding in BarnCRM**: there is no refund button; refund in the processor's dashboard.
- **Automatic Recurring Payments on without the subscription events** in the webhook: the first
  payment is recorded, but renewals, failed charges and card updates are not.

## Other Fundraising Tools

Givebutter, Donorbox and similar tools are connected through Zapier, not through Payments: see
[Online Giving Through Zapier](online-giving-zapier.md).
