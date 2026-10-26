# Setup Assistant

## What it does

The Setup Assistant is the guided path from "I just installed BarnCRM" to "we are
working with real records", in under thirty minutes, without opening Salesforce Setup and
without reading anything else. It asks its questions one screen at a time, in the order that
makes each answer easy, and it remembers where you got to. Close the browser in the middle
of step four and come back tomorrow: the assistant opens on step four.

How many steps you see depends on what is installed. BarnCRM Core on its own asks eight
questions, starting with which edition you want. When the **Giving** module is installed as
well, Giving adds its own: a step for the default fund and appeal, the receipt details on the
identity step, and a first gift to check everything with, which makes nine steps. This page
numbers the steps as they appear with Giving installed and marks what comes from Giving.
Without Giving, the steps after step three move up by one.

Nothing it asks is permanent. Every answer is a setting you can change later on the
BarnCRM Settings page, and you can re-run the whole assistant whenever your organization
changes. The edition is the one answer you give once, and you give it before the assistant:
until an administrator finishes the first-run setup window (see
[BarnCRM Settings, First-run setup](barncrm-settings.md#first-run-setup)), the home page shows
that window instead of the assistant. The assistant's step one then shows the edition
read-only, and [Editions](editions.md) says how to change it later. The same window asks which
Core features to turn on; a feature cannot be turned off once on, and one left off can be
turned on later in BarnCRM Settings, General (see
[BarnCRM Settings, Features](barncrm-settings.md#features-general)).

## How to turn it on

There is nothing to turn on. The Setup Assistant is the BarnCRM home page until you
finish it.

1. Click the app launcher (the grid of dots at the top left of Salesforce).
2. Type `BarnCRM` and choose **BarnCRM**.
3. The home page opens on the assistant, at the first step you have not finished.

When every step is done, the assistant collapses to a small **Setup complete** tile that
shows how many steps you finished. The tile has a **Reopen setup** button, so the assistant
is always one click away, and it opens straight back on the first step rather than on the
completion screen.

You need the **Manage BarnCRM Settings** permission to change anything in the assistant.
Everyone else sees the same steps, reads the same explanations, and cannot save. If you can
read but not save, the assistant says so at the top and names the permission you are
missing. Ask whoever installed BarnCRM to add you to the **BarnCRM Admin** role on
the Access page.

Two things sit outside the assistant, because Salesforce does not let an app do them:

- **Creating a Salesforce user** who has never signed in. Step five links you to the Setup
  page that does it, then you come back and give the new person a role.
- **Installing another BarnCRM module.** Step one opens Salesforce's installer for the
  module your edition needs, and step seven tells you which modules are present and links
  to what each one does. You click through Salesforce's install screens yourself: BarnCRM
  never installs anything for you.

## A five-minute walkthrough, and then the nine steps

Maria has just installed BarnCRM Core and the Giving module in her organization's
Salesforce org. That org has Person Accounts turned on, which matters in step two and
nowhere else. She has half an hour before her next meeting.

### Before you start

Have these to hand. Every one of them is optional, and every one of them is faster to have
ready than to go and find:

- Your organization's legal name as it appears on your official filings.
- Your mailing address as you want it printed.
- With Giving: your tax identification number (in the United States, your EIN).
- With Giving: your logo, as a PNG or JPG file.
- With Giving: a scan of the signature that goes on receipt letters, if you use one.

### Step 1: Choose your edition

BarnCRM comes in two editions built from the same parts, and both include the full core suite of tools. Any organization can choose either
one. You choose once: the edition decides which modules BarnCRM shows and offers everywhere
(see [Editions](editions.md)). In a new install the edition is already chosen in the
first-run setup window, so this step shows it read-only; the choice below appears only in an
org where no edition was ever saved and the window was not shown.

- **Standard Edition**: the full core suite of tools, including households, people, organizations, relationships, addresses,
  importing and everything else in BarnCRM Core. Nothing more to install.
- **Nonprofit Edition**: everything in the Standard Edition, plus the nonprofit tools, starting with the Giving
  module for gifts, funds and receipts. Giving is a separate package.

Choose one and click **Confirm and continue**.

- **Standard Edition:** the assistant moves on to step two.
- **Nonprofit Edition, Giving already installed:** the step says "Giving is installed. Its
  steps are part of this setup." Click **Next**.
- **Nonprofit Edition, Giving not installed yet:** the step stays open and says "The
  Nonprofit Edition needs the Giving module, which is not installed yet." Click **Open the
  Giving installer**. Salesforce's install screen opens in a new tab: choose who to install
  for (**Install for Admins Only** is the safe choice; you give people access in step five),
  click **Install**, and wait for the email that says it finished. Come back to this tab and
  click **Check again**. The step now says Giving is installed, and Giving's own steps join
  the assistant.

BarnCRM never installs anything for you: Salesforce does not let one app install another, and
you should see and approve what goes into your org. If the step says "The Giving install
link is not published yet.", there is no installable version of Giving to link to yet: click
**Read about Giving**, and ask whoever gave you BarnCRM for the install link.

Choosing an edition loads no sample data and changes no records. With the Nonprofit Edition,
step seven also offers the nonprofit modules; with the Standard Edition, BarnCRM shows none of
them.

Once an edition is saved, this step shows it read-only ("Edition: Standard Edition", for
example) instead of the choice, even after **Start again**. The **Edition** setting, in the
General section of BarnCRM Settings, shows the same choice; to change it later, follow
[Editions](editions.md).

**What Maria sees:** both editions, with **Nonprofit Edition** already selected because Giving
is installed in her org. She clicks **Confirm and continue**, reads "Giving is installed",
and clicks **Next**.

**What she decides:** which edition fits her organization.

### Step 2: Confirm how BarnCRM fits your org

The step reads: "If your org uses Person Accounts, household membership uses the flexible way
of belonging, with one membership record per person, so that what you already have keeps
working. Confirm that here, or choose a different fit." BarnCRM then looks at your org and tells you what it found, in plain words:

- **"Your org uses Person Accounts. Household membership is tracked with one record per
  person, so a person can be in more than one household and everything you already have
  keeps working."** This is Maria's case. BarnCRM recommends **Standalone** and proposes
  a membership record for each person, because a person stored as an account needs one.
  Your existing records keep working exactly as they do today. Confirming switches
  household membership to those membership records, unless an administrator already chose
  a way of belonging, which is never overwritten. From then on saving a new person creates
  their household and their membership of it, exactly as it does in the simple mode. The
  switch that governs that is "create a household automatically" on the Households page of
  BarnCRM Settings.
- **Only in an org with Salesforce Nonprofit Cloud:** when BarnCRM finds Nonprofit Cloud
  objects, it recommends **Nonprofit Cloud coexistence**, with a membership record for
  each person as above. See [Nonprofit Cloud households](nonprofit-cloud-households.md).
- **Only in an org with NPSP: "NPSP is installed in this org."** BarnCRM recommends **NPSP
  coexistence**, which records that NPSP is here. In this version it changes no behaviour:
  BarnCRM builds its own households and leaves NPSP's alone.
- **"This looks like a fresh org, with no other household model and no Person Accounts.
  BarnCRM can run on its own."** BarnCRM recommends **Standalone**, the simplest
  arrangement.

The list of modes offers **Standalone** in every org, **NPSP coexistence** only when NPSP
is in your org, and **Nonprofit Cloud coexistence** only when Nonprofit Cloud objects are
in your org. A mode you saved earlier is always in the list, so your choice is never
hidden. The **Coexistence mode** setting, in the General section of BarnCRM Settings,
offers the same list. See [Coexistence mode](coexistence-mode.md).

Read the recommendation, then click **Confirm and continue**. If you know something the
detection cannot see, choose a different mode from the list first and then confirm.

**What Maria sees:** the sentence about Person Accounts, **Standalone** already selected,
and one button. She clicks it. Two seconds.

**What she decides:** nothing, unless she disagrees with the detection.

### Step 3: Confirm how households are named

The assistant opens the household naming settings inside the step, with the live preview.
Choose the pattern for the household name, the formal greeting, and the informal greeting,
and watch five sample households, which ship with the product, change as you type.

Click **Save**, and the step completes itself. If your org does not have the household
naming screen yet, the step says so and tells you that BarnCRM will name households
with the pattern it ships until you change it.

**What Maria sees:** `The Smith Family`, `Mr. and Mrs. John Smith`, `John and Jane`. She
tries `Smith Household` in the name box, sees it in the preview, decides she prefers the
default, and puts it back.

**What she decides:** whether her households are a Family or a Household. That is genuinely
the whole decision.

### Step 4: Pick your default fund and appeal (Giving)

This step comes with the **Giving** module, which is a separate package. Without Giving the
step is not there at all, and the assistant goes straight from naming to access.

You get two pickers: the fund a gift belongs to when nobody says otherwise (usually your
general operating fund) and the appeal it is credited to (usually a general or unsolicited
appeal). Choose them and click **Save**. The pickers only offer real funds and appeals, and
anything else is refused, so a default can never point at the wrong kind of record. If you
install Giving after finishing setup, this step appears as **To do** the next time you open
the home page.

A new org already has a **General Fund**, created at install and set as the default, so the
fund picker opens with **General Fund** chosen and the step counts as done once you reach
it. Change it only if another fund should catch undesignated gifts. If the org already had
funds or a default when Giving was installed, nothing is chosen for you.

**What Maria sees:** her General Fund, already chosen, and her Unsolicited appeal in the
pickers. She picks the appeal and clicks **Save**.

**What she decides:** where a gift goes when nobody says.

### Step 5: Give your colleagues access

Pick one person, pick a role, and click **Give access**. The step confirms with "Access
given. Add another person, or continue.", and the person box clears so you can do the next
one. Give access to as many colleagues as you like, one at a time. The roles are:

| Role | Who it is for |
|---|---|
| BarnCRM Admin | Maria: everything, including settings |
| Fundraising Staff (comes with Giving) | David: gifts, donors, receipts |
| Team Member | Priya: day to day work with people and households, plus programs and services when that module is on |
| Coordinator | Whoever schedules people: shifts and hours when the Volunteers module is on |
| Read Only | Tom and Jen: see everything, change nothing |

The person has to exist as a Salesforce user first. If someone is missing from the list,
click **Create a user in Setup**, create them there, come back, and refresh the step.

If you add people often, the step's **Set up automatic access** link opens
[Automatic access](automatic-access.md): a Salesforce user access policy, created once in
Setup, that gives each new user with your staff profile a role without this step.

**What Maria sees:** her four colleagues in the picker. She gives David the Fundraising
Staff role and Tom the Read Only role. The step marks itself done.

**What she decides:** who gets to change settings. Give that to as few people as the work
allows: settings change how the whole org behaves.

### Step 6: Set your organization's identity

This is the form the "before you start" list was for. Core asks for two things:

- **Legal name**, exactly as on your official filings, not your nickname.
- **Organization address**, as you want it printed, in one block laid out like a Salesforce
  address: **Street**, **Street 2**, then **City**, **State** and **Zip Code** on one row, then
  **Country**. You can leave the whole address blank. Once you fill in any part, **Street**,
  **City**, **State** and **Zip Code** are required and are marked as required; **Street 2**
  and **Country** are optional. If a required part is missing when you click **Save**, the
  step tells you which and saves nothing.

With the Giving module installed, the same form also asks for what your receipts print:

- **Tax identification number** (EIN in the United States).
- **Logo**: click **Upload logo** and choose the file. The logo appears under the button
  once it has uploaded, so you can see what your receipts will carry.
- **Signature image**: the same, for the scanned signature on receipt letters.
- **Signer name and title**, for example `Ana Ruiz` and `Executive Director`.

Click **Save**. The step completes when the legal name is filled in, because that is the
one a letter (or, with Giving, a receipt) cannot be printed without.

Two things to know about the uploaded files. They are stored as Salesforce files owned by
whoever uploads them, and they are attached to that person's user record, because
Salesforce requires an uploaded file to be attached to a record and there is no better
record to attach a logo to. Two consequences: keep the person who uploads the logo as an
active user, and if the logo needs to change, upload the new one rather than editing the
old file.

**What Maria sees:** five boxes, two upload buttons, and the logo and signature themselves
once they are uploaded. The tax identification number box says what one looks like
(`12-3456789`) and tells her to leave it blank outside the United States.

**What she decides:** which name is the legal one. If you have a "doing business as" name,
the legal name goes here and your everyday name goes on the letter text later.

### Step 7: Choose which modules to turn on

A list of the BarnCRM packages that fit your org. Each says **Present** or **Not
installed**, with a **What this module does** link to that package's description (its README on
GitHub). A module that is not installed and has a published version also has an
**Install** link, which opens Salesforce's installer for it in a new tab.

- With the Standard Edition chosen in step one (or no edition chosen), the list shows Core
  and BarnCRM Rollup Builder, plus any module that is already installed. It offers no
  nonprofit modules.
- With the Nonprofit Edition chosen, it shows all seven: Core, BarnCRM Rollup Builder, BarnCRM
  Giving, BarnCRM Volunteers, BarnCRM Programs, BarnCRM Funders, and BarnCRM Mirror.

Core is always present. The rest are separate packages, and a module that is not installed
leaves nothing behind in your org: no objects, no tabs, no automation. Installing one means
opening its install link and following the Salesforce install screens yourself: the
assistant never installs anything for you.

To turn an installed module on or off, or to see what uninstalling one would delete, use the
[Module Manager](module-manager.md): the **Modules** section of BarnCRM Settings.

Click **Next** when you have read it. The step marks itself done.

**What Maria sees:** all seven packages, Core and Giving present, the other four not
installed. She makes a note to read about Volunteers this afternoon.

### Step 8: Bring in your data

Two buttons, and you may use either, both, or neither:

- **Load the sample data** puts about two hundred realistic households, people, and
  organizations in your org so you can practise on something that is not your real data.
  You can remove it again from the same panel.
- **Import a spreadsheet** opens the Import tab, where you upload your file, map your
  columns, run a preview, and see what would happen before anything is created.

If the Import tab is not in your org yet, the step says so rather than sending you to a
page that does not exist, and the same is true of the sample data loader.

**What Maria sees:** both buttons. She loads the sample data, because her real export is
still being cleaned up.

**What she decides:** practise first, or go straight to the real thing. Practise first.

### Step 9: Check that everything works

Follow the short walkthrough: add a person and see their household appear. With the Giving
module installed, the step also has **Enter your first gift**, which opens the Giving
module's own gift entry screen: enter one gift, save it, and you have proved the whole chain
works, from donor to household to gift. Come back to the home page afterwards and click
**Finish**.

Click **Finish**. The assistant shows the completion screen: every step with its status,
and how long setup took, measured from the first change you made.

**What Maria sees:** "You are ready", her nine steps, and "Time taken: 21 minutes". Two buttons sit
under the summary: **Reopen setup** walks the steps again with her answers intact, and
**Start setup again** forgets the progress it recorded so the checklist starts from the
first step. Neither of them empties a setting: a step whose answer is already saved stays
finished, because it is.

## Common mistakes

- **Treating Skip for now as done.** Skipping moves you on without marking the step
  finished, on purpose. A skipped step shows a **Skipped** badge, not **Done**, and the next time you open
  the home page the assistant opens on it again.
- **Marking coexistence mode and then changing your mind quietly.** Changing the mode later
  is allowed and is a real change: it changes how household membership is tracked from that
  point on. Change it on the BarnCRM Settings page, read the note there first, and do it
  before you import, not after.
- **Uploading the logo from a colleague's login, then deactivating them.** The file belongs
  to the person who uploaded it. Upload the logo and the signature from an account that
  will stay active, ideally the administrator's.
- **Putting the everyday name in the legal name box.** Letters (and, with Giving, receipts)
  have to carry the name your official filings carry. If they differ, the legal name goes in step six.
- **Expecting the assistant to install a module.** No app can install another package for
  you. Step one and step seven open Salesforce's installer in a new tab, where you click
  through the install yourself. A module's steps (Giving's, for example) appear once you
  come back and click **Check again**, or reload the home page.
- **Choosing the Nonprofit Edition and closing the installer tab before it finishes.** The
  edition is saved, but Giving is not installed until Salesforce's install email arrives.
  Open the installer again from step one, or from step seven.
- **Looking for the edition choice after step one.** The step shows the saved edition
  read-only. Change it in BarnCRM Settings, as [Editions](editions.md) describes.
- **Re-running setup to fix one thing.** You do not have to. Every answer is on the
  BarnCRM Settings page, grouped by section, with a search box. Reopen the assistant when
  something big changes, such as a new fiscal year or a merger, not to correct a typo.
