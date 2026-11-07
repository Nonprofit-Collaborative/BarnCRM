# Forms

Forms let you take someone's answers a step at a time and have BarnCRM put them in the right
records for you: it finds the person if they are already in BarnCRM and adds them if not. Your
BarnCRM admin builds the forms (see [Forms](../admin-guide/forms.md) in the Admin Guide).

## To Fill In a Form

1. Open the **BarnCRM Forms** app, the **Forms** tab, and the form.
2. Select the **Fill In** tab.
3. Answer the questions on the first step and select **Next**. A question you must answer, or an
   answer BarnCRM cannot take (an email without an `@`, a date that is not a date), says what to
   fix in red below it. A **file** question takes a document or picture (at most 1 MB for all
   the form's files together).
4. Some steps and questions appear only when an earlier answer calls for them, and the path at
   the top shows only the steps you will see. **Back** returns to the step before.
5. On the last step select **Submit**.

BarnCRM then says what happened:

- **Thank you. The answers are saved and written to BarnCRM.** The person (and any organization
  or other record the form writes) is found or added and up to date.
- A message saying the answers are **held for review**: usually more than one person matched.
  See [To Finish a Submission Held for Review](#to-finish-a-submission-held-for-review).

Select **Open Submission** to see what was written, or **Fill In Another** to start again.

Where your admin has put the form on another page (an event, for example), you fill it in there
the same way, and the answers are linked to that record.

## To See a Submission

1. Open the **Form Submissions** tab and the submission.
2. Its **Submission** tab shows the **Status**, the answers by question, and under **Records
   Written** each record found or added, with a link to it.

## Answers From a Public Form

Your admin can put a form on a public web page. Answers sent there show on the **Form
Submissions** tab with **Source Public** and status **Received** until BarnCRM writes them to
your records, within about 15 minutes. A public form only fills in fields that are blank on a
person already in BarnCRM; it never replaces what you know. If the answers look wrong, change
the records by hand; a submission held for review is finished the same way as any other.

A file sent with a form (a public one or one you fill in) is under the submission's **Files**,
and once the answers are written, under the person's and organization's **Files** too. Someone
who saved a public form to finish later shows up only when they send it.

## To Finish a Submission Held for Review

A submission is held, with status **Needs Review**, when more than one person (or organization)
in BarnCRM matches the answers, so BarnCRM does not guess. A **Failed** one says why nothing
was written.

1. Open the submission and read the message at the top.
2. On its **Details** tab, set **Person** (or **Organization**) to the right record and save.
3. On the **Submission** tab select **Process Again**.

The status becomes **Processed** and **Records Written** lists what was written. If the
message says something else is wrong, such as a field you cannot change, ask your BarnCRM admin.
