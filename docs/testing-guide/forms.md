# Forms

Scripts for the Forms module (C-42a, C-42b): the Form Builder, conditions, publishing, the Form
Runner, matching, Process Again, and public forms on a Salesforce Site. Setup detail:
[Forms](../admin-guide/forms.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and Forms
deployed. Forms works on the platform-only shape and in both editions. Give the testers their
roles on the **Access** page: admin (Admin role), staff (Team Member role) and read-only (Read
Only role). Each gets its Forms permission set from the role.

## T-FORM-01: Build and Publish a Form

**Purpose:** confirm the Form Builder builds steps, questions and records, checks them, and
publishes a version.
**Prerequisites:** admin.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the **BarnCRM** app, **Forms** tab (after **Data Manager**; there is no BarnCRM Forms app), **New**. Name `Volunteer Interest`, save. | The record page opens on the **Builder** tab (the **Form Builder** panel) with one step, a person under **Records to Write**, and **Fix Before Publishing** listing that the person needs a question written to Last Name. **Publish** is disabled. |
| 2 | Set **Step Title** to `You`. Select **Add Question**: **Question** `Last Name`, **Required**, **Write To** `person (Person)`, **Field** `Last Name (LastName)`. Add `First Name` written to `FirstName` and `Email` (type Email) written to `Email`. | The three questions are under `You`. **Fix Before Publishing** is gone; **Publish** is enabled. |
| 3 | Select **Add Question** on `You`: `Age`, type Number, not written to a record. Select **Add Step**: title `Guardian`, a question `Guardian Name`, required, written to the person's `Description`. | Two steps in the left column. |
| 4 | Select the `Guardian` step. Under **Show When** choose **All Are True**, then the test `Age`, **is less than**, value `18`. | The condition shows one row. |
| 5 | Select **Preview**. Answer `Lee`, `Pat`, `pat@example.org`, then Age `16`; then change Age to `30`. | With `16` the step offers **Next** and the path shows `Guardian`; with `30` the path drops it and the step offers **Submit**, disabled, under the note that nothing is sent. Select **Preview** again to close it. |
| 6 | Select **Save Draft**. | `Draft saved...` shows. The status line still says Draft. |
| 7 | Select **Publish**. | The status says Published and `Version 1 is published...`. The **Versions** related list has V-0001. |
| 8 | Change the step title to `About You`, select **Publish**. | `Version 2 is published...`. |

**Cleanup:** None (the later scripts use this form).

## T-FORM-02: Fill In a Form and Match the Person

**Purpose:** confirm the runner checks answers, follows conditions and writes the person, found
or added.
**Prerequisites:** staff, the form from T-FORM-01, a contact `Pat Lee` with email
`pat@example.org` and a blank Description.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open `Volunteer Interest`, **Fill In** tab. Select **Next** with nothing answered. | `Answer this question.` under Last Name; the step stays. |
| 2 | Answer `Lee`, `Pat`, `pat@example.org`, `16`, select **Next**. | The `Guardian` step shows. |
| 3 | Answer `Sam Lee`, select **Submit**. | `Thank you. The answers are saved and written to BarnCRM.` |
| 4 | Select **Open Submission**. | Status Processed; the answers by question; **Records Written** shows `person (Person): found and filled in`, linked to Pat Lee. |
| 5 | Open Pat Lee. | Description is `Sam Lee`; nothing else changed. |
| 6 | Select **Fill In Another** and answer `Rivera`, `Jo`, `jo@example.org`, `40`, **Submit**. | **Submit** is on the first step (no guardian step); the submission's record is `added`, a new contact Jo Rivera. |

**Cleanup:** delete Jo Rivera.

## T-FORM-03: A Held Submission and Process Again

**Purpose:** confirm two matching people are never guessed and Process Again finishes the
submission.
**Prerequisites:** staff, the form from T-FORM-01, two contacts named `Pat Lee` with email
`twins@example.org`.

| Step | Action | Expected result |
|---|---|---|
| 1 | Fill in `Lee`, `Pat`, `twins@example.org`, `30`, **Submit**. | A message that more than one person matches and nobody was changed. |
| 2 | Open the submission. | Status Needs Review, the same message, no **Records Written**, **Process Again** offered. |
| 3 | On **Details**, set **Person** to one of the two, save. On **Submission**, select **Process Again**. | Status Processed; **Records Written** links to the person chosen. **Process Again** is gone. |

**Cleanup:** None.

## T-FORM-04: Access

**Purpose:** confirm staff fill in but never build, and read-only only looks.
**Prerequisites:** the form from T-FORM-01.

| Step | Action | Expected result |
|---|---|---|
| 1 | As staff, open the form's **Builder** tab. | The panel says you can look but not change it; no Save Draft, Publish, Add Step or Add Question. **Preview** works. |
| 2 | As read-only, open the **Form Submissions** tab and a submission. | The answers and records show; no **Process Again**. |
| 3 | As read-only, open the form's **Fill In** tab. | The form cannot be sent (an error, or Submit unavailable); nothing is written. |

**Cleanup:** None.

## T-FORM-05: Publish Refuses a Missing Field

**Purpose:** confirm a form never publishes a target the org lacks.
**Prerequisites:** admin, a sandbox where you can delete a custom field on Contact, or a form
written to a related record's object you then remove from the org.

| Step | Action | Expected result |
|---|---|---|
| 1 | Write a question to a custom Contact field, **Publish**. Then delete that field in Setup. | Version published. |
| 2 | Change any title, **Publish**. | An error naming the missing field; no new version. |
| 3 | Fill the form in. | The submission is Failed, `Nothing was written:` with the missing field; nothing else changed. |

**Cleanup:** remove the question, publish.

## T-FORM-06: Public Form on a Salesforce Site

**Purpose:** confirm a public form stores answers with no access to records, and processing
matches and fills blanks only.
**Prerequisites:** admin; the form from T-FORM-01; a person on file, `Sam Zztest`,
`sam.zztest@example.org`, mailing postal code `11111`; an active Salesforce Site set up as in
the Admin Guide (Setup steps 1 to 5).

| Step | Action | Expected result |
|---|---|---|
| 1 | In the Form Builder, turn on **Public on a Salesforce Site**, set **When Found** to **Replace field values with the answers**. | **Fix Before Publishing** says a public form can only fill in blank fields; Publish is unavailable. |
| 2 | Set **When Found** back to fill blanks, **Publish**. | Published; the panel lists the form's link on the Site. |
| 3 | Open **Health Check** in the Settings console. | **A Site guest user can't open public forms** and **Public form answers are not being processed**. No finding that a guest can read people. |
| 4 | Select **Give Forms Public Guest**, confirm; then **Schedule Processing**, confirm. | Both findings clear on the re-run. |
| 5 | In a private browser window (not signed in), open the link. | The form shows, with its steps; no BarnCRM data shows anywhere. |
| 6 | Enter `Sam`, `Zztest`, `sam.zztest@example.org`, postal code `22222`, and send. | The thank-you message; nothing says whether Sam was found. |
| 7 | Leave the page open over a day, then send again. | Asked to reload the page; nothing is stored. |
| 8 | Signed in, open **Form Submissions**. | A submission with Status **Received**, Source **Public**, no Person. |
| 9 | Wait for the next quarter hour (or run Health Check's schedule again later), reopen it. | Status **Processed**; Person is Sam Zztest (no new contact); Sam's postal code is still `11111`. |
| 10 | Set the form's **Status** to **Closed** and reload the public page. | "This form isn't open right now." |

**Cleanup:** delete the submission, set the form back to Published or delete it, delete the
Site if you made one only for this.

## T-FORM-07: Files and Save for Later

**Purpose:** confirm a file is kept on the submission and the person, a wrong or large file is
refused, and saved answers reopen from the emailed link only.
**Prerequisites:** T-FORM-06 done (public form, Site, processing scheduled); Admin Guide Site
steps 6 and 7 done; an inbox you can read.

| Step | Action | Expected result |
|---|---|---|
| 1 | In the Form Builder add a question **Resume**, Type **File**, not written to a record; turn on **Let People Save and Finish Later**, **Days a Saved Link Works** `2`; **Publish**. | Published. Choosing a record for the file question instead shows a problem and blocks Publish. |
| 2 | In a private window open the public link; for Resume choose a `.html` file. | "Choose a PDF, picture, Word, Excel, CSV or text file." |
| 3 | Choose a PDF over 1 MB and send. | Says the files can be at most 1024 KB; nothing is sent. |
| 4 | Fill in `Sam`, `Zztest`, `sam.zztest@example.org`, choose a small PDF, then **Save and Finish Later**, enter your email, **Email Me the Link**. | "Your answers are saved..." and an email arrives with a link. |
| 5 | Open the link. | The form opens with the answers filled in and a note to choose files again. |
| 6 | Choose the PDF again and send. | The thank-you message. |
| 7 | Open the link again. | "This link to saved answers has expired or was already used." and an empty form. |
| 8 | Signed in, after processing, open the submission and Sam Zztest. | The PDF is under the submission's Files and Sam's Files. |
| 9 | As staff, fill in the form on its **Fill In** tab with a file. | Processed; the file is on the submission and the person. |

**Cleanup:** delete the submissions and files, remove the file question, republish.
