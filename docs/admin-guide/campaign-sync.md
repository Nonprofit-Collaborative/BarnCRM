# Campaign Sync

## What it does

Open Impact records fundraising efforts as appeals. Salesforce has its own object for the
same idea, the Campaign, and many tools only understand that one: Campaign Members, email
marketing apps, event tools, and the Campaign reports your team may already use.

Campaign sync gives each appeal a matching Campaign and keeps it up to date. When David
creates the spring appeal, a Campaign named `Spring appeal` appears with the same dates,
goal and cost, and anyone who manages mailing lists can add Campaign Members to it straight
away. When David changes the appeal, the Campaign follows.

It works in one direction only. The appeal is the record you edit; the Campaign is a copy.

| On the appeal | On the Campaign |
|---|---|
| Name | Campaign Name |
| Description | Description |
| Start Date | Start Date |
| End Date | End Date |
| Goal | Expected Revenue in Campaign |
| Cost | Actual Cost in Campaign |
| Active | Active |
| Parent Appeal | Parent Campaign (the parent appeal's Campaign) |

Nothing else is written. A new Campaign takes your organization's usual Type and Status. The
Campaign's own money totals come from Opportunities, not from gifts, so they stay empty
unless your organization also mirrors gifts to Opportunities.

Campaign sync never deletes a Campaign you have. Deleting an appeal leaves its Campaign,
and its members, where they are. The one exception is a Campaign that **Sync all appeals**
created a moment earlier and then could not link to its appeal (see Common mistakes): it is
removed again, so the next run does not leave a second one beside it.

## How to turn it on

You need the Connect module installed, and a Salesforce edition that has Campaigns (Sales
Cloud, Service Cloud, or Nonprofit Cloud). An org on Salesforce Platform licenses only has no
Campaigns, and the Campaign sync page says so.

1. Give yourself the **Campaign Sync** permission set. Until the Module Manager arrives,
   module permission sets are assigned in Setup.
2. Open **Open Impact Settings**, choose **Giving**, and switch on **Copy appeals to
   Campaigns**.
3. Still in **Giving**, open **Campaign sync**. It shows how many appeals have a Campaign.
   Click **Sync all appeals** once, so the appeals you already had get their Campaigns.

**Who gets a Campaign when they save an appeal.** The Campaign is created with the access of
the person saving the appeal. Salesforce only lets someone create Campaigns when their user
record has the **Marketing User** box ticked and their profile or a permission set allows
creating and editing Campaigns. Both are in Setup. If David does not have them, his appeals
still save, but they get no Campaign until someone who does have them clicks **Sync all
appeals**. Choose one:

- tick **Marketing User** for the people who create appeals, and give them Campaign create
  and edit access; or
- leave their access as it is, and click **Sync all appeals** after a batch of new appeals.

Clicking **Sync all appeals** needs the Manage Open Impact Settings permission (the Open Impact
Admin permission set has it) as well as Campaign access.

**Two switches, one of them in charge.** **Copy appeals to Campaigns** in Open Impact Settings
is the switch that decides whether Campaign sync is on. The **Campaign sync** row on the
Automation page is the pause every Open Impact automation has. It stops only the copy made
when an appeal is saved, and it does nothing while **Copy appeals to Campaigns** is off. Leave
it on, and use **Copy appeals to Campaigns** to turn the feature on or off. **Sync all
appeals** follows **Copy appeals to Campaigns** alone.

**Very large saves.** When one save holds so many appeals that copying them would push it
past Salesforce's limits, for example a data load of thousands of appeals from Apex or a
tool that sends them in one transaction, the appeals save without their Campaigns and one
Warning says so. Click **Sync all appeals** afterwards. A load that sends 200 rows at a
time, as Data Loader does by default, is copied as usual.

## A five-minute walkthrough

Do this as Maria, in an org that has Campaigns, with the sample data loaded and Campaign
sync switched on as above.

1. Open **Open Impact Settings**, **Giving**, **Campaign sync**. Note the numbers: for
   example `0 of 6 appeals have a Campaign.`
2. Click **Sync all appeals**. The page says the sync has started. Wait a minute and reload
   the page: every appeal now has a Campaign.
3. Open the **Appeals** tab and click **New**. Name it `Giving Tuesday`, set a **Goal** of
   5,000 and a **Start Date**, and save.
4. Open the App Launcher, search for **Campaigns**, and open the list. `Giving Tuesday` is
   there, with Expected Revenue of 5,000 and the same start date.
5. Back on the appeal, change **Goal** to 7,500 and save. Reload the Campaign: its Expected
   Revenue is now 7,500.
6. Create a second appeal, `Giving Tuesday: matching challenge`, with **Parent Appeal** set
   to `Giving Tuesday`. Its Campaign shows `Giving Tuesday` as its Parent Campaign.
7. On the `Giving Tuesday` Campaign, add a Campaign Member. Open the appeal again: nothing
   about it changed, because the copy only goes from appeal to Campaign.

## Common mistakes

**An appeal has no Campaign.** The **Appeals and their Campaigns** list view on the
Appeals tab shows which ones: their Campaign ID is empty. Most often the person who created
it cannot create Campaigns (see How to turn it on). The Error Log has one Warning when such a
person creates appeals; later edits by the same person are skipped without a new Warning, so
the log does not fill up. Otherwise a rule on Campaign refused it: a validation rule or a
required field your organization added to Campaign. The Error Log has a Warning naming the
appeal and what Salesforce said. Fix the cause, then click **Sync all appeals**.

**Sync all appeals made a Campaign but the appeal still has none.** The Campaign was made,
but the appeal itself could not be saved with its Campaign ID: a rule on Appeal refused it,
or the person running the sync cannot edit that appeal. Campaign sync deletes the Campaign it
has just made, so the next run does not make a second one, and logs a Warning naming the
appeal. If that person cannot delete Campaigns either, the Warning names the Campaign that was
left behind: delete it, or paste its ID onto the appeal once the cause is fixed.

**A child appeal's Campaign has no Parent Campaign.** When a parent appeal and its child are
saved together and the parent's Campaign is refused, the child's Campaign is made without a
parent. Fix what refused the parent's Campaign, then click **Sync all appeals**: it puts
every child Campaign under its parent's.

**Editing a copied field on the Campaign.** The next time the appeal changes, its values
replace yours. Edit the appeal instead. Fields that are not copied, such as Type, Status or
your own custom fields, are never touched.

**Linking an appeal to a Campaign you already had.** Open the **Appeals** tab and choose
the **Appeals and their Campaigns** list view, which Campaign sync adds. It shows each
appeal's **Campaign ID**. Double-click the appeal's Campaign ID cell, paste the existing
Campaign's record ID (the 18-character code in its web address, starting `701`), and save.

Be sure it is the right Campaign. The moment you save, the appeal's name, description, dates,
goal, cost, active flag and parent are written onto that Campaign, replacing what it had, and
there is no undo. Paste the wrong Campaign's ID and that Campaign is renamed after your
appeal. One Campaign can belong to only one appeal: pasting an ID another appeal already
holds makes the save fail with a duplicate value error, and nothing is written. A value that
is not a Campaign's record ID is refused.

**A linked Campaign was deleted, or is not visible to you.** Campaign sync does not make a
replacement, because it cannot tell a deleted Campaign from one the person saving is not
allowed to see, and a replacement for a Campaign that still exists would be a duplicate. Each
change to the appeal logs a Warning saying the Campaign was deleted or is not visible. First
check, as someone who can see every Campaign, whether it still exists. If it does, give the
person who saves the appeal access to it. If it was deleted, clear the appeal's **Campaign
ID** in the **Appeals and their Campaigns** list view and save: a new Campaign is created.

**Turning Campaign sync off and expecting the Campaigns to go.** They stay. Switching it off
stops the copying and deletes nothing.

**Switching on in an org that already uses Campaigns, such as an NPSP org.** Sync all
appeals creates a new Campaign for every appeal that has none. If an appeal and an existing
Campaign are the same effort, link them by Campaign ID first (see above), then sync.
