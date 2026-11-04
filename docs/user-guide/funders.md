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
2. Read the tiles at the top: **Open Requests**, **Amount Requested** on them, and **Awarded This
   Fiscal Year**.
3. Choose **Everyone** for every open grant, or **Mine** for the ones you own.

You should see: one column per open stage, each with its count and amount, and a card for each
grant showing its name, amount requested, funder, deadline, next step and owner. A deadline in
the next 14 days shows an amber badge (`10 days left`, `Due today`), a past one a red badge
(`3 days overdue`). Click a grant's name to open it.

## To Move a Grant to Another Stage

1. On the grant's card, click the menu (the small arrow).
2. Choose **Move to** and the stage.

You should see: `Moved to` and the stage, and the card in its new column. A grant moved to
**Awarded**, **Declined** or **Withdrawn** leaves the board.

## To Record the Award

1. On the grant's card, click the menu, then **Move to Awarded**.
2. In **Record the Award**, check **Amount Awarded** (filled in with the amount requested) and,
   from the award letter, fill in **Award Start Date**, **Award End Date** and **Restricted**.
   Each is optional.
3. Click **Save**.

You should see: `Awarded. Open` and the grant's name `to build its payment schedule.`, with the
grant's name as a link. If the save is refused (for example an end date before the start
date), the dialog stays open with the reason.

## To See the Deadlines Coming Up

Under the board, **Upcoming Deadlines** lists every grant at Prospect, Letter of Inquiry or
Invited to Apply whose application deadline is past or within the next 60 days, and every open
requirement due in that time or overdue, soonest first. Under each name it says **Application**,
or the requirement's type and grant.
Each row says how many days are left, `Due today`, or how many days overdue; within 14 days it
is an amber badge, overdue a red one. Click a grant's name to open it.

## To See a Month of Deadlines

Open the **Grant Calendar** tab. Each day shows its application deadlines, requirements due and
payments expected. An overdue item shows a warning icon, the word **Overdue** and bold text (not red alone). A key under the month heading names the border colours: **Application** (blue), **Grant Requirement** (orange) and **Grant Payment** (green), plus the **Overdue** mark. Click one to open it. Use **Previous Month** and
**Next Month** to move, and **Mine** to see only your grants and the requirements assigned to
you. Click **Print** to print the month without the app's header and navigation.

## To Show the Board Where the Money Comes From

1. Open the **BarnCRM Funders** app. It opens on the **Board Dashboard**, its home: tiles for
   this fiscal year's revenue and awards, then a tile for each Funders tab.
2. Read the three parts, all for this fiscal year:
   - **Revenue Mix**: grants awarded by funding source and, if you use Giving, gifts to funds,
     each with its amount and share as a bar.
   - **Concentration**: the five organizations giving the most, with a warning when one gives
     more than 25 percent or the five together more than half.
   - **Restricted Balances**: restricted funds and what each raised, and restricted grants'
     balances once fund tracking is in use.

You should see: amounts in your currency and shares as percents, or `Nothing to show for this
fiscal year yet.` To print it for a board packet, click **Print**. If a line says
**Not set**, those grants have no **Funding Source**; fill it in on each grant.

If your organization also enters a grant's payments as Giving gifts, that money is counted twice:
once in the grant lines and once in the gifts line, and in that funder's share. Ask your
administrator which one your organization records awards in.

## To Name the Program a Grant Pays For

Only when your organization uses Programs.

1. On the grant's page, in the **Program** card, choose the program.
2. Click **Save**.

You should see: `Program saved.` Choose **No program** and **Save** to clear it. Without Programs
the card says to install the Programs module. If the program was deleted, the card says so;
choose another.

## To Link a Requirement to the Outcome It Reports On

Only when your organization uses Logic Models.

1. On the grant's page, find the **Logic Model Outcomes** card. It lists the grant's requirements.
2. For a requirement, choose the outcome or output it reports on, shown as "Logic model: Outcome".
3. Click **Save**.

You should see: `Outcome saved.`, and under the requirement each of the outcome's indicators
with the target and result of every period in the award period, for example `2026 Q1: target 30,
result 25`. Choose **No outcome** and **Save** to clear it. If the outcome was deleted, the card
says so; choose another.

## To Make a Funder Report

1. On the grant's page, find the **Funder Report** card.
2. In **Template**, choose the report template, for example **Grant report**.
3. Click **Download Printable**.

You should see: `Report downloaded.`, and a file named like `Funder_Report-2026-11-02.html` in
your downloads. Open it in your browser to read it, print it, or save it as a PDF from the print
dialog. It holds the grant's details, its requirements table and, with Logic Models, the results
of each linked outcome. Nothing is saved in BarnCRM. If the card says there is no active
template, ask your admin to add one on the **Funder Report Templates** tab.

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

You should see: `Marked submitted.` with an **Undo** link, and the row leaves the list. The
requirement's **Status** is **Submitted** and its **Submitted Date** today. Clicked it by
mistake? Click **Undo**: the status and date go back to what they were (`Undone.`). You can also open the requirement and set
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

## To Save an Answer You Reuse

1. Click the **Grant Answers** tab, then **New**. Or click **New Answer** in the **Answer Library**
   card on any grant's page.
2. Type an **Answer Title** that says what it is and how long, for example "Mission statement
   (100 words)".
3. Paste the text into **Answer**.
4. In **Topics**, type the topics it answers, separated by commas, for example "Mission, Need".
5. Click **Save**.

You should see: the answer in the **Answer Library** card on every grant's page.

## To Copy an Answer Into an Application

1. On the grant's page, scroll to the **Answer Library** card.
2. Type words in **Search Answers**, or choose a **Topic**, to narrow the list. Each answer shows
   its topics, word count and when it was last used.
3. Click **Show All** to read a long answer in full, then **Copy**.
4. Paste it into the funder's form or your proposal document.

You should see: `Copied. Paste it into the application.`, and the answer's **Last used** date
becomes today. If your browser does not allow copying, click **Show All**, select the text and
copy it yourself.

## Tips

- **Declined is history worth keeping.** Set Declined rather than deleting: it tells you whom to
  ask again and when.
- **Use Next Step.** It shows on the card, so the team sees what is next without opening the
  grant.
- **A changed deadline.** If the funder extends a deadline, change the Application Deadline; the
  grant moves down the Upcoming Deadlines list.
