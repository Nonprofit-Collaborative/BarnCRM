# Health Check

## What it does

Health Check looks at your org and tells you, in plain language, whether Open Impact is set
up the way it should be. It reports what it found in your org (what else is installed, which
licenses are in play), whether your coexistence mode matches that, who can and cannot get
into the app, and anything that is currently getting in the way, such as paused automation
or errors nobody has looked at.

Every finding says what is wrong and what to do about it, and most of them have a button.
Some buttons take you to the page where you decide. Others fix the problem on the spot, but
only when there is exactly one right answer, and only after you confirm (see **How a fix
button works** below).

Run it after you install, after you add people, and any time something feels wrong.

## How to turn it on

Health Check is on as soon as Open Impact is installed. There is nothing to enable and
nothing to configure.

1. Open the **Open Impact** app.
2. Click the **Open Impact Settings** tab.
3. Choose **Health** in the left navigation. The report is there.
4. Click **Re-run** whenever you want a fresh look. Health Check reads your org each time;
   it never shows you a saved result.

The Open Impact home page does not carry a Health Check card today, although the Hub
itself has shipped. The settings console is the way in, and it is the way that always
works.

To act on a finding you need the **Manage Open Impact Settings** permission, which the
Open Impact Admin role includes. Without it you can still read most of the report: the page says
so at the top and the Fix buttons are hidden. Three checks are skipped for you rather than
answered wrongly, because Salesforce only lets you see your own access: who holds the
Open Impact Admin role, who holds the Override Receipt Lock permission (asked only where Giving is installed), and how many errors
nobody has read. In their place you get one line, **Sign in as an Open Impact Admin to see the
access checks**.

## A five-minute walkthrough

Maria has just installed Open Impact into her organization's Nonprofit Cloud org. Person
Accounts are on. She has not set anything up yet.

1. Maria opens the **Open Impact** app, clicks **Open Impact Settings**, and chooses
   **Health**.
2. The first card is **What we found in your org**. It reads:
   **Person Accounts enabled. Agentforce Nonprofit objects detected.** Under it, the card
   shows the mode this org is in now and the mode Open Impact recommends:
   **Agentforce Nonprofit coexistence**.
3. Below the card, the findings are grouped: **Your org**, **Licenses**, **Access**, and
   **Settings**. Each finding has an icon: a red circle for something that needs fixing, an
   amber triangle for something to be aware of, a blue dot for information.
4. The first finding is blue, **Your org at a glance**, and it repeats what was found in a
   sentence, adds that Open Impact supports this org shape directly, and says that Shield
   Platform Encryption cannot be detected from inside the app. If her org uses it, she should
   say so before she loads data.
5. The next finding is amber: **Coexistence mode is not confirmed yet**. It explains that
   Open Impact is running as Standalone but this org is a Nonprofit Cloud org, and that until
   she confirms, households will be built the wrong way for Person Accounts. There is a
   button, **Use recommended mode**.
6. Maria clicks **Use recommended mode**. The page saves Agentforce Nonprofit coexistence,
   switches household membership to junction mode with it, and re-runs. The amber finding is
   replaced by a blue one: **Coexistence mode matches your org**.
7. Under **Access** there is a red finding: **No one is assigned the Open Impact Admin role**.
   She clicks **Open the Access page**, which takes her to the Access section of Open Impact
   Settings, adds herself, and comes back to Health.
8. Another finding is amber: **4 users cannot see the app**. Four active users have a
   Salesforce license but none of the Open Impact roles, so the Open Impact app is invisible to
   them. She clicks **Open the Access page** again and assigns roles.
9. There is a blue finding too: **The Gift Transaction mirror is in the Connect module**.
   Her org has Nonprofit Cloud gift objects and the Connect module is not installed, so if she
   wants Nonprofit Cloud's own donor summaries to keep working, that is what she will install
   in v0.6. Nothing is broken today.
10. She clicks **Re-run**. The red finding is gone, the amber ones are gone, and what is left
    is blue: her org shape, the mode, the Connect note, and **Automation is running normally**.

Total time: about five minutes, most of it assigning roles.

**If your org has the Nonprofit Success Pack instead**, step 2 reads **NPSP detected** and the
recommendation in step 5 is **NPSP coexistence**. Everything else is the same.

## What Health Check looks at

