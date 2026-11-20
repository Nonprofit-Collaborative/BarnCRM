# BarnCRM Connector

BarnCRM Connector links BarnCRM to the other apps your organization uses, such as a mailing list
service or a chat app. It is an optional module in beta, set up by your admin.

**Is there anything for you to do?** Usually not. Your admin sets up **Connections** to other
apps and **Recipes** that move data between them, on the **Super Connector** tab. Recipes run on
their own, never as you: as BarnCRM Automation, or as an integration user your admin chose. Some
run on a schedule, some run when records change, about 15 minutes after the change, and some
run when another app sends data, such as a gift made on a giving form, moments later. A record
you save may therefore be updated by a recipe a little later; its history shows BarnCRM
Automation (the Automated Process user) or the integration user as who changed it.

**If your admin gave you BarnCRM Connector Viewer,** you can open **Super Connector** to see the
recipes and **Run History**: each run's status, what started it, how many records it wrote and,
when it failed, the step that failed and why in plain words. A **Waiting** run failed for a
reason that may pass, such as the other app being down, and shows when it is tried again. Viewers
cannot change, test, run or retry a recipe. If a run failed, tell your admin; they can fix the
recipe and select **Retry**. A run started by **Webhook** also shows its **Reference**: the same
reference the other app was given, so a post in that app can be matched to its run.

**A flow may run a recipe for you.** Your admin can add the action **Run a BarnCRM Connector
Recipe** to a flow, such as one behind a button. The recipe still runs as BarnCRM Automation, so
it can do only what your admin allowed recipes to do, and its run shows in Run History as started
by Flow.

**Keys stay with your admin.** A connection's key is kept in Salesforce's credential store and
never shown again, not even to the admin who saved it. If another app asks you for a BarnCRM key
or password, do not give one: tell your admin.

Setting up connections and recipes is on [BarnCRM Connector](../admin-guide/connector.md) in the
Admin Guide.
