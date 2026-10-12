# Quick Gift Entry

## What it does

Quick Gift Entry is a one screen form for recording a gift the moment it arrives: at an
event, at the front desk, or from the mail pile. It asks for the donor, the amount, the
date, how the gift arrived, and which appeal it answered, and it fills in the rest from
your settings. It is built for a phone, so David can enter a check while he is standing
at the gala table and hand the donor a thank you on the spot.

Every gift entered here is a normal gift: it counts in the giving totals, it can be
receipted, and it appears in the Giving dashboard the next time the numbers are
calculated.

## How to turn it on

Nothing to install and no Setup step. Quick Gift Entry arrives with the Giving package.

1. Open the **Fundraising** app from the app launcher (the grid of dots in the top left
   corner). The Giving package ships this app, and Quick Gift Entry is its first tab.
2. Open **Open Impact Settings**, then **Giving**, and check two values:
   - **Default fund**: the fund a gift is allocated to when nobody picks one. Most
     organizations choose the Annual Fund or the General Fund.
   - **Default appeal**: the appeal proposed on a new gift. Leave it empty outside of
     appeal season, or set it to the appeal you are running right now so that staff do
     not have to pick it every time.
3. Give your fundraising staff access. In Open Impact Settings, open **Access** and assign
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
6. In **How it arrived**, choose **Check**.
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

## Common mistakes

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
in Open Impact Settings to the appeal you are running before the event starts, and every
gift entered that evening carries it.

**Saving with no default fund set.** Every gift has to be designated to a fund, so a gift
saved without one is refused rather than saved incomplete: the message names the missing
default fund. Choose a default fund in Open Impact Settings, or mark one fund as the default
on the fund record, and it is done for good. Set it once, on the day you install.

**Choosing a fund on a gift that is already split.** The Fund box sets the gift's single
allocation. A gift that already carries a split across several funds keeps its split, and
the form says so instead of quietly repointing it: open the gift to change the allocations.

**Losing the form on a bad signal.** The form saves one gift per tap and tells you when it
has saved. If you do not see the confirmation, the gift did not save; the values stay on
screen, so tap Save again when you have signal rather than retyping. You cannot enter the
same gift twice by accident: once a gift is saved, Save and Save and new are greyed out
until you change something or start another gift.

## Field reference

For the person building a report later, these are the fields the form writes.

| On the form | Field |
|---|---|
| Donor, person | Donor Contact, or Donor Account in an org where people are accounts |
| Donor, organization | Donor Account |
| Amount | Amount |
| Gift date | Gift Date |
| How it arrived | Type |
| Appeal | Appeal |
| Fund | the gift's single allocation |
| Check or reference number | Payment Reference |