| Group | What it checks |
|---|---|
| Your org | What else is installed: Person Accounts, Nonprofit Cloud objects, the Nonprofit Success Pack, standard Sales and Service Cloud objects. |
| Your org | Whether your coexistence mode matches what was found. |
| Your org | Whether household membership is still set to the person's account while Person Accounts are on, which does not work. |
| Your org | Whether your org has Nonprofit Cloud gift objects while the Connect module is not installed. |
| Settings | Whether household membership uses membership records while automatic household creation is off, which means no new person gets a household. |
| Licenses | Whether the org uses more than one currency, which Open Impact does not support yet. |
| Access | Whether anyone holds the Open Impact Admin role. |
| Access | Whether active users with a Salesforce license have no Open Impact role at all. |
| Access | With Giving: whether anyone holds the Override Receipt Lock permission, which is meant to be granted for one correction and taken away again. |
| Settings | Whether Open Impact automation is paused, and says so plainly when it is running. A pause that nothing is set to end, or that ends more than 24 hours from now, is a warning. |
| Settings | Whether there are new entries in the Error Log that nobody has looked at. |
| Settings | Whether the error digest is scheduled but has not run for more than two days, which usually means the person who scheduled it was deactivated. |
| Settings | Whether anybody is in no household while every new person is meant to get one. |
| Settings | Whether any household has nobody in it. |
| Settings | Whether the fiscal year in Setup is the same month as the fiscal year start month in Open Impact Settings. |
| Settings | With Giving: whether receipts have been voided with the reason "Generation failed", which is a receipt run that did not finish. |
| Settings | Whether any of the totals Open Impact ships are missing from the Rollups page. |
| Settings | Whether any Open Impact automation is missing its on and off switch on the Automation page. |
| Settings | Whether any import template Open Impact ships is missing from the Import page. |
| Settings | Whether a total is set to be recalculated nightly while the nightly run is not scheduled. |
| Settings | Whether any gift dated in a closed accounting period has not been marked posted to accounting. |
| Settings | With Connect: whether the Opportunity mirror's nightly run is scheduled but has not completed a run for more than two days. |

Five of those are new: the Override Receipt Lock permission, the two fiscal years, the
failed receipts, the unposted gifts in a closed period, and the stalled Opportunity mirror. Each one is a quiet problem, where
nothing looks broken and the cost arrives months later, so each is explained in full below.

## The five quiet findings

| Finding | What it means | Why it matters | What to do |
|---|---|---|---|
| **Someone can override the receipt lock** | One or more active people hold the **Override Receipt Lock** permission. Open Impact ships it assigned to nobody. | That permission is the only way to change or delete a gift that carries a receipt number. It is meant to be granted in Setup for one correction and removed the same day. Left assigned, the guarantee that a receipted gift cannot change quietly stops being a guarantee, and nothing in the app will tell you again. | Read the names in the finding. If nobody is in the middle of a correction right now, open **Setup, Custom Permissions, Override Receipt Lock** and take it off the permission set or profile that grants it. Every change made with it is already in the Error Log at Warning severity, so you can see what it was used for. |
| **Your two fiscal years disagree** | The fiscal year in **Setup** starts in a different month from **Fiscal Year Start Month** in Open Impact Settings. | Open Impact computes Giving This Year, Giving Last Year and Giving Two Years Ago from its own setting, and the packaged retention reports (LYBUNT, SYBUNT, new versus retained, conversion) read the fiscal year from Setup. When the two disagree, every one of those numbers is measured on a different year boundary. Nothing errors: a donor simply appears on the LYBUNT list while their Giving This Year is not zero, and usually nobody asks until a year end number is questioned. | Decide which month is right, then set both to it: **Setup, Company Information, Fiscal Year**, and **Open Impact Settings, General, Fiscal Year Start Month**. The **Open general settings** button on the finding takes you to the second one. Recalculate rollups afterwards. |
| **Receipts failed to generate** | There are receipts with status **Void** and the reason **Generation failed**. | Every receipt number is used once. When a document fails to generate after its number was handed out, Open Impact records the number as a void receipt so an auditor asking what happened to number 47 gets an answer. One of those is ordinary. A number of them means receipt generation is failing over and over, donors are not getting the documents they are waiting for, and nobody has looked. | Open the Error Log from the finding and read the receipt entries: they say what failed. Fix the cause (most often a missing letter template or a donor with no address), then re-run the receipt or the statement run. The void records stay: they are the audit trail for the numbers that were consumed, and deleting them is not a fix. |
| **Gifts in a closed period are not posted** | One or more gifts are dated on or before **Books Closed Through**, so they are already locked from editing, but nothing has marked them **Posted to Accounting**. | A gift in this state fell into a closed period without the ordinary export-and-mark step ever reaching it: the period was closed before it was exported, or it was entered after the close. Either way, your books and Open Impact can quietly disagree about what has actually been recorded, and the gift is now locked, so nobody can fix it by editing the gift itself. | Read the linked gifts. If they genuinely belong in the export you already sent your accounting system, mark them posted from the **Accounting Export** page in Connect. Without Connect, or if they should not have been closed yet, move **Books Closed Through** back on the Accounting Periods page, which needs the **Override Posting Lock** permission and is written to the Error Log. The **Open Giving settings** button on the finding opens the Giving section, which the Accounting Periods page lives in. |
| **The Opportunity mirror has not run** | The Opportunity mirror's nightly run is scheduled and a direction is chosen, but no run has completed for more than two days. | The scheduled run executes as the person who scheduled it. When that person is deactivated, or loses the Opportunity Mirror permission set or Opportunity access, every run fails before it starts, and gifts and Opportunities quietly drift apart. | Open **Opportunity mirror** from the Giving section of Open Impact Settings, read **Last completed run**, then **Stop nightly run** and **Schedule nightly** again as someone who can still run it. The Error Log says why the runs failed. |

