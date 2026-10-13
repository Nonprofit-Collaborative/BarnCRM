# In-app tips

## What it does

BarnCRM ships four short tips that Salesforce shows the first time someone opens a BarnCRM
page where a pointer saves them a search through this guide. They use Salesforce's own
In-App Guidance (prompts), so they look and behave like any other Salesforce tip.

| Page (tab) | Kind of tip | What it says |
|---|---|---|
| BarnCRM Settings | Docked, bottom right | How the sections and search work, that changing a setting needs the BarnCRM Admin role, and where the Setup Assistant and the What's new card are |
| Import | Floating | Check the preview before you import; an import can be undone from Recent imports |
| Find | Floating | Run, save and export a query; bulk update and bulk delete start here |
| Bulk Update | Floating | The tab lists recent bulk updates and deletes with their undo; new ones start in Find |

Each tip appears once for each person, in the BarnCRM app only. The tips do not repeat the
Setup Assistant or the What's new card on the Home tab: those already show themselves on the
home page, so the Settings tip only says where they are.

Nobody needs a licence for these tips. They are single prompts, not walkthroughs, so they do
not count toward Salesforce's limit of three active walkthroughs in an org without the
Enablement add-on, and Salesforce sets no limit today on prompts installed with a package.

## How to turn it on

There is nothing to turn on. The tips are active as soon as BarnCRM is installed.

- **Who sees them:** anyone who opens the page in the BarnCRM app. A person who cannot open a
  tab (for example Import without the BarnCRM Admin role) never sees its tip.
- **How often:** once per person per tip. Salesforce also waits 24 hours between any two tips
  in the same app, counting your organization's own prompts, so someone who opens Settings and
  Import on their first day sees the Import tip on a later visit. BarnCRM does not skip that
  wait.
- **Where they do not appear:** in another app that has the same tabs, and in the Salesforce
  mobile app, which does not show in-app guidance.

## A five-minute walkthrough

1. As a person who has never opened BarnCRM Settings, open the **BarnCRM** app and the
   **BarnCRM Settings** tab. Result: a docked panel opens at the bottom right, headed "BarnCRM
   tips", with three short paragraphs.
2. Minimize the panel. Result: it closes. It does not come back on your next visit.
3. The next day, open the **Find** tab. Result: a small floating tip titled "Find exactly the
   records you need" appears.
4. Choose **Got it**. Result: the tip closes for good.

## Turning the tips off

The tips are managed in Salesforce Setup, not in BarnCRM Settings, because they are
Salesforce In-App Guidance: Salesforce gives an app no supported way to switch its prompts on
or off for you, and Setup is where your organization's own prompts are managed too.

- **Turn off one tip:** in Setup, type `In-App Guidance` in Quick Find and choose **In-App
  Guidance**. In the list, find the tip (each one's name starts with "BarnCRM"), open its menu
  and choose **Deactivate**.
- **Turn off every tip, BarnCRM's and your own:** on the same page, turn off custom in-app
  guidance. Salesforce then stops showing every custom and installed prompt in the org, not
  only BarnCRM's.
- **Show tips less often:** on the same page, change the time Salesforce waits between tips.
  It applies to every prompt in the org.

After a BarnCRM upgrade, check that the tips you turned off are still off.

## Common mistakes

- **"Nobody sees the Import tip."** Salesforce shows at most one tip per app per day. If your
  organization has its own prompts in the BarnCRM app, they share that allowance.
- **"I want to see the tip again."** A tip that has been closed does not come back for that
  person. This page and the page each tip points to say the same things.
- **"The tip is in English in our translated org."** Translate it in Setup, Translation
  Workbench, like your own prompts. BarnCRM ships the tips in English only.
- **"A tip covers part of the page."** Close it: it will not come back. Or deactivate it for
  everyone, as above.
