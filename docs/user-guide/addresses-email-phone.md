# Addresses, email and phone

BarnCRM keeps every address a household, organization or person uses, and marks one as the
default. The default is copied into the standard address fields, so letters and reports always
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
5. Click **Add address** at the foot of the form.

You should see: "Address saved." The first address a record gets is made the default
automatically and carries a **Default** badge.

## To choose household or personal

- An address you add on a **household** belongs to the whole household.
- An address you add on a **person** belongs to that person only. The rest of the household
  keeps its own address.
- If you edit a person's mailing address in the person's own address fields, what happens
  depends on your org's setting: either the whole household moves, or the person gets an
  address of their own. Ask your admin which yours is.

## To make an address the default

1. On the **Addresses** card, click **Set as default** on the address you want to use.

You should see: "This is now the default address, and it has been copied to the standard
address fields." The **Default** badge moves, and the record's own address fields at the
top of the page refresh. Nothing is deleted: the other addresses stay on the card.

## To add a seasonal address

Use this for a household that spends part of each year somewhere else.

1. Click **Add address** and choose **Type** Seasonal.
2. Fill in the address.
3. Fill in **Seasonal Start Month** and **Seasonal Start Day** (when it takes over) and
   **Seasonal End Month** and **Seasonal End Day** (when it stops). Months are 1 to 12.
4. Click **Add address**.

You should see: the address on the card with its dates, for example "Used from January 1 to
March 31". A nightly job makes it the default when the season starts and puts the previous
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

1. Edit the person. Fill in the numbers you have, for example **Work Phone**.
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
- Problem: "This is the address in use. To change that, make another address the default, or
  delete this one." You tried to untick **Default** on the only address in use. Use **Set as
  default** on another address instead.
- Problem: "The address could not be saved. Check the fields marked in the form and try
  again." Fix the marked fields.
- Problem: "We could not make that the default address. Check that you have permission to
  edit addresses ..." Ask your admin for edit access.
- Problem: "The Work email address is empty, so there is nothing to put in the ordinary Email
  box. Type that address in, or choose a different preferred email." Fill in the address you
  chose, or choose another. The same message appears for phones ("The Mobile phone number is
  empty ...").
- Problem: you typed into **Email** or **Phone** and it changed back. Once a preferred email
  or phone is set, those fields are filled from your choice on every save. Edit the address
  or number you chose instead, or clear the preference.
- Problem: you cannot see **Home Phone**, **Mobile** or **Other Phone** on the page. The
  packaged person page shows **Phone**, **Work Phone** and **Preferred Phone** only. Ask your
  admin to add the other phone fields to your page.
- Problem: there is no **Addresses** card. The Addresses feature is off. Ask your admin.

## Related

- [People and households](people-and-households.md)
- [Relationships and affiliations](relationships-affiliations.md)
- Admin Guide: [Addresses](../admin-guide/addresses.md),
  [Email addresses](../admin-guide/emails.md),
  [Preferred phone](../admin-guide/preferred-phone.md)
