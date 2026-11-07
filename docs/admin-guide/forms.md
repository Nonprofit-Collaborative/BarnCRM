# Forms

## What It Does

The BarnCRM Forms module lets you build **forms** in BarnCRM: questions in **steps**, with
**conditions** that show a step or a question only when an earlier answer calls for it. When
someone fills a form in, BarnCRM checks the answers, keeps them as a **form submission**, and
writes them into your records: it **matches** the person (and, if the form asks, their
organization) to someone already in BarnCRM, adds them only when nobody matches, and adds any
**related record** the form writes, such as an affiliation between the two.

In this release staff fill forms in inside BarnCRM, for example while on the phone with someone
or from a paper sign-up sheet. Public forms on a website, file uploads and save-and-resume come
in later releases and use the same forms.

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

Then open the **BarnCRM Forms** app from the App Launcher. Its tabs are **Forms** and **Form
Submissions**.

Forms has no settings, so it adds no section to BarnCRM Settings. It has no nightly job.

### Roles and Permission Sets

You never assign the Forms permission sets by hand. Give people their BarnCRM role on the
[Access](access.md) page, and the module gives each role its set:

| BarnCRM role | Forms set they get | What they can do |
|---|---|---|
| Admin (anyone holding BarnCRM Admin) | Forms Admin | Everything: build, publish and delete forms, fill them in, work submissions |
| Team Member, Coordinator | Forms Staff | Fill in published forms and work their submissions, including Process Again; never builds or deletes a form |
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

## Form Submissions

Every sent form is a **Form Submission**: its **Status** (Processed, Needs Review or Failed), the
answers, the **Person** and **Organization** it matched or added, and the version of the form it
was filled in from. Its record page shows the answers by question and the records written,
each linked. Reports on Form Submissions work like any other.

## Limits

A form has at most 20 steps, 100 questions and 10 records to write, and a picklist at most 200
choices. A form writes at most one person and one organization. Person accounts are matched as
contacts in this release.
