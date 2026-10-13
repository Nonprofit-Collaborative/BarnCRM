# Using BarnCRM actions with your own AI assistant

## What it does

If your organization already uses an AI assistant inside Salesforce, it can call BarnCRM's
actions the same way a flow does. You might ask your assistant "which household is Maria
Garcia in?", "add her son Luis to that household", or "how did yesterday's import go?", and it
picks the action and fills it in for you.

BarnCRM has five such actions. Four are part of Core, so every BarnCRM org has them:

| Action | What it does | What it never does |
|---|---|---|
| **Find People** | Finds people by part of their name or their exact email address, and gives each one's household. | Create or change anything. |
| **Get Household Summary** | Gives a household's name, greetings, primary contact, mailing address and members with their roles, from a household or a person. | Change anything. |
| **Create Person** | Creates a new person, either in a household that already exists or with a household of their own. | Change, merge or delete a person who already exists. |
| **Get Data Job Status** | Reports how an import, bulk update or bulk delete is going: its status and row counts. With no job named, the most recent import. | Start, commit or undo a job. |

The fifth, **Record Inbound Gift**, is part of the Connect module. It records a gift that has
already arrived for a donor who is already in BarnCRM: "record a 25 dollar card gift from Luis
Garcia for the Building Fund".

The same actions are in Flow Builder, under the **BarnCRM** category, for any flow you build.
A flow needs none of the setup below.

BarnCRM ships no AI. It contains no agent, no prompt template and no AI model, it calls no
paid AI service, and it costs you nothing in AI credits. What it does provide is clear
instructions on its actions: each one says what it does, what it never does, and exactly what
each value must look like, so an assistant can choose the right action and fill it in
correctly. Whether you use an assistant at all, which one, and what it costs is your choice and
your agreement with its provider.

Two kinds of assistant can use the actions:

- **Agentforce**, Salesforce's own assistant, if your organization has it. You add the actions
  to an agent you build. BarnCRM's source code includes a ready-made example topic you can
  start from (see "Start from the example topic" below).
- **Any assistant that speaks MCP** (Model Context Protocol, an open standard for connecting AI
  tools to data), such as a desktop AI app your staff use, through a **Hosted MCP server** that
  you create in Salesforce and that lists the actions as tools.

Both need a Salesforce edition that includes them (Enterprise or above at the time of
writing). If your organization does not have either, there is nothing to set up and nothing
in BarnCRM changes: BarnCRM installs and works the same with or without Agentforce.

## How to turn it on

The four Core actions are there as soon as BarnCRM is installed. Record Inbound Gift needs the
Connect module. Everything below is in Salesforce Setup, because agents and MCP servers belong
to Salesforce, not to BarnCRM.

1. **Decide who the assistant acts as.** An assistant always acts as a Salesforce user and can
   do only what that user can do. An assistant your staff talk to (an Agentforce employee
   agent, or an MCP client a staff member signs in to) acts as that staff member. An agent
   that answers people outside your organization acts as its own agent user. Never give that
   agent user more than it needs.
2. **Give that user what the actions need.** Each action needs the same access as doing the
   job by hand, and BarnCRM's own permission sets already include the four Core actions, so
   there is no Apex Class Access to add:
   - **BarnCRM Staff** and **BarnCRM Admin** (and so Program Staff, Volunteer Coordinator and
     BarnCRM Admin Group) give Find People, Get Household Summary, Create Person and Get Data
     Job Status.
   - **BarnCRM Read Only** (and so the Read Only group) gives Find People and Get Household
     Summary. For an assistant that should only look things up, use a user with Read Only.
   - Record Inbound Gift needs **Giving Staff**, which covers the records involved, and
     Connect's **Record Inbound Gift Action** permission set (Setup, Users, choose the person,
     Permission Set Assignments), which runs that one action and grants nothing else. Assign it
     only to the users who may record gifts through an assistant; no BarnCRM role includes it,
     so no one gets the action without your decision.
   The actions run with the user's own access, so what each user can find or change is still
   decided by their object and field access.
