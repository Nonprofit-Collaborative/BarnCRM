# Importing gifts

## 1. What it does

Importing gifts loads a spreadsheet of gifts, with the donor on each row, through the same
**Import** tab you use for people. Each row becomes an ordinary gift: the donor is found or
created, the gift is allocated to the fund you name (or split across several), and a soft
credit and an in honor or in memory tribute can come with it. Nothing is written until you
have seen a dry run, and a gift import can be undone like any other import.

When a gift pays a pledge or a monthly gift the donor already has, Open Impact can find the
scheduled payment it pays and link the two, so the pledge balance goes down on its own. This
is **donation matching** (section 5).

## 2. How to turn it on

Nothing to turn on once the Giving module is installed. You need the **Manage Open Impact
Settings** permission to import, and the Giving admin role to create gifts; the **Access**
page gives both to an Open Impact Admin. The importer must also be able to delete gifts (Giving
Admin can; Giving Staff cannot), because a row is saved whole or not at all: when a gift's soft
credit or tribute is refused, the import removes the gift it had just made. Without that right
every gift row is rejected, in the dry run too, saying so.

Two settings decide how donation matching behaves when a mapping does not say:

1. Open **Open Impact Settings** and choose **Import**.
2. **Days either side of a payment's due date** is 7. A gift dated within 7 days of a
   scheduled payment can match it.
3. **Amount difference allowed** is 0: a gift matches a payment only for exactly the amount
   expected. Raise it (for example to 1.00) if a processor's rounding means amounts are
   sometimes a few cents out.

Open Impact ships a **generic gift list** mapping. It reads donor first name, last name,
email and organization, gift amount, date, payment method, payment reference and fund. For
gifts exported from Nonprofit Cloud or NPSP, use the mappings in [Migrating from Nonprofit
Cloud](migrating-from-nonprofit-cloud.md) or [Migrating from NPSP](migrating-from-npsp.md)
instead.

## 3. A five-minute walkthrough (as Maria)

Start with a small file: five gifts, each with a donor name, an email, an amount, a date
(for example `2026-03-15`) and a fund name you already have.

1. Open the **Import** tab, select **Generic gift list**, then **Next**, and upload the file.
2. Check the columns. The gift columns now read **Gift: amount**, **Gift: date**, **Gift:
   fund** and so on. Map a column of processor transaction numbers to **Gift: external ID**:
   it is what stops the same file loading twice.
3. On the matching step, choose how people are matched (**Email exact** is the safe default)
   and how gifts are matched to scheduled payments (**Match or create** is the default,
   section 5).
4. Under **Control totals**, type the number of rows and the total of the amounts from your
   deposit slip or your processor's report. Both are optional.
5. Select **Dry run**. The counts say how many rows would create a gift, how many match a
   gift you already have, and how many would be rejected, with the reason for each. The run
   log says whether the control totals match, and how many gifts would pay a scheduled
   payment.
6. If a row is rejected (a fund name spelled differently, a date Open Impact cannot read),
   fix the file and dry run again.
7. Select **Commit**. Open one of the donors: the new gift is on their record, allocated to
   the fund you named, and its **Created By Import Batch** links back to the import.
8. Load the same file again and dry run it. Every row now says it matches a gift you already
   have, because of the external ID column. Nothing would be created twice.

## 4. What a row can say

A row is one gift. Besides the donor, it can carry:

- **Who gave it.** The row's first person is the donor. If there is no person, the
  organization is. A file of company gifts that also lists a contact person should map a
  column, or set a default, of **Gift: donor** to `Organization`. `Household` makes the
  household the donor.
- **The gift.** Amount, date and payment method are required, except that an in-kind gift
  (payment method In-kind) has no amount: leave it empty or 0 and put what the goods were
  worth in **Gift: fair market value**, with **Gift: in-kind description**. A file with no
  payment method column can set one for every row as the mapping's default. Payment method is
  matched to Open Impact's
  list whatever the capitals, and common words are understood: "credit card" is Card,
  "cheque" is Check, "bank transfer" is ACH. The appeal is named by its name. Payment
  reference, external ID, in-kind description and benefit description load as they are.
  Every imported gift is **Received**.
- **The fund, or a split.** **Gift: fund** names one fund by its name or its accounting code;
  an inactive fund is accepted, so old gifts can go to funds you have since closed. To split a
  gift, map **Fund 1** with **Amount 1** or **Percent 1**, **Fund 2** with **Amount 2** or
  **Percent 2**, and so on. The parts must add up to the gift, or to 100 percent. A row with
  no fund goes to your default fund, as a gift typed by hand does.
- **A soft credit.** Map **Soft credit: role** (Solicitor, Influencer, Honoree, Household
  Member, Matched Donor or Other) and the row's second person is credited with the whole
  gift. **Soft credit: amount** credits part of it, and **Soft credit: credit whom** can name
  `Contact1`, `Organization` or `Household` instead of the second person. A spouse already
  credited automatically as a household member is not credited twice.
