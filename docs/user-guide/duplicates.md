# Duplicates

Imports and busy weeks leave the same person or family in BarnCRM twice. Salesforce warns you
as you type a new person who looks like someone already there. BarnCRM adds a scan of the
records you already have, a list of possible pairs, and the tidy-up after a merge. Nothing is
ever merged for you: every merge is a pair someone looked at and confirmed.

Before you start: reviewing suggestions needs the **BarnCRM Duplicate Review** add-on, which
Salesforce allows only for users with a Sales Cloud or Service Cloud license. With it you see
the **Duplicate Matching** tab and its **Review** list. Dismissing and merging from that list,
and running the scan, also need the admin role (**BarnCRM Admin Group** on the Access page).
Ask your admin; see [Duplicates](../admin-guide/duplicates.md).

## To Review a Possible Duplicate Person

1. Open the person. On the right of the page, the **Potential Duplicates** card names any
   record Salesforce thinks is the same person.
2. Click **View Duplicates**, then **Compare and merge**.
3. Pick the record to keep and, field by field, the values to keep.
4. Confirm the merge.

You should see: one person. This is Salesforce's own merge: it keeps the activities and files
of both (and, with Giving, their gifts). Salesforce lets you merge people only if you may
delete people. The staff roles do not include that on purpose, so if you cannot, ask your
admin. Merging two households with **Merge or Split** needs no such permission.

## What BarnCRM Tidies After a Person Merge

Within a minute or so, without you doing anything:

- The kept person joins any household the other one belonged to, and their totals are
  recalculated.
- One primary address stays.
- A relationship the two records had with each other is removed, and so is a second copy of a
  relationship both had with the same person.
- Their primary affiliation is chosen again.

A household the other person leaves empty is kept, not deleted, because records can still
point at it. Merge it into the kept person's household (below).

## To Merge Two Households That Are the Same Family

1. Open the household you want to keep and click **Merge or Split**.
2. On the **Merge** tab, find and pick the other household, choose the values to keep, and
   click **Merge**, then **Merge Households**.

You should see: "Merged. The household you kept now holds everyone from both." Always merge
households this way, never with Salesforce's own account merge. The full steps are in
[People and households](people-and-households.md#to-merge-two-households).

## To Work Through the Duplicates List (Admins)

1. Open the **Duplicate Matching** tab. The **Review** list opens; the tab name says how many
   suggestions are waiting, for example **Review (40)**. A suggestion is usually a pair of
   records, sometimes three or more.
2. Under **Possible Duplicates**, read each suggestion. It says why it was suggested (see
   below), then shows the records side by side, each marked **Person** or **Household**, with
   their email, phone and address. A value that differs between them has a **Different**
   badge. With three or more records, each is compared with the first one, and the card says
   so. The list shows 10 suggestions at a time; click **Show More** for the next 10. Press
   **Refresh** to see the latest.
3. For two people, open either one and use **Compare and merge**, as above. The note above the
   list reminds you: "To merge two people, open either one and use Compare and merge on the
   Potential Duplicates card."
4. For two households, click **Merge Households**. In **Merge Two Households**, choose the
   **Household to keep** and click **Merge These Two**. To choose field by field, use **Merge
   or split** on the household instead.

You should see: "The two households are now one." Merged pairs leave the list.

To merge the obvious duplicates in one go, an admin opens **Auto-Merge** on the same tab, clicks
**Preview Exact Matches**, reads the pairs and confirms. A run can be undone for 15 days from
**Recent Runs**. See [Auto-Merge](../admin-guide/duplicates.md#auto-merge).

## Why a Pair Is Suggested

Each pair shows a short reason:

- The name of the duplicate rule that matched it, for example a similar name with the same
  email, phone or address on the person or household itself.
- A shared value on a related record, such as "Same email on Contact Point Email", "Same phone
  on Contact Point Phone" or "Same address on Address (person)". BarnCRM also checks these
  related records (contact point emails, phones and addresses, and BarnCRM addresses). Your
  admin chooses which on the **Duplicate Matching** tab, **Matching Logic**.
- Similar names with something else in common, such as "Similar names (97%) and the same
  email", or "Same name in the same household". Case, spacing and punctuation do not count, and
  a similar name alone never pairs two people: in one household similar names are usually
  family, so there only an identical name is listed.

A pair found both ways is listed once, under the rule. Some shared values are ignored on
purpose: a value shared by more than ten people or households (such as an office's main
number), and a phone or address shared by people in the same household, since that is what
living together looks like. A shared email still pairs them.

## To Mark a Pair as Not a Duplicate (Admins)

1. On the pair, click **Not a Duplicate**.
2. In **Reason**, type why, for the next person who wonders (for example "Twin sisters at one
   address").
3. Confirm.

You should see: "Noted. This suggestion will not come back." It stays off the list after
later scans, too. A suggestion with three or more records is dismissed as a whole, so merge
any real duplicates in it first.

## Common Problems

- Problem: "Suggestions need access to duplicate record sets, which Salesforce gives only to
  Sales Cloud and Service Cloud licenses. ..." You do not have the BarnCRM Duplicate Review
  add-on, or your license cannot have it. Ask a colleague with one of those licenses to
  review.
- Problem: "You can see this list. Scanning, dismissing and merging here need the Manage
  BarnCRM Settings permission." Only admins act from the list. Merge people from their own
  page and households with **Merge or Split**.
- Problem: there is no **Duplicate Matching** tab, or no **Duplicates** section on **Org
  Optimizer** where you used to find it. The list moved to the **Duplicate Matching** tab, which
  is for admins and holders of the BarnCRM Duplicate Review add-on. Ask your admin, or use the
  **Potential Duplicates** card on the person.
- Problem: **No Possible Duplicates**, "No possible duplicates are waiting. Scan again after a
  large import." Nothing to review. Ask your admin to scan after an import.
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
  [Access](../admin-guide/access.md)
