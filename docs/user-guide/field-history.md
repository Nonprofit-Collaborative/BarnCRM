# Field History

When your administrator has turned on **Field History** for some fields, a record's
**Field History** card shows each change to those fields: when it was made, who made it, and
the value before and after, newest first. You see only the fields you can read on the record.
Setup detail: [Field History](../admin-guide/field-history.md).

## Putting an Earlier Value Back

Only a BarnCRM admin sees **Restore** beside a change. It asks you to confirm, then saves the
earlier value on the record as you, so the record's rules still apply. The restore shows as a
new change at the top of the card.

A very long text value (over 1,000 characters) is kept cut short and marked as cut; it cannot
be restored.

## Why a Change Is Missing

- The field is not one your administrator chose.
- The change was made while BarnCRM automation was paused, for example during a large data
  load.
- The change is older than your organization keeps (two years unless your administrator chose
  otherwise).
