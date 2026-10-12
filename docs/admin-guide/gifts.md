# Gifts

## What it does

A gift is one transaction that arrived: money, stock or goods, from one donor, on one date.
David enters the gift, and Open Impact fills in the rest: the household it should be
credited to, the date if he leaves it blank, and the fund it is designated to when he does
not choose one. Because a gift is a record of something that happened, it is never edited
away: a refund is a separate, linked gift (see the Refunds page).

Everything the board and the bookkeeper ask for comes off these records: donor totals, fund
balances, appeal results, and the receipt.

A gift of goods or services rather than money is entered here too, with the type **In-kind**.
It works differently in two ways that catch people out: its amount is always zero and its
worth goes in **Fair market value**, and its receipt describes what arrived without stating
what it was worth. [In-kind gifts](in-kind-gifts.md) is the page for that.

## How to turn it on

Gifts arrive with the Giving module. Before David enters his first gift, do two things
once:

1. Create at least one fund and mark it as the default (see the Funds page). A gift saved
   without a designation goes there.
2. Open **Open Impact Settings**, choose **Giving**, and check the settings on that page:
   **Default Fund**, **Default Appeal** (optional), and **Automatic Household Soft Credits**.

Then give your fundraising staff the **Giving Staff** permission set, and give yourself
**Giving Admin**. People who only need to see gifts get **Giving Read Only**.

Those three are assigned in Salesforce Setup, which is the one step here that Open Impact
cannot yet do for you: the roles on the Access page carry what Core provides and do not
include a module's permission sets until the Module Manager arrives in version 0.7.

## A five-minute walkthrough

You are David, and a check from Maria's neighbour arrived this morning.

1. Open the **Funds** tab, click **New**, name the fund `General`, tick **Is Default**, and
   save.
2. Open the **Appeals** tab, click **New**, name the appeal `Spring appeal`, and save.
3. Open the **Gifts** tab and click **New**.
4. In **Donor Contact**, choose a person who belongs to a household. Leave **Donor Account**
   empty: a gift has one donor, either a person or an organization, never both.
5. Enter an **Amount** of 250, choose the **Type** `Check`, and leave **Gift Date** empty.
   (Had this been a gift of goods you would choose `In-kind` here instead, leave the amount
   at zero, and describe the goods: [In-kind gifts](in-kind-gifts.md).)
6. Choose `Spring appeal` in **Appeal** and save.
7. Look at the saved gift. **Gift Date** is today, because you left it blank. **Household**
   shows the donor's household, filled in by Open Impact rather than by you, which is what
   keeps household totals right after somebody moves house or marries.
8. Scroll to **Gift Allocations**. There is one allocation, for the whole 250, designated to
   `General`. You never asked for it: a gift with no designation is allocated in full to the
   default fund, so no money is missing from fund reporting.
9. Open that allocation and change its **Amount** to 100. The save is refused with "The
   allocations of this gift total 100.00, but the gift is 250.00. The difference is 150.00."
   Set it back to 250 and save. Allocations always add up to the gift, which is why the money
   in your fund reports is never more or less than the money you received.
10. Now refund part of the gift: follow the Refunds page from step 1.

## Lifting the receipt lock

Sooner or later an organization holds a receipted gift that is wrong in a way that voiding
and reissuing cannot reach, for example a receipt number issued against the wrong donor.
There is one way past the lock. It is deliberately awkward, it lives in Salesforce Setup
rather than in Open Impact, and every use of it is recorded.

**What it is.** A custom permission called **Override Receipt Lock**. Open Impact ships it
assigned to nobody: it is on no permission set and in no permission set group, so no role,
including Open Impact Admin, carries it. A user who holds it can save a change to a receipted
gift's amount, date, donor or receipt number, and can delete a receipted gift. Nobody else
can, whatever else they are allowed to do.

**The receipt number needs one more thing.** Receipt Number is read only for everyone in Open
Impact's permission sets, because a receipt number is issued by Open Impact and never typed in
(see [Receipts](receipts.md)). To change or clear one, the temporary permission set below has
to grant Edit on that field as well as the custom permission. Grant it there and nowhere else:
a permission set people already hold is the one you will forget to take it out of.

**What it does not lift.** A gift that has been refunded or written off still cannot be
deleted by anyone, override or not. The refund is a separate negative gift linked back to
the original, so deleting the original would leave that negative gift standing with nothing
to say what it reverses, and a total that is wrong with no trace of why. Correct a refunded
gift by working with the refund (see [Refunds](refunds.md)), never by removing the original.

