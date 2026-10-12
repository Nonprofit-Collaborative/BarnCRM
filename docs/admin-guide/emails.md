# Email addresses

**Feature:** C-25 Multiple email addresses on a person
**Package:** Core
**Iteration:** v0.5

## What it does

Most people you know have more than one email address: one at home, one at work, and
sometimes a third. Salesforce gives a person one email box, so keeping the other addresses
usually means a note somewhere nobody reads.

Open Impact gives each person three email boxes, personal, work and alternate, and one
choice: which of them you write to. Whatever you choose is copied into the ordinary email
box on the person, so every mailing, every acknowledgment and every list view sends to the
right address without anybody having to remember which one it was.

## How to turn it on

There is nothing to switch on and nothing to set up in Salesforce Setup. The three email
boxes and the choice arrive with Core and are on the person's page as soon as it is
installed.

If you never fill any of them in, nothing changes: the ordinary email box keeps whatever
you type in it, exactly as it did before. The copying only starts on a person once you have
chosen a preferred email for that person.

Who can do what comes from the permission set somebody already holds:

| Permission set | What they can do with the three addresses |
|---|---|
| Open Impact Admin | Read and change all three addresses and the choice |
| Open Impact Staff | Read and change all three addresses and the choice |
| Open Impact Read Only | Read them, change nothing |

## A five-minute walkthrough

Maria does this from the sample data.

1. Open the **Open Impact** app, click the **Contacts** tab, and open **Maria
   Whitfield**.
2. Look at the **Email addresses** section. The three boxes, **Personal Email**, **Work
   Email** and **Alternate Email**, are empty, and **Preferred Email** is empty too. The
   ordinary **Email** box above it already has her address in it.
3. Click into **Personal Email** and type `maria.whitfield@example.org`. Click into **Work
   Email** and type `mwhitfield@springfieldfoodbank.example.org`. Click **Save**.
4. Nothing has moved yet. The ordinary email box still reads what it read before, because
   you have not said which address to use.
5. Click **Edit**, set **Preferred Email** to **Work**, and click **Save**.
6. Look at the ordinary **Email** box. It now reads
   `mwhitfield@springfieldfoodbank.example.org`. Anything that sends this person an email
   now reaches her at work.
7. Maria leaves that job. Click **Edit**, set **Preferred Email** to **Personal**, and click
   **Save**. The ordinary email box now reads `maria.whitfield@example.org`. You did not
   retype an address, you changed one choice.
8. Try the mistake on purpose. Click **Edit**, set **Preferred Email** to **Alternate**, and
   click **Save**. The save is refused and you are told the alternate email is empty. Set
   the choice back to **Personal**, or fill the alternate address in, and save again.

That is the whole feature: three boxes, one choice, and an ordinary email box that is always
the address you meant.

## Common mistakes

**"I filled the three boxes in and nothing happened."**
You have not chosen a preferred email yet. The three boxes on their own are just somewhere
to keep the addresses. Set **Preferred Email** to Personal, Work or Alternate and save, and
the ordinary email box catches up on that save.

**"It will not let me save."**
You chose an address that is empty. The message names the one you chose: fill that address
in, or choose one of the others. Open Impact will not empty the ordinary email box for you,
because a person with no email address stops getting every mailing you send and nobody would
notice for months.

**"I typed a new address into the ordinary email box and it went back to what it was."**
That is the copying doing its job. Once a person has a preferred email, the ordinary email
box is filled from the address you chose on every save, so it is not the place to make a
change. Edit the personal, work or alternate address instead, or clear the preferred email
if you want to go back to typing into the ordinary box by hand.

**"I cleared the preferred email and the ordinary box still has the old address."**
Clearing the choice stops the copying, it does not undo it. Whatever was copied in last
stays there until somebody changes it, which is deliberate: the address is still a real
address for that person. Type over it if you want a different one.

## Field reference

For report builders only. Maria never needs this to use the feature.

| Where | Field label | Purpose |
|---|---|---|
| Person | Personal Email | The person's own address, the one they read at home |
| Person | Work Email | The address this person uses at work |
| Person | Alternate Email | A third address, for a person who has one |
| Person | Preferred Email | Personal, Work or Alternate: which address to write to. Copied into the ordinary Email field on every save |
| Person | Email | The ordinary Salesforce email field, which everything that sends email reads |
