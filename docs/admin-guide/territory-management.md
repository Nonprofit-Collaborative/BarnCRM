# Territory Management

## What It Does

BarnCRM Territory Management is an optional module, in either edition, that puts people,
households and organizations into territories by rules you set, and gives each one an owner:

- **Territories** (C-40): a region, a set of postal codes, a donor tier or any other split of
  your records, each with a priority. A record goes to the first territory, by priority, whose
  rule it matches.
- **Rules** (C-40): conditions on a person, household or organization, built with the same
  condition builder as Find: postal code starts with 021, state equals MA, type equals
  Foundation, total giving greater than 10,000, and so on.
- **Owner routing** (C-40b): when a record moves into a territory it can keep its owner, take
  the territory's owner, or go to the territory's members in turn (round robin) or to the member
  with the most room under their capacity.
- **Preview, assign and undo**: Preview shows what would move, to which territory and owner,
  without changing anything. Assign makes the changes and records them as a data job you can
  undo.

Each person, household and organization gets a **Territory** field you can use in list views,
reports, Find and Super Transformer. Territory Management never uses Salesforce's own Enterprise
Territory Management, so it works on a Platform-only org.

## Turn It On

1. Open **BarnCRM Settings**, **Modules**, and turn on **BarnCRM Territory Management**.
2. Setup gives the person who turned it on **Territory Admin**, and within the hour gives
   everyone holding BarnCRM Admin the same set, Team Member and Fundraising Staff **Territory
   Staff**, and Read Only **Territory Read Only** (Finish Setup does it at once). It never takes
   a set away.
3. Add the **Territory** field to your person, household and organization page layouts or
   Lightning pages if you want people to see it on the record.

| Set | Gives |
|---|---|
| Territory Admin | The Territory Management page; create, edit and delete territories, rules and members; preview, assign and undo; edit Territory on records. |
| Territory Staff | Read territories, rules and members; edit Territory on records by hand. |
| Territory Read Only | Read territories and the Territory of records. |

Assign changes records as the person who runs it, so they need edit access to the people,
households and organizations it moves. A record they cannot see or edit is skipped.

## Set Up Territories

Open the **Territory Management** tab (in the BarnCRM admin apps, or from BarnCRM Settings,
**Territory Management**, **Open**).

1. Press **New Territory**. Give it a name, a priority (lower numbers are checked first; the
   default is 100) and a routing:
   - **Keep Owner**: only the Territory field changes.
   - **Territory Owner**: the record's owner becomes the territory owner you choose.
   - **Round Robin**: each record goes to the next active member in turn. The next run carries on
     where the last one stopped.
   - **Capacity**: each record goes to the active member with the most room: their capacity
     minus the records of this territory they already own. A member with no capacity is never
     full.
2. Add one or more **rules**. Choose what the rule applies to (People, Households or
   Organizations) and add conditions. A rule with no conditions matches every record of that
   kind, which is useful for a catch-all territory with the highest priority number.
   **Check Rule** counts the records the rule matches now.
3. For Round Robin or Capacity, add **members**: a user and, if you want a limit, a capacity.
   Members take turns in the order you added them. Untick **Active** to stop giving someone new
   records without removing them.

Round Robin also respects a member's capacity: a member at capacity is skipped. When every
member is full, the record still moves to the territory and keeps its owner; the run counts it
as "with no member room".

At most 50 active rules for each kind of record. Households are accounts of the household record
type; organizations are accounts of your organization record type (BarnCRM Settings,
**Organization**), or of none.

## Preview and Assign

1. Press **Preview**. The run reads every person, household and organization in the background
   and changes nothing. Press **Refresh** until it is done: its line under **Recent Runs** shows
   how many records it checked and how many would move. **Show Details** lists the count for
   each territory (and how many found no member with room) and up to 50 example changes, each
   with its new owner.
2. If the preview looks right, press **Assign** and confirm. It reads the records again and
   moves them, as you. Records already in their territory are left alone, owner included. A
   record no rule matches keeps the territory it has.
3. The run's line shows what moved and how many records the save refused (for example because
   of a validation rule). Refused records are listed in Data Manager, **Data Jobs**, under the
   run's job.

Tick **Only records with no territory** before Preview or Assign to leave records that already
have a territory alone. Only one run happens at a time, and a kind of record with more than 50
active rules is refused (the page warns first).

## Undo

Every Assign run is one data job, operation Update. **Undo** on the run's line (or the job's
**Undo** in Data Manager, **Data Jobs**) puts back each record's territory and owner, except on
records someone has changed since. Undo is available for the data jobs' undo window, as for any
bulk update.

## Assign New Records Each Night

The job **Territory assignment** on the Nightly Jobs panel (BarnCRM Settings, **General**; 5:45 AM) runs Assign for records that
have no territory yet, so new people, households and organizations join a territory and an owner
overnight. Its switch ships **off**, because it changes owners; turn it on there. It runs as the
user the nightly run is scheduled under. Each night's run is its own data job, with its own
Undo.

## Limits and Notes

- Capacity counts the records of the territory each member owns when the run first needs that
  territory. The count reads those records, so for a territory of more than about 40,000 records
  use Round Robin.
- A person stored as a person account is checked as an account of its record type.
- Turning the module off stops the page and the nightly step; Territory values on records stay.