## How a fix button works

Most buttons open a page. A button that changes something in your org works like this:

1. The finding says exactly what the fix will do, counted from your org: for example
   **3 shipped totals are missing**, followed by their names (Total Gifts, Largest Gift, Last
   Gift Date) and what the fix will create.
2. Click the button. A box headed **Before this fix runs** opens at the top of the panel, the
   page scrolls to it, and it shows that sentence again with **Confirm** and **Cancel**.
   Nothing has changed yet. **Cancel** or the Escape key closes it and takes you back to the
   button.
3. Click **Confirm**. The fix runs, the panel says what it did (for example **Done. Created:
   Total Gifts, Largest Gift, Last Gift Date.**), and Health Check re-runs underneath it. If it
   fails, nothing is changed, the panel says so in a sentence, and the details are in the Error
   Log.

The fix creates exactly what the box showed you. If something changed since Health Check last
ran, for example a colleague restored the same totals a minute ago, the fix does nothing, says
so, and Health Check runs again so you can read the finding as it is now.

Every fix that runs is recorded under **Recent changes** in Open Impact Settings, as
**Health Check:** followed by the button's name, with what it created, your name and the time.

Every fix only creates something that is missing or switches on something that is off. No
fix deletes anything or changes a value you chose, and pressing it twice does no more than
pressing it once. Most can be undone on their own page:

| Finding | What the fix does | How to undo it |
|---|---|---|
| **Shipped totals are missing** | Creates the missing totals exactly as shipped. Each one starts calculating donor totals straight away, as it would have from install. Your own totals are not touched, and a shipped total whose field one of your own active totals already writes is skipped and named, so the two never overwrite each other. | Switch a total off on the Rollups page. Do not delete it: a deleted shipped total comes back the next time totals are restored or the package is upgraded (see Rollups). |
| **Automation switches are missing** | Creates the missing switches, each set to its shipped default, so nothing that runs now stops. An automation that always runs, such as the receipt lock, is listed with its switch locked. | Switch any automation off on the Automation page. |
| **Shipped import templates are missing** | Creates the missing templates. | There is no undo in the app: the Import page cannot delete or switch off a template. A template does nothing until somebody picks it for an import. |
| **Nightly totals are not scheduled** | Schedules the nightly run at 2:00 AM. | **Stop the nightly recalculation** on the Rollups page. |
| **Coexistence mode is not confirmed**, **Household membership does not fit Person Accounts**, **No new person is getting a household** | As described in the walkthrough and Common mistakes. | Change the setting back in Open Impact Settings. |

Some findings deliberately have no fix button, because the answer is yours to choose: who
should be an Open Impact Admin when nobody is, whether paused automation should resume, what
to do about errors in the Error Log, and what should become of a person with no household or
a household with nobody in it.

## People with no household, and households with nobody in them

Health Check finds these and links them; it never changes them. Cleaning them up in bulk
belongs to the data hygiene console, planned for a later release.

