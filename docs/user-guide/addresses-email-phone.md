# Addresses, email and phone

BarnCRM keeps every address a household, organization or person uses, and marks one as the
primary. The primary is copied into the standard address fields, so letters and reports always
use the right one. People also get three email boxes and a choice of which one you write to,
and a choice of which phone number to call.

Before you start: open the **BarnCRM** app. Changing addresses, email and phone needs the Team
Member, Coordinator, Fundraising Staff or Admin role. The **Addresses** card appears once your
admin has turned on the Addresses feature. Ask your admin; see
[Addresses](../admin-guide/addresses.md).

## To add an address

1. Open the household, organization or person. Find the **Addresses** card.
2. Click **Add address**. The **New address** form opens.
3. Choose a **Type**: Home, Work, Mailing, Seasonal or Other.
4. Fill in **Street**, **City**, **State**, **Postal Code** and **Country**.
5. Tick **Primary** only if this is where they moved to (see "To Record a Move").
6. Click **Add address** at the foot of the form.

You should see: "Address saved." The first address a record gets is made the primary
automatically and carries a **Primary** badge.

## To choose household or personal

- An address you add on a **household** belongs to the whole household.
- An address you add on a **person** belongs to that person only. The rest of the household
  keeps its own address, and the person keeps theirs when the household moves later.
- If you edit a person's mailing address in the person's own **Mailing Address** field
  (**Reaching This Person** section), what happens
  depends on your org's **Address Updates** setting: either the whole household moves, or
  the person gets an address of their own. Ask your admin which yours is.
- If you edit a household's **Billing Address** field, the new address becomes the
  household's primary address, and everyone in the household moves with it except a person
  with an address of their own. If your org's setting is **Nobody moves until you choose**,
  only the household moves until someone chooses **Update Everyone's Address** on its
  primary address card.

## To Make an Address the Primary

1. On the **Addresses** card, click **Set as Primary** on the address you want to use.

You should see: "This is now the primary address, and it has been copied to the standard
address fields." The **Primary** badge moves, and the record's own address fields at the
top of the page refresh. Nothing is deleted: the other addresses stay on the card.

**Set as Primary** is not a move: the old primary stays **Current**. Use it to switch between
addresses someone still uses, such as a home and a work address. To record a move, see below.

## To Record a Move

1. On the **Addresses** card, click **Add address** and fill in the new address.
2. Tick **Primary**.
3. Click **Add address** at the foot of the form.

You should see: the new address at the top with the **Primary** badge and "Since" today's date.
The old address moves into **Former Addresses**, with the day it started (when known) to today.
The same happens when the household's or person's own address field is changed, or when
**Use for Whole Household** moves the household.

## To See Former Addresses

Below the addresses in use, the card shows **Former Addresses** with a count. Click it to open
the group: each old address shows the dates it was used, for example "January 5, 2020 to
October 1, 2026". Click it again to close it.

## To Mark an Address Former, Undeliverable or Current

1. On the **Addresses** card, click the status menu (the small arrow) on the address.
2. Choose **Mark as Former**, **Mark as Undeliverable** or **Mark as Current**.

You should see: "The address status is saved." **Mark as Former** ends the address today
(unless it already has an end date) and moves it into **Former Addresses**; the primary address
cannot be marked Former. **Mark as Undeliverable** is for mail that comes back: the address
gets an **Undeliverable** badge, and if it is the primary, a red warning on the card asks you
to add the new address. **Mark as Current** brings a former address back and clears its end
date. You can also change **Status**, **Start Date** and **End Date** on the address record.

## To Move the Whole Household to a Person's Address

Use this when a person's own address becomes the household's, for example when the family
moves into the home one of them already had.

1. Open the person. On the **Addresses** card, click **Use for Whole Household** on their
   address. (Seasonal addresses do not offer it.)
2. If the person belongs to more than one household, choose one under **Which household?**.
   Their own household is listed first.
3. Click **Use for Whole Household** in the confirmation, or **Cancel**.

You should see: "The household now uses this address." The household gets this address as
its primary, and everyone in it without an address of their own moves to it. If it is the
person's own household, they move with the household from now on; their own address stays
on their card without the **Primary** badge.

## To Give Everyone in the Household Its Address

Use this to bring people back to the household's address, or, if your org's **Address
Updates** setting is **Nobody moves until you choose**, to move them after the household's
address changes.

