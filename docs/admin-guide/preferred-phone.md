# Preferred phone

**Feature:** C-25 Multiple email addresses on a person, preferred phone extension (R-C6a)
**Package:** Core

## What it does

A person often has a home number, a mobile and another number. Salesforce lists, dialers and
reports read the ordinary **Phone** box. BarnCRM adds one choice, **Preferred Phone**: Home,
Mobile or Other. Whatever you choose is copied into the ordinary Phone box every time the
person is saved, the same way **Preferred Email** fills the ordinary Email box (see
[Emails](emails.md)).

## How to turn it on

There is nothing to set up in Salesforce Setup. **Preferred Phone** arrives with Core and sits
on the person's page next to the ordinary Phone box.

If you never choose a preferred phone, nothing changes: the ordinary Phone box keeps whatever
you type in it. The copying only starts on a person once you choose one.

The copy belongs to the **Preferred email and phone** feature (BarnCRM Settings, General) and has
its own switch on the Automation page: **Copy preferred phone on a person**. It is on by default
and separate from household upkeep. Switch it off only if you want the ordinary Phone box left
exactly as typed.

| Permission set | What they can do with Preferred Phone |
|---|---|
| BarnCRM Admin | Read and change it |
| BarnCRM Staff | Read and change it |
| BarnCRM Read Only | Read it, change nothing |

Preferred Phone is on people held as contacts. People held as accounts in an org that uses
person accounts are not touched, because their phone numbers live on fields only some orgs have.

## A five-minute walkthrough

1. Open the **BarnCRM** app, click the **Contacts** tab, and open a person.
2. Type a number into **Home Phone** and a different one into **Mobile**. Click **Save**. The
   ordinary **Phone** box does not change, because you have not said which to use.
3. Click **Edit**, set **Preferred Phone** to **Mobile**, and click **Save**. The ordinary
   **Phone** box now reads the mobile number.
4. Click **Edit**, set **Preferred Phone** to **Home**, and click **Save**. The ordinary
   **Phone** box now reads the home number.
5. Try the mistake on purpose: set **Preferred Phone** to **Other** while **Other Phone** is
   empty. The save is refused and the message names the empty number.

## Common mistakes

**"It will not let me save."** You chose a number that is empty. Fill that number in, or choose
another. BarnCRM will not empty the ordinary Phone box for you.

**"I typed a new number into the ordinary Phone box and it went back."** Once a person has a
preferred phone, the Phone box is filled from the number you chose on every save. Edit Home
Phone, Mobile or Other Phone instead, or clear Preferred Phone to type into Phone by hand.

**"I cleared Preferred Phone and the Phone box still has the old number."** Clearing the choice
stops the copying, it does not undo it. Type over it if you want a different number.

## Field reference

| Where | Field label | Purpose |
|---|---|---|
| Person | Home Phone, Mobile, Other Phone | The numbers to choose from (Salesforce standard fields) |
| Person | Preferred Phone | Home, Mobile or Other: which number to call. Copied into Phone on every save |
| Person | Phone | The ordinary Salesforce phone field that lists and dialers read |
