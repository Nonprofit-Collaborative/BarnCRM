# Relationships

## What it does

Relationships records how the people in your database are connected to each other: who is
married to whom, whose child is at the same school, which two board members are siblings,
and which friend introduced your largest donor. You enter the connection once, from either
person, and Open Impact writes the other side for you, so the wife's record shows her
husband and the husband's record shows his wife without anyone typing it twice.

Because the other side is kept in step, editing or ending a relationship on one person
changes it on the other person at the same moment, and there is never a record that says a
connection is current while the matching record says it ended two years ago.

## How to turn it on

Relationships is part of Core and is on as soon as Open Impact is installed. There is
nothing to install and no Setup step.

1. Open the **Open Impact** app and choose **Open Impact Settings**.
2. In the left navigation choose **Relationships**.
3. Leave **Keep both sides of relationships in step** switched on, which is how it ships.
   Switch it off only if your organization deliberately keeps one side of every connection,
   for example because another system writes both sides and you do not want two sources
   writing the same records.
4. Choose **Save**. The change applies to the next relationship you save.

On the **Automation** page in Open Impact Settings you will see two rows for relationships
rather than one:

- **Check relationships before saving.** The rules: a relationship is between two
  different people, both sides name someone, the same relationship is not entered twice, and
  the status agrees with the dates. Leave this on. Switching it off lets an import create
  duplicate relationships and relationships between someone and themselves, with nothing to
  tell you afterwards which records those were.
- **Keep both sides of a relationship in step.** The upkeep: writing, updating, and removing
  the matching record on the other person.

They are two rows on purpose. Switching the upkeep off before a large import, which is the
usual reason to touch it, leaves every check running.

To let your team see and manage relationships, make sure they have one of the packaged
access levels (Open Impact Admin, Fundraising Staff, or Program Staff) on the **Access** page
in Open Impact Settings. Read Only users see relationships and cannot change them.

Relationships appear in two places once you are set up: a **Relationships** card on every
person's record, and a **Relationships** tab in the Open Impact app for reporting and
list views.

### The types you can choose, and what the other side becomes

The list ships ready to use, and none of it depends on anyone's gender.

| You choose | The other person's record says |
|---|---|
| Spouse | Spouse |
| Partner | Partner |
| Parent | Child |
| Child | Parent |
| Sibling | Sibling |
| Grandparent | Grandchild |
| Grandchild | Grandparent |
| Friend | Friend |
| Colleague | Colleague |
| Employer contact | Colleague |
| Other | Other |

## A five-minute walkthrough

You are Maria. Your Executive Director wants to know which of your donors are related to
each other before the gala seating is decided, and the Garcia family keeps coming up. Start
from the sample data.

1. Open the **Open Impact** app and choose **Households**. Open **The Garcia Family** and
   choose the person named **Harper Garcia**.
2. Scroll to the **Relationships** card. It is empty, and it says "No relationships on file
   yet."
3. Choose **Add relationship**. Fill in:
   - **Related person**: Luis Garcia
   - **Type**: Spouse
   - **Status**: leave it as Current
   - **Start date**: leave it empty
   Choose **Save**.
4. The card now shows one line: "Luis Garcia, Spouse, Current". Nothing else was asked of
   you.
5. Open **Luis Garcia**. His **Relationships** card already shows "Harper Garcia, Spouse,
   Current". You did not enter it. Open Impact wrote it when you saved Harper's.
6. Go back to **Harper Garcia** and choose **Edit** on the Luis line. Set **End date** to
   last month and choose **Save**. The line now reads **Former**.
7. Open **Luis Garcia** again. His line reads **Former** too, with the same end date. The
   two records can never disagree.
8. Now add a second one from Harper: choose **Add relationship**, pick **Diego Garcia**,
   type **Child**, and save. Harper's card reads "Diego Garcia, Child", because the type
   says what the other person is to the person whose record you are on. Open **Diego
   Garcia** and his card reads "Harper Garcia, Parent", the same fact from his side.
9. Finally, delete the Luis line from Harper's card. Open Luis and the matching line is gone
   from his card too.

That is the whole feature: enter one side, get both, and never clean up after yourself.

## Common mistakes

**Reading the type from the wrong side.** The type says what the **other person** is in
relation to the person whose record you are on. On Harper's record, a line reading "Diego
Garcia, Child" means Diego is Harper's child. If a relationship looks backwards, open the
other person's record and read it there: Diego's card says "Harper Garcia, Parent", which is
the same fact from the other direction. Change the type on either side and both sides move
together.

**Entering both sides by hand.** If you enter Luis as Harper's spouse and then open Luis and
enter Harper as his spouse, the second save is refused with "Luis Garcia already has this
relationship with Harper Garcia. Open RL-000123 to change it." That is the feature working:
the second record already existed, because Open Impact wrote it. Open the record the message
names instead of creating another one.

**Expecting a relationship to move someone into a household.** It does not, deliberately. A
relationship says two people are connected; a household says who receives one letter and one
receipt. Spouses in the same household usually have both, and adding a Spouse relationship
to someone in a different household leaves both households exactly as they were. To move a
person, use **Move to another household** on their record, which is the Households feature.

**Deleting one side and expecting the other to survive.** Deleting a relationship deletes
both sides, because they are one connection. If you meant to keep the other person's
record, edit the relationship and set an end date instead: it then reads Former on both
sides and stays on file, which is what you want for anything you may need to explain later.

**Turning the setting off and wondering why nothing mirrors.** With **Keep both sides of a
relationship in step** switched off, Open Impact writes only the side you entered and
leaves any pairing it made earlier exactly as it is. Your relationships are still checked:
duplicates and self relationships are still refused, because the checks are the separate
**Check relationships before saving** row on the Automation page. Switch the upkeep
back on and the next save on a relationship brings its other side back into step. You can
also stop the mirroring for one relationship only, without changing the setting for everyone:
clear **Keep both sides in step** on that one record.

**Nothing mirrors and you never touched the setting.** In releases before v0.3 the setting
could be stored as off without anyone switching it off, if Open Impact Settings had been saved
for some other reason. Open Open Impact Settings, Relationships, and check that **Keep both
sides of a relationship in step** is on. Relationships entered while it was off stayed one
sided: re-save one and its other side is written.
