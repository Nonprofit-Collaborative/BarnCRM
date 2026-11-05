# Donor Scoring

## What It Does

Donor scoring rates every donor on three questions: how recently did they give, how often,
and how much. Each answer becomes a score from 1 to 5, the three scores are added into one
**Donor Score** (3 to 15), and BarnCRM names a **Giving Pattern** from them: Champion, Loyal,
Promising, At Risk, Lapsed or Occasional. The three scores are **Recency Score**,
**Frequency Score** and **Amount Score** (often called RFM elsewhere).

Nothing is typed in. The three inputs are totals the Rollup Builder keeps on every person,
household and organization, so a score always agrees with the numbers printed beside it.
The pattern shows in the **Giving** section of the donor's record and the scores in **Giving
Details** below it, on the **Details** tab. Every one is a normal field,
so Find can filter, sort and show them, and donor segments can use them.

| Score | What it measures | Where it comes from |
|---|---|---|
| Recency | Days since the donor's last gift | **Days Since Last Gift**, from **Last Gift Date** |
| Frequency | Gifts in the recent window | **Recent Gift Count**, a rollup of gifts in the last 730 days |
| Amount | Giving in the recent window | **Recent Giving**, a rollup of gifts in the last 730 days |

A donor with no gift has no scores and no segment.

## How Scores Are Worked Out

Each score uses four cutoffs, which you can change (see below). With the defaults:

| Score | 5 | 4 | 3 | 2 | 1 |
|---|---|---|---|---|---|
| Recency (days since last gift) | 90 or fewer | 91 to 180 | 181 to 365 | 366 to 730 | more than 730 |
| Frequency (gifts in the window) | 6 or more | 4 to 5 | 2 to 3 | 1 | none |
| Amount (given in the window) | 5,000 or more | 1,000 to 4,999 | 250 to 999 | 50 to 249 | under 50 |

The segment is the first line that fits, with R, F and M the three scores:

| Segment | When |
|---|---|
| Champion | R, F and M are all 4 or 5: recent, frequent, generous |
| Loyal | R is 3 or more and F is 3 or more |
| Promising | R is 4 or 5 and F is 1 or 2: recent, not yet frequent |
| At Risk | R is 1 or 2 and F is 3 or more, or M is 4 or 5: used to give a lot, not lately |
| Lapsed | R is 1 or 2 |
| Occasional | Everyone else |

## How to Change the Cutoffs

Everything is in the app. You never open Setup.

1. Open **BarnCRM Settings**, then **Giving**.
2. Open **Donor Levels and Scores**.
3. Change any of the three cutoff settings. Each is four numbers separated by commas:
   - **Donor score recency days**, default `90,180,365,730`. Numbers rise.
   - **Donor score frequency gifts**, default `6,4,2,1`. Numbers fall.
   - **Donor score monetary amount**, default `5000,1000,250,50`. Numbers fall.
4. Save. Scores update as each donor next changes, and every night.

These settings apply to your whole organization. If a value is not four numbers in the right
order, BarnCRM ignores it and uses the default, so a typing mistake never stops scoring.

## How to Change the Recent Window

The recent window is the last 730 days, two years. To change it, open **Rollup Builder**,
open **Contact recent gift count** (and the Account and Household versions of it, and the
three **recent giving** definitions), and change the 730 in the filter that reads **Gift Date
in the last 730 days**. A total that depends on today's date is refreshed every night.

## When Scores Update

A donor is scored in the same save that changes their totals, so a new gift moves the score
at once. Because the days since the last gift change even when nothing is saved, the nightly
**Donor Levels** job on **Nightly Jobs** also refreshes every donor's scores. To switch
scoring off, open **Automation** and turn off **Donor score assignment** for contacts,
accounts or both; scores already on records stay as they are.

## Using Scores

- **On the donor:** the **Giving** section shows the **Giving Pattern**; **Giving Details**
  shows the **Donor Score**, the three scores, days since the last gift, the recent gift count
  and recent giving.
- **In Find:** choose **Giving Pattern**, **Donor Score** or any score as a column or a condition.
- **In donor segments:** [Donor segments](donor-segments.md) has two starter templates,
  **Champions** and **Slipping Donors**.

## Common Problems

- **A donor has no score.** They have no gift, or the **Recent Gift Count** and **Recent
  Giving** rollups are switched off in the Rollup Builder. Run **Recalculate** there.
- **Scores look old.** Open **Nightly Jobs** and check the Donor Levels job is scheduled.
- **A segment seems wrong.** Look at the three scores on the record, then at the cutoffs.
  A donor who gave once a long time ago and a lot is At Risk, not Lapsed, on purpose.
