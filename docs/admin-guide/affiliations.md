# Affiliations

## What it does

Affiliations records a person's connection to an organization: where someone works, which
board they sit on, the congregation they belong to, or the foundation whose program officer
they are. One person can be connected to as many organizations as they really are, each with
a role and the dates it ran, and one of them is marked primary so that a list view or a mail
merge can show an employer without anyone building a report.

The point of keeping this as its own record is that a donor who works at a foundation stays
in their own household. Their giving, their letters, and their receipts are unchanged; you
have simply written down where they work.

## How to turn it on

Affiliations is part of Core and is on as soon as Open Impact is installed. There is nothing
to install, no Setup step, and no setting to choose: an affiliation means the same thing in
every organization, so there is nothing to configure.

On the **Automation** page in Open Impact Settings you will see two rows for affiliations,
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

To let your team see and manage affiliations, make sure they have one of the packaged access
levels (Open Impact Admin, Fundraising Staff, or Program Staff) on the **Access** page in
Open Impact Settings. Read Only users see affiliations and cannot change them.

Affiliations appear in three places once you are set up: an **Affiliations** card on every
person's record, an **Affiliations** card on every organization's record showing the people
connected to it, and an **Affiliations** tab in the Open Impact app for reporting and list
views. Every person also carries a **Primary Affiliation** field holding the one organization
they are chiefly associated with, which you can put on a list view or a mail merge.

## A five-minute walkthrough

You are Maria. Your Development Director is preparing a corporate matching gift ask and needs
to know who among your donors works where. Start from the sample data.

1. Open the **Open Impact** app and choose **Households**. Open **The Garcia Family** and
   choose **Harper Garcia**.
2. Scroll to the **Affiliations** card. It is empty, and it says "No affiliations on file
   yet."
3. Choose **Add affiliation**. Fill in:
   - **Organization**: The Union Foundation
   - **Role**: Program Officer
   - **Status**: leave it as Current
   - **Primary**: select it
   - **Start date**: January 1 of last year
   Choose **Save**.
4. The card shows one line: "The Union Foundation, Program Officer, Current", with a
   **Primary** badge on it. Look at the top of Harper's record: **Primary Affiliation** now
   reads The Union Foundation. You did not fill that in.
5. Open **The Union Foundation** from the **Organizations** tab. Its **Affiliations** card
   shows Harper Garcia, Program Officer. The same record, read from the organization's side.
6. Go back to Harper and choose **Add affiliation** again:
   - **Organization**: Summit Congregation
   - **Role**: Board chair
   - **Primary**: select it
   Choose **Save**. The card now shows two lines, and the **Primary** badge has moved to
   Summit Congregation. The Union Foundation line is still there, still Current, and is no
   longer primary. **Primary Affiliation** at the top of the record now reads Summit
   Congregation. Only one organization can be primary at a time, and you never have to clear
   the old one.
7. Edit the Summit Congregation line and set **End date** to last month. Save. The line reads
   **Former**, the **Primary** badge disappears, and **Primary Affiliation** at the top of
   Harper's record is empty, because a connection that has ended is not the one Harper is
   chiefly associated with. Mark The Union Foundation line primary to fill it again.
8. Check the Households tab. Harper is still in The Garcia Family, exactly where she was.
   Nothing about an affiliation moves a person.

## Common mistakes

**Expecting an affiliation to move the person to the organization.** It does not, and that
is the whole reason affiliations exist as records. In systems that put a person "at" a
company, adding an employer moves them out of their household and their giving history goes
with them. Here, Harper stays in The Garcia Family and simply has a connection to The Union
Foundation on file. If you actually want to move someone, use **Move to another household**
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
already has an affiliation with The Union Foundation as Program Officer covering those dates.
Open AF-000123 to change it." End the first one before you start the second.

**Looking for a setting to turn on.** There is not one. Affiliations behaves the same way in
every organization, so nothing is exposed in Open Impact Settings, and there is nothing you can
get wrong by leaving it alone.
