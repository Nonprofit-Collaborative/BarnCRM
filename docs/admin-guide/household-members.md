# Household Members and the Primary Contact

**Feature:** C-01 Household model (Members panel)
**Package:** Core
**Iteration:** v0.1

## What It Does

Every household record carries a **Members** panel that lists the people in it,
says which one is the primary contact, and lets you change that with one click. A person's
record carries a **Household** panel that names the household they belong to and links to
it, so you can get from a person to their household and back without searching.

The primary contact is the person letters are addressed to when only one person can be.
Mail merges read it (and, with Giving, receipts and acknowledgments), so a household with the wrong primary
contact sends its mail to the wrong person.

## How to Turn It On

Both panels are there as soon as Core is installed and the BarnCRM app is in use.
There is nothing to switch on.

**Who can do what.** Anyone who can see a household sees its members. The Members panel offers
each action only to someone whose access allows it, so a Read Only user sees the list with no
**Add member**, **Move to another household** or **Make Primary** button. In the simple way of
belonging, **Make Primary** needs edit access on households, **Move to another household** edit
access on contacts, and **Add member** create access on contacts; in the flexible way, all three
need access to household memberships (create to add, edit to move or make primary). Someone
who has that access but cannot edit this particular household (sharing) still sees the button,
and the product tells them the change was refused rather than pretending it worked.

**Where the panels are.** Core ships the placement: the Members panel sits on the packaged
Household record page, and the Household panel sits on the packaged Contact record page,
both of which the BarnCRM app uses. If either is missing, you are most
likely looking at the record outside the **BarnCRM** app, or somebody has overridden
the page assignment in the Lightning App Builder.

## The Members Panel

Each row on the panel names one person and their role in the household, followed by a
**Primary** badge on the primary contact and a **Deceased** badge on anyone who has died.
Two actions sit on each row:

- **Make Primary** turns that person into the household's primary contact. It is hidden on
  the person who already is.
- **Move to another household** takes that person out of this household and into one you
  choose. In the flexible way of belonging only their membership in this household ends:
  a child who also belongs to another parent's household stays in that one. It only appears where a move can actually be carried out: a person your org
  stores as an account can only be moved in the flexible way of belonging, so in the simple
  way the button is not offered on them.

Both actions name the person for a screen reader ("Make Maria Garcia the primary contact",
"Move Maria Garcia to another household"), so a reader who cannot see the row still knows
whose button it is. While the panel is loading or saving, it says so.

An **Add member** button sits below the list.

- In the simple way of belonging it opens the same new contact form you would use anywhere
  else in the org, with this household already filled in.
- In the flexible way of belonging it offers two ways to add someone. **Add someone already
  in Salesforce** searches by name as you type and lists matches to add with one click. In
  an org that stores people as person accounts, each such person is listed once, as their
  person account, and joins the household that way. **Or
  add someone new** takes a salutation, first name and last name and creates the person as
  it joins them. Either way the list refreshes to show the new member once it is added.
  Where your org stores people as accounts (person accounts) and you can create one, the new
  person is created as a person account; otherwise as a contact.

### The Primary Contact in the Simple Way of Belonging

In the simple way (one household per person, the shipped default), the primary contact is
the **Primary Contact** field on the household itself. The panel reads that field and badges
the matching person. **Make Primary** writes that field, using your own access to the
household, so it succeeds exactly when you could have edited the field by hand.

The primary contact has to be in the household. Typing somebody from another household into
the field is refused with "The Primary Contact has to be somebody in this household."
Clearing the field is always allowed. A household BarnCRM creates for a new person names that
person its primary contact.

### The Primary Contact in the Flexible Way of Belonging

In the flexible way, each person's membership is a record of its own, and the primary
contact is the membership marked primary. **Make Primary** marks the person you chose and
unmarks everyone else in that household, again using your own access, so you need to be
able to edit the membership records of that household.

The household's **Primary Contact** field follows along by itself, so reports, the compact
layout and thank-you emails all see the same person. A person your org stores as an account
(a person account) appears in that field under their own name, as the contact record
Salesforce keeps behind every person account. Because the field follows the membership
records, you cannot type a different Primary Contact on a household in this way of
belonging: the save is refused with a message pointing you back to **Make Primary**. An
organization's Primary Contact is yours to set by hand either way.

## The Household Panel on a Person

Open any person and the **Household** panel shows the household's name as a link, how many
people are in it, and the formal greeting, so you can check how a letter to that household
will open without leaving the person's record. Click the name to open the household.

