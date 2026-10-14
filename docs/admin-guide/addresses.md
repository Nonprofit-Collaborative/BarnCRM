# Addresses

## What it does

Addresses gives every household, organization, and person one place to keep all of the
places they receive mail, instead of a single set of address boxes that gets overwritten
every time someone moves. One address is marked the default, and BarnCRM copies that
one into the standard address boxes on the household, the organization, or the person, so
mail merges, reports, letter templates, and any other app you use keep reading the address
they have always read.

Because the addresses are kept as records, a household can hold a winter address alongside
its year round one, an old address stays on file so a mailing sent last year can still be
explained, and one person can have an address of their own without moving the rest of
their household.

In an org that stores people as person accounts, a person saved with a mailing address, or
whose mailing address is changed afterwards, also gets an address of their own (type Home,
marked default), and an address that is already on file for them, with the same words, is not
added a second time. This is the same as it is for a person held as a contact, except that a
person account never moves a household: the address is theirs alone.

A winter address does not have to be moved by hand. A **seasonal** address carries the dates
it is used, and a nightly job makes it the address in use on the day its season starts and
puts the previous address back on the day the season ends. The job records when it last ran
and what it did, in two places you can see without leaving the app: the BarnCRM home
page and the Addresses page of BarnCRM Settings. A nightly job you cannot see is a nightly
job you cannot trust, which is why the last run is shown rather than assumed.

## How to turn it on

Addresses is part of Core and is on as soon as BarnCRM is installed. There is nothing
to install and no Setup step. Two things are worth setting once.

1. Open the **BarnCRM** app and choose **BarnCRM Settings**.
2. In the left navigation choose **Addresses**.
3. Set **When a person's address is edited** to the behavior your organization wants:
   - **Update household** (the default): editing one person's address moves the whole
     household, which is what most organizations want, because a household shares a mailbox.
   - **Create personal address**: editing one person's address gives that person an
     address of their own and leaves the rest of the household where it is. Choose this if
     you often track students away at school, adult children at a parent's household, or
     staff contacts who move without their family.
4. Choose **Save**. The change applies to the next address you edit.

Then switch on the seasonal address swap, which is off until you switch it on.

5. Stay on the **Addresses** page. Under **Seasonal address swap** you will see
   "The nightly swap is not scheduled, so seasonal addresses will not move on their own."
6. Choose **Schedule nightly run**. The message changes to "The swap runs every night at
   12:30 AM, in your organization's time zone" and the date of the next run appears under it.
7. Choose **Run the swap now** once, so you do not have to wait until tomorrow to see that it
   works. Refresh the page after a minute: **Seasonal addresses last swapped** shows the time
   it finished and a sentence saying how many addresses moved.

You need the **Manage BarnCRM Settings** permission, which the BarnCRM Admin access level
gives you, to use those two buttons. Everyone else sees the same last run and cannot change
the schedule.

There is nothing to do in Setup. Scheduling Apex is normally a Setup task, and BarnCRM
does not ask you to do that: the button on this page is the supported way to schedule the
swap. The Module Manager switches whole modules on and off; the seasonal swap belongs to Core, which is always on, so it
is scheduled here.

Two things to know about the schedule.

- **If you stop the swap, nothing moves back.** Addresses stay exactly where the last run put
  them. If you stop it in February, the household stays at its winter address until you start
  the job again or move the address yourself.
- **Whoever schedules the job should be an administrator.** The swap itself sees every address
  in the org, but the copy of the new address into the standard address boxes runs as the
  person who scheduled the job. If that person cannot edit a household, that household's swap
  is written to the Error Log instead of going through quietly.

To let your team see and manage addresses, make sure they have one of the packaged access
levels (BarnCRM Admin, Team Member, or Coordinator, or Fundraising Staff with
Giving) on the **Access** page in
BarnCRM Settings. Read Only users can see addresses and cannot change them.

Addresses appear in two places once you are set up: an **Addresses** card on every
household, organization, and person record, and an **Addresses** tab in the BarnCRM
app for reporting and list views.

The card reads and saves addresses as the person using it, through Salesforce's own record
service, so it shows exactly what their object and field access allows and nothing more. An
address edited elsewhere on the page shows on the card without a reload, and after **Set as
default** the record's own address boxes refresh too.

