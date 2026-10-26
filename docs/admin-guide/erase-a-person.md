# Erase a person

## 1. What it does

**Erase person** removes what your organization holds about one person when they ask you to
(the right to be forgotten under GDPR and several state privacy laws). It is one action on the
person's record page, and **it cannot be undone**.

The person's record is kept but made anonymous, so every total stays right:

- **Every personal field is emptied**: name, email addresses, phone numbers, mailing address,
  birth date, notes, and any field your organization added. The record's name becomes
  "Erased person". Opt-out flags (email opt out, do not call) are switched on so no mailing
  reaches the record.
- **Addresses** the person owns are deleted.
- **Relationships and affiliations** are ended today and lose their descriptions, so the other
  person's history still says a relationship existed, but not with whom.
- **Households**: the person leaves every household. A household with other members is
  recounted, and its name and greetings are made again from the people still in it. If its
  name was typed by hand (**Custom Name** on), BarnCRM cannot tell safely which words name the
  person, so it turns Custom Name off and the name and greetings are made again from the
  remaining members; type a new custom name afterwards if you want one. A household Nonprofit
  Cloud names keeps its wording: the preview tells you to check it and change it by hand. The
  preview lists each household with exactly the fields that changed.
  If the person was the only member, the household follows your **Delete empty households**
  setting; a household that is kept (the setting is off, or gifts or other records credited
  to the household, such as volunteer hours, keep it) is made anonymous too: it is renamed
  "Erased household" and its greetings and address are emptied. The preview lists it as
  **Household**, with a note saying why it was kept: "Kept because Delete Empty Households is
  off (BarnCRM Settings, Households)." when the setting is off, or "Kept because records are
  credited to it." when the setting is on and records keep it.
- **Salesforce's privacy record**: where your org uses the Individual record (Setup, Data
  Protection and Privacy), it is emptied and marked **Forget this Individual**.
- **Field history** of the record (old values of tracked fields) is deleted a moment after the
  erasure, if you hold the Salesforce permission **Delete From Field History**. Without it the
  preview says the history is kept.
- **Totals stay**: giving totals, counts and dates on the person and the household are kept,
  because they say nothing about who the person was.

With the Giving module installed, gifts, soft credits, pledges and receipts are kept with their
amounts and dates, still credited to the anonymous record, except the automatic household soft
credits the person had as a household member, which are deleted because they are no longer in
a household. See section 4.

With the Volunteers module installed, volunteer hours and shift sign-ups are kept the same way,
with their notes emptied; bookings on shifts still to come are cancelled; onboarding
requirements and skills are deleted. See [Volunteers](volunteers.md#erasing-a-volunteer).

Every erasure writes an **Erasure** record: who erased, when, the request reference you typed,
and each record that changed with the fields that were emptied. It never holds an erased value.

## 2. How to turn it on

1. Erasing needs the **Erase People** permission, which is **in no role, not even BarnCRM
   Admin**. Assign the **BarnCRM Erase People** permission set to the one or two people who handle
   privacy requests (BarnCRM Settings, Access, Extra Permissions).
2. The person erasing also needs edit access to the person and to everything the erasure changes
   (their addresses, relationships, affiliations and household memberships, a household whose
   custom name it turns off, and with Giving their automatic household soft credits). BarnCRM
   Admin, with Giving Admin or Giving Staff, has it.
3. Optional, recommended: give them the Salesforce system permission **Delete From Field
   History** (in a permission set of your own), so field history is erased too.
4. **Erase person** is on the person record pages BarnCRM ships. On a page of your own, add the
   **Erase person** action.

## 3. A five-minute walkthrough (as Maria)

Jordan Lee emailed asking to be forgotten. Maria checked it was really Jordan, and logged the
request as ticket PR-2041.

1. Open Jordan Lee's record and choose **Erase person**.
2. Press **Preview**. BarnCRM works through the whole erasure and then takes it back, and lists
   exactly what would change: each record, what happens to it (emptied, ended, deleted, kept),
   and which fields. Nothing has changed yet.
3. Read the list. Anything listed as **Kept** stays as it is, with the reason (for example,
   receipts kept as tax records).
4. Type the reference `PR-2041` into **Request reference** (never a name or an email address:
   the reference is kept).
5. Type `Jordan Lee` into **Type the person's name to confirm**, then press **Erase**.
6. The page shows what was done and links to the **Erasure** record, whose Details keep the
   same list in the same words.

## 4. What stays, and what you still have to do

- **Gifts and receipts (Giving).** Gifts, soft credits, pledges and their payments keep their
  amounts, dates and funds, credited to the anonymous record. The one exception: the person's
  automatic household soft credits (the ones BarnCRM gives each household member on another
  member's gift) are deleted, because the person is no longer in the household, and the
  preview lists them as **Deleted**. Soft credits someone entered by hand are kept. Receipt records and their PDF
  documents are kept, because a tax authority can ask for them, and the PDFs print the donor's
  name and address. The preview counts them. If your rules let you, delete the documents by hand
  once you no longer have to keep them. Tribute names typed for the person, the message on a
  tribute of their own gift, and the email address in the acknowledgment ledger are emptied;
  active stewardship plans for them are ended.
- **Tasks, events and files** about the person are **listed, never erased**. The preview counts
  them as **Kept**: every task and event that names the person (as its Name, its Related To, or
  one of the people on a shared activity) and every file attached to the person's record. The
  count includes ones you cannot open. Delete or edit them by hand, preferably before you
  erase, while the person's name still shows on the record: open the person's record, then
  the **Activity** and **Files** related lists. An activity's subject or a file's contents
  can hold anything, so BarnCRM cannot tell which ones are safe to keep.
- **Not reached by the erasure**: notes and emails about the person; Chatter posts and feed
  tracking; reports and exports already downloaded; backups; other systems; contact point
  records (Nonprofit Cloud's email, phone and address records); and records of your
  organization's own custom objects that hold personal details in their own fields. Review
  these yourself; the erasure's record page lists none of them.
- **Health Check** and the data hygiene console do not count an erased person as a person with
  no household: erasing them took them out of it on purpose.

## 5. Common mistakes

- **"You can't edit ..."** The erasure stopped before changing anything: you cannot edit a record
  or a field that holds a value. Ask your administrator for access, or ask them to erase.
- **"Type the person's name exactly as shown."** The confirmation must match the name on the
  record.
- **"This person was already erased."** There is an Erasure record for them already.
- **Something refused the change part way.** A validation rule or other automation of your org
  refused a change. Nothing was erased: the whole erasure is taken back. The message names the
  record and the reason.

## Field reference

| Where | Field | What it holds |
|---|---|---|
| Erasure | Contact, Person Account | The anonymous record that was erased. |
| Erasure | Erased Record Id | The same record's Id, kept as text if the record is deleted later. |
| Erasure | Request Reference | The reference typed when erasing, for example a ticket number. |
| Erasure | Details | Each record changed, with what was done and which fields were emptied. No values. |
| Erasure | Created By, Created Date | Who erased, and when. |