**How to grant it.** There is no screen for this inside Open Impact, on purpose.

1. In Salesforce, click the gear icon and choose **Setup**.
2. Enter `Permission Sets` in the Quick Find box and click **Permission Sets**.
3. Click **New**. Give it a label such as `Receipt Lock Override (temporary)` and save.
   Make a fresh set for this rather than adding the permission to a set people already
   hold: it is the set you are going to delete afterwards.
4. On the new permission set, click **Custom Permissions**, then **Edit**, move **Override
   Receipt Lock** into the Enabled list, and save.
5. Only if you are changing or clearing a receipt number: on the same permission set click
   **Object Settings**, then **Gifts**, then **Edit**, tick **Edit Access** for **Receipt
   Number**, and save. Skip this step for a correction to an amount, a date or a donor.
6. Click **Manage Assignments**, then **Add Assignment**, tick the one person who is going
   to make the correction, and save.

**How to remove it.** As soon as the correction is saved, come back to the permission set,
click **Manage Assignments**, tick the person, and click **Remove Assignment**. Deleting
the whole permission set afterwards is better still: a set that exists is a set somebody
can be added to later without anyone noticing.

**Every use is logged.** Whenever a change is saved that the lock would otherwise have
refused, Open Impact writes an entry to the [Error Log](error-log.md) at **Warning**
severity, naming the gift, its receipt number, and exactly which values changed (or that
the gift was deleted). Nobody has to remember to record it. Filter the Error Log on
Severity `Warning` to see every override an org has ever made.

**Before you use it, check that you need to.** A refund or a write-off is the right answer
when money went back (see [Refunds](refunds.md)), and correcting a receipt is the right
answer when the document itself is wrong. The override is for the case where neither
reaches the problem.

## Common mistakes

- **Filling in both Donor Contact and Donor Account.** The save is refused with "Enter a
  donor contact or a donor account, not both. A gift has exactly one donor." Use the account
  when an organization or a household gives in its own name, and the contact when a person
  gives.
- **Entering a gift of zero.** The save is refused with "A gift amount cannot be zero."
  Zero-value records break averages and counts. The one exception is a gift of goods: an
  in-kind gift is always zero, and its worth goes in **Fair market value**. See
  [In-kind gifts](in-kind-gifts.md).
- **Editing the amount after a receipt has been issued.** The save is refused with "This
  gift has a receipt number, so its amount, date, donor and in-kind description cannot
  change. Void the receipt and reissue it, or record a refund." The in-kind description is
  in that list because it is what an in-kind receipt prints; the fair market value is not,
  because it is printed nowhere. That rule protects the document already in the
  donor's hands. Deleting the gift is refused for the same reason, and so is changing or
  clearing the receipt number itself.
- **Typing a receipt number onto a gift.** Receipt Number is read only, and a save that fills
  it in anyway, from a list view, an import or an integration, is refused with "A receipt
  number is issued by Open Impact when it creates the receipt, and cannot be filled in by
  hand." A number that Open Impact did not issue belongs to no receipt, locks the gift, can be
  handed out again later to somebody's year-end statement, and stops that gift ever being
  receipted. Click **Issue receipt** on the gift instead. Importing historical gifts that
  carry receipt numbers from an old system is the one real case, and it needs the override
  below, deliberately.
- **Pausing automation to get around the lock.** It does not work, and that is deliberate.
  The receipt lock is one of the few automations that always run: it is listed on the
  Automation page with its switch off and greyed out, and a pause does not suspend it. See
  [Automation control](automation-control.md).
- **Splitting a gift one row at a time.** Allocations always total the gift, so a change that
  leaves the gift over-allocated or under-allocated is refused, even halfway through a split
  you meant to finish. Enter a split in one go on the gift entry screen, which sends the whole
  split at once. The error names the difference so you can see exactly how much is out.
- **Mixing amounts and percentages in one split.** Enter a split either way, but not both ways
  at once: when every row is a percentage and they come to 100, Open Impact works out the
  amounts and puts the odd cent on the largest row. Mix the two and you are back to making the
  amounts add up yourself.
- **Typing a name for the gift.** You never do: gifts number themselves, `G-000001` and
  onward. That number is not a receipt number.
