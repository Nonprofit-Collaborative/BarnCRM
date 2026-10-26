# Duplicates

Imports and busy weeks leave the same person or family in BarnCRM twice. Salesforce warns you
as you type a new person who looks like someone already there. BarnCRM adds a scan of the
records you already have, a list of possible pairs, and the tidy-up after a merge. Nothing is
ever merged for you: every merge is a pair someone looked at and confirmed.

Before you start: reviewing suggestions needs the **BarnCRM Duplicate Review** add-on, which
Salesforce allows only for users with a Sales Cloud or Service Cloud license. The
**Duplicates** list on the **Org Optimizer** tab, and dismissing and merging from it, also need
the admin role (**BarnCRM Admin Group** on the Access page). Running the scan is admin work. Ask your admin; see
[Duplicates](../admin-guide/duplicates.md).

## To review a possible duplicate person

1. Open the person. On the right of the page, the **Potential Duplicates** card names any
   record Salesforce thinks is the same person.
2. Click **View Duplicates**, then **Compare and merge**.
3. Pick the record to keep and, field by field, the values to keep.
4. Confirm the merge.

You should see: one person. This is Salesforce's own merge: it keeps the activities and files
of both (and, with Giving, their gifts). Salesforce lets you merge people only if you may
delete people; if you cannot, ask your admin.

## What BarnCRM tidies after a person merge

Within a minute or so, without you doing anything:

- The kept person joins any household the other one belonged to, and their totals are
  recalculated.
- One default address stays.
- A relationship the two records had with each other is removed, and so is a second copy of a
  relationship both had with the same person.
- Their primary affiliation is chosen again.

A household the other person leaves empty is kept, not deleted, because records can still
point at it. Merge it into the kept person's household (below).

## To merge two households that are the same family

1. Open the household you want to keep and click **Merge or split**.
2. On the **Merge** tab, find and pick the other household, choose the values to keep, and
   click **Merge**, then **Merge households**.

You should see: "Merged. The household you kept now holds everyone from both." Always merge
households this way, never with Salesforce's own account merge. The full steps are in
[People and households](people-and-households.md#to-merge-two-households).

## To work through the Duplicates list (admins)

1. Open the **Org Optimizer** tab and choose **Duplicates**.
2. Under **Possible duplicates**, read each pair. It is marked **Person** or **Household**, and
   says why it was suggested (see below). Press **Refresh** to see the latest.
3. For two people, open either one and use **Compare and merge**, as above. The list reminds
   you: "To merge two people, open either one and use Compare and merge on the Potential
   Duplicates card."
4. For two households, click **Merge households**. In **Merge two households**, choose the
   **Household to keep** and click **Merge these two**. To choose field by field, use **Merge
   or split** on the household instead.

You should see: "The two households are now one." Merged pairs leave the list.

## Why a pair is suggested

Each pair shows a short reason:

- The name of the duplicate rule that matched it, for example a similar name with the same
  email, phone or address on the person or household itself.
- A shared value on a related record, such as "Same email on Contact Point Email", "Same phone
  on Contact Point Phone" or "Same address on Address (person)". BarnCRM also checks these
  related records (contact point emails, phones and addresses, and BarnCRM addresses).

A pair found both ways is listed once, under the rule. Some shared values are ignored on
purpose: a value shared by more than ten people or households (such as an office's main
number), and a phone or address shared by people in the same household, since that is what
living together looks like. A shared email still pairs them.

## To mark a pair as not a duplicate (admins)

1. On the pair, click **Not a duplicate**.
2. In **Reason**, type why, for the next person who wonders (for example "Twin sisters at one
   address").
3. Confirm.

You should see: "Noted. This pair will not be suggested again." It stays off the list after
later scans, too. A suggestion with three or more records is dismissed as a whole, so merge
any real duplicates in it first.

## Common problems

- Problem: "Suggestions need access to duplicate record sets, which Salesforce gives only to
  Sales Cloud and Service Cloud licenses. ..." You do not have the BarnCRM Duplicate Review
  add-on, or your license cannot have it. Ask a colleague with one of those licenses to
  review.
- Problem: "You can see this list. Scanning, dismissing and merging here need the Manage
  BarnCRM Settings permission." Only admins act from the list. Merge people from their own
  page and households with **Merge or split**.
- Problem: there is no **Duplicates** section on **Org Optimizer**, or no **Org Optimizer** tab.
  The list is for admins. Use the **Potential Duplicates** card on the person.
- Problem: "No possible duplicates are waiting. Scan again after a large import." Nothing to
  review. Ask your admin to scan after an import.
- Problem: a pair of organizations never appears. The list shows people and households only.
  Ask your admin.
- Problem: after merging two people, an empty household is left. That is on purpose. Merge it
  into the kept person's household.
- Problem: you dismissed a pair by mistake. Ask your admin; dismissals can be deleted, and the
  next scan suggests the pair again.

## Related

- [People and households](people-and-households.md)
- [Finding people and records](find.md)
- Admin Guide: [Duplicates](../admin-guide/duplicates.md),
  [Merging and splitting households](../admin-guide/household-merge-split.md),
  [Org Optimizer](../admin-guide/org-optimizer.md), [Access](../admin-guide/access.md)
