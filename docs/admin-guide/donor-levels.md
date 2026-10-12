# Donor levels

## What it does

Donor levels put your organization's own names on your donors: Friend, Sustainer,
Leadership Circle, whatever your ladder calls them. You set the rungs and the amount each
one starts at, and Open Impact keeps every household, organization, and person on the
right rung as their giving changes, without anybody running a report or updating a field.

Each donor record also keeps the level they were on before and the date they moved, so
"who joined the Leadership Circle this month" and "who slipped out of it" are both a list
view away.

A level is a label on a total you already have. It reads the giving total that appears on
the same record, the one the Rollups page maintains, so a donor's level and the number
printed next to it can never disagree.

## How to turn it on

Everything is in the app. You never open Setup.

1. Open **Open Impact Settings**, then **Giving**.
2. Open **Donor levels**. This is the page that shows your ladder.
3. Choose **New level** and create your first rung. Each rung has:
   - a **name**, the one you use with donors and on your donor wall;
   - a **minimum amount**, the amount at which a donor reaches this rung. A donor whose
     total is exactly the minimum is on it;
   - a **maximum amount**, optional. Leave it empty on your top rung. On the others, set
     it to the next rung's minimum: a donor whose total is exactly the maximum has moved
     up to the next rung, not stayed on this one;
   - a **description**, optional, for what this level means and what a donor at it is
     offered;
   - **active**, which is on for a new rung.
4. Repeat until your ladder is complete. There is no limit and no required number of
   rungs; four or five is usual.
5. Back in **Open Impact Settings**, then **Giving**, set **Donor level source**. This is
   the total your ladder is measured on:
   - **Total giving**, everything the donor has ever given. This is the default and the
     safe choice: it never resets.
   - **Giving this year**, the current fiscal year only. Choose this for an annual
     society, and know that on the first day of your new fiscal year every donor starts
     again from nothing, which is what an annual society means.
   - **Giving last year**, the fiscal year before this one.
   - **Largest gift**, the single biggest gift the donor has given, for a ladder built on
     one gift rather than on a total.
6. Turn **Donor levels** on in the same section.
7. Back on the **Donor levels** page, choose **Recalculate now**. Levels are assigned to
   everyone who already has giving. The page then shows how many donors are on each rung
   and the time the recalculation finished.

From then on it looks after itself. A gift updates the donor's giving total, and the level
is worked out in the same moment. A nightly pass catches the two things a gift does not
announce: your fiscal year turning over, and a ladder you edited.

## A five-minute walkthrough

Start with the sample data loaded (Open Impact Settings, then Sample data).

1. Open **Open Impact Settings**, then **Giving**, then **Donor levels**. The ladder is
   empty.
2. Choose **New level**. Name it `Friend`, minimum `100`, maximum `1000`. Save.
3. Choose **New level** again. Name it `Sustainer`, minimum `1000`, maximum `5000`. Save.
4. Choose **New level** once more. Name it `Leadership Circle`, minimum `5000`, leave
   maximum empty. Save. You now have three rungs and the page lists them lowest first.
5. Go back to **Giving** and turn **Donor levels** on. Leave the source as **Total
   giving**.
6. Open **Donor levels** again and choose **Recalculate now**. Each rung now shows a donor
   count, and the page says when the recalculation finished.
7. Use **Quick gift entry** to enter a gift of 1200 from one of the sample households.
   Open that household. **Total giving** reads 1200, **Donor level** reads `Sustainer`,
   **Previous donor level** is empty because this donor has not moved before, and **Donor
   level changed** is today.
8. Enter a second gift of 4500 from the same household. Open it again. Total giving is
   5700, **Donor level** now reads `Leadership Circle`, **Previous donor level** reads
   `Sustainer`, and **Donor level changed** is today. That is the movement David wants to
   see.
9. Refund the 4500 gift (open the gift, then **Refund**, full amount). Open the household
   once more. Total giving is back to 1200, **Donor level** reads `Sustainer` again, and
   **Previous donor level** reads `Leadership Circle`. The level always matches the total
   on the record, and the record still shows where the donor came from.

## Common mistakes

**A big in-kind donor is not on the ladder.** Levels are measured on a giving total, and a
gift of goods carries no amount, so it moves no level. That is deliberate: a level is a
promise about recognition, and most organizations make that promise about cash. If yours
recognizes goods, there is no setting for it: **Donor level source** offers the four cash
totals and not in-kind value, so the honest way to do it is to recognize those donors
alongside the ladder rather than on it. See [In-kind gifts](in-kind-gifts.md).

**Nobody has a level after you build the ladder.** Two causes. Either **Donor levels** is
still off in Open Impact Settings, or you have not pressed **Recalculate now**. Editing the
ladder does not reassign anybody by itself: a donor moves when their giving changes, or
when the nightly pass runs, or when you recalculate. Press the button after every change
to the ladder.

**A gap between rungs, so some donors have no level.** If Friend ends at 1000 and
Sustainer starts at 1500, a donor at 1200 is on no rung, which is a legitimate answer and
looks like a bug. Set each rung's maximum to the next rung's minimum and there are no
gaps. Rungs that overlap are not an error either: the higher rung wins.

**A donor drops a level after a refund and somebody asks why.** That is working as
intended. The level says what the donor's current total earns, because a level that
disagreed with the total on the same page would be worse than no level. The rung they left
stays in **Previous donor level** and the date is on the record. If your organization
awards a level permanently, record that on the donor rather than expecting Open Impact to
hold a number it can no longer see.

**Deleting a rung wipes it from the donors who held it.** Deleting a level record removes
that name from every donor's current and previous level, and there is no undo. To retire a
rung, clear its **active** box instead: donors already on it keep the name, and nobody new
is assigned to it.

**Choosing "Giving this year" and being surprised in July.** A fiscal year source empties
everybody's level on the first day of the new fiscal year, because nobody has given
anything in it yet. That is correct for an annual society and startling if you did not
mean it. If you want a ladder that never resets, the source is **Total giving**.

**Wanting a window we do not offer, such as the last twelve months.** A level can only be
measured on a total Open Impact already keeps. If you need a different window, add the
rollup you want on the Rollups page first; the level source then has a number to read.
