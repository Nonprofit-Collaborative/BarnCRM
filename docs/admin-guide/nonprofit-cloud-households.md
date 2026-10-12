# Households you already have in Nonprofit Cloud

## What it does

Salesforce Nonprofit Cloud has its own way of grouping people into a household, and Open
Impact has its own way. If your org is already using the Nonprofit Cloud way, both kinds of
household can end up on the same record, pulling in different directions. Open Impact looks
for the households Nonprofit Cloud built, tells you what it found, and, since this release,
stays out of their way automatically: it never renames such a household, never rewrites its
formal or informal greeting, never writes its address, and never creates a second, duplicate
Open Impact household for someone already grouped by Nonprofit Cloud.

Nothing is moved, merged, or taken over. Each guard only ever leaves a record alone; none of
them changes what Nonprofit Cloud already has.

## How to turn it on

There is nothing to turn on. The guards run automatically, every time the naming batch runs,
every time a household's membership changes, every time an address is saved, and every time a
new person would otherwise get a household of their own. Health Check reads your org every
time it runs.

1. Open the **Open Impact** app.
2. Click the **Open Impact Settings** tab.
3. Choose **Health** in the left navigation.
4. Read the **What we found in your org** card. If your org has households built the
   Nonprofit Cloud way, the card says so and gives you the number it counted, as information:
   this is expected, and it is Open Impact leaving those households alone.
5. If any Account is both an Open Impact household and a Nonprofit Cloud household at once,
   a separate warning names how many. That is the one case worth looking at: pick one model
   for each of those Accounts.

If Open Impact cannot count native households, it says that instead of showing you a number.
That happens when your own permissions do not let you read them, which is common and is not a
problem with your org. When the answer is not certain, Open Impact assumes the households are
there and stays out of their way. It would rather leave your data alone than tidy up something
that was never its to tidy.

## A five-minute walkthrough

Maria has installed Open Impact into an org that has been running Nonprofit Cloud for two
years. Her colleagues have been grouping families there the whole time.

1. Maria opens the **Open Impact** app, clicks **Open Impact Settings**, and chooses
   **Health**.
2. The **What we found in your org** card tells her that this org already has households
   built the Nonprofit Cloud way, and how many.
3. She decides which way her organization is going to group families from now on. She picks
   one, and only one.
4. If she keeps using the Nonprofit Cloud households, she leaves Open Impact's household
   features alone and does not create Open Impact households for those families.
5. If she moves to Open Impact households, she does it for families that do not already have a
   Nonprofit Cloud household, and she leaves the ones that do until a migration is available.
6. She writes down which choice she made, so that the next person to enter a family knows
   where it goes.

Total time: about five minutes, and the only real work is step 3.

## Common mistakes

**Expecting Open Impact to take the households over.** It does not. An account that already
carries a Nonprofit Cloud household is left to Nonprofit Cloud: Open Impact will not name it,
will not rewrite its greetings, will not write its address, will not tidy it up, and will not
delete it when it looks empty, because to Open Impact it always looks empty.

**Waiting for the migration.** A tool to move households from one model to the other is
planned, but it does not exist yet, and there is no date for it. Nothing in this version
moves them. If you need them moved today, that is manual work.

**Running both models on the same family.** This is the one the collision warning on the
Health page exists to catch, and it is still worth avoiding: the family is grouped in
Nonprofit Cloud, someone else groups it again in Open Impact, and now two records disagree
about who lives in that house. Open Impact's guards leave that Account's name, greetings and
address exactly as they are rather than guess which model should win, but reports can still
double up and letters can still go out twice while both models stand. Pick one model per
household and stay with it.

**Expecting the guard to catch every native household.** It only recognizes an Account that
already carries a native household group or native membership rows. A person who belongs to a
Nonprofit Cloud household only through membership data Open Impact cannot see, and whose own
record carries no link to that Account yet, can still be given an Open Impact household. This
is deliberate: the alternative would be a query against `AccountContactRelation`, which Core
cannot run on a Platform-only org.

**Reading a missing number as a zero.** If the card cannot give you a count, that means
nobody could count them, not that there are none. Ask a colleague with fuller access to look,
or ask whoever set up your Nonprofit Cloud org.
