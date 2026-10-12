# In-kind gifts

## What it does

An in-kind gift is a gift of goods or services rather than money: a donated minibus, a case
of wine for the auction, a lawyer's afternoon, twenty turkeys at Thanksgiving. Open Impact
records it as a gift like any other, with the donor, the date, the appeal it came in on and
the fund it was designated to, plus two things only an in-kind gift has: a **description** of
what arrived, and a **fair market value** that your organization records for its own
reporting.

Two rules run through everything below, and they are the whole feature.

**An in-kind gift carries no amount.** Its amount is zero, always. Goods are not money your
organization holds, and your finance team reports contributed goods separately from cash. So
an in-kind gift adds nothing to a donor's total giving, nothing to a gift count, nothing to
your dashboard and nothing to a donor level. It rolls up instead onto **In-kind value** and
**In-kind gift count**, which sit next to total giving on the donor's record. Total giving is
cash. In-kind value is goods. They are two numbers and they do not add up to a third.

**The receipt never states what the gift was worth.** It describes what was given and says
plainly that your organization has not valued it. This is not a design preference, it is how
receipting a non-cash gift works in the United States: the donor is responsible for
substantiating what donated property was worth, and a charity that prints a dollar figure on
its own letterhead has handed the donor a problem and taken on one of its own. Record the
fair market value for your board and your auditor; it never reaches the donor's receipt.

## How to turn it on

There is nothing to turn on and no setting to choose. In-kind is one of the gift types the
package has always shipped, and everything on this page works as soon as Giving is installed.

Two things are worth doing once, so that the numbers are visible where people look for them.

1. Put **In-kind value** and **In-kind gift count** on your household, organization and
   person record pages, beside **Total giving**. Add them to a field section of the record
   page in the Lightning App Builder, in the same place you added the other giving totals
   (or to your page layouts, if your org uses its own record pages): Open Impact ships the
   fields but does not place them for you. Put them next to total giving rather than under it. A
   reader who sees one number without the other reads the one they see as everything the
   donor gave, which is the whole mistake this feature exists to prevent.
2. Open **Open Impact Settings**, then **Giving**, then **Rollups**, and choose **Recalculate
   now** after your first in-kind gifts are entered, unless you are content to wait for the
   nightly run. In-kind value and in-kind gift count are maintained by the same rollup engine
   as every other total on those records.

If you want in-kind gifts on paper, the report **In-kind Gifts This Year** is in the Giving
reports folder. It lists each gift with its description, its fair market value and its donor,
which is the list a finance team asks for at year end. It counts gifts in the books only:
Pending and Cancelled gifts are left out.

### Recording one

1. Create a gift the way you record any other, from the **Gifts** tab or from **Quick Gift
   Entry**.
2. Set **Type** to **In-kind**. The amount box disappears, because an in-kind gift has none.
3. Fill in **What was given**, written the way the donor should read it on their receipt. "A
   used minibus in working order" is a description. "Vehicle" is not.
4. Fill in **Fair market value**: what your organization values it at, for your own
   reporting. Leave it empty if you do not have a figure yet, and add it later.

Open Impact refuses the entries that would produce a wrong record or a wrong receipt:

- An in-kind gift with an amount that is not zero, because that figure would land in the
  donor's total giving and in the money on your dashboard.
- An in-kind gift with no description, because the receipt would have nothing to print in
  place of an amount.
- A gift of money carrying an in-kind description or a fair market value, because its receipt
  would describe goods nobody gave.
- A negative fair market value, because goods are worth nothing or something, never less than
  nothing.

### What the donor sees

Issue the receipt from the gift the usual way (see [Receipts and year-end
statements](receipts.md)). On the document:

- Where your letter asks for the amount, the receipt says "the goods or services described
  below" instead of a figure, and a line under the letter states in plain words that no value
  has been stated.
- Below that, Open Impact prints the description you typed, followed by the sentence that
  says the organization has not placed a value on the gift and that valuing donated property
  is the donor's responsibility.
- On a year-end statement, the gift is a line with its date, its type and its status, and the
  amount column says "Not valued". The statement's total is the money only, and the statement
  says so in one sentence, so a donor who adds the lines up is not left puzzled.
- Your organization's name and address are at the top and your tax identification number is
  at the bottom, exactly as on a cash receipt.

## A five-minute walkthrough

