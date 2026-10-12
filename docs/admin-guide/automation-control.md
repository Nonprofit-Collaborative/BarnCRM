# Automation control

## What it does

Open Impact does small pieces of work for you in the background: it creates a household
for a new person, keeps household names and greetings up to date, and so on. Automation
control is the page where you can see every one of those pieces of work, read what it
does, and switch it off if it is getting in your way.

It also gives you one big switch: pause everything for a couple of hours while you load a
spreadsheet, then let it turn itself back on. You never have to call anyone to get
unstuck.

A small number of automations are not switches at all. They enforce a rule rather than
doing something for you, and Open Impact runs them whatever this page says: the receipt
lock on gifts is the first of them. They are still listed here, so you can find them and
read what they do, but their switch is off, greyed out, and carries a line explaining that
the automation always runs. See "Automations that always run" below.

## What you will see in v0.1

This page describes the finished feature. Two parts of it arrive with the next pieces of
v0.1, and until they do the walkthrough below cannot be completed end to end:

- The Open Impact app, its home page, and the Open Impact Settings console are built by
  feature C-03. Until then there is no page to put automation control on.
- The list of automations is empty, because the first automations (creating households,
  naming them) arrive with feature C-01. Until then the page says so rather than listing
  anything, and the pause button works on nothing.

The pause itself, the switches, the banner and the audit trail are all built and tested.

## How to turn it on

Automation control is on as soon as Open Impact is installed. There is nothing to enable
and nothing to install: installing or upgrading each package creates the switch for every
automation it ships, and leaves every switch you already have as you set it. If a switch is
ever missing, the automation still runs, and Health Check names it and offers to restore it.

You will find it in two places:

- **Open Impact Settings, then Automation.** This is the full page: the list of every
  automation with its on and off switch, and the pause button.
- **The Open Impact home page.** While automation is paused, a banner appears at the top
  of the home page telling you what is paused and when it will come back on.

Changing anything on this page requires the Manage Open Impact Settings permission, which
comes with the Open Impact Admin role. If you do not have it, the page still opens and you
can read everything, but the switches are greyed out and a message names the permission
you need to ask for.

## A five-minute walkthrough

Maria is about to load a spreadsheet of 400 people from a partner organization. She wants
the records in first and the automatic housekeeping to happen afterwards, so nothing runs
400 times while she is watching.

1. Open the **Open Impact** app and click **Open Impact Settings**.
2. In the left navigation, click **Automation**. You see a list of every piece of
   automation Open Impact ships, each with a plain-language description and a switch.
3. At the top of the page, choose **2 hours** in the **How long** list, then click
   **Pause all automation**. The page now shows a yellow bar: "Automation is paused until
   3:40 PM. Paused by Maria Lopez. It turns itself back on then." Every switch in the list
   is still where you left it: pausing does not change anything you have chosen.
4. Click **Home**. The same banner appears at the top of the Hub, so anyone else working
   today can see why records are not updating themselves.
5. Load your spreadsheet. Nothing runs automatically while you do.
6. Come back to **Open Impact Settings**, then **Automation**, and click **Resume
   automation**. The banner disappears and the automation starts running again on the next
   record anyone saves. If you forget this step, nothing breaks: automation turns itself
   back on at the two hour mark, and the change is recorded like any other (see "How long
   a pause lasts" below).
7. Now switch off a single automation instead. Find **Household naming** in the list and
   click its switch to **Off**. Only that one stops running. Everything else carries on.
   (In v0.1 the list is empty until feature C-01 adds the first automations, so there is
   nothing to switch yet.)
8. Switch it back **On**. Every change you make here is recorded with your name, the time,
   and what the value was before, so you can always see who changed what.

That is the whole feature: one switch per automation, one switch for all of them, and it
expires by itself.

## How long a pause lasts

You choose the length when you pause: 1, 2, 4, 8 or 24 hours. Two hours is already
selected, because most spreadsheet loads are done in less. There is no longer choice and no
"until I say so": a pause always ends by itself.

When the time is up, automation starts again at that moment, whether or not anybody has the
page open. Open Impact also writes the end of the pause into the list of recent changes at the
bottom of Open Impact Settings, with the time it ended and the name of the person who paused, as
if they had clicked **Resume automation** themselves. So the list always shows every pause
with its start and its end.

Clicking **Resume automation** early, or pausing again to get more time, replaces the
scheduled end: the new length counts from the moment you click.

If Health Check says **Automation is paused with no automatic resume**, a pause is in effect
that nothing is set to end: usually one started before this version of Open Impact, or one
set somewhere other than this page. Open this page, click **Resume automation**, and pause
again for a set time if you still need to.

## Automations that always run

Pause stops Open Impact filling things in for you. It never stops Open Impact refusing
something. An automation whose job is to refuse a change, rather than to save you typing,
is marked as always running, and neither the pause nor its own switch turns it off.

In the list you can tell one at a glance: its switch sits at **Off** and is greyed out even
when you hold the Manage Open Impact Settings permission, and underneath the description is
the line "This automation enforces a rule, so it always runs. It cannot be switched off
here and a pause does not suspend it." Clicking the switch does nothing, and if a change
somehow reaches the server it is refused with the same explanation.

Three ship today:

- **Gift: receipt lock** refuses a change to the amount, the date, the donor or the receipt
  number of a gift that carries a receipt number, and refuses to delete such a gift. That
  rule is what a receipt in a donor's hands means: see the [Gifts page](gifts.md).
- **Gift: posting lock** and **Gift Allocation: posting lock** refuse a change to a gift that
  is posted to accounting or dated in a closed period, and to its funds, and refuse a new gift
  in a closed period. See [Posting and Closed Periods](posting-and-closed-periods.md); that
  lock has its own override, Override Posting Lock.

If you genuinely have to change a receipted gift, there is a way, and it is deliberately
not on this page. It is the Override Receipt Lock permission, described under "Lifting the
receipt lock" on the [Gifts page](gifts.md). Every change made with it is written to the
[Error Log](error-log.md).

## Common mistakes

- **Expecting the pause to last longer than 24 hours.** It cannot. For a load that runs
  over several days, pause again each morning, or switch off only the automation that is
  in your way: a switch stays where you put it.
- **Pausing and forgetting, then wondering why names are wrong.** While automation is
  paused, new people do not get households and names are not recomputed. The records are
  fine, they are just not finished. Resume automation and then re-save the records, or run
  the recompute action on the Households page.
- **Expecting the pause to suspend everything.** It does not, and it never did what its
  name suggests for the rules that refuse a change. The pause stops the housekeeping:
  households, names, greetings, default allocations. An automation marked as always running
  keeps running through the pause, so a receipted gift stays locked while everything else is
  paused for your import.
- **Expecting pause to undo work already done.** Pause stops future automation. It does
  not roll back anything that already ran. If something ran that you did not want, fix the
  records themselves.
- **Switching an automation off to stop an error, and never switching it back on.** An
  automation that is off is a piece of your setup that has quietly stopped working. Look at
  the Error Log first: it usually tells you what to fix in the data, and then you can leave
  the automation on. See the [Error Log page](error-log.md).
- **Assuming a pause covers other people's work.** The pause is for the whole organization,
  not for you alone. Anyone saving a record during the pause gets the same behavior, so say
  something in your team channel before you pause during working hours.
- **Looking for the switches with the wrong role.** If the switches are greyed out, you are
  signed in as a user without the Manage Open Impact Settings permission. Ask whoever
  administers your Salesforce to give you the Open Impact Admin role.
