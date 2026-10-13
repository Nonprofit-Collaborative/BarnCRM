# Your own version of an automation

## What it does

Every piece of automation BarnCRM ships has a switch on the **Automation** page of BarnCRM
Settings. Sometimes an automation does almost what your organization wants, but not quite:
you want the other side of a relationship written only for family connections, or you want a
different rule for which affiliation counts as primary.

You do not edit BarnCRM's automation to get that. An upgrade would put ours back and your
change would be gone without warning. Instead you switch ours off and run your own. For every
automation that a flow can do, BarnCRM ships a **flow template**: a flow that does the same
work ours does, which you copy, change, and switch on. Your copy belongs to you. Upgrades
never touch it, and never touch your switch settings either.

Some automations do not have a template, because they cannot be done well as a flow. The table
under "Which automations have a template" says which, and why.

## How to turn it on

The templates arrive with Core. There is nothing to install and nothing to enable: until you
copy one and activate your copy, a template does nothing at all.

Making your own version is the one task in BarnCRM that happens in Salesforce Setup, because
that is where Flow Builder, the Salesforce tool for building flows, lives. BarnCRM cannot
offer it anywhere else.

1. In Setup, search for **Flows** and open it.
2. Choose **New Flow**, then the **Templates** tab (in some orgs it is **All Templates**).
3. Search for **BarnCRM template**. Each template's name starts with those words and then
   names the automation it copies, using the same words as the Automation page.
4. Open the one you want and choose **Save As**, then **A New Flow**. Give it a name of your
   own, for example "Our relationship sides".
5. Change your copy. Each template has a description on every step saying what that step is
   for, so you can see where to add your own condition.
6. Choose **Activate** on your copy.
7. Open **BarnCRM Settings**, then **Automation**, and switch our version **Off**. Do this
   straight after step 6. While both are on, the same work is done twice.

### Which automations have a template

| On the Automation page | Template | Why there is no template |
|---|---|---|
| Keep the address an account started with | BarnCRM template: Keep the address an account started with | |
| Check affiliations before they are saved | BarnCRM template: Check affiliations before they are saved | |
| Keep one primary affiliation per person | BarnCRM template: Keep one primary affiliation per person, and BarnCRM template: Keep one primary affiliation per person (delete) | |
| Check relationships before saving | BarnCRM template: Check relationships before saving | |
| Keep both sides of relationships in step | BarnCRM template: Keep both sides of relationships in step, and BarnCRM template: Keep both sides of relationships in step (delete) | |
| Household upkeep when a person changes | None | Creating households, counting members, naming and greeting households, and tidying away empty ones depend on how your organization holds household membership (BarnCRM Settings, Households). It is one piece of work spread across three objects, and a copy that got any part of it wrong would leave households miscounted or misnamed. Use the household settings instead. |
| Household upkeep on household changes | None | The same household upkeep, from the household side. |
| Household upkeep on membership changes | None | The same household upkeep, from the membership side. |
| Keep households together on a move | None | Which household a person's new address goes to depends on how your organization holds household membership, and on the **Addresses** setting. A flow cannot read either the way BarnCRM does. Change the Addresses setting instead. |
| Copy default address to standard fields | None | The copy reaches every member of a household, in either way of holding household membership, people held as accounts in orgs that use them, and seasonal addresses. A flow in Core cannot name the fields of a person held as an account, because an org without them would refuse to install BarnCRM. |
| Update rollups when a person changes | None yet | Totals are worked out by the rollup engine. A flow that runs the engine for records you choose arrives with the next rollup update: see "Rollups on your own objects" below. |
| Update rollups when membership changes | None yet | The same as above. |
| Check rollups before saving | None | It checks a rollup definition against the field it fills, which only BarnCRM's rollup engine knows how to read. A flow copy could let a rollup save that the engine then skips on every run. Leave it on, or switch it off and read the Error Log. |

With Giving, Giving's automations are listed on the same page. Their templates are not built
yet, and this page lists them when they are.

## A five-minute walkthrough

Maria's organization records family connections, colleagues, and friends as relationships, but
it only wants the other side written for family. A colleague relationship should stay on the
one person who entered it.

1. In Setup, open **Flows**, choose **New Flow**, then **Templates**, and search for
   **BarnCRM template**.
2. Open **BarnCRM template: Keep both sides of relationships in step** and choose **Save
   As**, then **A New Flow**. Name it "Our relationship sides" and save. You now have your own
   flow. The template is unchanged.
3. Open the start of your flow (the box at the top) and look at **Entry Conditions**. Add a
   condition: **Type** **Does Not Equal** **Colleague**. Save.
4. Choose **Activate**.
5. Open **BarnCRM Settings**, then **Automation**, and switch **Keep both sides of
   relationships in step** to **Off**. Leave **Check relationships before saving** on: the
   checks are a separate automation and yours does not replace them.
6. Copy **BarnCRM template: Keep both sides of relationships in step (delete)** the same
   way, name it "Our relationship sides (delete)", and activate it.