1. Open the household. On the **Addresses** card, click **Update Everyone's Address** on the
   primary address.
2. The confirmation lists who will get this address, and who has an address of their own.
   Tick anyone with their own address who should move too; the rest stay where they are.
3. Click **Update Everyone's Address** in the confirmation, or **Cancel**.

You should see: "Everyone's address has been updated." A person you ticked keeps their own
address on their card, without the **Primary** badge.

If you cannot see either button, you can read addresses but not change them. Ask your admin.

## To add a seasonal address

Use this for a household that spends part of each year somewhere else.

1. Click **Add address** and choose **Type** Seasonal.
2. Fill in the address.
3. Fill in **Seasonal Start Month** and **Seasonal Start Day** (when it takes over) and
   **Seasonal End Month** and **Seasonal End Day** (when it stops). Months are 1 to 12.
4. Click **Add address**.

You should see: the address on the card with its dates, for example "Used from January 1 to
March 31". A nightly job makes it the primary when the season starts and puts the previous
address back when it ends. You do not move it by hand.

## To change or delete an address

The card has no Edit or Delete button. Change the address on its own record:

1. Open the **Addresses** tab from the navigation menu (it is near the end), or the
   **Addresses** related list on the record.
2. Open the address and click **Edit** to change it, or **Delete** to remove it.

You should see: the change on the record's **Addresses** card without a reload.

## To set a person's email addresses

Each person has **Personal Email**, **Work Email** and **Alternate Email**, and **Preferred
Email** to choose between them. They are in the **Reaching This Person** section of the
person.

1. Click **Edit** on the person (or the pencil next to a field).
2. Fill in the addresses you have.
3. Set **Preferred Email** to Personal, Work or Alternate.
4. Click **Save**.

You should see: the ordinary **Email** field now holds the address you chose. Every mailing
and list view uses it. To switch, change **Preferred Email**; you never retype the address.

## To set a person's preferred phone

1. Edit the person. In the **Reaching This Person** section, fill in the numbers you have:
   **Home Phone**, **Mobile**, **Work Phone** or **Other Phone**.
2. Set **Preferred Phone** to Home, Mobile, Work or Other.
3. Click **Save**.

You should see: the ordinary **Phone** field now holds the number you chose. Home maps to
Salesforce's **Home Phone**, Mobile to **Mobile**, Other to **Other Phone**, and Work to
BarnCRM's **Work Phone**.

## Common problems

- Problem: "A seasonal address needs a start month, a start day, an end month, and an end day
  so we know when to use it." Fill in all four seasonal fields.
- Problem: "A seasonal month is a number from 1 (January) to 12 (December)." or "A seasonal
  day is a day its month has ..." Correct the number.
- Problem: "An address belongs to one household, one organization, or one person. Choose only
  one." Clear one of **Household or Organization** and **Person** on the address.
- Problem: "This is the address in use. To change that, make another address the primary, or
  delete this one." You tried to untick **Primary** on the only address in use. Use **Set as
  Primary** on another address instead.
- Problem: "The address could not be saved. Check the fields marked in the form and try
  again." Fix the marked fields.
- Problem: "We could not make that the primary address. Check that you have permission to
  edit addresses ..." Ask your admin for edit access.
- Problem: "The address status could not be saved. You may not have access to change it." Ask
  your admin for edit access to addresses. A card with no status menu means the same.
- Problem: the **Addresses** card has no **Add address** or **Set as Primary** button. Your
  access lets you read addresses but not change them (the Read Only role, for example). Ask
  your admin.
- Problem: "The Work email address is empty, so there is nothing to put in the ordinary Email
  box. Type that address in, or choose a different preferred email." Fill in the address you
  chose, or choose another. The same message appears for phones ("The Mobile phone number is
  empty ...").
- Problem: you typed into **Email** or **Phone** and it changed back. Once a preferred email
  or phone is set, those fields are filled from your choice on every save. Edit the address
  or number you chose instead, or clear the preference.
- Problem: there is no **Addresses** card. The Addresses feature is off. Ask your admin.

## Related

- [People and households](people-and-households.md)
- [Relationships and affiliations](relationships-affiliations.md)
- Admin Guide: [Addresses](../admin-guide/addresses.md),
  [Email addresses](../admin-guide/emails.md),
  [Preferred phone](../admin-guide/preferred-phone.md)