## A five-minute walkthrough

You are Maria. The Garcia household spends January to March in Arizona and the rest of the
year at home, and letters have been going to the wrong place. Start from the sample data.

1. Open the **BarnCRM** app and choose **Households**. Open **The Garcia Family**.
2. Scroll to the **Addresses** card. You will see one address already there, of type
   **Home**, with a **Default** badge on it. BarnCRM created it from the address that
   was already in the household's standard address boxes when the household was created,
   so nothing you had was lost.
3. Choose **Add address** on the card. Fill in:
   - **Type**: Seasonal
   - **Street**: 4120 East Camelback Road
   - **City**: Phoenix
   - **State**: AZ
   - **Postal Code**: 85018
   - **Country**: United States
   - **Seasonal Start Month**: 1, **Seasonal Start Day**: 1
   - **Seasonal End Month**: 3, **Seasonal End Day**: 31
   Choose **Save**. The new card appears with its dates shown as "January 1 to March 31".
4. Choose **Set as default** on the Arizona card. The **Default** badge moves to it, and
   the badge disappears from the home address. Scroll up: the household's address boxes at
   the top of the record now read Phoenix. Anything that reads the household's address,
   including a mail merge or a report, now gets Arizona.
5. Choose **Set as default** on the home address card to move the badge back. The
   household's address boxes read the home address again. Nothing was deleted: both
   addresses are still on the card, and you can move the default between them whenever you
   like.
6. Open **Harper Garcia**, one of the household's members, from the household's related
   people. Change her **Mailing Street** to a new street and save.
7. Go back to **The Garcia Family**. Because your setting says **Update household**, the
   household's default address now shows Harper's new street, and every other member of the
   household has the same new mailing address. One edit moved the whole household, which is
   what a household moving actually means. The new street is a new Home address card marked
   default; the address it replaced stays on the card as history and is not overwritten. If
   the household is away for the season when you make the edit, the seasonal address card is
   left as it is, and the new street is the one the household comes back to.

If you had set **Create personal address** instead, step 7 would look different: Harper
would have her own address card on her own record, marked default for her, and the rest of
the
Garcia household would still be at the old street. Both behaviors are correct; they are
just different organizations.

## A five-minute walkthrough for the seasonal swap

Still the Garcia household, and still five minutes. This time you are proving to yourself
that the nightly job really works, before the winter mailing goes out.

1. Open **BarnCRM Settings** and choose **Addresses**. Under **Seasonal address swap**,
   choose **Schedule nightly run** if it is not already scheduled.
2. Open **The Garcia Family** and look at the **Addresses** card. The Arizona address you
   added is of type **Seasonal** and reads "Used from January 1 to March 31". The **Default**
   badge is on the home address.
3. Change the Arizona address's dates so that today falls inside them: set **Seasonal Start
   Month** and **Seasonal Start Day** to yesterday's month and day, and the end month and day
   to a date next month. Save.
4. Go back to **BarnCRM Settings**, **Addresses**, and choose **Run the swap now**.
5. Wait a minute and refresh the page. **Seasonal addresses last swapped** now shows a time a
   minute ago and reads "1 moved to a seasonal address, 0 moved back, 0 could not be changed."
6. Open **The Garcia Family** again. The **Default** badge is on the Arizona address, the
   household's address boxes at the top of the record read Phoenix, and every member of the
   household has Phoenix as their mailing address. Nobody typed any of that.
7. Now set the Arizona address's end date to yesterday, save, and choose **Run the swap now**
   again. The summary reads "0 moved to a seasonal address, 1 moved back", the badge is back
   on the home address, and the household's address boxes read Springfield again.
8. Open the **BarnCRM** home page. The **Seasonal addresses last swapped** tile shows
   the same time and the same sentence. That tile is where you will notice, on an ordinary
   morning, if the job has stopped running.

A range that crosses New Year works the same way and is entered as one range. November 1 to
March 31 means the household is in Arizona on November 1, on Christmas Day, and on March 31,
and back home on April 1. Do not split it into two addresses.

## Common mistakes