7. Starting from the sample data, open **The Garcia Family** and choose **Harper Garcia**.
   On the **Relationships** card add a relationship: **Diego Garcia**, type **Child**. Open
   Diego's record: his card reads "Harper Garcia, Parent", written by your flow.
8. Back on Harper's record, add a relationship to anyone in another household, type
   **Colleague**. Open that person's record: nothing was written, because your flow leaves
   colleagues alone.
9. Delete the Diego line from Harper's card. Open Diego's record: his line is gone too,
   removed by your delete flow.

To go back to BarnCRM's version at any time, switch ours **On** and then deactivate yours.

## What a template does differently from ours

A template does the same work as ours with the tools a flow has. Those tools are not the same
as ours in a few places, and you should know where before you switch ours off.

- **A pause does not stop your flow.** **Pause all automation** on the Automation page pauses
  BarnCRM's automation only. Your flow keeps running during a pause, as every flow you build
  does. To stop it during an import, deactivate it, and activate it again afterwards.
- **Your flow does not look at our switch.** BarnCRM's own automation checks its switch on the
  Automation page every time it runs. A copy of a template does not: activating and
  deactivating your flow is its switch.
- **A flow cannot run when a record is restored from the recycle bin.** BarnCRM writes the
  other side of a restored relationship, and settles the primary affiliation when an
  affiliation is restored. Your copy does neither. After restoring, open the record and save it
  once.
- **A flow sees one record at a time.** Our checks compare all the records in one save with
  each other, so an import with the same relationship in it twice is refused. The check
  templates compare each record with what is already saved, so two copies arriving in the same
  import are both let through. Remove duplicates from a file before you load it.
- **Deleting both sides of a relationship in one go can be refused.** Our version notices that
  both sides are going and does nothing extra. The delete template cannot tell, and Salesforce
  may refuse the delete with a message that a record is already being deleted. Delete one side:
  the other goes with it.
- **Moving an affiliation to a different person.** Ours refreshes the Primary Affiliation
  field on both people. A copy of the template refreshes the person the affiliation now
  belongs to; the first person's field catches up the next time one of their affiliations is
  saved.
- **The relationships template does not read Keep both sides of relationships in step in
  BarnCRM Settings.** Activating your flow is the choice.
- **Two people editing both sides of one relationship in the same save.** Ours lets one of
  the two edits win, always the same one. A copy of the template keeps whichever
  edit is written last.

## Rollups on your own objects

The rollup update that is coming adds a flow action, **Recalculate rollups for these
records**, and a template, **BarnCRM template: Recalculate rollups**, for totals that come
from an object your organization added itself. BarnCRM can only keep totals up to date
instantly for objects it ships. For your own object you will copy the template, point it at
your object, and activate it. Until then, set rollups from your own objects to **Every
night** on the **Rollups** page.

## Common mistakes

- **Editing the template instead of a copy.** An upgrade replaces the template, and your
  change with it. If the flow you are changing is still named "BarnCRM template", you are in
  the template: choose **Save As**, then **A New Flow**, and change the copy.
- **Leaving ours on as well.** Both run, and the work is done twice. For relationships the
  second attempt to write the other side is refused as a duplicate, and the person saving sees
  a message that the person already has this relationship. Switch ours off on the Automation
  page.
- **Switching off a check and not copying it.** The two check automations, for affiliations
  and relationships, are what stop an import from creating duplicates. Switch one off only when
  your own copy of it is active.
- **Expecting a pause to stop your flow.** It does not. Deactivate your flow for the import,
  and activate it again afterwards.
- **Copying only half a pair.** Relationships and affiliations each have a template for saving
  and a second one, ending "(delete)", for deleting. If you switch ours off and copy only the
  first, nothing happens on a delete.

## Reference

For whoever maintains your flows. The API name is what a deployment or a change set uses.

| Template | API name | Runs on | When |
|---|---|---|---|
| Keep the address an account started with | `Template_Account_Address_Capture` | Account | After a household or organization is created |
| Check affiliations before they are saved | `Template_Affiliation_Validation` | Affiliation | Before an affiliation is created or changed |
| Keep one primary affiliation per person | `Template_Affiliation_Primary` | Affiliation | After an affiliation is created or changed |
| Keep one primary affiliation per person (delete) | `Template_Affiliation_Primary_Delete` | Affiliation | Before an affiliation is deleted |
| Check relationships before saving | `Template_Relationship_Validation` | Relationship | Before a relationship is created or changed |
| Keep both sides of relationships in step | `Template_Relationship_Reciprocal` | Relationship | After a relationship is created or changed |
| Keep both sides of relationships in step (delete) | `Template_Relationship_Reciprocal_Delete` | Relationship | Before a relationship is deleted |
| Recalculate rollups (coming with the rollup update) | `Template_Recalculate_Rollups` | Your object | After a record is saved, and before it is deleted |

A template's API name is `Template_` followed by the name of the automation it copies, and
`_Delete` for the delete half, so a template can always be matched to its row on the
Automation page.
