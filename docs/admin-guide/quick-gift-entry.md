# Quick Gift Entry

## What it does

Quick Gift Entry is a one screen form for recording a gift the moment it arrives: at an
event, at the front desk, or from the mail pile. It asks for the donor, the amount, the
date, the payment method, and which appeal it answered, and it fills in the rest from
your settings. It is built for a phone, so David can enter a check while he is standing
at the gala table and hand the donor a thank you on the spot.

Every gift entered here is a normal gift: it counts in the giving totals, it can be
receipted, and it appears in the Giving dashboard the next time the numbers are
calculated.

## How to turn it on

Nothing to install and no Setup step. Quick Gift Entry arrives with the Giving package.

1. Open the **Fundraising** app from the app launcher (the grid of dots in the top left
   corner). The Giving package ships this app, and Quick Gift Entry is its first tab. On a
   computer it is also in the app's utility bar at the bottom of the screen, so the form
   opens over whatever page you are on.
2. Open **BarnCRM Settings**, then **Giving**, and check two values:
   - **Default fund**: the fund a gift is allocated to when nobody picks one. Most
     organizations choose the Annual Fund or the General Fund.
   - **Default appeal**: the appeal proposed on a new gift. Leave it empty outside of
     appeal season, or set it to the appeal you are running right now so that staff do
     not have to pick it every time.
3. Give your fundraising staff access. In BarnCRM Settings, open **Access** and assign
   the **Fundraising Staff** role, and then, in Salesforce Setup, the **Giving Staff**
   permission set that the Giving module ships. The tab and the save both come from that
   permission set, and no role carries it yet: joining the two up arrives with the Module
   Manager in version 0.7.

