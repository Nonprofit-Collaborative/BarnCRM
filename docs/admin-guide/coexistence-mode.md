# Coexistence mode

## What it does

Open Impact can be the only fundraising system in your Salesforce org, or it can sit
alongside something that is already there. Coexistence mode is the one setting that records
which situation you are in. In this version it is a record of what is installed: it does not
read, adopt, or change any household data, and the only behaviour attached to it is that
choosing Agentforce Nonprofit coexistence also switches household membership to the
junction, because Person Accounts require that.

Most organizations arriving at Open Impact are already on Salesforce Nonprofit Cloud
(Agentforce Nonprofit), usually with Person Accounts turned on. That is the case Open Impact
is built to land in, and it has its own mode. Open Impact reads your org the first time you
open the Setup Assistant or the Health Check, proposes the matching mode, and asks you to
confirm it. You can change it later, and nothing about it is permanent.

## The three modes

| Mode | Choose it when | What it changes |
|---|---|---|
| **Agentforce Nonprofit coexistence** | Your org is on Nonprofit Cloud, or Person Accounts are turned on. This is the common case. | Household membership uses membership records rather than the person's account, so Person Accounts work properly and one person can belong to more than one household. Your Nonprofit Cloud objects are left alone. |
| **Standalone** | Your org is new, or it has never had a fundraising package in it. This is the default in a fresh org. | Nothing, in this version. How households group people is the separate **household membership** setting, which Standalone leaves as it is. |
| **NPSP coexistence** | The Nonprofit Success Pack is installed and you still want it working while you move. | Nothing, in this version. It records that NPSP is here. Open Impact builds its own households and leaves NPSP's records alone. Feeding NPSP's own totals arrives with the Connect module (v0.6). |

If you are not sure, take the mode Open Impact proposes. It reads your org, it does not
guess.

## How to turn it on

Coexistence mode is always on: every org has a mode. What you do is confirm or change it.

1. Open the **Open Impact** app.
2. Click the **Open Impact Settings** tab.
3. Choose **General** in the left navigation.
4. Find **Coexistence mode**. It shows the current mode and, underneath, what Open Impact
   detected in your org.
5. Pick a mode and click **Save**.

You need the **Manage Open Impact Settings** permission to change it. If you do not have it,
the setting is visible but greyed out and the page tells you which permission to ask for.
Everyone with the Open Impact Admin role has it.

There is nothing to do in Salesforce Setup. Detection happens inside the app.

## A five-minute walkthrough

Maria has just installed Open Impact into her organization's Nonprofit Cloud org. Person
Accounts are on, because that is how the org was set up for her two years ago.

1. Maria opens the **Open Impact** app, clicks the **Open Impact Settings** tab, and chooses
   **Health** in the left navigation.
2. Health Check runs. The first card is **What we found in your org**.
3. It reads **Person Accounts enabled. Agentforce Nonprofit objects detected.** Underneath,
   in plain language: this is a Nonprofit Cloud org, Open Impact supports it directly, and
   the recommended mode is **Agentforce Nonprofit coexistence**.
4. Below the card there is a finding titled **Coexistence mode is not confirmed yet**, with
   the button **Use recommended mode**.
5. Maria clicks **Use recommended mode**. The page saves Agentforce Nonprofit coexistence,
   switches household membership to junction mode at the same time (Person Accounts require
   it), re-runs itself, and the finding is replaced by **Coexistence mode matches your org**.
6. She chooses **General** in the left navigation and sees Coexistence mode set to
   **Agentforce Nonprofit coexistence**. The change is in the settings history with her name
   and the time.

Total time: about two minutes. If Maria disagrees with the recommendation, she picks a
different mode in step 6 and saves. Nothing is locked.

**If your org has the Nonprofit Success Pack instead**, the same walkthrough applies with
different words: the card reads **NPSP detected** and the recommendation is **NPSP
coexistence**. Household membership is left as it is, because only the Agentforce Nonprofit
mode changes it.

## Common mistakes

**Expecting the mode to sort out Person Accounts.** What matters in a Person Accounts org
is the household membership setting, not the mode. Confirming Agentforce Nonprofit
coexistence switches membership to the junction for you; choosing any other mode leaves the
membership setting alone. Health Check reports the wrong membership setting in a Person
Accounts org as an error with a one-click fix. Take the fix.

**Changing the mode to fix something else.** Coexistence mode is about what is installed in
your org, not about how you want households named or how gifts are entered. Those are their
own settings. If a household is named wrongly, change the naming settings, not the mode.

**Expecting NPSP coexistence to take over your NPSP households.** It does not. Open Impact
builds its own households in every mode, so an org with NPSP has NPSP's households and Open
Impact's, and reconciling them is manual work in this version. Switching between NPSP
coexistence and Standalone changes nothing about that either way.

**Expecting the mode to move data.** Confirming a mode records what is in your org and, for
Agentforce Nonprofit, sets household membership. It does not migrate anything, and it does
not touch your Nonprofit Cloud or NPSP records. Importing your old data is a separate step in the Setup Assistant.
