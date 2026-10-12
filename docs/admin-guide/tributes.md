# Tributes: gifts in honor and in memory

## What it does

A tribute records that a gift was given in honor of someone or in memory of someone, and
who should be told about it. It is what turns a memorial gift into the letter a family
receives. BarnCRM keeps the honoree, the person to notify, and the donor's message on
the gift, and tracks whether the notification has gone out, so nobody is thanked twice and
no family is missed.

A tribute never states the amount. The letter to a bereaved family says that a gift was
made in memory of their mother, not what it was worth.

## How to turn it on

Nothing to turn on. Tributes are part of the Giving module.

One piece of first-time setup: the **Tribute** panel lives on a gift's record page, and
BarnCRM ships a page called **Gift Record Page** with the panel already on it. Assign
it once, as your org default for Gift, and every gift shows the panel from then on. If your
organization has built a gift record page of its own, add the **Tribute Notification**
component to that page instead.

The panel reads the tribute back to you and records that the notification has gone out. You
create and edit the tribute itself on the **Tributes** related list on the gift, or on the
**Tributes** tab, because a tribute has more to fill in than a panel should ask for.

Two choices are worth making once, as a team:

- **Whether you create a Contact for the honoree and the family.** You do not have to. A
  typed name and address is enough, and that is the usual case for a memorial. Create
  records when you expect a continuing relationship.
- **Who marks the notification as sent.** Whoever posts the letters. The date is stamped
  for you when they do.

## A five-minute walkthrough

You are David. Start from the sample data.

1. Click the **Gifts** tab and press **New**. Enter a gift for **100** from any donor,
   dated today, status **Received**. Save.
2. On the gift, open the **Tributes** related list and press **New**.
3. Choose the type **In memory of**. In **Honoree name** type a name that is not in your
   database, for example **Rosa Garcia**. Leave the honoree lookup empty: a memorial
   honoree is very often not a record, and BarnCRM does not make you create one.
4. Fill in the notification. Pick **Harper Garcia** as the **Notification recipient**, because
   the family should hear about the gift. If the family is not in your database, type
   their name and address in **Notification recipient name** instead.
5. In **Message**, type what the donor asked you to pass on, for example **With love from
   the Tuesday reading group**. Save.
6. The gift now shows a tribute summary: **In memory of Rosa Garcia, notify Harper Garcia,
   not yet sent**.
7. Post your letter, then come back and press **Mark notification sent**. The panel now
   says the notification has been sent, and shows the date. The button is gone, because it
   has been done.
8. Try a tribute with nobody to notify. Add a tribute with an honoree and no notification
   recipient at all. The panel shows the tribute and, in place of the button, says:
   **Nobody is recorded as the person to notify, so there is no letter to send. Add a
   notification recipient, or a name and address, on the tribute.** That is the intended
   state for a tribute the donor asked you to record but not to announce, and it is also
   how you find the ones somebody forgot to finish: the **Notifications to send** list view
   is built for exactly that.
9. Try one thing that should fail. Open a new gift, add an **In memory of** tribute whose
   honoree is a Contact marked deceased, and make that same person the notification
   recipient. Save. BarnCRM refuses with: **This gift is in memory of the person you
   have chosen to notify. Choose a family member or friend as the notification recipient.**

## Common mistakes

- **Naming the honoree as the person to notify.** It is one line down in the form, and it
  is the mistake that would send a letter to a family about the person they have just
  buried. BarnCRM refuses the save when the honoree is a record marked deceased, whether
  that person is stored as a Contact or as an Account. It cannot catch a typed name, so read
  the tribute summary back before you post.
- **Expecting BarnCRM to send the letter.** It does not. There is no email or mail
  merge behind **Mark notification sent**: the button records that your organization sent
  something, and the address or email you write to is on the recipient's own record. A
  recipient with no address and no email is not refused, because a typed name and a phone
  call is a legitimate way to tell a family; it is your judgment, not a validation rule.
- **Creating a Contact for every honoree.** You do not need to, and a database full of
  one-time honorees makes your lists harder to use. Type the name.
- **Adding a second tribute to one gift.** A gift is given in honor of one person or in
  memory of one person. If two names belong on one check, record the second in the message
  or split the gift.
- **Marking the notification sent before it is posted.** The flag and its date are not
  cleared by automation once set, because they are a record of what your organization did.
  If it was set in error, clear the checkbox on the tribute yourself and note why.

## Fields, for report builders

| What you see | Field |
|---|---|
| In honor of or in memory of | Type |
| Who is honored | Honoree name, Honoree contact, Honoree account |
| Who is told | Notification recipient contact, Notification recipient account, Notification recipient name |
| Whether the letter has gone | Notification sent, Notification sent date |
| What the donor asked you to say | Message |