**Editing the standard address boxes directly in a third party app.** BarnCRM treats
the address records as the truth and copies the default into the standard address boxes. If
a third party app, a data loader, or an integration writes straight into the standard
boxes, BarnCRM will put the default address back the next time that address record is
saved, and the edit will look like it vanished. Make the change
on the address card instead, or mark a new address as the default. This is also why address
verification apps should be pointed at the address records.

**Marking two addresses as default.** You cannot end up with two. Marking a second address
as the default clears the first one automatically, and when one save (an import, say) marks
two addresses of the same household or person as default, the last of them is kept and the
others are saved unmarked. If you expected both to stay marked, you wanted two addresses
with different types (for example Home and Work), not two defaults.

**Unticking Default on the address in use.** Refused, with "This is the address in use. To
change that, make another address the default, or delete this one." A household or person
is never left with no address in use while their standard address boxes still show the old
one. Choose **Set as default** on the address you want instead.

**The first address on a record.** The first address you add from the address card to a
household, organization or person with none is saved as the default, so it is in use straight
away. After that, a new address is added unmarked until you choose **Set as default**.

**Two defaults just after a merge.** When Salesforce's own merge combines two records that
each had a default address, the kept record briefly has both. Within a minute or so BarnCRM
keeps one: the one that matches the kept record's address boxes (billing for a household or
organization, mailing for a contact or a person account), or else the most recently created. The other stays on
the card as an ordinary address. This runs in the background because Salesforce does not let
anything change records while it is merging them.

**Filling in a seasonal address with no dates.** A Seasonal address needs all four date
boxes: start month, start day, end month, end day. Saving without them gives you
"A seasonal address needs a start month, a start day, an end month, and an end day so we
know when to use it." The day must be one its month has (April 31 is refused; February 29
is accepted). Fill in the four boxes, or change the type to Other if the address is
not really seasonal. A range that crosses New Year, such as November 1 to March 31, is one
range: enter it exactly that way, do not split it into two addresses.

**Putting an organization or another household in a household.** In an org that stores
people as person accounts, an address is copied into a household member's own mailing boxes.
A member that is not a person, for example an organization record that has been added to a
household by mistake, has no mailing boxes to copy into, so BarnCRM skips it and copies
the address to everyone else. The address still saves. If someone should have received the
address and did not, check that they are a person rather than an organization.

**Choosing more than one owner for an address.** An address belongs to a household, to an
organization, or to one person, never to two at once. If you fill in both a household and a
person you get "An address belongs to one household, one organization, or one person.
Choose only one." Clear the one you did not mean. If you want a person to have their own
address inside a household, put the person on it and leave the household blank.

**Deleting the default address.** You can delete it, and BarnCRM promotes the most
recently created remaining address to default so the household is never left with no
address in its standard boxes. An address that is not seasonal is preferred: a seasonal one
is promoted only when nothing else is left, so mail does not go to a winter home in July. If
the household has only one address, deleting it leaves the standard address boxes as they
were and nothing is promoted. Prefer adding a new
address and marking it default over deleting the old one: the old address is the record of
where a mailing actually went.

**Expecting the swap to happen without scheduling it.** Entering seasonal dates is not enough:
the nightly job has to be scheduled once, on the Addresses page of BarnCRM Settings. Until
you do that, the page says so in as many words and the home page tile says the swap has not run. If
the tile ever says the swap is scheduled but has not run in more than 36 hours, choose
**Run the swap now** and check the Error Log.

**Two seasonal addresses covering the same day.** If a household has a November to March
address and a December to February address, both cover Christmas. BarnCRM uses the one
that was added first, so the answer does not change from night to night, and writes a warning
to the Error Log naming the address. Fix the dates so that only one seasonal address covers
each day.

**Wondering what the Replaced By Seasonal box means.** It is how the job remembers which
address to put back in the spring, and you will see it ticked on the home address of a
household that is away for the season. It is set and cleared by the job and is read only on
the address record, so there is nothing for you to do with it. If it is ever missing when a
season ends, the job falls back to the most recently created address that is not seasonal,
which is usually the same address anyway.

**Deleting the address a season replaced.** The seasonal address stays in use and there is
nothing to put back when the season ends, unless the household has another address that is not
seasonal. Add the new year round address before deleting the old one, and the swap will find
it.
