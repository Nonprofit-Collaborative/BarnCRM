# Engagement Score

## What It Does

**Engagement Score** gives every person one number from 0 to 100 that says how engaged they
have been lately, across four parts:

- **Gifts:** the amount they gave in the window (Received gifts where they are the donor).
  Needs Giving.
- **Hours:** the volunteer hours they worked in the window (Approved hours). Needs Volunteers.
- **Events:** the events they attended in the window (attendees marked Attended). Needs Event
  Management.
- **Activity:** how recently a task, call or meeting was logged for them (the person's Last
  Activity). Always available, including on a Platform-only org.

You decide how much each part counts and what earns it full marks. BarnCRM works the score out
each night and shows it on the person page as a meter, with the day it was scored. It is a
plain number field, **Engagement Score**, so Find, list views and reports can sort and filter
by it.

Giving's [Donor Scoring](donor-scoring.md) still rates gifts alone (recency, frequency and
amount). Engagement Score is the broader number and does not replace it.

## How to Turn It On

It is off on a new install.

1. In **BarnCRM Settings**, open **People and Households**. In the **People** box turn on
   **Turn on engagement score**. Change the weights and targets if you like (below). Save.
2. Make sure the nightly run is scheduled: **BarnCRM Settings**, **General**, the **Nightly
   Jobs** panel lists **Engagement Score** as On. If it says Not Scheduled, press **Schedule
   Nightly Jobs**; see [Nightly Jobs](nightly-jobs.md). Turning the setting on does not
   schedule anything by itself. People are first scored the night after.
3. The **Engagement Meter** is already on BarnCRM's Contact record page. On a page of your own,
   add it in Lightning App Builder.

## Settings

All three are in **BarnCRM Settings**, **People and Households**, **People**, and apply to the
whole organization. Weights and targets are each one line: a part's name and a whole number,
parts separated by commas. A part you leave out, or write in a way BarnCRM cannot read, keeps
its default.

- **Turn on engagement score** (default off).
- **Engagement score weights** (default `Gifts 40, Hours 25, Events 20, Activity 15`): how much
  each part counts. Use whole numbers; they need not add up to 100. A weight of 0 leaves a part
  out.
- **Engagement score targets** (default `Gifts 1000, Hours 40, Events 4, Activity 90,
  Months 12`): what earns each part its whole weight within the last **Months** months (1 to
  60). Gifts is an amount, Hours is hours, Events is a count, and Activity is the number of
  days over which a logged activity stops counting.

## How the Score Is Worked Out

Each part becomes a share from 0 to 1:

- Gifts, Hours and Events: the person's total in the window divided by the target, and never
  more than 1. Giving 500 against a target of 1000 is one half.
- Activity: 1 on the day of the activity, falling evenly to 0 after the Activity days. With the
  default 90, an activity 45 days ago is one half. No activity is 0.

The score is each share times its weight, added up, divided by the weights of the parts that
can be measured, times 100, rounded. A part whose module is not installed is left out of both
sums, so a Core-only organization scores on activity alone, and installing a module later does
not lower anyone's ceiling.

Example, with the defaults and every module installed: 500 given (0.5 x 40 = 20), 40 hours
(1 x 25 = 25), one event (0.25 x 20 = 5), an activity 45 days ago (0.5 x 15 = 7.5). The total
57.5 out of 100 is a score of 58.

Not counted: soft credits, gifts credited only to a household or organization, and, where
people are kept as person accounts, gifts recorded without the person as Donor Contact.

## When It Runs

The nightly step **Engagement Score** runs at 2:30 while the setting is on, after the steps
before it finish. It rescores every person and saves only those whose score changed, with
**Scored On** set to that day, so **Scored On** is the day the current score was set. People
whose score did not change are not saved, so their Last Modified date stays as it was. A
person who cannot be saved (a validation rule of your own, say) is listed in the
[Error Log](error-log.md) and the others are saved. It is skipped while the setting is off.

Turning the setting off hides the meter and stops scoring; the last scores stay on the records
until you clear them (for example with Super Transformer).

## Who Sees It

Everyone who can read a person sees their score and the meter: BarnCRM Admin, Staff and Read
Only can read both fields, and no one can edit them. The score shows no amounts, hours or
events, only the result.

## Common Mistakes

- **The meter does not show.** The setting is off, or the person has not been scored yet (the
  nightly run is not scheduled, or has not run since you turned it on).
- **Everyone scores 0 or 100 on a Core-only org.** Only Activity can be measured there, so the
  score is the Activity share alone. Log activities, or install the modules whose parts you
  want.
- **A part seems ignored.** Check its weight is above 0 and the line reads as name then number,
  for example `Hours 25`.
