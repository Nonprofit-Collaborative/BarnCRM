# Stewardship plans

## What it does

A stewardship plan is a sequence of follow-up work your organization repeats. Somebody gives
for the first time, and three things should happen: a thank-you call this week, a welcome
packet next week, a check-in call in a month. A plan writes that sequence down once, and
then lays the tasks out for you every time it applies.

Open Impact can start a plan by itself when a gift arrives or when a pledge begins, or a
person can start one by hand on a donor. Either way, the plan creates ordinary Salesforce tasks, assigned to real
people, with real due dates. Your team works them in the same list they already use.

Three things to hold on to, because they are the questions people ask first:

- **A plan is laid out once, when it starts.** Editing a template later does not reach back
  into plans already running. The tasks are in somebody's list and they have planned their
  week around them.
- **Open Impact never deletes a task it created.** Cancelling a plan marks the plan
  cancelled and leaves the tasks alone, because a task is a record of somebody's work.
  Closing the leftovers is theirs to do.
- **You close a plan yourself.** Open Impact does not mark a plan complete when its last
  task closes. See "What this does not do yet" at the end.

## How to set one up

Everything is in the app. You never open Setup.

Open **Open Impact Settings**, choose the **Giving** section, and open **Stewardship plans**.
The page lists every plan you have written down, how many steps each one lays out, how many
copies of it are running right now, and whether it is switched on.

1. Choose **New plan** and fill in:
   - a **plan name**, the one your team will recognize, for example "First gift welcome";
   - a **plan key**, a short unchanging code such as `first_gift_welcome`. You will not
     see it again. It is how Open Impact recognizes the plan across upgrades even if you
     rename it;
   - **what starts it**:
     - **Manual**: nothing starts it automatically. Somebody starts it on a donor.
     - **First gift**: starts when a donor's first gift arrives.
     - **Gift received**: starts on any gift.
     - **Commitment started**: starts when a pledge or recurring gift becomes active,
       either because it was entered active or because somebody turned it on later.
   - a **smallest gift that starts it**, optional, and only for the two gift events. Set it
     to 1000 and the plan waits for a gift of a thousand or more. Leave it empty for any
     gift;
   - a **description**, optional, which is what somebody reads when picking a plan to start
     by hand.
2. Leave **On** unchecked until the steps are in. A plan that is off starts nothing.
3. Choose the plan's name in the list to open its steps, then **Add step** for each task,
   with:
   - a **subject**, which is the line the assignee sees in their task list. Write it as an
     instruction: "Call to say thank you", not "Thank you";
   - **days after start**, which is how many days after the plan starts the task is due.
     Zero means the day it starts;
   - **assign to**: **Record owner** gives the task to whoever owns the donor record,
     **Plan starter** gives it to whoever started the plan, and **Specific user** gives it
     to one named person every time;
   - a **priority**;
   - **comments**, optional, which become the task's description.
4. Use **Move up** and **Move down** to put the steps in the order they should happen.
5. Choose **Turn on** in the plan's row when the steps are right.

The page says it where you will read it, and it is worth repeating: editing a plan changes
what starts next. The number in **Running now** is how many copies of that plan are already
laid out, and none of them changes when you edit it.

## A five-minute walkthrough

1. Open **Open Impact Settings**, **Giving**, **Stewardship plans**, and choose **New plan**.
   Call it "First gift welcome", key `first_gift_welcome`, started by **First gift**, no
   smallest gift. Leave **On** unchecked and save.
2. Choose the plan in the list, then add three steps:
   - "Call to say thank you", 1 day after start, Record owner, High;
   - "Send the welcome packet", 7 days after start, Record owner, Normal;
   - "Check in and ask what drew them to us", 30 days after start, Record owner, Normal.
3. Choose **Turn on** in the plan's row.
4. Record a gift for a donor who has never given before.
5. Open that donor. Under **Stewardship Plans** you will see one running plan, and three
   tasks now sit in the record owner's list, due tomorrow, next week, and next month.
6. Go back to the page. The plan now says **1** under Running now.

## Common mistakes

- **Steps added after the plan started.** They do not appear on plans already running.
  Add the step, and the next plan to start gets it.
- **A minimum amount on a manual plan.** Open Impact refuses this at save. A minimum only
  means something for the two gift events, and left on a manual plan it reads like a
  condition that is quietly never applied.
- **Assign To set to Specific user with nobody named.** Refused at save, for the same
  reason. If the named person later becomes inactive, the task goes to whoever started the
  plan rather than to nobody.
- **Expecting the same plan to run twice on one donor.** It will not, while the first one
  is still running. Mark the running one complete or cancelled first. This is what stops a
  donor getting the same three tasks every time they give.
- **Expecting a bulk import to start hundreds of plans.** Switch stewardship off before a
  bulk load, on the **Automation** page in Open Impact Settings, and the records load quietly.
  There are two switches, one for gifts and one for commitments, so stopping a year of
  gifts does not stop the pledges your team enters by hand. Switching either back on does
  not catch up what it missed: a welcome for a gift from three weeks ago is not a welcome.
- **Expecting a paused pledge to start the plan again when it resumes.** Turning a
  commitment back on is a start, but the plan it started the first time is probably still
  running, and the same plan does not run twice on one donor. Mark the first one complete
  or cancelled if you want the sequence laid out again.

## What this does not do yet

- **Open Impact does not close a plan for you.** When the last task on a plan closes, the
  plan stays Running until somebody marks it Complete. Closing it automatically would need
  Open Impact to put automation on the Task object, which it does not ship. Use the
  **Running Plans** list view to see what is still open.
