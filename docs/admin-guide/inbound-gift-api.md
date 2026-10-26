# Inbound Gift API

## What it does

Your online giving page, payment processor or integration tool can record gifts in BarnCRM by itself, instead of somebody typing them from an emailed report. It sends each gift
with the donor's email address or record, the amount, how it was paid and, if it wants, the
fund and appeal. BarnCRM records an ordinary gift: it gets its household, its fund,
counts in the totals and can be receipted, exactly as if David had typed it.

Sending the same gift twice is safe. Every gift carries the identifier it has in the
sending system, and a gift that is already recorded is recognized and not recorded again.
If that identifier arrives with a different amount, the gift is refused rather than guessed
at.

Two ways in, doing the same thing:

- **The web address (REST API)**, for a processor or an integration platform outside
  Salesforce. A developer connects it once, using the [API reference](../api/inbound-gift-api.md).
- **The Record Inbound Gift action in Flow**, for anything already inside Salesforce, such
  as a flow that runs when a payment app writes its own record.

BarnCRM never creates a donor from a gift. If nobody matches, the gift is refused and
the refusal is written to the Error Log, so a gift from someone new needs the person added
first (by hand or with [Importing](importing.md)) and then the gift sent again.

## How to turn it on

The Mirror module has to be installed. The Flow action needs nothing else.

The web address needs a Salesforce user for the sending system to sign in as, and that
sign-in is set up in Salesforce Setup. It cannot be avoided: how outside systems
authenticate belongs to Salesforce, not to BarnCRM. Do it once, with your developer or
the processor's support team.

1. **Create the user the system signs in as.** In Setup, create a user for the integration,
   for example "Online Giving Integration". A Salesforce Integration user license is the
   usual choice where you have one. The user needs **API Enabled**.
2. **Give it the Inbound Gift API permission set, and nothing else from BarnCRM.** It
   holds exactly what recording a gift needs: reading people, organizations, funds, appeals
   and acknowledgment rules; creating gifts, their fund allocations and the household soft
   credits Giving adds; and the web address. It cannot edit or delete a donor, edit or
   delete a gift, change a fund, or read the Error Log, so a leaked key can do little more
   than send gifts. Give it on the Access page, under Extra Permissions: no BarnCRM role includes a module's permission sets.
3. **Let it see your donors.** It finds a donor only among the people and organizations it
   can see. If contacts and accounts are private in your organization, share them with it
   (see "The integration user cannot see the donors" below).
4. **Set up how it signs in.** Your developer creates an External Client App (or connected
   app) with the OAuth client credentials flow, running as that user. They keep its key and
   secret in the sending system, never in an email.
5. **Tell the developer which funds and appeals to use.** A fund is named by its
   **Accounting Code**, so check each fund the system will use has one (see [Funds](funds.md)).
   An appeal is named by its record id, which is the last part of the web address when the
   appeal is open.

There are no settings for the API.

## A five-minute walkthrough

Do this as Maria, with the sample data loaded, in Flow Builder. It shows the one thing that
matters most: sending the same gift twice records it once.

1. From Setup, open **Flows** and click **New Flow**. Choose **Autolaunched Flow (No
   Trigger)**.
2. Add an **Action**. Search for `Record Inbound Gift` and pick it. Name it `Send gift`.
3. Set **External Id** to `walkthrough-1`, **Amount** to `25`, **Payment Method** to `Card`,
   **Donor Email** to `luis.garcia2@example.org` and **Fund Accounting Code** to `4100`.
   Leave the rest empty. Click **Done**.
4. Click **Debug**, then **Run**. The debug panel shows the action's result: **Outcome**
   `created`, a **Gift Id**, and **Message** `Gift recorded.`
5. Click **Debug** and **Run** again, with the same values. This time **Outcome** is
   `existing`, with the same **Gift Id** and **Message** `This gift was already recorded.
   Nothing was changed.`
6. Change **Amount** to `30`, save, and run once more. **Outcome** is `rejected` and **Error
   Code** is `external_id_conflict`: the identifier is already used by a gift of 25.00.
7. Open the gift from its **Gift Id** (the **Gifts** tab, search `walkthrough`, or paste the
   id after `/lightning/r/` in the address bar). It is Luis Garcia's, 25.00, type Card, today,
   with one allocation to the Building Fund. Close the flow without activating it.

## Common mistakes

**`donor_not_found` for a new donor.** Expected: the API never creates people. Add the
person, then send the gift again with the same external id. The Error Log entry for the
refusal names the external id so you can find it in the sending system.

**Reusing identifiers across two systems.** Two processors can both number their payments
from 1. Ask each sending system to put its own name in front, for example `stripe:ch_3N1`,
so the identifiers never collide. A collision shows up as `external_id_conflict`.

**A fund without an accounting code.** The sending system names funds by accounting code.
A gift naming a code no active fund has is refused with `fund_not_found`; a gift naming no
fund goes to your default fund.

**Sending a refund.** A refund is not a new gift from outside: record it from the original
gift with its refund action (see [Refunds](refunds.md)). The API refuses an amount of zero
or less.

**The integration user cannot see the donors.** The API finds a donor only among the people
and organizations its user can see, the same as a search by that user would. If contacts
and accounts are private in your organization, every gift is refused with
`donor_not_found` even though the donor is there. Give the integration user a role above
the staff who own donor records, or a sharing rule that shares them with it; both are in
Setup, under Roles and Sharing Settings.

**The integration user cannot see older gifts.** Gifts are private by default, and the API
checks for an earlier copy only among gifts its user can see. A gift entered by hand with
the same identifier is still never duplicated: the platform refuses the second copy and the
API answers `external_id_conflict`.