The panel is on the contact page BarnCRM ships. Where your org stores people as person
accounts, add it to the person account page yourself, because BarnCRM ships no page for
them:

1. Open a person account, click the gear icon, and choose **Edit Page**.
2. Drag **Household of Person** from the custom components onto the page.
3. If the same page is also used for organizations, select the component, click **Add
   Filter** under **Set Component Visibility**, and show it only when **Is Person Account**
   equals **True**. On an organization the panel has no person to look up and would only
   say the record is not in a household.
4. Save, and activate the page for the person account record type if it is new.

In the flexible way of belonging a person can be in more than one household (a child of
divorced parents, for example). The panel then lists each household they belong to.
Wherever BarnCRM has to pick one household for such a person (totals rolled up to "their
household", an import, a donation match), it picks the one they are the primary member of,
and when they are primary in none, the one they joined first.

When the person is not in any household, the panel says **This person is not in a
household yet**. In the simple way that means the person has no household filled in, or the
account they point at is an organization rather than a household. In the flexible way it
means no current membership record names them.

## A Five-Minute Walkthrough

Maria does this from the sample data.

1. Open the **BarnCRM** app and click the **Households** tab, then open **The Garcia
   Family**. The **Members** panel lists Harper, Luis and Diego Garcia, with a
   **Primary** badge on one of them.
2. On Luis's row, click **Make Primary**. The badge moves to Luis and the message "Luis
   Garcia is now the primary contact." appears. The **Make Primary** button disappears from
   his row and appears on the person who used to be primary.
3. Click Luis's name to open his record. The **Household** panel names **The Garcia
   Family**, says how many members it has, and shows the formal greeting.
4. Click the household name. You are back on the household, and Luis still carries the
   **Primary** badge.
5. Open the **Contacts** tab, click **New**, enter the first name `Wei` and the last name
   `Lee`, leave the household blank, and save.
   His **Household** panel names **The Lee Family**, the household that was created for him,
   with one member.

## Common Mistakes

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
primary on the household's members. Use **Make Primary** on the **Members** panel
instead; the field updates on its own.

**"A membership record I made by hand, or loaded, was refused."**
In the flexible way, a membership record names exactly one person: a contact or a person
account, never both and never neither. A person can also have only one current membership
in a household, so a second one for the same person and household is refused with "This
person is already a current member of this household." Edit the membership they already
have instead. An ended membership beside a current one is history and is kept.

**"Ticking Primary Member on a membership was refused."**
A household has one primary member. Saving a membership record that would give it a second
one is refused with "This household already has a primary member." Use **Make Primary** on
the **Members** panel, which moves the mark in one step. A load of many records
(Data Loader, an import) is not refused: if it leaves a household with two primaries, the
first in member order is used as the Primary Contact and nothing else is changed, so you
can choose with **Make Primary** afterward.

**"I cannot move this person."**
There is no **Move to another household** button on a person your org stores as an account
while the org uses the simple way of belonging, because that move cannot be carried out.
Switch to the flexible way in BarnCRM Settings, People and Households, if you need it. In the simple way
the button also needs edit access to the person's **Account Name** field, since that is what
a move changes; the BarnCRM Admin and Staff permission sets grant it.

**"Saving a person with an organization in Account Name was refused."**
In the simple way of belonging, a person's **Account Name** is their household, so changing it
from a household to an organization would take them out of their household. The save is
refused with "This person is in a household, so Account Name must stay a household, not an
organization. To connect them to an organization, add an affiliation. To move them, use Move
to another household." Add an affiliation (see [Affiliations](affiliations.md)) to record
where they work, or use **Move to another household**. A person who is already at an
organization, or has no account, can still be pointed at any account, and the flexible way
of belonging is not affected.

**"The Household panel on a person says they are not in a household yet, but they are."**
In the simple way, check that the household field on the person is filled in and points at
a household rather than an organization. In the flexible way, check that their membership
has no end date in the past: somebody whose membership has ended is no longer in that
household, and the panel says so.

## Field Reference

For report builders only.

| Where | Field label | Purpose |
|---|---|---|
| Household | Primary Contact | The primary contact. In the simple way of belonging, written by Make primary. In the flexible way, kept in step with the member marked primary (a person account appears as its person contact) |
| Household | Member Count | The number shown on the Household panel of a person |
| Household | Formal Greeting | The greeting shown on the Household panel of a person |
| Household Member | Primary Member | The primary contact in the flexible way of belonging. Written by Make primary |
| Household Member | End Date | A membership with an end date in the past no longer counts |
