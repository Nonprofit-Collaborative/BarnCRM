# Retention Reports

## What it does

Four reports answer the four questions a fundraiser asks about donor loyalty, and each one
says in writing exactly who it counts.

- **LYBUNT Donors**: gave last fiscal year, has not given this fiscal year.
- **SYBUNT Donors**: gave in some earlier fiscal year, has not given this fiscal year.
- **New Versus Retained Donors**: of the people who have given this fiscal year, how many are
  new, how many were kept, and how many came back after a gap.
- **First to Second Gift Conversion**: of the people whose first gift fell in a completed
  fiscal year, how many have given a second one.

They arrive with the Giving package, in the same **Open Impact Giving** folder as the
dashboard reports, and they need no building and no filters set. They are ordinary
Salesforce reports: open one, change a filter, save a copy of your own.

The reports count donors, not gifts. One row is one household, one organization, or one
person account, so the record count at the bottom of a group is a number of donors you can
put in a board paper.

## The definitions, in plain language

Read this section once. It is the part of the feature that matters, because a retention
report you cannot explain is a report nobody acts on.

**A qualifying gift** is a gift with the status Received, Refunded or Written off, for an
amount greater than zero. Two consequences, both deliberate:

- **A gift that was refunded later is still a gift.** The donor gave. The money went back,
  and their total giving shows that, but they are not a person who never gave.
- **A refund is never itself a gift.** Open Impact records a refund as a second gift for a
  negative amount, so the amount test leaves it out. A refund dated this year of a gift made
  three years ago does not make its donor a this year donor.

This is the same rule the donor's Gift Count, First Gift Date and Last Gift Date already
follow, which is why these reports read those fields instead of reading last year's total.

**LYBUNT** means Last Year But Unfortunately Not This year. A donor is on the list when their
most recent qualifying gift falls in the last fiscal year. The year boundary is the fiscal
year, not the calendar year, and it is the one set in Setup, which must match the fiscal year
start month in Open Impact Settings (see step 1 below).

The refund cases, spelled out because they are where other systems go wrong:

- A donor gave last year, and you refunded that gift this year. They are **on** the list.
  They gave last year and they have not given this year, which is true whatever happened to
  the money afterwards.
- A donor gave this year, and you refunded it. They are **not** on the list. They gave this
  year. Their total for the year is zero, and they are still not somebody to solicit as a
  lapsed donor.

**SYBUNT** means Some Year But Unfortunately Not This year. A donor is on the list when their
most recent qualifying gift falls before this fiscal year began. "Some year" reaches all the
way back to their first gift, with no five year cutoff or any other cutoff, because the test
is on a date rather than on a window. The report groups by the fiscal year of that last gift,
so if you only want the last three years, read the top three groups and stop. Every LYBUNT
donor is also a SYBUNT donor.

**New, retained and reactivated** are three names for the people who have given this fiscal
year:

- **New**: their first qualifying gift ever falls in this fiscal year. Nothing earlier, in
  any year.
- **Retained**: they gave this fiscal year and last fiscal year.
- **Reactivated**: they gave this fiscal year, their first gift was in an earlier year, and
  they gave nothing last fiscal year. This is the donor who gave two years ago, skipped last
  year, and is back. Every system names this person differently. Open Impact calls them
  reactivated, never new and never retained, and the report tells you which year they first
  gave so you can see how long they were away.

Retained is counted by counting gifts, not by adding money. A donor whose only gift last year
was refunded inside that same year still counts as having given last year, so they read as
retained rather than reactivated.

**First to second conversion** is, of the donors whose first gift fell in a given fiscal year,
the share who have given at least one more gift. The window is from the first gift until
today. The report covers the two completed fiscal years, so the newest cohort has had between
twelve and twenty four months to give again, and the older cohort has had longer. Compare a
cohort with the same cohort a year later rather than comparing the two cohorts to each other,
because they have not had the same amount of time.

## How to turn it on

1. **Make the two fiscal years agree.** In Open Impact Settings, open the **Rollups** page and
   read **Fiscal year start month**. Then, in Salesforce Setup, search for **Fiscal Year** and
   check that the org's
   fiscal year starts in the same month. Salesforce reports can only read the Setup value, and
   the donor fields these reports rest on are calculated from the Open Impact Settings value, so
   if the two disagree the reports draw the year boundary in a different place from the donor
   record. This is the one setup step, and it takes a minute.
2. **Run the rollups once.** On the same **Rollups** page, choose **Recalculate all**.
   These reports read First Gift Date, Last Gift Date, Gift Count and Gifts Last Year, and a
   donor whose rollups have never run is invisible to them. After the first run the rollups
   keep themselves current as gifts are entered.
