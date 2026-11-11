# Forms

## What It Does

The BarnCRM Forms module lets you build **forms** in BarnCRM: questions in **steps**, with
**conditions** that show a step or a question only when an earlier answer calls for it. When
someone fills a form in, BarnCRM checks the answers, keeps them as a **form submission**, and
writes them into your records: it **matches** the person (and, if the form asks, their
organization) to someone already in BarnCRM, adds them only when nobody matches, and adds any
**related record** the form writes, such as an affiliation between the two.

Staff fill forms in inside BarnCRM, for example while on the phone with someone or from a paper
sign-up sheet. A form can also be made **public**: anyone with its link fills it in on a
Salesforce Site, with no login (see [Public Forms](#public-forms)). File uploads and
save-and-resume come in a later release and use the same forms.

Other BarnCRM modules can attach a form to their own records (for example, an event's
registration form in the Event Management module). The form is then filled in from that record
and the module receives each submission. A module that does this says so on its own page.

## How to Turn It On

### Before You Install

- Forms is offered in **both editions** (see [Editions](editions.md)).
- It needs BarnCRM Core and nothing else.

### Installing

Install it from **Module Manager** (see [Module Manager](module-manager.md)). When the install
finishes, BarnCRM gives you, the person who installed it, the **Forms Admin** permission set,
and gives everyone who already has a BarnCRM role their Forms permission set (see below).

Forms has no app of its own (D-188): its **Forms** and **Form Submissions** tabs are in the
**BarnCRM** and **BarnCRM Console** apps, after **Data Manager**. A source install puts them
there itself; after a package install, add them once in App Manager (see
[The BarnCRM Apps](barncrm-app.md#a-modules-pages-in-the-barncrm-apps)). A form or submission
opens on its own record page from any app.

Forms has no org-wide settings: each form is set up on its own record. BarnCRM Settings has a
**Forms** section with one row, **Open Forms**, which opens the Forms tab. That row is also how
BarnCRM knows Forms is installed. It has no nightly job. Public
forms add their own checks to **Health Check** and a processing job you schedule from there (see
[Public Forms](#public-forms)).

### Roles and Permission Sets

You never assign the Forms permission sets by hand. Give people their BarnCRM role on the
[Access](access.md) page, and the module gives each role its set:

| BarnCRM role | Forms set they get | What they can do |
|---|---|---|
| Admin (anyone holding BarnCRM Admin) | Forms Admin | Everything: build, publish and delete forms, fill them in, work submissions |
| Team Member, Fundraising Staff (Giving) | Forms Staff | Fill in published forms and work their submissions, including Process Again; never builds or deletes a form |
| Read Only | Forms Read Only | Look at forms and submissions |

Filling in a form writes the person, organization and related records **as the person filling
it in**: they need access to those records and fields through their other BarnCRM sets.

## Building a Form

1. Open the **Forms** tab and select **New**. Give the form a **Name** and save. The form
   opens on its **Builder** tab (the **Form Builder** panel).
2. The left column lists the **steps** and their **questions**, and below them the **Records to
   Write**. Select a step or a question to change it on the right.
3. Give the first step a **Step Title**. Select **Add Question** to add a question, then set:
   - **Question**: the wording people see.
   - **Key**: a short name for the answer, made for you (`question1`). Change it if you like; a
     condition that tests the question follows the new key.
   - **Type**: Text, Long Text, Email, Phone, Number, Date, Checkbox or Picklist. A picklist
     takes its **Choices**, one per line.
   - **Required**, and **Help Text** shown beside the question.
   - **Write To** and **Field**: the record and field the answer is written to. Choose **Not
     written to a record** for an answer kept only on the submission.
4. Select **Add Step** for the next step. Steps and questions move with **Move Up** and **Move
   Down**, and **Remove** removes one.

### Records to Write

A new form writes one **person** (a contact). **Add Record** adds:

- **Organization**: an account, matched by its name.
- **Related Record**: a record of another object, such as an affiliation. Choose its
  **Object**, then for each of its lookup fields choose what it links to: the person, the
  organization, or **The record the form is filled in from**.

A person needs a question written to **Last Name**, and an organization one written to its
name; the Form Builder says so until they have one. For a person, **Match By** is **Email, then
last name and postal code** (the default) or **Email only**. **When Found** is **Fill in only the
fields that are blank** (the default, so a form never overwrites what you already know) or
**Replace field values with the answers**.

### Conditions

Every step and question has **Show When**: **Always**, **All Are True** or **Any Is True**,
with **Add Condition** for each test. A condition tests an earlier question only: equals, does
not equal, contains, is greater than, is less than, is blank or is not blank. A step whose
questions are all hidden is skipped, and a hidden question's answer is never kept or written.

### Preview, Save Draft and Publish

- **Preview** shows the draft in the Form Runner as people will see it. Nothing is sent.
- **Save Draft** keeps your changes. People still fill in the published version.
- **Publish** makes the draft the version people fill in, from now on. Earlier submissions keep
  the version they were filled in from. **Fix Before Publishing** lists anything that stops it,
  and Publish also refuses a field or object your org does not have.

## Filling In a Form

Staff open the form and select its **Fill In** tab, or add the **Form Runner** component to any
page in Lightning App Builder. On an app or home page, the component's **Form Record Id** sets
the form; left blank, people pick a published form. The runner shows one step at a time, checks
each answer before moving on, and checks every answer again when it is sent. See
[Forms](../user-guide/forms.md) in the User Guide.

## How Matching Works

BarnCRM matches with the same rules as **Import**:

1. A person with the email given. With a first name given, only someone with that first name,
   or no first name, is taken, so two people sharing a family email are never mixed up.
2. Then, with **Email, then last name and postal code**, a person with the same last name and
   mailing postal code.
3. Then your org's own active duplicate rules, if any.

An organization is matched by its name among organization accounts, then by your duplicate
rules. When more than one record matches, BarnCRM changes nothing: the submission is kept as
**Needs Review** with a message. Choose the right record in the submission's **Person** or
**Organization** field and select **Process Again**.

Writing is all or nothing: if any record cannot be written, nothing is, and the submission is
kept as **Failed** with the reason. Fix the cause (often a field's access or a validation rule)
and select **Process Again**.

## Public Forms

A public form is filled in by anyone with its link, on a **Salesforce Site**, with no login and
no Salesforce license. BarnCRM keeps the people on your Site away from your data:

- The Site's guest user gets **no access to any record**. It may only open the public form page
  and send answers. The answers are stored as a submission with **Status Received** and
  **Source Public**, and nothing else is read or written.
- The answers are written to your records later, by **public form processing**, which runs every
  15 minutes as the administrator who scheduled it, with the same matching as a staff form.
- The person filling it in is told only that the answers were received. Whether they matched
  someone on file is never shown to them.
- A public form only **fills in blank fields** of a person or organization already on file; it
  never replaces what you know.
- Scripts are kept out with no outside service: a hidden question only scripts fill in, a
  minimum time before sending (**Seconds Before Sending**, default 3), a limit on how many sends
  the form takes an hour (**Sends Per Hour**, default 50), and a signed link that lasts a day.

### Setting Up a Site (Once)

Salesforce requires these steps in **Setup**, and no app can do them for you:

1. **Setup > Sites**: register your Sites domain, if the org has none yet.
2. Select **New**, give the Site a label and name, set **Active Site Home Page** to
   **FormsPublic**, and save.
3. On the Site, select **Public Access Settings** only if you want to check it: the guest user
   needs no object access for forms. Under **Site Visualforce Pages**, add **FormsPublic** if it
   is not listed.
4. Choose the Site's default owner for records its guest user creates, if Salesforce asks.
5. **Activate** the Site.
6. Only if a public form asks for a file: **Setup > Salesforce Files > General Settings**, turn
   on **Allow site guest users to upload files**. Salesforce does not let an app change this.
7. Only if a public form lets people save and finish later: check **Setup > Deliverability**
   allows **All email**, so the link can be emailed.

Then open **Health Check** in the Settings console. With a public form published it checks:

| Check | What to do |
|---|---|
| No Active Site for Public Forms | Do the steps above. |
| A Site Guest User Can't Open Public Forms | Select **Give Forms Public Guest**. It gives the Site's guest user the Forms Public Guest permission set: the public form page and its Apex class, nothing else. |
| A Site Guest User Can Read People or Organizations | Remove Read on Contact and Account from the guest user's profile and permission sets in Setup. BarnCRM never changes this for you. |
| Public Form Answers Are Not Being Processed | Select **Schedule Processing**. It runs every 15 minutes as you, so keep your user active. |
| Public Form Answers Are Waiting | Answers have waited over an hour: check processing is scheduled and its user is active, then the Error Log. |

### Making a Form Public

In the Form Builder, at the bottom, turn on **Public on a Salesforce Site**, set **Seconds
Before Sending**, **Sends Per Hour** and an optional **Thank-You Message**, and **Publish**. A
public form may write people, organizations and custom objects, through fields you can create
that are not lookups or encrypted (lookups are set by the record links you choose), and must
use **Fill in only the fields that are blank**; Publish names anything that breaks this. After
publishing, the Form Builder lists the form's link on each active Site:
`<your Site address>/FormsPublic?form=<form record Id>`. A form attached to a record by another
module adds `&record=<record Id>`; BarnCRM writes the link only when that module says the record
uses this form.

Closing the form (Status **Closed**) stops its public link at once.

### Files and Save for Later

A **File** question (in the question's **Type**) lets the person attach a document or picture:
PDF, JPG, PNG, GIF, HEIC, Word, Excel, CSV, text, RTF or ODT, at most 1 MB for all the form's
files together. A file question is not written to a field: the file is kept on the submission
as a Salesforce File and, when the answers are processed, added to the person's and the
organization's **Files** too. Staff filling in a form in the Form Runner attach files the same
way.

On a public form, turn on **Let People Save and Finish Later** and set **Days a Saved Link
Works** (1 to 30, default 7). The person sees **Save and Finish Later**, gives an email
address, and gets a link that opens the form with their answers filled in, on the same version
of the form, until it expires or they send it. Files are not saved: they choose them again.
BarnCRM keeps the answers in a **Form Draft** but not the email address, and stores only a
scrambled copy of the link's code, so nobody can open a draft without the email. Saved drafts
count toward **Sends Per Hour**, and public form processing deletes expired ones. So the form
cannot be used to flood an inbox or use up your org's daily email allowance, it sends at most
3 links an hour to one email address and at most 100 links an hour in all (or the form's
**Sends Per Hour**, if lower); past either, the person is told to try again later and no
email goes out. To tell addresses apart BarnCRM keeps only a scrambled key of each, never the
address. Save and
Finish Later is not offered on a form opened from a record (such as an event's registration).

### Integrations and Portals

A portal or website off Salesforce can serve the same public form through a signed-in
integration user (which license it needs is on the [Portal Builder](portal-builder.md) page),
at `/services/apexrest/barncrm/forms/v1/<form record Id>` (GET loads the form,
POST sends `ticket`, `answers` and `trap`, with optional `files` as `{ key: { name, data } }`
in base64 and `resume` for a resumed form; POST with `saveFor` (an email address) and `step`
saves the answers for later instead, and GET with `?resume=<code>` loads them). Give that user
the **Forms Staff** permission set
and access to what the form writes; its answers are processed at once, as that user. The same
checks apply.

The same Site page and API also serve a module's public pages: an event's page with its
registration form (`FormsPublic?record=<event ID>`, `FormsPublic?list=events`, and
`GET .../forms/v1/pages/<event ID>` or `GET .../forms/v1/pages?kind=events`). The module
decides what is published; see [Event Management](events.md), Public Event Page.

## Form Submissions

Every sent form is a **Form Submission**: its **Status** (Received, Processed, Needs Review or
Failed), its **Source** (Staff or Public), the
answers, the **Person** and **Organization** it matched or added, and the version of the form it
was filled in from. Its record page shows the answers by question and the records written,
each linked. Reports on Form Submissions work like any other.

## Limits

A form has at most 20 steps, 100 questions and 10 records to write, and a picklist at most 200
choices. A form writes at most one person and one organization. The files sent with one form
can be at most 1 MB together. A person who is stored as a
person account is never changed by a form: the submission is held as Needs Review so you can
update them by hand.
