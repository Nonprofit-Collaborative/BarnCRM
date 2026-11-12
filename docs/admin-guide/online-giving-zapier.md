# Online Giving Through Zapier

## What It Does

Many organizations take donations on another giving tool: Givebutter, Donorbox, Zeffy, Classy
and similar. This page gives Zapier recipes that copy each new donation from such a tool into
BarnCRM as a Giving gift, for the right person, recorded once however many times it is sent.

BarnCRM does not connect to these tools itself, and BarnCRM holds no Zapier account: you use
your own. If you take payments through **your own Stripe or PayPal account**, you do not need
Zapier: the Payments module receives them directly (see [Payments](payments.md)).

## Before You Start

- **Giving** must be installed (Nonprofit Edition). Recipe B also needs **Mirror**.
- A Zapier account of your own that can use the Salesforce app. Zapier lists Salesforce as a
  premium app; check Zapier's current plans for what your account includes.
- A Salesforce user for Zapier to sign in as, made as in
  [Inbound Gift API](inbound-gift-api.md#how-to-turn-it-on). For Recipe B give it only the
  **Inbound Gifts** permission set. Recipe A also adds new people and writes gift fields, so give
  that user the **Fundraising Staff** role on the [Access](access.md) page instead.
- Your giving tool's Zapier app, with a trigger for a new donation (named **New Donation**,
  **New Transaction** or similar by each tool).

## Recipe A: Zapier's Salesforce Actions (Giving Only)

One Zap per giving tool. Every step is in Zapier.

1. **Trigger:** your giving tool, the new donation trigger. Test it so Zapier has a sample
   donation.
2. **Action: Salesforce, Find Record.** Object **Contact**, field **Email**, value the donor's
   email from step 1. Tick **Create Salesforce Record if it doesn't exist yet**, with **First
   Name**, **Last Name** and **Email** from step 1. BarnCRM gives a new person a household, as
   for a person added by hand.
3. **Action: Salesforce, Find Record.** Object **Gift**, field **External Id**, value the tool's
   name and its donation id, for example `givebutter:` followed by the transaction id. Tick
   **Create Salesforce Record if it doesn't exist yet**, and fill in:

| Gift field | Value |
|---|---|
| External Id | The same `tool:id` value as the search |
| Donor Contact | The Contact id from step 2 |
| Amount | The donation amount (the gross amount, before the tool's fees) |
| Gift Date | The donation date, as `YYYY-MM-DD` |
| Type | `Card` (or `ACH` for a bank payment) |
| Status | `Received` |
| Payment Reference | The tool's transaction or receipt id |
| Appeal | Optional: the id of the appeal this campaign belongs to |

Because the search looks for the External Id first and **External Id** is unique, a donation
Zapier sends twice finds the gift it made the first time and makes no second one. Giving puts
the whole gift in your default fund, as for a gift entered by hand.

## Recipe B: Mirror's Inbound Gift API (Fund Codes and Email Matching)

If Mirror is installed, a developer can point a **Webhooks by Zapier** step, or any tool that
can make an authenticated web request, at the Inbound Gift API. It matches the donor by email
the way the importer does, names a fund by its accounting code, and refuses a resend that
changes the amount. Send `externalId` as `tool:id`, `amount`, `paymentMethod` `Card`,
`giftDate`, `donorEmail` and, if you use one, `fundCode`. The contract and sign-in are in the
[Inbound Gift API reference](../api/inbound-gift-api.md).

## Refunds

Recipes only add gifts. When a tool refunds a donation, record the refund in BarnCRM as for any
refund (see [Refunds](refunds.md)). Payments through your own Stripe or PayPal account are the
exception: the Payments module records their refunds itself.

## Tools That Write NPSP Opportunities

Some tools only know NPSP and write Opportunities. With Mirror's Opportunity Mirror turned on,
those Opportunities become Giving gifts (see [Opportunity Mirror](opportunity-mirror.md)), so
such a tool can stay as it is.

## Common Mistakes

- **No External Id**: every resend becomes another gift. Always search and create by External
  Id.
- **The same External Id for two tools**: always start it with the tool's name.
- **The net amount instead of the gross**: record what the donor gave; the tool's fee is an
  expense, not a smaller gift.
- **More access than the recipe needs**: for Recipe B give the Zapier user the Inbound Gifts set
  only, so a leaked sign-in can do little more than add gifts; for Recipe A, Fundraising Staff
  and no admin role.
