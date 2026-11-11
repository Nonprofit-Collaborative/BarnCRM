# Territory Management

Scripts for the optional BarnCRM Territory Management module: territories, rules, preview,
assign, owner routing and undo. Setup detail:
[Territory Management](../admin-guide/territory-management.md).

Before you start: an org from [Before you test](before-you-test.md), with Core and Territory
Management deployed and the module turned on in BarnCRM Settings, **Modules**. You need an admin
(BarnCRM Admin), two other active users (User A and User B), and sample data loaded (people,
households and organizations with addresses).

## T-TM-01: Install and Access

**Purpose:** confirm setup gives access and that nothing changes until a run.
**Prerequisites:** admin; a Team Member user.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Open the BarnCRM admin app. | A Territory Management tab, before Error Log. |
| 2 | Open Setup, the Team Member user's permission set assignments. | Territory Staff is assigned (within the hour, or after Finish Setup). |
| 3 | Open any person and household. | Territory is empty; owners are unchanged. |
| 4 | Open BarnCRM Settings, **Territory Management**, and press **Open**. | The Territory Management page opens. |

**Cleanup:** None.

## T-TM-02: Rules, Priority and Preview

**Purpose:** confirm first match wins and Preview changes nothing.
**Prerequisites:** admin; T-TM-01.

| Step | Action | Expected result |
|---|---|---|
| 1 | Create territory **Boston**, priority 10, Keep Owner, with a People rule: Mailing Postal Code starts with 021. Press **Check Rule**. | A count of people whose postal code starts with 021. |
| 2 | Create territory **Everyone Else**, priority 900, Keep Owner, with a People rule and no conditions. | Saved. |
| 3 | Press **Preview**, press **Refresh** until its line under **Recent Runs** reads Done, and press **Show Details**. | Checked equals the number of people (only kinds with a rule are read); the Boston count matches step 1; Everyone Else has the rest of the people; households and organizations are not moved (no rule). |
| 4 | Open a Boston person. | Territory is still empty: Preview changed nothing. |

**Cleanup:** None (T-TM-03 uses the territories).

## T-TM-03: Assign and Undo

**Purpose:** confirm Assign moves records once, and Undo puts them back.
**Prerequisites:** T-TM-02.
**Smoke:** yes

| Step | Action | Expected result |
|---|---|---|
| 1 | Press **Assign**, confirm, and wait. | Changes equals the preview's count; Failed 0. |
| 2 | Open a person with postal code 02108. | Territory Boston; owner unchanged. |
| 3 | Press **Assign** again. | Changes 0: records already in their territory are left alone. |
| 4 | Open Data Manager, **Data Jobs**. | One Update job from step 1, with Undo. |
| 5 | On the Territory Management page press **Undo** on the step 1 run and confirm. | After the undo job, the person from step 2 has no Territory again. |

**Cleanup:** None.

## T-TM-04: Owner Routing

**Purpose:** confirm Territory Owner, Round Robin and Capacity (C-40b).
**Prerequisites:** T-TM-02; User A and User B.

| Step | Action | Expected result |
|---|---|---|
| 1 | Set Boston's routing to **Round Robin** and add members User A and User B. Press **Preview**, then **Show Details** on its line. | The example changes name User A and User B in turn as the new owner. |
| 2 | Press **Assign**. | Boston people are owned alternately by User A and User B. |
| 3 | Undo the run. Set Boston to **Capacity**, User A capacity 2, User B blank. Preview. | In the example changes, User A gets 2 at most (less if they already own Boston people); User B gets the rest. |
| 4 | Set User B's capacity to 1 and Preview again. | Boston's line in **Show Details** counts the records past both capacities as "with no member room"; their example changes read "owner unchanged". |
| 5 | Set Boston to **Territory Owner** with User A as territory owner, and Preview. | Every Boston change names User A. |

**Cleanup:** Undo any Assign runs.

## T-TM-05: Nightly Assignment Ships Off

**Purpose:** confirm the nightly step is off until turned on, and then assigns only new records.
**Prerequisites:** T-TM-03 run assigned (do not undo).

| Step | Action | Expected result |
|---|---|---|
| 1 | Open BarnCRM Settings, **General**, the Nightly Jobs panel. | Territory assignment at 5:45, Status Off. |
| 2 | Switch it on, add a person with postal code 02110, and check the next morning. | A Territory run, Only Unassigned, moved just the new person to Boston; the panel shows Done. |
| 3 | Switch the step off. | Off. |

**Cleanup:** Undo the step 2 run.
