# Household names and greetings

**Feature:** C-02 Household naming and greetings
**Package:** Core
**Iteration:** v0.1

## What it does

Every household gets a name and two greetings, written for you and kept up to date: the
household name for lists and reports ("The Garcia Family"), a formal greeting for letters
and receipts ("Mr. and Mrs. John Smith"), and an informal greeting for personal notes
("John and Jane").

They are recalculated whenever the people in the household change, so a mail merge is
right without anyone checking it first. When staff want to word one household themselves,
they check one box and the product stops touching it.

## How to turn it on

Naming is on as soon as Core is installed, with patterns that work out of the box. To
change them:

1. Open the **Open Impact** app and click the **Open Impact Settings** tab.
2. Click **Households** in the left navigation. The naming panel is in that section.
3. Change any of the three patterns. A preview of five sample households updates as you
   type, so you can see the result before you save. The samples ship with the product; they
   are not your own households.
4. Choose whether people who have died stay in the household name. They are always left
   out of the informal greeting.
5. Click **Save**.
6. Saving changes the pattern everywhere it is used next. Every household is renamed from
   the current patterns the next time anything touches it, so an org that does not recompute
   drifts into the new pattern one household at a time. To bring every household up to date
   at once, click **Recompute all households** and confirm. The page tells you the recompute
   has started; it then runs in the background, and households are renamed a few hundred at
   a time. A large org takes a few minutes. The page does not report progress or tell you
   when the batch has finished.

You need the "Manage Open Impact Settings" permission to change these. Without it the page
opens read only and says so.

### Patterns and tokens

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

Two rules are built in rather than written into a pattern, because they read badly any
other way:

- When the people in a household do not share a last name, the name lists the surnames
  instead of using your pattern: "Garcia and Lee Household", or "Garcia, Lee, and Smith
  Household" for three or more.
- When exactly two people share a last name and both have a title, the formal greeting
  combines them: "Mr. and Mrs. John Smith" rather than "Mr. John Smith and Mrs. Jane
  Smith".

## A five-minute walkthrough

Maria does steps 1 to 5. David does step 6.

1. Open the **Contacts** tab, click **New**, and enter the first name `Maria` and the last
   name `Garcia`. Leave the household blank and click **Save**. Open the household from
   her record: it is called **The Garcia Family**, the formal greeting reads **Ms. Maria
   Garcia** if you gave her a title, and the informal greeting reads **Maria**.
2. On the household's **Members** panel, click **Add member** and enter the first name
   `Wei` and the last name `Lee`. Save, then refresh the household. Because the two people
   do not share a last name, the name now reads **Garcia and Lee Household** and the
   informal greeting reads **Maria and Wei**.
3. Open Wei's record, check **Deceased**, and save. Refresh the household: the informal
   greeting reads **Maria** again. The household name still mentions Lee only if you chose
   to keep people who have died in household names.
4. Open **Open Impact Settings**, click **Households**, and change the household name
   pattern to `{LastName} Household`. Watch the sample preview change as you type.
   Click **Save**, then **Recompute all households**, and confirm.
5. Go back to a household with one surname. It now reads **Garcia Household**.
6. David opens the household for the Reverend and Mrs. Smith, checks **Custom name**, and
   types the name and greetings the way he wants them. From now on nothing recalculates
   that household: adding a member, a recompute, and a pattern change all leave his wording
   alone.

## If your org stores people as accounts

Names and greetings are written the same way when a person is stored as an account rather
than as a contact, and a household can hold both kinds of person at once. The details that
feed the wording (preferred name, title, whether the person has died, and the two exclusion
boxes) sit on the person's own record wherever that record lives, so put them where you
enter the person.

## Common mistakes

**"I changed the pattern and nothing changed."**
An existing household keeps its old name only until something touches it: naming reads the
current patterns every time it runs, so the household is renamed the next time a member is
added, changed, or moved. Click **Recompute all households** to rename them all now instead
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

## Field reference

For report builders only.

| Where | Field label | Purpose |
|---|---|---|
| Household | Account Name | The computed household name |
| Household | Formal Greeting | Used on letters and receipts |
| Household | Informal Greeting | Used on personal notes |
| Household | Custom Name | When checked, nothing recalculates this household |
| Person | Preferred Name | Used in place of the first name in greetings |
| Person | Deceased | Left out of greetings |
| Person | Exclude From Household Name | Left out of the name only |
| Person | Exclude From Greetings | Left out of both greetings only |
