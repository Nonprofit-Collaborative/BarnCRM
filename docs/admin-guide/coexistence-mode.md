# Coexistence mode

## What it does

BarnCRM can be the only system in your Salesforce org that keeps households, or it can sit
alongside one that is already there. Coexistence mode is the one setting that records
which situation you are in. In this version it is a record of what is installed: it does not
read, adopt, or change any household data, and the only behaviour attached to it is that
choosing Nonprofit Cloud coexistence also switches household membership to the junction,
because Person Accounts require that.

Most organizations have nothing else in the org, and BarnCRM runs on its own: that is
**Standalone**, and it is the only mode most orgs ever see. BarnCRM reads your org the first
time you open the Setup Assistant or the Health Check, proposes the matching mode, and asks
you to confirm it. You can change it later, and nothing about it is permanent.

## The modes

BarnCRM offers only the modes that fit your org:

- **Standalone** is offered in every org.
- **NPSP coexistence** is offered only when the Nonprofit Success Pack (NPSP) is installed
  in your org.
- **Nonprofit Cloud coexistence** is offered only when Salesforce Nonprofit Cloud objects
  are in your org.
- The mode you saved is always offered, even if what it was chosen for is gone, so your
  choice is never hidden.

The Setup Assistant's second step and BarnCRM Settings offer the same list.

| Mode | Choose it when | What it changes |
|---|---|---|
| **Standalone** | Your org has no other household model. This is the default, and the recommendation in any org without NPSP or Nonprofit Cloud, including one with Person Accounts. | Nothing, in this version. How households group people is the separate **household membership** setting, which Standalone leaves as it is. In an org with Person Accounts, BarnCRM proposes junction membership (one membership record per person) because Person Accounts need it, but never overwrites a membership choice an administrator already made. |
| **NPSP coexistence** (only with NPSP) | NPSP is installed and you still want it working while you move. | Nothing, in this version. It records that NPSP is here. BarnCRM builds its own households and leaves NPSP's records alone. Feeding NPSP's own totals arrives with the Mirror module (v0.6). |
| **Nonprofit Cloud coexistence** (only with Nonprofit Cloud) | Your org has Salesforce Nonprofit Cloud objects. | Household membership uses membership records rather than the person's account, so Person Accounts work properly and one person can belong to more than one household. Your Nonprofit Cloud objects are left alone. |

BarnCRM recommends Nonprofit Cloud coexistence when it finds Nonprofit Cloud objects,
otherwise NPSP coexistence when it finds NPSP, otherwise Standalone. If you are not sure,
take the mode BarnCRM proposes. It reads your org, it does not guess.

## How to turn it on

Coexistence mode is always on: every org has a mode. What you do is confirm or change it.

1. Open the **BarnCRM** app.
2. Click the **BarnCRM Settings** tab.
3. Choose **General** in the left navigation.
4. Find **Coexistence mode**. It shows the current mode and, underneath, a description of
   it. What BarnCRM detected in your org is shown on the **Health** page and in the Setup
   Assistant's second step.
5. Pick a mode and click **Save**.

You need the **Manage BarnCRM Settings** permission to change it. If you do not have it,
the setting is visible but greyed out and the page tells you which permission to ask for.
Everyone with the BarnCRM Admin role has it.

There is nothing to do in Salesforce Setup. Detection happens inside the app.

## A five-minute walkthrough

Maria has just installed BarnCRM into her organization's Salesforce org. Person Accounts
are on, because that is how the org was set up for her two years ago, and nothing else that
keeps households is installed.

1. Maria opens the **BarnCRM Admin** app, clicks the **BarnCRM Settings** tab, and chooses
   **Health** in the left navigation.
2. Health Check runs. The first card is **What we found in your org**.
3. It says Person Accounts are enabled, and the recommended mode is **Standalone**.
4. Below the card there is a finding titled **Coexistence mode is not confirmed yet**, with
   the button **Use recommended mode**.
5. Maria clicks **Use recommended mode**. The page saves Standalone, re-runs itself, and the
   finding is replaced by **Coexistence mode matches your org**. Household membership is a
   separate setting: because her org has Person Accounts, BarnCRM proposes a membership
   record for each person, and never overwrites a membership choice already made.
6. She chooses **General** in the left navigation and sees Coexistence mode set to
   **Standalone**. The list offers only Standalone, because her org has neither NPSP nor
   Nonprofit Cloud. The change is in the settings history with her name and the time.

Total time: about two minutes. Nothing is locked.

**If your org has NPSP or Nonprofit Cloud**, the same walkthrough applies with different
words. With NPSP the card reads **NPSP detected** and the recommendation is **NPSP
coexistence**; household membership is left as it is. With Nonprofit Cloud the card reads
**Nonprofit Cloud objects detected** and the recommendation is **Nonprofit Cloud
coexistence**, which switches household membership to junction mode at the same time.

## Common mistakes

**Expecting the mode to sort out Person Accounts.** What matters in a Person Accounts org
is the household membership setting, not the mode. Confirming Nonprofit Cloud coexistence
switches membership to the junction for you; any other mode leaves a membership setting you
already chose alone. Health Check reports the wrong membership setting in a Person Accounts
org as an error with a one-click fix. Take the fix.

**Looking for a mode that is not in the list.** BarnCRM offers NPSP coexistence only when
NPSP is installed, and Nonprofit Cloud coexistence only when Nonprofit Cloud objects are in
the org. If you saved a mode earlier, it stays in the list. A mode you try to save that the
org does not offer is refused with "{0} is not a coexistence mode. Choose one of the modes
BarnCRM offers for this org.", with the mode you sent in place of {0}.

**Changing the mode to fix something else.** Coexistence mode is about what is installed in
your org, not about how you want households named or how records are entered. Those are
their own settings. If a household is named wrongly, change the naming settings, not the
mode.

**Expecting NPSP coexistence to take over your NPSP households.** It does not. BarnCRM
builds its own households in every mode, so an org with NPSP has NPSP's households and
BarnCRM's, and reconciling them is manual work in this version. Switching between NPSP
coexistence and Standalone changes nothing about that either way.

**Expecting the mode to move data.** Confirming a mode records what is in your org and, for
Nonprofit Cloud coexistence, sets household membership. It does not migrate anything, and
it does not touch your Nonprofit Cloud or NPSP records. Importing your old data is a
separate step in the Setup Assistant.
