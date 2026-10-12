# Household members and the primary contact

**Feature:** C-01 Household model (Members panel)
**Package:** Core
**Iteration:** v0.1

## What it does

Every household record carries a **Household Members** panel that lists the people in it,
says which one is the primary contact, and lets you change that with one click. A person's
record carries a **Household** panel that names the household they belong to and links to
it, so you can get from a person to their household and back without searching.

The primary contact is the person letters are addressed to when only one person can be.
Receipts, acknowledgments and mail merges read it, so a household with the wrong primary
contact sends its mail to the wrong person.

## How to turn it on

Both panels are there as soon as Core is installed and the Open Impact app is in use.
There is nothing to switch on.

**Who can do what.** Anyone who can see a household sees its members. Making somebody the
primary contact edits the household, so you need edit access on the household to do it.
Without it the button is still there, and the product tells you that the change was refused
rather than pretending it worked. Moving a person out of the household needs edit access on
that person as well.

**Where the panels are.** Core ships the placement: the Members panel sits on the packaged
Household record page, and the Household panel sits on the packaged Contact record page,
both of which the Open Impact app uses. If either is missing, you are most
likely looking at the record outside the **Open Impact** app, or somebody has overridden
the page assignment in the Lightning App Builder.

## The Members panel

Each row on the panel names one person and their role in the household, followed by a
**Primary** badge on the primary contact and a **Deceased** badge on anyone who has died.
Two actions sit on each row:

- **Make primary** turns that person into the household's primary contact. It is hidden on
  the person who already is.
- **Move to another household** takes that person out of this household and into one you
  choose. It only appears where a move can actually be carried out: a person your org
  stores as an account can only be moved in the flexible way of belonging, so in the simple
  way the button is not offered on them.

Both actions name the person for a screen reader ("Make Maria Garcia the primary contact",
"Move Maria Garcia to another household"), so a reader who cannot see the row still knows
whose button it is. While the panel is loading or saving, it says so.

An **Add member** button sits below the list.

- In the simple way of belonging it opens the same new contact form you would use anywhere
  else in the org, with this household already filled in.
- In the flexible way of belonging it offers two ways to add someone. **Add someone already
  in Salesforce** searches by name as you type and lists matches to add with one click. **Or
  add someone new** takes a salutation, first name and last name and creates the person as
  it joins them. Either way the list refreshes to show the new member once it is added.

### The primary contact in the simple way of belonging

In the simple way (one household per person, the shipped default), the primary contact is
the **Primary Contact** field on the household itself. The panel reads that field and badges
the matching person. **Make primary** writes that field, using your own access to the
household, so it succeeds exactly when you could have edited the field by hand.

### The primary contact in the flexible way of belonging

In the flexible way, each person's membership is a record of its own, and the primary
contact is the membership marked primary. **Make primary** marks the person you chose and
unmarks everyone else in that household, again using your own access, so you need to be
able to edit the membership records of that household.

The household's **Primary Contact** field follows along by itself, so reports, the compact
layout and thank-you emails all see the same person. A person your org stores as an account
(a person account) appears in that field under their own name, as the contact record
Salesforce keeps behind every person account. Because the field follows the membership
records, you cannot type a different Primary Contact on a household in this way of
belonging: the save is refused with a message pointing you back to **Make primary**. An
organization's Primary Contact is yours to set by hand either way.

## The Household panel on a person

Open any person and the **Household** panel shows the household's name as a link, how many
people are in it, and the formal greeting, so you can check how a letter to that household
will open without leaving the person's record. Click the name to open the household.

In the flexible way of belonging a person can be in more than one household (a child of
divorced parents, for example). The panel then lists each household they belong to.

When the person is not in any household, the panel says **This person is not in a
household yet**. In the simple way that means the person has no household filled in, or the
account they point at is an organization rather than a household. In the flexible way it
means no current membership record names them.

## A five-minute walkthrough

Maria does this from the sample data.

1. Open the **Open Impact** app and click the **Households** tab, then open **The Garcia
   Family**. The **Household Members** panel lists Harper, Luis and Diego Garcia, with a
   **Primary** badge on one of them.
2. On Luis's row, click **Make primary**. The badge moves to Luis and the message "Luis
   Garcia is now the primary contact." appears. The **Make primary** button disappears from
   his row and appears on the person who used to be primary.
3. Click Luis's name to open his record. The **Household** panel names **The Garcia
   Family**, says how many members it has, and shows the formal greeting.
4. Click the household name. You are back on the household, and Luis still carries the
   **Primary** badge.
5. Open the **Contacts** tab, click **New**, enter the first name `Wei` and the last name
   `Lee`, leave the household blank, and save.
   His **Household** panel names **The Lee Family**, the household that was created for him,
   with one member.

## Common mistakes

**"There is no Primary badge on anyone."**
The household has no primary contact yet. Nothing chooses one for you: click **Make
primary** on the right person. This is also what you see after moving the primary contact
out of a household, because the product clears the field rather than guessing a
replacement.

**"Make primary says the change was refused."**
The message is "The primary contact could not be changed. Check that you can edit this
household and try again." You need edit access on the household in the simple way of
belonging, and on that household's membership records in the flexible way. Ask whoever
manages access, or ask them to make the change.

**"The household will not let me change its Primary Contact."**
Your org uses the flexible way of belonging, where the field follows whoever is marked
primary on the household's members. Use **Make primary** on the **Household Members** panel
instead; the field updates on its own.

**"I cannot move this person."**
There is no **Move to another household** button on a person your org stores as an account
while the org uses the simple way of belonging, because that move cannot be carried out.
Switch to the flexible way in Open Impact Settings, Households, if you need it.

**"The Household panel on a person says they are not in a household yet, but they are."**
In the simple way, check that the household field on the person is filled in and points at
a household rather than an organization. In the flexible way, check that their membership
has no end date in the past: somebody whose membership has ended is no longer in that
household, and the panel says so.

## Field reference

For report builders only.

| Where | Field label | Purpose |
|---|---|---|
| Household | Primary Contact | The primary contact. In the simple way of belonging, written by Make primary. In the flexible way, kept in step with the member marked primary (a person account appears as its person contact) |
| Household | Member Count | The number shown on the Household panel of a person |
| Household | Formal Greeting | The greeting shown on the Household panel of a person |
| Household Member | Is Primary | The primary contact in the flexible way of belonging. Written by Make primary |
| Household Member | End Date | A membership with an end date in the past no longer counts |