- **A tribute.** Map **Tribute: type** (In honor of, In memory of) and **Tribute: honoree
  name**, and optionally the name of who to notify and the message.

A row's gift and everything that comes with it is saved together or not at all. If the soft
credit cannot be saved, the gift is not kept either, and the row is rejected with the reason.
The donor, if the import created them, stays, and is matched when you load the corrected row.

## 5. Donation matching

Donation matching decides what happens when a gift in the file pays something the donor
already owes: a pledge payment or this month's recurring gift.

Open Impact looks, in this order, for:

1. **A gift you already have with the same external ID.** That row is the same gift, loaded
   before. It is matched and nothing changes.
2. **A scheduled payment of the same donor** (the person, the organization, or anyone in
   their household) that is not yet paid, whose due date is within the window of the gift's
   date and whose expected amount is within the allowed difference. The new gift is linked to
   it, and the payment's status and the pledge's paid to date and balance update on their own.
   If two payments qualify, the one with the closest date wins; if two are equally close, the
   row is rejected naming both, so you can decide.

Each mapping says what to do, on the matching step of the wizard:

| Choice | What happens |
|---|---|
| **Match or create** (default) | Link the gift to the payment it matches; create it on its own if nothing matches. |
| **Always create** | Never look for payments. Each gift is created on its own. |
| **Match only** | Reject a gift that matches no payment. Use it for a file that should only hold pledge payments. |
| **Never match** | Reject a gift that matches a payment or a gift you already have. Use it for a file of new gifts that should not touch pledges. |

The same step lets a mapping use its own window and allowed difference instead of the ones in
**Open Impact Settings**. Leave them empty to use the settings.

The commit matches under the choice, window and allowed difference the dry run used. If you
change them on the mapping, or in **Open Impact Settings**, after a dry run, run the dry run
again: the commit keeps to what the last dry run showed you.

## 6. Undoing a gift import

Undo removes the gifts the import created, with their allocations, soft credits and
tributes, and then the people, households and organizations it created, exactly as section 5
of [Importing](importing.md) describes. Two things are kept on purpose, each listed with the
reason in the import's journal:

- **A gift with a receipt.** Once a receipt or a year-end statement has gone to the donor
  listing the gift, the gift stays. Void the receipt and refund or write off the gift if it
  really was a mistake.
- **A gift in the books.** A gift posted to accounting, or dated in a closed accounting
  period, stays (see [Posting and Closed Periods](posting-and-closed-periods.md)). Refund it
  if it was a mistake: the refund is dated today.
- **The donor of a gift that stays.** A person, household or organization is not removed
  while a gift that is kept still names them.

A removed gift that paid a scheduled payment stops paying it: the payment is owed again, and a
pledge that gift had completed is active again. A pledge you marked complete yourself stays
complete.

## 7. Common mistakes

**`The books are closed through...` on a row.** The row's gift is dated in a closed accounting
period, and the dry run refuses it as the import would. Date it after the close date, or ask
the administrator (see [Posting and Closed Periods](posting-and-closed-periods.md)).

**Rows rejected with "Not attempted: this chunk ran out of room".** One gift in the chunk was
refused and the rest were retried one at a time until the chunk ran short of room. Nothing was
saved for those rows. Load the file again: rows already loaded are matched, not duplicated.

**Rows rejected with "No fund named ...".** The fund in the file is spelled differently from
the fund in Open Impact. Either rename the column values in your spreadsheet or give the fund
an accounting code that matches the file.

**Rows rejected because a date cannot be read.** Write dates as `2026-03-15`, or in the
format your own Salesforce locale shows dates. An Excel workbook's date cells are always read
correctly.

**The commit button refuses: "the control totals do not match".** The dry run counted a
different number of rows, or a different total, from the ones you typed. Check the run log
for both numbers. Either the file is not the one you meant (a report cut short, a row
duplicated) or a total was typed wrong. Fix whichever is wrong and dry run again.

**A gift did not pay the pledge you expected.** The payment was outside the date window, the
amounts differed by more than the allowed difference, or the pledge belongs to somebody the
row did not resolve to. The dry run's run log counts the gifts that would pay a scheduled
payment. Widen the window on the mapping, or check that the donor columns match the pledge's
donor.

**The same gifts appear twice.** The file had no external ID column, so loading it again
created every gift again. Undo the second import, and map the processor's transaction number
to **Gift: external ID** from now on.

## Column reference

| Picker label | Loads into |
|---|---|
| Gift: amount, date, payment method, payment reference, external ID, in-kind description, fair market value, benefit description | The gift's field of the same name |
| Gift: appeal | The appeal with that name |
| Gift: donor | Which record on the row gave the gift: `Contact1`, `Organization` or `Household` |
| Gift: fund, Fund 1 to Fund 5, Amount 1 to Amount 5, Percent 1 to Percent 5 | The gift's allocations |
| Soft credit: role, custom role, amount, credit whom | One soft credit on the gift |
| Tribute: type, honoree name, notify (name), message | One tribute on the gift |
