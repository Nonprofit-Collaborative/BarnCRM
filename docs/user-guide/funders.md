# Grants and Funders

This page covers tracking grants in BarnCRM: the requests you send to foundations, companies and
government funders, how far along each one is, the deadlines coming up, and the reports an award
requires.

**Before you start:** open the **BarnCRM Funders** app from the App Launcher. Fundraising Staff,
Team Members and Coordinators add grants and move them through the stages, but cannot delete a
grant. Admins can also delete one. Read Only users can look but change nothing. If you need more
access, ask your admin (see the [Funders admin guide](../admin-guide/funders.md#roles-and-permission-sets)).

A funder is always an organization record: the foundation, company or agency you are asking. Its
program officer is a contact at that organization.

## To Add a Grant

1. Click the **Grants** tab, then **New**. Or, on the **Grant Pipeline** tab, click **New Grant**.
2. Type a **Grant Name**, for example "2027 Literacy Grant".
3. Choose the **Funder** (required) and, if you know one, the **Funder Contact**.
4. Leave **Stage** at **Prospect**, or choose where it already stands.
5. Fill in **Amount Requested** and the **Application Deadline** if you know them, then click
   **Save**.

You should see: the grant's page with a **Program** card at the top.

## The Stages

| Stage | Means |
|---|---|
| Prospect | A funder you plan to ask. |
| Letter of Inquiry | You are writing or have sent a letter of inquiry. |
| Invited to Apply | The funder asked for a full application. |
| Applied | The application went in. |
| Awarded | The funder said yes. |
| Declined | The funder said no. |
| Withdrawn | You decided not to go ahead. |

The first four are open; the grant shows on the Grant Pipeline board. When a grant reaches
**Applied**, an empty **Submitted Date** becomes today. When it reaches **Awarded**, **Declined**
or **Withdrawn**, an empty **Decision Date** becomes today. A date you typed is kept.

## To Work the Grant Pipeline

1. Click the **Grant Pipeline** tab.
2. Read the totals at the top: **Open Requests**, **Amount Requested** on them, and **Awarded This
   Fiscal Year**.
3. Choose **Everyone** for every open grant, or **Mine** for the ones you own.

You should see: one column per open stage, each with its count and amount, and a card for each
grant showing its funder, amount requested, deadline, next step and owner.

## To Move a Grant to Another Stage

1. On the grant's card, click the menu (the small arrow).
2. Choose **Move to** and the stage.

You should see: `Moved to` and the stage, and the card in its new column. A grant moved to
**Awarded**, **Declined** or **Withdrawn** leaves the board.

Moving to **Awarded** first asks for the **Amount Awarded**, filled in with the amount requested.
Change it if the funder gave a different amount, then click **Save**.

## To See the Deadlines Coming Up

Under the board, **Upcoming Deadlines** lists every grant at Prospect, Letter of Inquiry or
Invited to Apply whose application deadline is past or within the next 60 days, and every open
requirement due in that time or overdue, soonest first. Under each name it says **Application**,
or the requirement's type and grant.
Each row says how many days are left, `Due today`, or how many days overdue (in red). Click a
grant's name to open it.

## To See a Month of Deadlines

Open the **Grant Calendar** tab. Each day shows its application deadlines, requirements due and
payments expected; overdue ones are in red. Click one to open it. Use **Previous Month** and
**Next Month** to move, and **Mine** to see only your grants and the requirements assigned to
you.

## To Name the Program a Grant Pays For

Only when your organization uses Programs.

1. On the grant's page, in the **Program** card, choose the program.
2. Click **Save**.

You should see: `Program saved.` Choose **No program** and **Save** to clear it. Without Programs
the card says to install the Programs module. If the program was deleted, the card says so;
choose another.

## To Add What an Award Requires

Funders usually want reports back. Record each one on the grant.

1. On the grant's page, in the **Requirements** list, click **New**.
2. Type a **Requirement Name**, for example "Year 1 interim report", and choose its **Type**.
3. Fill in the **Due Date** and, in **Assigned To**, the person doing it.
4. Paste what the funder asks for into **Instructions**, then click **Save**.

You should see: the requirement in the grant's **Requirements** list, and on the **Grant
Pipeline** under **Upcoming Deadlines** once it is due within 60 days.

## Your Reminders

When a requirement assigned to you is coming due (14 days ahead unless your admin changed it),
you get a task on the grant, due on the due date, and, if your admin turned email reminders on,
an email with a link to the grant. If
nobody is assigned, the grant's owner gets them. You are reminded once for each due date; if the
date changes, you are reminded again.

## To Mark a Requirement Submitted

1. On the **Grant Pipeline**, under **Upcoming Deadlines**, find the requirement.
2. Click **Mark Submitted**.

You should see: `Marked submitted.` and the row leaves the list. The requirement's **Status** is
**Submitted** and its **Submitted Date** today. You can also open the requirement and set
**Status** yourself: **Accepted** when the funder approves it, **Waived** when the funder excuses
it.

## To Set Up an Award's Payments

When a funder pays an award in parts (for example once a year for three years):

1. Open the grant. It must be **Awarded**, with **Amount Awarded**, **Award Start Date** and
   **Award End Date** filled in.
2. On the **Award Schedule** card, choose the **Payment Frequency**.
3. Check the payments listed: the amount split evenly, the first on the award start date.
4. Click **Build Schedule**.

You should see: `Saved.` and the payments in the card, each **Expected**. **Amount Scheduled**
shows the total. To change one payment's date or amount, or add or cancel one, use the grant's
**Payments** list.

## To Record a Payment That Came In

On the grant's **Award Schedule** card, click **Mark Received** on the payment.

You should see: `Saved.`, the payment **Received** with today's date, and **Amount Received** at
the top of the card going up by its amount. If it came in on another day, open the payment and
change **Received Date**.

## To Keep a Restricted Grant's Ledger

When a funder limits the money to a purpose, tick **Restricted** on the grant (your admin may
have done it). Then:

- **Money that came in.** Marking a payment **Received** adds a **Received** entry to the grant's
  **Restricted Fund Entries** list for you. Money that came in another way: click **New** in that
  list, **Type** Received.
- **Money spent on the purpose.** Click **New**, **Type** Spent, the **Amount**, the **Entry
  Date** and a **Description**, for example `Q1 tutor salaries`.
- **Restriction lifted.** When the funder releases the money, or the restriction lapses, add a
  **Released** entry.

You should see: the grant's **Restricted Received**, **Restricted Spent**, **Restricted
Released** and **Restricted Balance** change at once.
A balance below zero means more was spent than came in so far, which is normal for a
reimbursement grant.

## To Name the Giving Fund

With Giving installed, choose the fund the money is booked to on the grant's **Giving Fund**
card and click **Save**.

You should see: `Saved.` and the fund's name on the card.

## To Record a Government Award

1. On the grant's page, click **Edit**.
2. Set **Funding Source**, for example **Federal** or, for federal money passed on by a state
   agency, **Federal Pass-Through** (the state agency is then the Funder).
3. In the **Government Award** section, fill in what the award letter gives: **Assistance Listing
   Number** (for example 84.287), **Award Number**, **Federal Agency**, **Indirect Cost Rate** and
   **Match Required**. Leave any you do not have blank.
4. Click **Save**.

You should see: the values on the grant's page. An Assistance Listing Number not written like
84.287, a rate above 100 or a negative match is refused with a message saying why.

## Tips

- **Declined is history worth keeping.** Set Declined rather than deleting: it tells you whom to
  ask again and when.
- **Use Next Step.** It shows on the card, so the team sees what is next without opening the
  grant.
- **A changed deadline.** If the funder extends a deadline, change the Application Deadline; the
  grant moves down the Upcoming Deadlines list.
