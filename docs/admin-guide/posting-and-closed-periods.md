# Posting and Closed Periods

## What it does

Once Jen has put last month's gifts into the accounting system, those gifts have to stay the
way they were when she took them. Open Impact gives her two controls:

- **Posted to accounting.** After she downloads the accounting export, one click marks those
  gifts as posted. A posted gift's date, amount, donor, payment method, reference and funds
  cannot change, and it cannot be deleted.
- **Closed periods.** When a month is finished, Maria closes the books through its last day. No
  gift dated in a closed period can be added, changed in those same ways, or deleted, whether it
  was posted or not.

Money that goes back is still recorded the usual way: a refund or a write-off is a new gift
dated today, which is always in an open period, so the books for the closed month stay as they
were and the refund lands in the month it happened.

Only gifts that are in the books are protected: Received, Refunded and Written off gifts that
are not in-kind, the same gifts the accounting export writes. A Pending, Cancelled or in-kind
gift is in no export file, so it stays editable. Everything that is not in the export stays
editable on any gift: the appeal, the acknowledgment, the receipt, soft credits, tributes and
the matching gift link.

A gift batch that has been **Posted** is a different thing: it means the batch's lines became
gifts. Those gifts are not in the books until Jen exports them and marks them posted.

## How to turn it on

Posting and closed periods arrive with the Giving module. Nothing is locked until someone marks
a gift posted or closes a period.

- **Marking gifts posted** is on the Accounting Export page, which needs the Connect module (see
  [Accounting Export](accounting-export.md)). The **Accounting Export** permission set includes
  the **Post Gifts** permission, so Jen can mark gifts posted and unpost them. **Giving Admin**
  includes it too.
- **Closing a period** is in **Open Impact Settings**, **Giving**, **Accounting periods**, for
  anyone with the **Manage Open Impact Settings** permission and the **Giving Admin** permission
  set. Choose **Open**, and the Accounting Periods page shows the date the books are closed
  through. The latest date it takes is the day before yesterday: a refund is dated today, and
  today has to stay open for it in every time zone your staff work in.

The rules above cannot be switched off on the Automation page, and pausing all automation does
not suspend them, for the same reason the receipt lock cannot be: they protect a record rather
than fill something in. See [Automation control](automation-control.md).

## A five-minute walkthrough

You need the sample data, Jen with the **Accounting Export** and **Giving Read Only** permission
sets, and David with **Giving Staff**.

1. As Jen, open **Accounting Export**, set **From** and **To** to the first and last day of last
   month, and click **Download file**.
2. Click **Mark these gifts posted**. The page says how many gifts it marked. If the button says
   the gifts changed since the download, download again and then mark.
3. Tick **Only gifts not yet posted** and click **Download file** again. The page says
   `No gifts in this range.`: every gift in last month is now posted.
4. Open one of those gifts. The **Posting** card on the right says when it was posted and by
   whom.
5. As David, open the same gift, change its **Amount**, and save. Open Impact refuses:
   `This gift has been posted to accounting...`. Change the **Acknowledgment Status** instead: that
   saves.
6. As David, click **Refund or Write Off** on the gift and refund 10. It works: the refund is a
   new gift dated today and is not posted. It will be in this month's export.
7. As Maria, open **Open Impact Settings**, **Giving**, **Accounting periods**, **Open**. Set **Books
   closed through** to the last day of last month (on the 1st or 2nd, the month before) and click
   **Save**. The page shows the new date.
8. As David, open **Quick Gift Entry** and enter a gift dated in last month. Open Impact refuses:
   `The books are closed through...`. Date it today and it saves.
9. As Jen, open the posted gift from step 4 and click **Unpost** on the Posting card. Type a
   reason and confirm. The card now says the gift is not posted, and that it is still locked
   because it is dated in a closed period.
10. As Maria, try to set **Books closed through** to an earlier date. The page refuses: reopening
    a closed period is not something the settings page can do (see Common mistakes).

## Common mistakes

**`This gift has been posted to accounting...` when fixing a typo.** The books already hold the
gift as it is. If the money is wrong, record a refund (or a refund and a new gift) so the change
lands in an open period and Jen sees it in the next export. If the gift really has to change and
the period is still open, Jen can unpost it, you fix it, and she marks it posted again after her
next export, adjusting the entry in the accounting system herself.

**`The books are closed through...` when entering a late gift.** A gift that arrived in a closed
month and was never entered goes in with today's date, or an administrator lifts the lock for it
(below). Talk to Jen first: the books for that month are finished.

**A Pending gift in a closed month that will never be paid.** Set its **Status** to
**Cancelled**. The lock allows it: a Pending gift is in no export, and neither is a Cancelled
one, so nothing Jen holds changes. See
[Refunds and write-offs](refunds.md#cancelling-a-pending-gift).

**Unpost is not on the Posting card.** You need the **Post Gifts** permission, which comes with
the **Accounting Export** and **Giving Admin** permission sets.

**Mark these gifts posted says the gifts changed.** Someone added, changed or refunded a gift in
that range after you downloaded the file. Download it again, import that file, and mark again.
Marking only marks gifts that are not yet posted, so marking twice does no harm.

**More than 5,000 gifts.** Marking posted takes up to 5,000 gifts at a time. Mark a shorter range
(a week, or one payment method at a time). An export of one fund cannot be marked: a gift split
across two funds would be locked with only half of it in the file.

**`...the books name it as their donor, so it cannot be deleted`.** A person or organization
whose gifts are in the books stays, and so does a gift whose refund is in the books: deleting
them would blank the donor or the original on gifts Jen already holds. Merge a duplicate person
into the right one instead; a merge moves the gifts and is allowed. A household whose member
gave a gift in the books stays too, because deleting a household deletes its members.

**Sample data after closing a period.** Sample gifts dated in a closed period cannot be loaded or
removed. Load and remove sample data before you close your first period.

**Reopening a period, or changing a locked gift.** Neither can be done from inside Open Impact on
purpose: a closed month that anyone with settings access can reopen is not closed. When it
really has to happen, for example an auditor's adjustment:

1. In Setup, create a permission set that includes the **Override Posting Lock** custom
   permission, and assign it to yourself.
2. Make the change: move **Books closed through** back, or edit, delete or add the gift.
3. Remove the permission set assignment again.

Every change made that way is written to the Error Log, naming the gift and what changed, so the
auditor can see it. It is a separate permission from Override Receipt Lock, which only reaches
receipted gifts.