3. **Give people access.** Assign the Giving module's **Giving Staff** or **Giving Read Only**
   permission set in Setup, as for the dashboard. The report folder ships public read only, so
   the reports themselves need no sharing.
4. Open the **Fundraising** app, choose **Reports**, then the **Open Impact Giving** folder.

Nothing else in Setup is required. There is no new setting to configure: the reports carry
their own definitions.

## A five-minute walkthrough

Do this after the sample data is loaded, or in an org with a couple of years of gifts.

1. Open **Reports**, folder **Open Impact Giving**, and open **LYBUNT Donors**. Every row is a
   donor to call. The list is sorted by what they gave last year, largest first, so the first
   twenty rows are the twenty conversations worth having first.
2. Look at the **Rollups Last Calculated** column on any row. That is when this donor's
   numbers were last worked out. If it says last month, the list is a month stale, and step 2
   of the setup above fixes it.
3. Open **SYBUNT Donors**. It is grouped by the fiscal year of the donor's last gift, newest
   group first. The first group is the same people you just saw on LYBUNT. The groups below it
   are the deeper lapses: a household that last gave four years ago is a different letter from
   one that last gave last spring.
4. Open **New Versus Retained Donors**. The outer grouping is the fiscal year of each donor's
   first gift. The group for the current fiscal year is your **new donors** this year, and the
   record count on that group is the number to report. Every other group is a returning donor.
5. Inside any earlier first gift year, look at the two subgroups. **Gave last fiscal year** is
   **retained**. **Did not give last fiscal year** is **reactivated**. Add up the retained
   subgroups across all the earlier years and divide by the number of donors who gave last
   year, which is that retained total plus the record count on the LYBUNT report, and you have
   your retention rate.
6. Open **First to Second Gift Conversion**. Each group is a cohort: the donors whose first
   gift fell in that fiscal year. Under it, **Gave again** over the group total is your
   conversion rate for that cohort. A number under a quarter is normal and worth a welcome
   series; a number under a tenth usually means nobody is thanking first time donors.
7. Choose **Save As** on any of these before you change a filter, so your version does not
   overwrite the shared one.

## Common mistakes

**A donor who gives goods every year never appears on any of these reports.** That is
correct, and it is worth knowing before somebody reports it as a bug. These reports are
built on cash: an in-kind gift carries no amount, so it is in no fiscal year total and in no
gift count, and a donor whose only gifts are goods has no first or last gift date to be
retained or lapsed against. Find them through the In-kind value figure on their record or
the In-kind Gifts This Year report instead. See [In-kind gifts](in-kind-gifts.md).

**A donor is on the LYBUNT list who gave last week.** Two causes. Either the rollups have not
run since that gift, which the Rollups Last Calculated column on their row will show, or the
gift is dated in the future. Last Gift Date is the date on the gift, so a gift dated next
month counts as next month, and until then the donor looks lapsed.

**The year boundary looks wrong: a December gift landed in the wrong year.** The two fiscal
years disagree. Setup's fiscal year decides which donors the report selects, and Open Impact
Settings' fiscal year start month decides what Giving Last Year and Gifts Last Year hold. The
symptom is a donor on the LYBUNT list whose Giving This Year is not zero. Fix it with step 1
of the setup above, then recalculate the rollups.

**The retention numbers do not add up to the number of donors.** They do, but across two
reports. Everyone who gave last year is either on the LYBUNT report, because they have not
given this year, or in a retained subgroup of the New Versus Retained report. New and
reactivated donors are extra: they did not give last year, so they are in neither of those two
counts.

**Conversion looks worse this year than last year.** Check the cohort. The newest cohort has
had less time to give a second gift than the one before it, because the window runs to today.
A cohort is comparable with itself a year later, not with the cohort before it.

**Organization donors seem to be missing.** They are not. These reports run on donors of every
kind: households, organizations, and, in a Person Account org, people. If a company is missing
from the LYBUNT list, check its Last Gift Date rather than assuming the report skipped it. A
gift credited to a contact rather than to their household or organization rolls up to that
contact, and these four reports read accounts, so a gift entered against a contact alone is
not on them.

**Somebody edited the shared report.** As with the dashboard reports, a person with edit
access can save over these. Ask staff to use **Save As**. A package upgrade does not restore a
packaged report that has been changed.

**The numbers have never been checked against an org.** These reports ship as metadata that
has been read and reviewed rather than run: the filters match the definitions on this page,
and the definitions are the promise. The first time you run them, spot check one donor from
each list against their gift history before you send a mailing.
