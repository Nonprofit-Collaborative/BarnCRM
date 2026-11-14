# LWC Builder

## What It Does

BarnCRM LWC Builder is an optional module, in either edition, for building your own Lightning
components without code:

- **Grid canvas builder** (LB-01): lay out sections, rows and columns on a 12-column grid, drag
  blocks into them, preview the result with a real record, and save it as a named component.
- **One packaged component** (LB-02): place **BarnCRM Built Component** on any record, app or
  home page in Lightning App Builder and pick which of your components it shows.
- **Building blocks** (LB-03): the page record's fields, a related list, a list of records, a
  chart from a standard report, text and images.
- **Buttons** (LB-04): open a quick action or run a screen flow.
- **Show or hide a block** (LB-05) by a field value on the page record or by a custom
  permission.
- **Export as LWC source** (LB-06): download the component as an LWC bundle for a developer.

Nothing is deployed when you save. A built component is a record (a Built Component) holding
its layout as JSON, and one packaged component draws it. Every block reads as the person viewing
the page, so they never see a record or field they could not open anyway.

## Install and Turn On

LWC Builder depends on BarnCRM Core only. Install it like any module, then turn it on in
BarnCRM Settings, **Modules** (it installs off). The install, and Finish Setup on the Modules
page, gives you and every BarnCRM Admin holder LWC Builder Admin, and gives the module's Staff
and Read Only sets to BarnCRM's other roles (see Access below). Installing changes no page: a
built component shows only where you place it.

The **LWC Builder** tab joins the BarnCRM and BarnCRM Console apps before Error Log, for admins.
LWC Builder has no app of its own.

## Access

| Permission set | Who gets it automatically | What it allows |
|---|---|---|
| LWC Builder Admin | BarnCRM Admin holders | The LWC Builder tab; create, edit and delete built components; export source |
| LWC Builder Staff | Team Member and Fundraising Staff holders | See built components placed on pages |
| LWC Builder Read Only | Read Only holders | See built components placed on pages |

Sets are given, never taken away. Someone with none of these sets sees nothing where a built
component is placed. A built component never grants access: each block shows only what the
viewer's object, field and record access allow.

## Settings

BarnCRM Settings, **LWC Builder**:

| Setting | Default | What it does |
|---|---|---|
| Show built components | On | Whether placed built components show at all. Turn it off to hide every one at once without editing pages. |
| Rows per list | 10 | How many rows a Related List or Record List block shows (1 to 200). |
| Allow source export | On | Whether the builder offers Export as LWC Source. |

## Five-Minute Walkthrough

1. Open the **LWC Builder** tab and press **New Component**. Give it a name, for example
   *Donor Snapshot*; the key fills in from the name. Set **Object** to `Contact` so the preview
   and the field pickers know which record it is for.
2. Press **Add Section** and title it *At a Glance*. In the section, press **Add Row** and pick
   the **6 + 6** layout.
3. Drag **Record Fields** from the block list into the left column. In the block's properties,
   choose Email, Phone and Mailing City.
4. Drag **Related List** into the right column. Set the object to the child object, the parent
   field to its lookup to Contact, and two or three fields to show.
5. Drag **Button** below the related list. Choose **Flow**, enter a screen flow's API name and
   tick **Pass the record Id**, so the flow gets a `recordId` input variable.
6. Press **Preview**, paste a contact's Id into **Preview record**, and check the result. Press
   **Save**.
7. Open a contact, then **Edit Page**. Drag **BarnCRM Built Component** onto the page, pick
   *Donor Snapshot*, save and activate the page.

You can also move a block without dragging: select it and use the arrow buttons in its
properties (up, down, previous column, next column).

## Blocks

| Block | What it shows | Notes |
|---|---|---|
| Record Fields | Fields of the record the page is for | Record pages only. A field the viewer cannot read is left out. Choose one or two columns. |
| Related List | Records whose lookup points at the page record | Name the child object and its lookup field. Up to six fields; sort by any field. |
| Record List | Records of any object | Up to six fields, one optional filter (a field equals, or does not equal, a value), a sort. |
| Report Chart | Bars for a standard summary or matrix report, by up to two groupings with up to three totals | Enter the report's API name (Report Unique Name). The report runs as the viewer. Tabular reports cannot be charted. See Report Charts below. |
| Text | Formatted text | Bold, italic, lists and links. Scripts are removed. |
| Image | A picture | Use a Salesforce address (for example `/resource/YourLogo`) or an `https` address listed in Setup, Trusted URLs. Always fill in the alternative text. |
| Button | Opens a quick action or runs a screen flow | See Buttons below. |

