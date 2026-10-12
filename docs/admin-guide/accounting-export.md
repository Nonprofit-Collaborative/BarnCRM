# Accounting Export

## What it does

Jen, who keeps the books, needs the month's gifts in the accounting system with each one
against the right fund. The accounting export gives her a spreadsheet file (CSV) of the
gifts in any date range: one row for each fund a gift was designated to, with the fund's
accounting code, the donor, how it was paid and the amount. A gift split across two funds
is two rows. A refund is its own row with a negative amount, on the day the money went
back, so the file's total is the net the bank statement shows.

The columns never change, so an import mapping set up once in QuickBooks, Xero or a
spreadsheet keeps working:

| Column | What it holds |
|---|---|
| Date | The gift date, as year-month-day (2026-09-30) |
| Gift Number | The gift's number, for example G-000123 |
| Original Gift | For a refund or write-off, the number of the gift it reverses |
| Donor | The person or organization who gave |
| Fund | The fund, empty for a gift that has no designation |
| Accounting Code | The fund's accounting code |
| Payment Method | Cash, Check, Card, ACH, Stock, Grant or Other |
| Reference | The check number or processor reference |
| Amount | This fund's share, as a plain number, negative for money that went back |

Only money is exported: gifts that are Received, Refunded or Written off. A Pending gift has
not arrived yet, a Cancelled one never will, and an in-kind gift is goods, not money, so none of
them is in the file.

Downloading changes nothing. Running it twice for the same dates gives the same file unless a
gift in those dates changed in between: a gift added or edited late, or a Pending gift that
arrived and was set to Received.

Once the file is in the accounting system, Jen clicks **Mark these gifts posted**, and those
gifts are locked: their date, amount, donor, payment method, reference and funds can no longer
change (see [Posting and Closed Periods](posting-and-closed-periods.md)). If any row of the file
changed since she downloaded it, even a fund share moved with the total unchanged, nothing is
marked and the page asks her to download again. Ticking **Only gifts
not yet posted** leaves posted gifts out of the file, so a gift entered late into a month she
already exported turns up in her next file instead of being missed.

## How to turn it on

The Connect module has to be installed. Then give the person who runs the export the
**Accounting Export** permission set, next to a Giving permission set that lets them see
gifts (**Giving Read Only** is enough). Until the Module Manager arrives, module permission
sets are assigned in Setup.

**The file holds the gifts the person running it can see**, the same as any report. Gifts
are private by default, so check that Jen can see all of them: export the same month once
as yourself and once as Jen, and compare the totals the page shows. If hers is lower, her visibility is a sharing
setting in Setup (her role, or the organization-wide default for gifts), not something Open
Impact can change. The page says this beside the button.

Open it from **Open Impact Settings**, **Giving**, **Accounting export**, or search the App
Launcher for **Accounting Export**. There are no settings.

The **Accounting Export** permission set includes **Post Gifts**, which shows the **Mark these
gifts posted** button and lets Jen unpost a single gift from its page.

## A five-minute walkthrough

Do this as Jen, with the sample data loaded.

1. Open the App Launcher, search for `Accounting Export` and open it.
2. Set **From** to the first day of last month and **To** to the last day of last month.
   Leave **Fund** and **Payment method** empty.
3. Click **Download file**. A file named like
   `accounting-export-2026-08-01-to-2026-08-31.csv` downloads, and the page says how many
   rows and gifts it holds and the net total.
4. Open the file in a spreadsheet. The first row is the column names above. Every row has a
   date inside the range. Check that the Amount column adds up to the net total the page
   showed.
5. Back on the page, choose **Building Fund** in **Fund** and download again. Every row now
   says Building Fund and accounting code 4100.
6. Choose **Check** in **Payment method** as well and download again. Only checks to the
   Building Fund remain.
7. Set a range with no gifts, such as a week next year, and click **Download file**. No file
   downloads and the page says `No gifts in this range.`
8. Set last month again, empty **Fund** and **Payment method**, and download. Click **Mark
   these gifts posted**. The page says how many gifts it marked.
9. Tick **Only gifts not yet posted** and download again. The page says
   `No gifts in this range.`: the month is in the books.

## Common mistakes

**The total is lower than the same export run by the administrator.** The person running
the export cannot see every gift. Give them visibility of all gifts (see How to turn it on) and run it again.

**`More than 10,000 rows in this range. Choose a shorter range, or one fund.`** The export
will not hand over a file that is missing rows. Export a quarter or a month at a time.

**A fund with no accounting code.** Its rows have an empty Accounting Code, which your
accounting system will not know where to put. Add the code on the fund (see
[Funds](funds.md)) and export again.

**A Pending gift that will never be paid.** It is not in the file, and cancelling it keeps it
out: set its **Status** to **Cancelled**. No negative gift is created, so no month you exported
changes, even a closed one. A Pending gift cannot be written off; see
[Refunds and write-offs](refunds.md#cancelling-a-pending-gift).

**A value in the file starts with an apostrophe.** A cell that begins with `=`, `+`, `-` or
`@` gets an apostrophe in front, so a spreadsheet does not run it as a formula. This also
applies to a reference such as `-123` or `+44 20 7946 0000`, which appears as `'-123`.
Amounts never get one: they are written as plain numbers. Remove the apostrophe in your
accounting system's import mapping if a reference must match exactly.

**No Mark these gifts posted button.** It appears after a download, for someone with Post
Gifts, and goes away when you change any choice, so it always marks the file you downloaded.
With a fund chosen the page asks for an export of all funds instead: a gift split across two
funds would be locked when only half of it was in the file.

**`Gifts in this range changed since you downloaded the file`.** A gift was added, changed or
refunded after the download. Download again, import that file, then mark. Marking skips gifts
already posted, so marking twice does no harm.