| Finding | Who is counted | Who is not counted | What to do |
|---|---|---|---|
| **People are not in a household** (amber) | With household membership on the person's account: every contact with no account. With membership records: every person, contact or person account, with no current membership (no end date, or one still to come). | A contact whose account is an organization: that person belongs to the organization. With membership records, a contact linked straight to a household: the separate membership finding covers it. Nobody at all while automatic household creation is off, because then a person without a household is your choice. | Open each linked person. With membership on the account, set the account to a household. With membership records, add them from the household's members panel. |
| **Households have nobody in them** (blue) | Households with no contact on them, or with membership records, no current member. | Organizations. | Open each linked household and add a member, merge it into another household, or delete it. Some are kept on purpose, for example when **Delete a household once it is empty** is off (Open Impact Settings, Households), or when merging two people emptied it: a merge never deletes a household, because gifts are credited to it, so merge it into the kept person's household (see Duplicates). |

Each finding counts up to 1,000 and then says **More than 1,000**, so a large org gets its
answer quickly, and links the first five records, oldest first. The counts use your own
access, so these two findings are shown only to people with the Manage Open Impact Settings
permission. In an org that also has Nonprofit Cloud households, some of the people and
households listed may belong to one: Open Impact cannot see that membership, and the finding
says so.

The four checks about shipped totals, switches, templates and the nightly run are shown only to
people with the Manage Open Impact Settings permission, because only they can act on them. The
two household checks are shown only to them too, for the reason given above.

If one check cannot run, the rest still run. The check that failed appears as its own finding
saying so, and the details are written to the Error Log.

## Common mistakes

**Treating an amber finding as a failure.** Amber means "be aware of this", not "broken".
Multi-currency, for example, is amber forever if your org uses more than one currency: Open
Impact will not break, it simply does not do currency conversion yet, and there is nothing
you can do to make the finding go away.

**Leaving "no new person is getting a household" unfixed.** That red finding means household
membership is set to the flexible mode and "create a household automatically" is off, so
every person saved from now on is left without a household and nothing else says so. Click
**Turn on automatic households** on the finding. If your org groups people another way and
means to leave it off, the finding stays, and it stays red, because the people being saved
today are the ones somebody has to group by hand later.

**Ignoring the red membership finding in a Person Accounts org.** "Household membership does
not fit Person Accounts" is red for a reason: in that state, new households are built through
the person's account, which in a Person Accounts org is the person. Click **Switch to junction
membership** and the app fixes it for you. The longer it waits, the more households have to be
sorted out afterward.

**Fixing access by editing profiles.** Health Check counts the packaged roles the Access page
assigns, and the packaged permission sets behind them if you assigned one by hand. A profile
change or a permission set of your own may well let someone in, but Health Check will still
list them, because the packaged roles are what the app relies on.

**Reading the access findings from someone else's screen.** Salesforce only lets a person see
their own access, so for anyone without the Manage Open Impact Settings permission Health Check
skips the two access counts rather than printing a number it cannot stand behind. If the report
you are looking at says **Sign in as an Open Impact Admin to see the access checks**, that is why:
run it again as an administrator.

**Treating the Override Receipt Lock finding as a formality.** It is amber rather than red
because the permission may be legitimately assigned for the next ten minutes. It is on the
report because the failure mode is forgetting: nobody notices a permission that is still
assigned six months later, and while it is assigned, an issued receipt no longer means the
gift behind it cannot change.

**Fixing the fiscal year in one place.** Setting Open Impact Settings and leaving Setup alone
(or the reverse) leaves the finding on the report and the reports wrong. Both values are a
month, and they have to be the same month.

**Deleting the "Generation failed" receipts to clear the finding.** Those records are what
account for the numbers that were used. Deleting them turns an explained gap into an
unexplained one, and the receipts still will not generate. Fix the cause and re-run.

**Expecting a fix to tidy up.** The fixes only ever add what is missing. An automation switch
left behind by an older version, or a total you created yourself, stays where it is. Nothing
runs an automation whose switch is left over, so it does no harm.

**Scheduling the nightly run only for the finding to come back.** The nightly-run finding only
appears while at least one total is set to Scheduled or Both. If you switch every total to Real
time, the finding goes away without the schedule, which is also correct.

**Leaving automation paused.** Pausing automation for a bulk load is exactly right. Forgetting
to turn it back on means households stop being created and names stop being recomputed, quietly.
That is why the paused finding is always shown, with the time it expires. If you see it and you
are not in the middle of a load, resume automation. If it says **Automation is paused with no
automatic resume**, the pause will not end by itself on time: it was started before automatic
resume existed, or somewhere other than the Automation page. Resume it there and pause again
for a set time if you need to (see the [Automation control page](automation-control.md)).
