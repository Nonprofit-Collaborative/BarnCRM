# Funds

## What It Does

A fund is the designation or restriction on money you receive: your general fund, a
building fund, a scholarship fund, a restricted grant. Every gift is designated to one or
more funds, so Tom can answer "how much of our cash is restricted" and Jen can hand the
bookkeeper a total per fund without a spreadsheet.

One fund is marked as the default. Any gift entered without a designation goes there, so
fund reporting stays complete even when David is entering checks quickly at an event.

## How to Turn It On

Funds arrive with the Giving module. There is nothing to install separately.

A new org arrives with one fund, **General Fund**: active, unrestricted, with no accounting
code, and already the default, so the first gift has somewhere to go. It is created only when
the org has no fund at all and no default fund set. An org that already has a fund, or has
chosen a default, is left exactly as it is, and an upgrade never brings the fund back if you
rename, deactivate or delete it. Rename it, give it an accounting code, or add your own funds
at any time.

1. Open the **Funds** tab.
2. Create the other funds your organization actually uses. Most organizations start with two
   or three. You can add more at any time.
3. To change which fund catches undesignated gifts, tick **Is Default** on that fund. Only one
   fund can be the default: ticking it on a second fund clears it on the first.
4. Open **BarnCRM Settings**, choose **Giving**, and confirm **Default fund** shows the
   fund you just marked. Setting it in either place keeps the other in step.

No Salesforce Setup step is needed.

## A Five-Minute Walkthrough

You are David, and you are setting up funds before your first gift entry session.

1. Open the **Funds** tab. **General Fund** is already there, ticked **Active** and **Is
   Default**, and not **Restricted**, because unrestricted money is money the board can spend
   on anything. (If your org already had funds, it is not added: click **New**, name a fund
   `General Fund`, tick **Active** and **Is Default**, and save.)
2. Open **General Fund**.
3. You see the fund's page with **Total Raised**, **Total Raised This Year**, **Gift
   Count** and **Last Gift Date** all empty. BarnCRM calculates these, so they are shown
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

## List Views

**Funds** has **All Funds**, **Active Funds** and **Inactive Funds**. Only the starting
**General Fund** ships; every other fund, and its accounting code, is your decision.

## Common Mistakes

- **No fund is marked as the default.** A gift entered without a designation then fails to
  save with "No default fund is set. Open BarnCRM Settings, choose Giving, and pick the
  fund that undesignated gifts should go to." Fix it by ticking **Is Default** on one fund.
- **Deleting a fund that has gifts.** BarnCRM blocks it, because deleting a fund would
  make historical allocations meaningless. Untick **Active** instead: the fund stops being
  offered on new gifts and keeps its history.
- **Two funds that mean the same thing.** "General" and "General Fund" split your reporting
  in half. Pick one, move any allocations, then deactivate the other.
- **Expecting an import to move Total Raised the instant it finishes.** A gift saved by a
  person updates its funds' totals a few seconds after the save (see "After the save, or
  during it" in [Rollups](rollups.md)), and the totals from an import or other bulk change
  catch up within minutes. **Rollups Last Calculated** on the fund
  tells you when the number was worked out, so you always know whether you are looking at a
  fresh number.
