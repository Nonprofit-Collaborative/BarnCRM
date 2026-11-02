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
you get a task on the grant, due on the due date, and an email with a link to the grant. If
nobody is assigned, the grant's owner gets them. You are reminded once for each due date; if the
date changes, you are reminded again.

## To Mark a Requirement Submitted

1. On the **Grant Pipeline**, under **Upcoming Deadlines**, find the requirement.
2. Click **Mark Submitted**.

You should see: `Marked submitted.` and the row leaves the list. The requirement's **Status** is
**Submitted** and its **Submitted Date** today. You can also open the requirement and set
**Status** yourself: **Accepted** when the funder approves it, **Waived** when the funder excuses
it.

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
