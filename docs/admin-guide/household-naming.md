# Household Names and Greetings

**Feature:** C-02 Household naming and greetings
**Package:** Core
**Iteration:** v0.1

## What It Does

Every household gets a name and two greetings, written for you and kept up to date: the
household name for lists and reports ("The Garcia Family"), a formal greeting for letters
("Mr. and Mrs. John Smith"), and an informal greeting for personal notes
("John and Jane").

They are recalculated whenever the people in the household change, so a mail merge is
right without anyone checking it first. When staff want to word one household themselves,
they check one box and the product stops touching it. When the last person leaves a
household that is kept, it keeps the name and greetings it had last, so reports still show
which family it was.

## How to Turn It On

Naming belongs to the **Household Upkeep** feature, which on a new install is off until you
turn it on: choose **Turn On** in the **Household Upkeep** row in **BarnCRM Settings**,
**General** (or leave it ticked in first-run setup); see
[BarnCRM Settings](barncrm-settings.md). Once it is on, the patterns work out of the box.
To change them:

1. Open the **BarnCRM Admin** app and click the **BarnCRM Settings** tab.
2. Click **People and Households** in the left navigation. The naming panel is in the
   **Household Names and Greetings** box, and
   it is the only place the three patterns are edited: they are not also listed as
   separate rows. Searching the settings for a pattern, for example `greeting`, takes you
   to the panel.
3. Change any of the three patterns. A preview of five sample households updates as you
   type, so you can see the result before you save. The samples ship with the product; they
   are not your own households.
4. Click **Save** to save the three patterns.
5. Whether people who have died stay in the household name is a separate row in the console,
   saved by the console's own **Save**, not by the patterns' Save. They are always left out
   of the informal greeting.
6. Saving changes the pattern everywhere it is used next. Every household is renamed from
   the current patterns the next time anything touches it, so an org that does not recompute
   drifts into the new pattern one household at a time. To bring every household up to date
   at once, click **Update All Household Names** and confirm. The page tells you the recompute
   has started; it then runs in the background, and households are renamed a few hundred at
   a time. A large org takes a few minutes. The page does not report progress or tell you
   when the batch has finished.

You need the "Manage BarnCRM Settings" permission to change these. Without it the page
opens read only and says so.

### Patterns and Tokens

A pattern is a sentence with blanks in it. The blanks are filled in from each person.

| Token | Filled in with |
|---|---|
| `{FirstName}` | The person's preferred name, or their first name when there is no preferred name |
| `{LastName}` | The person's last name |
| `{Salutation}` | The person's title, for example Mr., Mrs., or Dr. |

The patterns that ship are:

| Pattern | Ships as | Produces |
|---|---|---|
| Household name | `The {LastName} Family` | The Garcia Family |
| Formal greeting | `{Salutation} {FirstName} {LastName}` | Mr. and Mrs. John Smith |
| Informal greeting | `{FirstName}` | John and Jane |

Three rules are built in rather than written into a pattern, because they read badly any
other way:

- When the people in a household do not share a last name, the name lists the surnames
  instead of using your pattern: "Garcia and Lee Household", or "Garcia, Lee, and Smith
  Household" for three or more.
- When exactly two people share a last name and the pair is one Mr. and one Mrs., the
  formal greeting combines them under the Mr.'s first name: "Mr. and Mrs. John Smith"
  rather than "Mr. John Smith and Mrs. Jane Smith". Every other pair is named person by
  person, in the order of the members: "Ms. Rosa Hall and Ms. Ana Hall", "Mr. Luis Mensah
  and Ms. Ana Mensah", "Dr. Priya Nguyen and Dr. Thomas Nguyen".
- A name or greeting holds at most 255 characters. In a very large household the list
  names as many people as fit and counts the rest: "Garcia, Lee and 28 others Household".

## A Five-Minute Walkthrough

Maria does steps 1 to 5. David does step 6.

1. Open the **Contacts** tab, click **New**, and enter the first name `Maria` and the last
   name `Garcia`. Leave the household blank and click **Save**. Open the household from
   her record: it is called **The Garcia Family**, the formal greeting reads **Ms. Maria
   Garcia** if you gave her a title, and the informal greeting reads **Maria**.
2. On the household's **Members** panel, click **Add Member** and enter the first name
   `Wei` and the last name `Lee`. Save, then refresh the household. Because the two people
   do not share a last name, the name now reads **Garcia and Lee Household** and the
   informal greeting reads **Maria and Wei**.
3. Open Wei's record, check **Deceased**, and save. Refresh the household: the informal
   greeting reads **Maria** again. The household name still mentions Lee only if you chose
   to keep people who have died in household names.
4. Open **BarnCRM Settings**, click **People and Households**, and change the household name
   pattern to `{LastName} Household`. Watch the sample preview change as you type.
   Click **Save**, then **Update All Household Names**, and confirm.
5. Go back to a household with one surname. It now reads **Garcia Household**.
6. David opens the household for the Reverend and Mrs. Smith, checks **Custom name**, and
   types the name and greetings the way he wants them. From now on nothing recalculates
   that household: adding a member, a recompute, and a pattern change all leave his wording
   alone.

## If Your Org Stores People as Accounts

Names and greetings are written the same way when a person is stored as an account rather
than as a contact, and a household can hold both kinds of person at once. The details that
feed the wording (preferred name, title, whether the person has died, and the two exclusion
boxes) sit on the person's own record wherever that record lives, so put them where you
enter the person.

## Common Mistakes

**"I changed the pattern and nothing changed."**
An existing household keeps its old name only until something touches it: naming reads the
current patterns every time it runs, so the household is renamed the next time a member is
added, changed, or moved. Click **Update All Household Names** to rename them all now instead
of household by household.

**"One household refuses to update."**
Its **Custom name** box is checked, which is exactly what that box is for. Uncheck it and
the household is renamed from your patterns immediately.

**"A person who died is still in the household name."**
That is the "keep people who have died in household names" setting. Turn it off and
recompute. They are left out of the informal greeting either way. When you keep them, the
formal greeting says "the late" before their name.

**"The name is not using my pattern."**
Check whether the people in the household share a last name. When they do not, the name
lists the surnames instead, which is deliberate. Check also whether anyone is marked
"exclude from household name": that person is left out of the name but still counted as a
member.

**"Which language are the added words in?"**
The words BarnCRM adds to a name or greeting ("and", the comma between names, "the late",
"Household", and the placeholder name a new household gets) are in your org's default
language (Setup, Company Information), whoever saves the household. A colleague who uses
Salesforce in another language does not rename households into theirs. Where BarnCRM has no
translation for that language, the words stay in English. Your patterns are used exactly as
you typed them.

## Field Reference

For report builders only.

| Where | Field label | Purpose |
|---|---|---|
| Household | Account Name | The computed household name |
| Household | Formal Greeting | Used on letters (and receipts, with Giving) |
| Household | Informal Greeting | Used on personal notes |
| Household | Custom Name | When checked, nothing recalculates this household |
| Person | Preferred Name | Used in place of the first name in greetings |
| Person | Deceased | Left out of greetings |
| Person | Exclude From Household Name | Left out of the name only |
| Person | Exclude From Greetings | Left out of both greetings only |
