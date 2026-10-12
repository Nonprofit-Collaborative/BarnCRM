# Funds

## What it does

A fund is the designation or restriction on money you receive: your general fund, a
building fund, a scholarship fund, a restricted grant. Every gift is designated to one or
more funds, so Tom can answer "how much of our cash is restricted" and Jen can hand the
bookkeeper a total per fund without a spreadsheet.

One fund is marked as the default. Any gift entered without a designation goes there, so
fund reporting stays complete even when David is entering checks quickly at an event.

## How to turn it on

Funds arrive with the Giving module. There is nothing to install separately.

1. Open the **Funds** tab.
2. Create the funds your organization actually uses. Most organizations start with two or
   three. You can add more at any time.
3. On the fund that should catch undesignated gifts, tick **Is Default**. Only one fund can
   be the default: ticking it on a second fund clears it on the first.
4. Open **Open Impact Settings**, choose **Giving**, and confirm **Default Fund** shows the
   fund you just marked. Setting it in either place keeps the other in step.

No Salesforce Setup step is needed.

## A five-minute walkthrough

You are David, and you are setting up funds before your first gift entry session.

1. Open the **Funds** tab and click **New**.
2. Name the fund `General` and leave **Restricted** unticked, because unrestricted money is
   money the board can spend on anything.
3. Tick **Active** if it is not already ticked, tick **Is Default**, and save.
4. You now see the fund's page with **Total Raised**, **Total Raised This Year**, **Gift
   Count** and **Last Gift Date** all empty. Open Impact calculates these, so they are shown
   as read only.
5. Click **New** again and create a second fund named `Scholarship`, this time ticking
   **Restricted** and entering a description such as "Donor restricted: tuition support
   only". Leave **Is Default** unticked and save.
6. Reopen `General`. **Is Default** is still ticked, which confirms only one default exists.
7. Enter a gift for any donor without choosing a fund (see the Gifts page). Open the gift
   and look at its allocations: one allocation for the whole amount, pointing at `General`.
8. Return to the `General` fund. Once the giving totals have been calculated, **Total
   Raised** shows the gift and **Rollups Last Calculated** shows when the number was worked
   out.

## Common mistakes

- **No fund is marked as the default.** A gift entered without a designation then fails to
  save with "No default fund is set. Open Open Impact Settings, choose Giving, and pick the
  fund that undesignated gifts should go to." Fix it by ticking **Is Default** on one fund.
- **Deleting a fund that has gifts.** Open Impact blocks it, because deleting a fund would
  make historical allocations meaningless. Untick **Active** instead: the fund stops being
  offered on new gifts and keeps its history.
- **Two funds that mean the same thing.** "General" and "General Fund" split your reporting
  in half. Pick one, move any allocations, then deactivate the other.
- **Expecting Total Raised to change the instant you save a gift.** The rollup engine
  calculates the totals. **Rollups Last Calculated** on the fund tells you when the number
  was worked out, so you always know whether you are looking at a fresh number.
