# Matching gifts

## What it does

Many employers match the gifts their staff make. The match arrives weeks later, as a check
from the company, and it is easy to lose the connection between the two. Linking them in
BarnCRM keeps both facts true at once: the company is the donor of its own gift, and
the employee is recognized for having caused it.

The link is visible from both gifts, so David can open either one and see the other. The
employee gets a soft credit on the company's gift, which is how their real influence on
your income shows up in donor reporting without ever crediting them with money they did
not give.

BarnCRM does not tell you which employers match. That information comes from a
matching gift database and is out of scope: this feature records the match you have
received.

## How to turn it on

Nothing to turn on. Linking is available on every gift.

You link a match by opening the company's gift and setting **Matched gift** to the
employee's gift. BarnCRM fills in the other side of the link for you, so the employee's
gift shows the match too, and it refuses a link that cannot be right.

One piece of setup makes it safer and faster: fill in **Employer** on the people who work
for companies that match. Open a Contact and set **Employer** to the organization. When
the employer's check arrives, BarnCRM checks the link you are making against it and
warns you if the two do not agree.

## A five-minute walkthrough

You are David. Start from the sample data, which includes Harper Garcia and the
organization Riverside Consulting Group.

1. Open **Harper Garcia** and set **Employer** to **Riverside Consulting Group**. Save.
2. Click the **Gifts** tab and press **New**. Enter a gift from **Harper Garcia** for
   **500**, dated last month, status **Received**. Save. This is the employee's gift.
3. Press **New** again. Enter a gift from **Riverside Consulting Group** for **500**, dated
   today, status **Received**. Save. This is the employer's match.
4. On the employer's gift, set **Matched gift** to Harper's gift. Save.
5. Look at what happened on the employer's gift: **Matched gift** names Harper's gift, and
   in **Soft credits** Harper Garcia appears with the role **Matched donor** and the amount
   500, marked automatic.
6. Open **Harper Garcia's gift**. Its own **Matched gift** now names the Riverside gift. The
   link reads correctly from both sides, and you only entered it once.
7. Open **Harper Garcia**. Her **Total giving** is 500, the gift she actually made. Her
   **Total soft credits** is 500, the match she caused. Neither number has been inflated by
   the other.
8. Try a link that should fail because of the money. Record a refund against Harper's gift so
   its status is **Refunded**, then try to link it. BarnCRM refuses with: **A gift that
   has been refunded or written off cannot be part of a matching gift pair. Unlink the match
   before recording the refund, or link the replacement gift instead.** A link that outlived
   the money would go on crediting Harper for a match you gave back.
9. Try a link that should fail because of the employer. Go back to the employer's gift, clear **Matched gift**, save,
   then set it to a gift from a donor who works somewhere else. BarnCRM refuses the save
   with: **That gift is from someone whose employer is a different organization. Check the
   employer on the person's record, or clear it if you are not sure.**

## What a refund does to the match

If the company reverses its check, the recognition reverses with it. You do not have to
unlink anything and you do not have to edit a soft credit.

Record the refund on the company's gift the way you would on any other gift. BarnCRM
writes the usual negative gift, and alongside it a **negative matched donor credit** for the
same employee, for the amount that went back. Riverside matched Harper with 500 and asked
for 200 of it back: Harper's **Total soft credits** reads 300, which is what Riverside is
still holding because of her. Take the other 300 back as well and it reads 0.

Three things follow, and they surprise people the first time:

- **The original credit stays on the company's gift, at the full amount.** Nothing is
  erased. A recognition list you printed before the refund is still explicable afterwards,
  and the credit list shows both the 500 Harper was recognized for and the amount that took
  it back. This is the same shape as the gifts themselves, where the refunded gift keeps its
  row.
- **The link stays too.** The two gifts still name each other, because that is the record of
  what the money was. BarnCRM refuses to *create* a link involving a gift that has been
  refunded or written off, which is a different question.
- **Refunding the employee's own gift does not touch the match.** The company's money is
  still money you are holding, and the employee still caused it. Only a refund of the
  company's gift reverses the matched donor credit.

## Common mistakes

- **Linking two gifts that are both from people.** One gift of the pair has to come from an
  organization, because a match is what a company pays. If the save is refused with **The
  matching gift must come from an organization. Open the company's gift and link the
  employee's gift to it.**, neither of the two gifts you chose is the company's.
- **Entering the match as a second gift from the employee.** The company gave the money, so
  the company is the donor. Recording it under the employee inflates their giving total and
  makes your receipts wrong.
- **Leaving Employer blank and linking anyway.** That is allowed: BarnCRM only compares
  when an employer is set. Filling it in is what turns a silent mistake into a warning.
- **Unlinking a pair before refunding it.** You do not have to, and it loses the record of
  what the match was. Record the refund and the recognition reverses itself, as described
  above. What BarnCRM does refuse is a *new* link involving a gift that has already been
  refunded or written off.
- **Expecting the soft credit to survive an unlink.** Clearing Matched gift removes the
  matched donor credit that the link created, and any negative credit that was reversing it,
  because they exist only to record the link. A credit you entered by hand stays.

## Fields, for report builders

| What you see | Field |
|---|---|
| The other gift in the pair | Matched gift, on both gifts |
| The employee's employer | Employer, on Contact and on Account |
| The recognition the link creates | Soft credit with role Matched donor |
| The recognition a refund takes back | Soft credit with role Matched donor, negative amount, on the refund gift |