Start from the sample data (see `sample-data.md`), which includes about twenty in-kind gifts.

1. Open **Gifts** and switch to the **All Gifts** list view. Sort or filter by **Type** and
   find one of the **In-kind** gifts. Notice its **Amount** is 0.00 and its **Fair market
   value** is not.
2. Open the donor of that gift. Compare **Total giving** with **In-kind value**. The gift you
   just looked at is in the second number and not the first, and its gift count is separate
   too. This is the thing to be able to explain to a colleague: the two numbers answer two
   different questions.
3. Now enter one yourself. Open **Quick Gift Entry** (it is on the Open Impact app, and on
   every household and person page).
4. Choose the donor, leave the date at today, and set **How it arrived** to **In-kind**. The
   amount box disappears and two boxes take its place.
5. In **What was given**, type what actually arrived, in the words you would be comfortable
   seeing on the donor's receipt: `Sixteen folding tables, used, delivered to the community
   hall`. This text is printed on the receipt exactly as you type it.
6. In **Fair market value**, type `800`. Read the note under the box: this figure is for your
   reporting and is never printed on the receipt. Leave it empty if you do not have a figure
   yet; you can add it later.
7. Save. Open the gift. Amount is 0.00, and the description and value you typed are on the
   record.
8. From the gift, choose **Issue receipt**. Open the PDF. It names your organization, the
   donor, the date and the receipt number; where a cash receipt would print an amount it says
   that no value is stated; and it carries the sentence describing what you received and
   saying that your organization has not placed a value on it. There is no `$800` anywhere on
   the document, and there is no way to put one there.
9. Open a household that has both cash gifts and an in-kind gift in the same year, and issue
   or open its year-end statement. The in-kind line has no amount, and the total at the
   bottom is the cash only.

Steps 5, 8 and 9 are the ones worth reading closely: they are what an auditor or an
accountant would look at.

## Common mistakes

**Typing the value into Amount.** The most common one, and the app will stop you: an in-kind
gift with an amount that is not zero is refused with a message saying where the value goes.
If it were allowed, a donated vehicle would land in the donor's total giving, set their
largest gift, possibly promote them to a donor level, and appear in the money on your
dashboard, and none of those numbers would match what your finance team reports. If you find
old in-kind gifts imported with the value in the amount, fix them by moving the figure to
fair market value and setting the amount to zero, and recalculate the rollups afterwards.

**Putting a value on the receipt anyway, by typing it into your letter.** You cannot type a
donor's number into a packaged letter, but you can write "we valued your gift at" and a merge
token into the template. Do not. The sentence Open Impact adds says the organization has not
placed a value on the gift, and a letter that contradicts it in the paragraph above is worse
than either sentence alone.

**Recording one gift when there were two.** A donor who buys a 500 dollar table at your gala
and also donates the centrepieces has given you two gifts, not one: a 500 dollar cash gift
and an in-kind gift. Open Impact will not let one record be part money and part goods, and
trying to blend them produces a receipt that is wrong in both directions. Enter two gifts,
each with its own receipt.

**Leaving the description vague, or blank.** A gift saved as In-kind without a description is
refused, because the description is the receipt: `donation` or `misc items` is not something a
donor can put in front of an accountant. Write what a stranger would recognize twelve months
later: what it was, how many, and what condition.

**Expecting the fair market value to appear on the receipt, or on the donor's total.** It
never does, on purpose, and there is no setting that changes it. If somebody asks for it,
the answer is the In-kind Gifts This Year report, or the In-kind value figure on the donor's
record, both of which are yours and internal. The donor's own receipt is the one place the
figure does not belong.

**Trying to refund an in-kind gift.** There is nothing to give back, because no money came in,
so the Refund action has nothing to reverse. If goods were returned or the gift was recorded
in error, set the gift's status to **Written off**. If a receipt has already been issued, void
the receipt first; the description on a receipted in-kind gift is locked, exactly as the
amount is on a cash one, because it is printed on a document the donor is holding. The fair
market value stays editable at all times, because it is on no document.

## Fields, for a report builder

| What you want to report on | Object | Field |
|---|---|---|
| Which gifts were goods or services | Gift | Type, value In-kind |
| What was given | Gift | In-kind Description |
| What your organization valued it at | Gift | Fair Market Value, never Amount, which is zero |
| What a donor gave in goods over time | Household, Organization, Person | In-kind Value, In-kind Gift Count |
