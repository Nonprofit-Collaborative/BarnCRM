# Affiliations

## What it does

Affiliations records a person's connection to an organization: where someone works, which
board they sit on, the club they belong to, or the school where they teach. One person can be connected to as many organizations as they really are, each with
a role and the dates it ran, and one of them is marked primary so that a list view or a mail
merge can show an employer without anyone building a report.

The point of keeping this as its own record is that a person who works at a company stays
in their own household. Their history, their letters, and everything else you hold about them
are unchanged; you have simply written down where they work.

## How to turn it on

Affiliations is part of Core, but on a new install it is off until you turn it on. In
**BarnCRM Settings**, **General**, choose **Turn on** in the **Affiliations** row (or leave
it ticked in first-run setup); see [BarnCRM Settings](barncrm-settings.md). There is nothing
to install and no Setup step, and no setting to choose once it is on: an affiliation means
the same thing in every organization, so there is nothing to configure.

On the **Automation** page in BarnCRM Settings you will see two rows for affiliations,
both switched on as they ship:

- **Check affiliations before they are saved.** The rules: an affiliation names one person
  and one organization, a person is not affiliated with themselves, it does not cover dates
  another affiliation for the same person, organization, and role already covers, and the
  status agrees with the dates. Leave this on. Switching it off lets an import create
  overlapping affiliations and affiliations with no organization, with nothing to tell you
  afterwards which records those were.
- **Keep one primary affiliation per person.** The upkeep: making sure at most one current
  affiliation per person carries the Primary badge, and keeping the **Primary Affiliation**
  field on the person equal to it.

They are two rows on purpose. Switching the upkeep off before a large import, which is the
usual reason to touch it, leaves every check running.

A people import links each row's first person to the organization on the row with an
affiliation, or finds the one they already have (see [Importing](importing.md), section 8).

To let your team see and manage affiliations, make sure they have one of the packaged access
levels (BarnCRM Admin, Team Member, Coordinator, or, with Giving installed, Fundraising Staff) on the **Access** page in
BarnCRM Settings. Read Only users see affiliations and cannot change them: the Affiliations
card shows them no **Add affiliation** or **Make primary** button.

The upkeep does not depend on what the person saving can see or edit. Someone who may add an
affiliation but cannot edit the person it belongs to, or cannot see that person's other
affiliations (for example under private sharing), still ends up with one primary and the
right **Primary Affiliation** on the person: BarnCRM makes those two corrections itself. The
affiliation they save is still checked against their own access.

Affiliations appear in three places once you are set up: an **Affiliations** card on every
person's record, an **Affiliations** card on every organization's record showing the people
connected to it, and an **Affiliations** tab in the BarnCRM app for reporting and list
views. Every person also carries a **Primary Affiliation** field holding the one organization
they are chiefly associated with, which you can put on a list view or a mail merge.

The card reads and saves affiliations as the person using it, through Salesforce's own record
service, so it shows exactly what their object and field access allows. An affiliation
edited elsewhere on the page shows on the card without a reload, and after **Make primary**
the person's **Primary Affiliation** field refreshes too.

## A five-minute walkthrough

You are Maria. A colleague is planning an outreach to local employers and needs to know who
among your contacts works where. Start from the sample data.

1. Open the **BarnCRM** app and choose **Households**. Open **The Garcia Family** and
   choose **Harper Garcia**.
2. Scroll to the **Affiliations** card. It is empty, and it says "No affiliations on file
   yet."
3. Choose **Add affiliation**. Fill in:
   - **Organization**: Bayview Hardware
   - **Role**: Store Manager
   - **Status**: leave it as Current
   - **Primary**: select it
   - **Start date**: January 1 of last year
   Choose **Add affiliation** in the form.
4. The card shows one line: Bayview Hardware, Store Manager, with a **Primary** badge on
   it. A current affiliation carries no status badge. Look at the top of Harper's record: **Primary Affiliation** now
   reads Bayview Hardware. You did not fill that in.
5. Open **Bayview Hardware** from the **Organizations** tab. Its **Affiliations** card
   shows Harper Garcia, Store Manager. The same record, read from the organization's side.
6. Go back to Harper and choose **Add affiliation** again:
   - **Organization**: Heritage Rotary Club
   - **Role**: Club president
   - **Primary**: select it
   Choose **Add affiliation** in the form. The card now shows two lines, and the **Primary** badge has moved to
   Heritage Rotary Club. The Bayview Hardware line is still there, still Current, and is no
   longer primary. **Primary Affiliation** at the top of the record now reads Heritage
   Rotary Club. Only one organization can be primary at a time, and you never have to clear
   the old one.
7. The card has no Edit action, so change an affiliation on its own record: open the App
   Launcher, search for **Affiliations**, open Harper's Heritage Rotary Club affiliation,
   and choose **Edit**. Set **End date** to last month and save. Back on Harper's record,
   the line carries a **Former** badge, the **Primary** badge disappears, and **Primary Affiliation** at the top of
   Harper's record is empty, because a connection that has ended is not the one Harper is
   chiefly associated with. Mark the Bayview Hardware line primary to fill it again.
8. Check the Households tab. Harper is still in The Garcia Family, exactly where she was.
   Nothing about an affiliation moves a person.

## Common mistakes

**Expecting an affiliation to move the person to the organization.** It does not, and that
is the whole reason affiliations exist as records. In systems that put a person "at" a
company, adding an employer moves them out of their household and their history goes
with them. Here, Harper stays in The Garcia Family and simply has a connection to Bayview
Hardware on file. If you actually want to move someone, use **Move to another household**
on their record.

**Marking a second organization primary and expecting to clear the first.** You do not have
to. Marking any affiliation primary clears the primary flag on that person's other
affiliations in the same save. If two lines somehow both show the badge, open one and save it
again and the other clears. If it keeps happening, check whether **Keep one primary
affiliation per person** is switched off on the Automation page: with that row off nothing
settles the badge, though every rule on an affiliation still runs.

**Wondering why Primary Affiliation went empty.** A former affiliation is never the primary
one. Setting an end date, or setting the status to Former, clears the primary flag and empties
the person's Primary Affiliation field. That is on purpose: a field that still names an
employer someone left last year is worse than an empty one. Mark one of their current
affiliations primary to fill it again.

**Recording the same job twice instead of ending the first one.** If someone was a board
member from 2019 to 2022 and is a board member again now, that is two affiliations with two
date ranges, and both should have their dates filled in. Two affiliations for the same person,
the same organization, and the same role with overlapping dates is refused with "Harper Garcia
already has an affiliation with Bayview Hardware as Store Manager covering those dates.
Open AF-000123 to change it." End the first one before you start the second. Two that
already overlap (loaded before the rule, or with automation off) are checked only when you
change the person, organization, role or dates on one of them: marking one primary or
editing its description still saves, and changing its dates is how you fix the overlap.

**Looking for a setting to turn on.** The only switch is the **Affiliations** feature in
**BarnCRM Settings**, **General**, which is off on a new install until you turn it on (see
[BarnCRM Settings](barncrm-settings.md)). Beyond that, Affiliations behaves the same way in
every organization, so no other setting is exposed, and there is nothing you can get wrong
by leaving it alone.