Row and list counts stop at **Rows per list**. A Name field in a list links to the record.

## Report Charts

Build the chart's groupings and totals in the report, then name the report in the block
(release 1.20, D-196).

- **Groupings.** A summary report's first two row groupings, or a matrix report's row grouping
  and column grouping. For example, an Opportunities report grouped by Stage and then by Fiscal
  Year draws a group for each stage with a bar for each year. Up to 200 groups and 12 values of
  the second grouping are drawn.
- **Totals.** Up to three of the report's summaries, in the report's order, for example Sum of
  Amount and Record Count. Each total has its own bars and its own scale.
- **Stack the second grouping.** Ticked, each group shows one bar per total, split by the
  second grouping (a stacked bar); a legend names the colors. Unticked (the default), each
  value of the second grouping has its own bar.
- **Show Table.** Every chart carries a table of the same values for screen readers; viewers
  can press **Show Table** to see it instead of the bars.

The report runs once each time the block loads, as the viewer, so each person sees totals from
the records they can open.

## Buttons

- **Quick action**: enter the action's full name, for example `Global.NewTask` or
  `Contact.Send_Thank_You`. On a record page the action runs for that record. The action must
  be on the object's page layout or in its Lightning actions for the platform to open it.
- **Flow**: enter a screen flow's API name. The flow opens inside the block. With **Pass the
  record Id**, the page record's Id goes to the flow's `recordId` text input variable (create
  it, marked Available for Input, or the flow will not start).

The viewer runs the action or flow with their own permissions. If they may not run it,
Salesforce shows its own message.

## Show or Hide a Block

Each block has a **Visibility** rule:

- **Always** (the default).
- **Field value**: a field on the page record equals, does not equal, contains, is blank or is
  not blank. Record pages only; on other pages the field counts as blank.
- **Permission**: the viewer holds, or does not hold, a custom permission you name by its API
  name.

A rule only decides what is shown. It is not a security control: someone who can open the
record can still see its data elsewhere. Use permission sets and sharing to restrict access.

## Export as LWC Source

In the builder, **Export** turns the open component into an LWC bundle: an HTML file, a
JavaScript file and a `js-meta.xml` file, to download or copy. Every block exports working.

When the component has a Related List, Record List or Report Chart block (release 1.20,
D-196), the export also holds a small Apex controller named after the component (for example
`DonorSnapshotController`) with its test class, and a CSS file when there is a chart. The
blocks read through that controller as the viewer, with the same fields, filter, sort and
report, and as many rows as **Rows per list** allows when you export. The bundle does not
depend on BarnCRM: deploy the controller and its test with it.

Visibility rules export as comments. The exported bundle is for a developer to deploy and
maintain; BarnCRM does not deploy it.

## Moving a Component Between Orgs

A built component is an ordinary record. Export the Built Component records (Name, Key,
Description, Object, Active and Definition) with Data Loader or a report, and import them into
the other org, matching on **Key**. Lightning pages store the key, so a page moved with a
change set keeps finding its component.

## Common Mistakes

- **Nothing shows on the page.** Check that the component is Active, that **Show built
  components** is on, and that the viewer holds an LWC Builder set.
- **A Record Fields block is empty on a home page.** It needs a record page.
- **"This field is not on the object"** in a list block: a field was renamed or deleted; open
  the block and choose it again.
- **A chart says the report cannot be charted.** Use a summary or matrix report with at least
  one grouping and one summary.
- **A chart is missing a grouping or total.** Only the first two groupings and first three
  summaries are drawn; reorder them in the report.
- **An image does not load.** Add its site to Setup, Trusted URLs (Content Security Policy), or
  upload it as a static resource.

## Removing the Module

Uninstalling deletes every Built Component record. Remove the BarnCRM Built Component from your
Lightning pages first, or Salesforce will not let you uninstall.
