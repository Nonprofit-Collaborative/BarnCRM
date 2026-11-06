# Custom Metadata

## What It Does

Some of the lists BarnCRM works from are kept as custom metadata, the part of Salesforce
that travels with the app. The **Custom Metadata** page in BarnCRM Settings lets you add
your own entries to the lists that are meant to be extended, change them, and archive them,
without opening Salesforce Setup.

The first list is **Relationship types**: what the other side of a relationship becomes.
BarnCRM ships eleven types (Spouse, Parent and Child, and so on). If your organization
records godparents, mentors, or guardians, you add the pairs here and BarnCRM keeps both
sides in step for them the same way it does for its own.

The second list is **Merge Rules**: which value wins, field by field, when auto-merge merges
two people (see [Duplicates](duplicates.md#merge-rules)). BarnCRM ships none; a field with no
rule follows the **Merge rule for other fields** setting.

Match sources, the related records the duplicate scan and imports compare, are custom
metadata too, but they have their own editor: the **Matching Logic** area of the
**Duplicate Matching** tab (see [Duplicates](duplicates.md#matching-logic)). It saves the
same way and needs the same permission set and Setup step as this page.

The entries BarnCRM ships are shown on the same page, marked **Shipped with BarnCRM**,
and cannot be changed. Upgrades keep them up to date, and they never overwrite what you
added. A shipped relationship type your organization does not use can be turned off (see
[Turning Off a Shipped Relationship Type](#turning-off-a-shipped-relationship-type)).
The Relationship types list is shown only while the **Relationships** feature is on
(BarnCRM Settings, General, Features).

## How to Turn It On

The page is for administrators who can already change the org in Setup, because saving an
entry changes the org's metadata.

1. **BarnCRM Admin** already includes the permission to save here. Someone who is not a
   BarnCRM Admin needs the **BarnCRM Metadata Admin** permission set (BarnCRM Settings,
   Access, Extra Permissions); it is in no role on purpose. Without either you do not see
   the page at all.
2. If BarnCRM was installed as a package, Salesforce asks once whether the app may change
   metadata. In Setup, open **Apex Settings** and turn on **Deploy Metadata from
   Non-Certified Package Versions via Apex**. This setting is in Setup only, and BarnCRM
   cannot turn it on for you or read it: it is Salesforce's own safeguard. If it is off, a
   save fails with "Salesforce did not accept the change, so nothing was saved. If BarnCRM
   was installed as a package, turn on Deploy Metadata from Non-Certified Package Versions
   via Apex in Setup (Apex Settings), then save again. The Error Log has details." Where
   BarnCRM was deployed as source, the setting is not needed.
3. Open the **BarnCRM Admin** app, click **BarnCRM Settings**, choose **General**, and scroll to
   **Custom Metadata**.

A relationship type also has to be a choice in the **Type** list on a relationship, and
adding a choice to that list is done in Setup (Object Manager, Relationship, Fields, Type).
Add the choice there first, then add the type here. The page checks this and tells you if
the choice is missing. The **Reciprocal Type** field on a relationship needs nothing: BarnCRM
fills it in from your type, so it accepts any type you have added to **Type**.

## A Five-Minute Walkthrough

Maria's organization runs a mentoring program and wants to record who mentors whom. Each
mentor's record should say who they mentor, and each mentee's record should say who mentors
them.

1. In Setup, open **Object Manager**, **Relationship**, **Fields & Relationships**,
   **Type**, and add two values: `Mentor` and `Mentee`. Save.
2. Open **BarnCRM Settings**, **General**, **Custom Metadata**. Under **Relationship
   types** you see two tables. **Added by Your Organization** is empty. **Shipped with
   BarnCRM** lists the eleven types; each one's menu offers only **Turn Off**.
3. Click **Add**. Fill in:
   - **Name**: Mentor
   - **Type**: Mentor
   - **Reciprocal Type**: Mentee
   - **Description**: Someone who mentors this person through the program.
   Click **Save**. The page says "Saving. Salesforce applies the change in the
   background, usually within a minute." When it is done it says "Saved. Mentor is in the
   list." and the row appears under **Added by Your Organization**, with the status
   **In use**.
4. Click **Add** again and add the other side: **Name** Mentee, **Type** Mentee,
   **Reciprocal Type** Mentor. Save and wait for "Saved".
5. Open a person, add a relationship of type **Mentor** to someone else, and save. Open
   the other person: their card reads **Mentee**. Before step 3 it would have read
   **Other**.
6. Back on the Custom Metadata page, open the menu at the end of the Mentee row and choose
   **Archive**. Once it says "Saved", the row's status is **Archived** and BarnCRM stops
   using it: a new Mentee relationship gets **Other** on the other side. Choose
   **Restore** from the same menu to bring it back.
7. Scroll to **Recent Changes** at the bottom of the page. Each save is listed with your name and the
   values before and after.

## Common Mistakes

- **Adding the type here before adding the choice in Setup.** The save is refused with
  "Mentor is not a choice in the Type list on Relationship. Add it in Setup (Object
  Manager, Relationship, Fields, Type), then save again." Add the choice and save again.
- **Adding only one side.** BarnCRM writes the reciprocal type on the other person, and
  reads that type's own row whenever the other person's side is saved. Add both rows (Mentor
  to Mentee, and Mentee to Mentor). A type you add that is its own reciprocal, such as
  Neighbor to Neighbor, needs one row.
- **Trying to change a shipped type.** A shipped type can only be turned off and on. To use
  a different reciprocal for one of them, turn it off and add your own row for the same
  Type, or add your own type with a different name, for example `Employer` instead of
  `Employer contact`. A type can have only one active row, so the page refuses a second
  row for a type that already has one, and refuses to turn a shipped type back on while
  your own row for that Type is in use.
- **Expecting Delete.** There is no delete. Salesforce does not let an app delete custom
  metadata, so you archive an entry instead, and it stops being used. An archived entry can
  be restored. To remove it for good, delete it in Setup (Custom Metadata Types,
  Relationship Type, Manage Records).
- **Leaving the page before "Saved".** The change carries on in the background. Come back
  and click **Check Again**. If it failed, the reason is in the Error Log.
- **Adding the same entry twice before the first save finishes** (in a second tab, or
  after the page says it is still saving). Each new entry gets a short code at the end of
  its API name in Setup, for example `Org_Mentor_k3x9`, so the second add never overwrites
  the first. You may end up with two entries: archive the one you do not want.

## Turning Off a Shipped Relationship Type

If your organization never uses a type BarnCRM ships, for example **Grandparent** and
**Grandchild**, turn it off so nobody picks it by mistake.

1. Open **BarnCRM Settings**, **General**, **Custom Metadata**.
2. Under **Relationship types**, in **Shipped with BarnCRM**, open the menu at the end of
   the row and choose **Turn Off**. The change is saved at once, with no wait: the page says
   "Grandparent is turned off. It is no longer offered for new relationships, and the ones
   that already have it keep it." and the row's status is **Off**.
3. Choose **Turn On** from the same menu to offer it again.

What turning off does:

- The **Type** list on a person's relationship card no longer offers it, and a new
  relationship of that type, or a change to that type, is refused wherever it is saved
  (Salesforce's own edit page, an import, the API) with "Grandparent is turned off for new
  relationships in this organization. Choose another type, or ask your BarnCRM admin to turn
  it back on in BarnCRM Settings, Custom Metadata." Loading sample data skips it.
- Relationships that already have the type keep it, still show it, and both sides stay in
  step.
- BarnCRM still writes the other side of a pair whose other side is turned off. If you turn
  off only Grandchild, a new Grandparent relationship still gives the other person
  Grandchild. Turn off both sides of a pair to stop it entirely.
- The shipped row itself is not changed: BarnCRM lists it as off in a setting. An upgrade
  can still update its name or reciprocal, and never turns it back on.
- Each change is listed under **Recent Changes**, with your name and the list before and
  after.

## Match Sources

Match sources are no longer on this page. They are listed, added, deactivated and tried out
in the **Matching Logic** area of the **Duplicate Matching** tab; see
[Duplicates](duplicates.md#matching-logic). The permission to save
(BarnCRM Admin, or **BarnCRM Metadata Admin**) and the Setup step above apply there too.

## Which Lists Can Be Extended

| List | Here | Why |
|---|---|---|
| Relationship types | Add, edit, archive; turn a shipped one off and on | BarnCRM reads the list directly, so an entry you add is used at once. Shown while the Relationships feature is on. |
| Merge rules | Add, edit, archive | BarnCRM reads the list directly at each merge. |
| Match sources | On the Duplicate Matching tab, Matching Logic: add, edit, deactivate; deactivate and activate a shipped one | BarnCRM reads the list directly when it scans for duplicates and matches an import. |
| Rollups, import templates | No | BarnCRM copies the shipped entries into the Rollups and Import pages, which is where you add and change your own. |
| Automations, settings | No | These describe BarnCRM's own code and pages. An entry you added would point at nothing. |
| Receipt templates (Giving) | No | Copied into the Receipt Letters page, where you edit your own. |