3. **Add the actions to your assistant.**
   - *Agentforce:* either start from the example topic (next section), or in Agent Builder add
     a new action to a topic, choose **Apex** as the reference action type, and pick the
     action, for example **Find People**. Its instructions and the instructions for every
     input are filled in from BarnCRM; leave them as they are unless you need to narrow them.
     For **Create Person** and **Record Inbound Gift**, turn on the option that asks the user to
     confirm before the action runs.
   - *Hosted MCP server:* in Setup, create a custom MCP server and add the actions as tools
     (Salesforce's Hosted MCP Servers guide has the steps). Connect your MCP client to it as the
     user from step 1. Tell staff to read an action's summary before they approve it in their
     client.
4. **Tell the assistant how your organization names funds,** if you use Record Inbound Gift.
   The action names a fund by its **Accounting Code** (see [Funds](funds.md)). Add a line to
   the agent's topic instructions, or share a short list with staff, so the assistant uses the
   right code.

There are no BarnCRM settings for this.

### Start from the example topic

BarnCRM's source code has a folder, `examples/agentforce`, with a ready-made Agentforce topic,
**BarnCRM People and Households**, that holds the four Core actions and instructions such as
"look the person up before creating them" and "never suggest contacting a member marked
deceased". It is an example, not part of any BarnCRM package, because a package that contained
an agent topic could only be installed in an org that has Agentforce.

To use it, a developer or administrator who uses the Salesforce CLI deploys the folder to your
org: from the folder, `sf project deploy start --target-org <your org>`. If BarnCRM was
installed as a managed package, first add the package's namespace and two underscores in front
of each class name in the four files under `genAiFunctions` (for example
`barncrm__FindPeopleAction`), and in the `@apexClassType/c__` references in the output files.
Then open Agent Builder, add the topic to your agent, and change its instructions to fit your
organization. Without the CLI, build the same topic by hand in Agent Builder: its description,
scope and instructions are in the file `BarnCRM_People_And_Households.genAiPlugin-meta.xml`.

### What the assistant can and cannot do

- **It sees only what its user sees.** Every action finds people, households, data jobs,
  donors, funds and appeals only among the records its user can see, and creates records only
  where that user may. Your sharing settings and permission sets decide this, not the
  assistant. A user without the access an action needs gets a plain message saying so, and
  nothing is changed.
- **It adds people to a household only where its user may edit that household.** Create
  Person refuses a household its user cannot edit. Your duplicate rules and validation rules
  apply to a person it creates exactly as they do when someone saves one by hand.
- **It cannot change, merge or remove a person who exists,** and cannot start, commit or undo
  an import. Those stay on BarnCRM's screens.
- **It cannot change, refund or delete gifts.** Record Inbound Gift only records new gifts. A
  gift already recorded under the same external id is answered, never edited.
- **Every refused gift is logged.** A gift Record Inbound Gift refuses is written to the
  [Error Log](error-log.md) with its external id and error code, the same as a gift refused
  through the [Inbound Gift API](inbound-gift-api.md).
- **Other tools are not BarnCRM's.** An assistant can also use Salesforce's own standard
  actions and tools, for example to look up or update any record its user can see, including
  donor details. BarnCRM does not control those. Review what each assistant is allowed to do
  before you turn it on, and remember that what a staff member types to an assistant, and what
  it reads back, goes to the AI provider your organization chose, under your agreement with
  them.
- **Usage costs are yours.** Agentforce actions and MCP requests may count against your
  organization's Salesforce allowances or credits, and the AI app your staff use has its own
  pricing. BarnCRM adds none.

## A five-minute walkthrough: people and households

Do this as Maria, with the sample data loaded, in an org that has Agentforce and an agent you
can edit. It shows the assistant looking before it creates, and a new person landing in the
right household.

1. Open your agent in **Agent Builder** and add the four Core actions to a topic, or add the
   example topic, as above.
2. In the conversation preview, type: `Which household is Luis Garcia in?` The agent runs
   **Find People** and answers with Luis and his household's name.
3. Type: `Summarize that household.` The agent runs **Get Household Summary** and lists the
   members with their roles, the primary contact first, and the mailing address.
4. Type: `Add Sofia Garcia, sofia.garcia@example.org, to that household.` The agent runs
   **Find People** for the address first, finds nobody, then asks you to confirm **Create
   Person** with the household from step 2. Confirm.
5. Open the household. Sofia is a member, the member count has gone up by one, and the
   household name and greetings were updated, exactly as if David had added her by hand.
6. Type: `How did the last import go?` The agent runs **Get Data Job Status** and gives the
   status and the rows created, updated and rejected, or says there is no import yet.
7. Delete Sofia if you are not keeping her, and remove the actions from the agent if you are
   not keeping them.

## A five-minute walkthrough: recording a gift

Do this as Maria, with the sample data loaded and the Connect module installed, in an org that
has Agentforce and an agent you can edit. It shows the one thing that matters most: asking
twice records the gift once.

1. Open your agent in **Agent Builder** and add **Record Inbound Gift** to a topic, as in step
   3 above. Its instructions start "Records a gift that has already been received, for a donor
   who already exists."
2. In the conversation preview, type: `Record a gift of 25 paid by Card from
   luis.garcia2@example.org, external id ai-walkthrough-1, fund accounting code 4100.` The
   agent asks you to confirm, then shows **Outcome** `created` and a **Gift Id**.
3. Type the same request again. This time **Outcome** is `existing`, with the same **Gift Id**:
   the gift was not recorded twice.
4. Type: `Record a gift of 30 paid by Card from luis.garcia2@example.org, external id
   ai-walkthrough-1.` **Outcome** is `rejected` and **Error Code** is `external_id_conflict`:
   that identifier already belongs to a gift of 25.00.
5. Type: `Record a gift of 10 paid by Card from nobody@example.org, external id
   ai-walkthrough-2.` **Error Code** is `donor_not_found`, and the assistant does not create a
   new person.
6. Open the gift from step 2 (the **Gifts** tab, search `ai-walkthrough`). It is Luis Garcia's,
   25.00, type Card, today, with one allocation to the Building Fund, exactly as if David had
   typed it. Remove the action from the agent if you are not keeping it.

## Common mistakes

**The assistant does not offer the action.** Its user has none of the BarnCRM permission sets
that include the action (see step 2; Read Only has no Create Person or Get Data Job Status),
or, for Record Inbound Gift, is missing the **Record Inbound Gift Action** permission set, or the action
was not added to the agent's topic or the MCP server. Check step 2 and step 3 above.

**"You do not have access to the records this action reads or changes."** The assistant's user
is missing a BarnCRM permission set, for example **BarnCRM Staff**. The action itself ran, so
class access is in place; give the user the same access they would need to do the job by
hand.

**Find People returns nobody you know is there.** The assistant's user cannot see that
person, or the assistant searched for a nickname or a misspelling. Ask it to search by email
address, or by part of the last name.

**A duplicate person.** The assistant created someone who already existed. Keep the example
topic's instruction to look the person up first, keep the confirmation step on for Create
Person, and consider a duplicate rule that blocks rather than alerts (see
[Duplicates](duplicates.md)); a blocking rule refuses the save and the assistant shows the
rule's message.

**The example topic does not deploy.** If BarnCRM is a managed package in your org, the class
names in `examples/agentforce` need its namespace (see "Start from the example topic").
Otherwise check that your org has Agentforce turned on: an org without it has no agent topics
to deploy into.

**`donor_not_found` for someone you know is there.** The assistant's user cannot see that
person or organization, or the email address differs. Share donors with that user (Setup,
Roles and Sharing Settings), or ask the assistant to use the donor's record id instead.

**`fund_not_found`.** The assistant guessed a fund name instead of an accounting code. Give it
your list of accounting codes (step 4), or leave the fund out to use the default fund.

**A made-up external id.** An assistant may invent an identifier when none was given, so a
second request for the same gift gets a different one and records it twice. Ask staff to give
the identifier from the payment (a check number with a date, or the processor's transaction
id), and keep the confirmation step on so a person reads the values before the action runs.