If you would rather have the form on a household or a person's page than on its own tab,
open that page in the Lightning App Builder (from the page's setup gear, Edit Page), drag
**Quick Gift Entry** onto it, and save. On a person's or an organization's page the form
starts with that record already chosen as the donor, and Save and new keeps it, so a page
of gifts from one donor goes in without picking the donor each time.

## A five-minute walkthrough

Do this as David, on a phone, starting from the sample data.

1. Open the app launcher and tap **Fundraising**. Tap **Quick Gift Entry**.
2. The form opens with today's date already filled in, and with your default appeal and
   default fund already chosen. Leave the donor toggle on **Person**.
3. Tap the donor box and type the first few letters of a donor's last name, for example
   `Mar`. Tap the right person in the list. Their name stays in the box.
4. In **Amount**, type `50`.
5. Leave **Gift date** as today.
6. In **Payment method**, choose **Check**.
7. In **Check or reference number**, type the number printed on the check, for example
   `1042`. This is the field Jen uses when she reconciles with the bank, so it is worth
   the two seconds.
8. Confirm **Appeal** says Spring Appeal. If it does not, tap it and pick Spring Appeal.
9. Tap **Save and new**. A message says **Gift G-000123 saved**, with the gift's name as
   a link, and the form clears itself for the next gift while keeping today's date, the
   appeal, and the fund. You are ready for the next check with one tap.
10. Enter a second gift the same way: a different donor, `25`, Cash, no check number.
    Tap **Save**. The confirmation stays on screen with a link to the gift.
11. Tap the link. The gift record opens, showing the donor, the amount, the appeal, and
    one allocation to your default fund. That allocation is what makes the fund totals
    add up without anybody thinking about designation at the event.

Five gifts take about a minute once the rhythm is there. Nothing here needs a laptop.

## Paying a pledge or a recurring gift

When the donor you pick still owes payments on a pledge or a recurring gift, a list called
**Pays a scheduled payment** appears under **Gift date**. It holds that donor's payments that
are scheduled, overdue or partly paid, on pledges and recurring gifts that are active or
paused, including the ones made in the name of the donor's household. Each choice names the
pledge, the payment's due date and the amount expected.

- **None: a new gift on its own** is always in the list. It is what the form did before.
- A payment is marked **suggested** when its due date is within the date window of the gift
  date and its expected amount is within the allowed difference of the amount. These are the
  same two settings gift imports use to match payments: **BarnCRM Settings**, **Import**,
  **Days either side of a payment's due date** (7 unless you changed it) and **Amount
  difference allowed** (0, the amounts must be equal).
- When exactly one payment is suggested, the form chooses it for you and says so under the
  list. Read it before you save, and choose **None** if the gift is not for that payment.
  When two or more are suggested, nothing is chosen: pick the right one yourself.
- When none is suggested, **None** stays chosen. You can still pick any payment in the list,
  for example when a donor pays early or sends a different amount.

Saved with a payment chosen, the gift is linked to that payment and its pledge, and the
payment's status and the pledge's paid to date and balance update on their own, exactly as
for an imported gift that matched. The save checks the payment again: if it was paid, or the
pledge closed, in the meantime, the form says so and nothing is saved.

Changing the donor, the amount or the date refreshes the list. A payment you picked yourself
stays picked while it is still in the list. A gift of goods pays no pledge, so the list is
hidden when **How it arrived** is In-kind.

To try it, open an active pledge from the **Commitments** tab and note its donor and the
amount and due date of its next payment. Enter a gift from that donor, of that amount, dated
that day. The list chooses that payment and says it was suggested. Save, open the pledge
again, and the payment is Paid and the balance has gone down.

## Common mistakes

**The donor is not in BarnCRM yet.** Common at an event. Leave the donor toggle on
**Person** and tap **Not in the list? Add a new person** under the donor box. The standard
new person form opens; fill it in and save. You come back to Quick Gift Entry with what you
had typed still there: search for the new person in the donor box and pick them. For a new
organization, create it from the Organizations tab first.

**A field shows a message after you tap Save.** The message sits under the field it is
about, and the cursor moves to the first one. Fix that field and its message goes away;
then tap Save again.

**Picking the wrong donor because two people share a name.** The donor box shows the
name only. Before you save, check the name in the box is the person you meant; after you
save, the confirmation link opens the gift so you can look. If you saved a gift against
the wrong donor, open the gift and change the donor: nothing is locked until a receipt is
issued.

**Entering a refund as a negative amount here.** The form refuses it and says: **Enter an
amount greater than zero. A refund is entered from the original gift, not here.** A
refund is its own gift linked to the one it reverses, which is what keeps the totals
honest. Open the original gift and use the refund action.

**Forgetting the appeal at an event.** Gifts with no appeal are not wrong, but they
disappear from the appeal results Tom reads on the dashboard. Set the **Default appeal**
in BarnCRM Settings to the appeal you are running before the event starts, and every
gift entered that evening carries it.

**Saving with no default fund set.** Every gift has to be designated to a fund, so a gift
saved without one is refused rather than saved incomplete: the message names the missing
default fund. Choose a default fund in BarnCRM Settings, or mark one fund as the default
on the fund record, and it is done for good. Set it once, on the day you install.

**Choosing a fund on a gift that is already split.** The Fund box sets the gift's single
allocation. A gift that already carries a split across several funds keeps its split, and
the form says so instead of quietly repointing it: open the gift to change the allocations.

**Losing the form on a bad signal.** The form saves one gift per tap and tells you when it
has saved. If you do not see the confirmation, the gift did not save; the values stay on
screen, so tap Save again when you have signal rather than retyping. You cannot enter the
same gift twice by accident: once a gift is saved, Save and Save and new are greyed out
until you change something or start another gift.

**A check for a pledge saved as a gift on its own.** The pledge stays unpaid and the payment
turns Overdue. Open the gift, set its **Commitment** and **Installment** to the pledge and the
payment it was for, and save: the payment and the balance update. Next time, look at **Pays a
scheduled payment** before tapping Save.

**The payment you expected is not in the list.** The list shows only payments still owed on
an active or paused pledge of this donor or their household. A payment already paid in full,
or one on a completed or cancelled pledge, is not there. A pledge made in the name of a
different person or an organization is not there either: pick that donor instead.

**"That payment is no longer open" after Save.** Someone paid it, or the pledge was closed,
while the form was open. Nothing was saved. Choose again from the refreshed list, or None.

## Field reference

For the person building a report later, these are the fields the form writes.

| On the form | Field |
|---|---|
| Donor, person | Donor Contact, or Donor Account in an org where people are accounts |
| Donor, organization | Donor Account |
| Amount | Amount |
| Gift date | Gift Date |
| Payment method | Payment Method |
| Appeal | Appeal |
| Fund | the gift's single allocation |
| Check or reference number | Payment Reference |
| Pays a scheduled payment | Installment, and that payment's pledge in Commitment |
