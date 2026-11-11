# Field History

## What It Does

**Field History** keeps every change to the fields you choose on BarnCRM's own records, for as
many fields as you like. Salesforce's own field history stops at 20 fields per object and 18
months; Field History has neither limit, and costs nothing extra.

Each save that changes a chosen field is kept once, with who saved it, when, and each changed
field's value before and after. The record's **Field History** card lists them, newest first.
A BarnCRM admin can put an earlier value back with **Restore**.

Field History covers BarnCRM's own objects that run a BarnCRM trigger: addresses, funds,
programs, gifts, shifts and the like. It does not cover standard objects such as Contact and
Account; use Salesforce's field history for those (Setup, Object Manager, the object, Fields
and Relationships, Set History Tracking).

## How to Turn It On

It is off on a new install.

1. In **BarnCRM Settings**, open **Field History** and turn on **Turn On Field History**. Save.
2. In **BarnCRM Settings**, **Custom Metadata**, open **History Fields** and add one entry per
   field, named as the object and the field with a dot: `Address__c.City__c`,
   `Fund__c.Description__c`. Leave out any namespace. Saving needs BarnCRM Admin (or
   BarnCRM Metadata Admin), as every Custom Metadata entry does; see
   [Custom Metadata](custom-metadata.md).
3. Add the **Field History** card to the record pages of those objects in Lightning App
   Builder, or open the record's **Record Inspector**, which shows it below the fields.

A field is refused when it cannot be kept: a formula, roll-up summary, auto number, long text
area or rich text field, a field of an object without a BarnCRM trigger, or a name that is not
a field. To stop keeping a field, archive its entry.

## Settings

Both are in **BarnCRM Settings**, **Field History**, and apply to the whole organization:

- **Turn On Field History** (default off): keeps the changes to the chosen fields.
- **Days to keep field history** (default 730, accepted 30 to 3650): the nightly
  **Record Cleanup** job deletes kept changes older than this. See
  [Nightly Jobs](nightly-jobs.md#how-long-history-is-kept).

## What Is Kept, and When

- A change is kept when a record is saved and a chosen field's value differs from before. A new
  record is not a change; its first edit is.
- Nothing is kept while automation is paused for everyone, or for a person with **Bypass for
  me** (see [Automation Control](automation-control.md)).
- A text value longer than 1,000 characters is kept cut short, marked as cut, and cannot be
  restored.
- Keeping a change never stops a save. If it cannot be kept, the reason goes to the
  [Error Log](error-log.md).

## Who Sees It

Anyone who can open the record sees its Field History card, with only the fields they can
read. The kept changes themselves are BarnCRM's private records: no one reads or reports on them
directly.

**Restore** is shown only to people with Manage BarnCRM Settings (BarnCRM Admin). It asks to
confirm, then saves the earlier value on the record as you, so your field access and the
object's validation rules apply. The restore is itself kept as a change.

## Health Check

While Field History is on, Health Check warns when no field is chosen, or when a chosen field
can no longer be kept (deleted, or changed into a formula, for example), and names it.

## Common Mistakes

- **No changes appear.** Check the setting is on, the field has an active History Fields entry,
  and automation is not paused.
- **A change made by a data load is missing.** A load run with automation paused keeps no
  history, by design.
