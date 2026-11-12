# LWC Builder

Scripts for the optional BarnCRM LWC Builder module: the grid canvas builder, the packaged
component on Lightning pages, its blocks, buttons, visibility rules and source export. Setup
detail: [LWC Builder](../admin-guide/lwc-builder.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and LWC Builder
deployed and the module turned on in BarnCRM Settings, **Modules**. You need an admin (BarnCRM
Admin) and a second user with the Team Member role, called the staff user below, plus a contact
with an email and phone, and a summary report (for example any shipped BarnCRM report grouped by
a field).

## T-LB-01: Install, Access and the Builder Tab

**Purpose:** confirm setup gives access and the tab is for admins.
**Prerequisites:** admin and staff user.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | As admin, open the BarnCRM app. | An LWC Builder tab, before Error Log. |
| 2 | Open Setup, the staff user's permission set assignments. | LWC Builder Staff is assigned (within the hour, or after Finish Setup). |
| 3 | As the staff user, open the BarnCRM app. | No LWC Builder tab. |
| 4 | As admin, open BarnCRM Settings, **LWC Builder**. | Show built components On, Rows per list 10, Allow source export On. |

**Cleanup:** None.

## T-LB-02: Build, Preview and Save

**Purpose:** confirm the grid canvas, drag and drop, keyboard moves, preview and save.
**Prerequisites:** admin.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open LWC Builder, press **New Component**, name it *Donor Snapshot*, Object `Contact`. | The key shows `Donor_Snapshot`. |
| 2 | Press **Add Section**, title it *At a Glance*; press **Add Row**, layout **6 + 6**. | One section with two equal columns. |
| 3 | Drag **Record Fields** into the left column; choose Email and Phone. | The block shows in the left column with its title. |
| 4 | Drag **Text** into the right column, then drag the Text block onto the left column. | The Text block moves to the left column. |
| 5 | Select the Text block, press **Next Column**, then **Up**. | It moves to the right column, then stays first (it is the only block). |
| 6 | Press **Preview** and paste the contact's Id in Preview record. | The contact's email and phone show; the text shows on the right. |
| 7 | Press **Save**. | A message that the component is saved, version 1. Save again: version 2. |
| 8 | Create a second component with key `Donor_Snapshot`. | Refused: the key is already used. |

**Cleanup:** None (T-LB-03 uses the component).

## T-LB-03: Place the Component and Read as the Viewer

**Purpose:** confirm the packaged component, user-mode reads and the master switch.
**Prerequisites:** after T-LB-02; the staff user cannot read the contact's Phone field (field-level security).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the contact, **Edit Page**, drag **BarnCRM Built Component** on, pick *Donor Snapshot*, save and activate. | The component shows on the page. |
| 2 | As the staff user, open the contact. | Email shows; Phone does not. |
| 3 | As admin, clear **Active** on the component and save. | The component no longer shows on the page. Set it back. |
| 4 | Turn **Show built components** off in Settings. | Nothing shows where it is placed. Turn it back on. |

**Cleanup:** None.

## T-LB-04: Lists and Charts

**Purpose:** confirm Related List, Record List and Report Chart blocks.
**Prerequisites:** admin; the component from T-LB-02.

| Step | Action | Expected result |
|---|---|---|
| 1 | Add a Related List block: object `Contact`, parent field `ReportsToId`, fields Name and Email. | In preview, the contacts that report to the preview contact; names link to their records. |
| 2 | Add a Record List block: object `Contact`, fields Name and Email, filter MailingCity equals your test city, sort Name. | Only contacts in that city, sorted, at most 10 rows. |
| 3 | Change the Record List field to `Not_A_Field__c`. | The block says the field is not on the object; the rest of the component still shows. |
| 4 | Add a Report Chart block with the summary report's API name. | One bar per grouping with its value. |
| 5 | Enter a tabular report's API name. | The block says the report cannot be charted. |
| 6 | Point the chart at a summary report grouped by two fields (for example Stage, then Fiscal Year) with two summaries (for example Sum of Amount and Record Count). | Each group shows each total by name, with one bar per value of the second grouping and a legend; each total has its own scale. |
| 7 | Tick **Stack the second grouping**. | Each total is one bar per group, split into colored parts that match the legend; the total shows at its end. |
| 8 | Press **Show Table**, then **Show Chart**. | A table with a row per group and a column per second-grouping value and total, with the report's formatted values; then the bars again. |
| 9 | Use a matrix report (rows by one field, columns by another). | Rows are the groups and columns the bars or stacked parts. |

**Cleanup:** Fix the Record List field.

## T-LB-05: Buttons

**Purpose:** confirm quick actions and flows launch as the user.
**Prerequisites:** admin; a screen flow with a `recordId` text input variable that shows it.

| Step | Action | Expected result |
|---|---|---|
| 1 | Add a Button block: Quick action `Global.NewTask`, label *New Task*. | On the contact page, the button opens the New Task window. |
| 2 | Add a Button block: Flow, the flow's API name, Pass the record Id ticked. | The flow opens inside the card and shows the contact's Id. |
| 3 | As a user who may not run the flow, press the button. | Salesforce's own message; nothing runs. |

**Cleanup:** None.

## T-LB-06: Show or Hide a Block

**Purpose:** confirm field and permission rules.
**Prerequisites:** admin; the component on the contact page.

| Step | Action | Expected result |
|---|---|---|
| 1 | Set the Text block's visibility to Field value: MailingCity equals your test city. | Shown on a contact in that city; hidden on one elsewhere. |
| 2 | Set it to Permission: holds `LWC_Builder_Not_Real`. | Hidden for everyone. |
| 3 | Set it to Permission: does not hold `LWC_Builder_Not_Real`. | Shown. |

**Cleanup:** Set it back to Always.

## T-LB-07: Export as LWC Source

**Purpose:** confirm the exported bundle and the setting.
**Prerequisites:** admin; the component from T-LB-02.

| Step | Action | Expected result |
|---|---|---|
| 1 | Press **Export**. | Three files: `donorSnapshot.html`, `donorSnapshot.js`, `donorSnapshot.js-meta.xml`, each with Download. |
| 2 | Read the HTML. | `lightning-output-field` for each Record Fields field; a comment for each list or chart block. |
| 3 | Turn **Allow source export** off in Settings and reload the builder. | No Export button. Turn it back on. |

**Cleanup:** None.
