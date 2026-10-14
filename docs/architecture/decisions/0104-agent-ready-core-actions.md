# ADR-0104: Core ships four agent-ready Flow actions, and no agent metadata

**Status:** Accepted
**Date:** 2026-10-13
**Source:** Core quality pass item Q-14 (owner approval, 2026-10-13); plan decision D-23 (AI-ready invocable action descriptions, no shipped AI, no paid API); ADR-0009, ADR-0013, ADR-0017, ADR-0051

## Context

D-23 asks for BarnCRM's actions to describe themselves well enough that a customer's own AI
assistant can choose and fill them, with no AI shipped and no paid service called. X-03 did
this for one Connect action, Record Inbound Gift. Core had no action an assistant or a Flow
could call for its own main jobs: finding a person, reading a household, adding a person to
a household, and checking an import.

Salesforce's standard agent actions (query records, get record details, create and update
records) already reach every record a user can see. What they cannot do is answer in
BarnCRM's terms: which household a person belongs to depends on the membership mode
(ADR-0005, ADR-0037), a person can be stored as a contact or an account (PersonReference), a
household's primary member is a membership flag in one mode and a lookup in the other
(ADR-0044), and joining a household is a membership row in one mode and a reparent in the
other (R-M5). An assistant using only standard actions gets those wrong.

Two platform facts bear on the shape:

1. Only a `global` invocable method is offered to a Flow or an agent in a subscriber org, and
   an invocable method, once packaged, cannot be removed (ADR-0017 reserves `global` for this
   deliberately public surface; ADR-0051 is the precedent).
2. Agent topics and actions (`GenAiPlugin`, `GenAiFunction`) are packageable in managed 2GP,
   but building them needs an Agentforce-enabled org, and they are Agentforce components:
   a package that contains them is an Agentforce package. Vendors that ship them do so in a
   separate extension package that requires Agentforce and Einstein in the subscriber org.
   Core must install on a Platform-only org with no Agentforce (ADR-0009, ADR-0013).

## Decision

1. **Four Core actions, each a thin wrapper over an existing service, adding no rule of its
   own.** All `global with sharing`, category BarnCRM, every read and write in user mode:
   - **Find People** (`FindPeopleAction`): part of a name or an exact email; answers each
     person with their household, through `HouseholdService.getHouseholdIdsFor`. A person
     stored as an account is answered as that account, as everywhere in Core.
   - **Get Household Summary** (`GetHouseholdSummaryAction`): by household or person id;
     name, greetings, member count, primary contact, mailing address on one line, and members
     (primary first), through `HouseholdService.getMembersAsUser`.
   - **Create Person** (`CreatePersonAction`): an ordinary contact insert in user mode, so the
     org's duplicate, validation and sharing rules apply. With a household id the contact is
     saved against that household (so automatic creation leaves it alone, as an import that
     names a household does) and joined by `HouseholdService.addMembers`; joining needs edit
     access to the household, the check `HouseholdService.moveContact` makes. Without one,
     the contact trigger gives the person a household when the org asks for that.
   - **Get Data Job Status** (`GetDataJobStatusAction`): an import, bulk update or bulk delete
     by id, or the latest import; status as the results screen shows it
     (`ImportUndoService.effectiveStatus`) and the row counts.
2. **Every request is answered in its position, and a refusal is an answer.** Each result
   carries an Error Message in plain words (custom labels); a user without access is told so
   rather than failing the Flow or the agent turn. One call is answered from a fixed number
   of queries whatever the number of requests. Create Person saves the requests it can and
   answers the others; a join that fails undoes the whole call.
3. **Labels and descriptions are written for an administrator and an assistant at once,** as
   X-03's are: what the action does, what it never does, the exact form of each value, under
   255 characters.
4. **No action starts, commits or undoes an import, merges people, or updates an existing
   person.** Those stay decisions a person makes on a screen, or a standard action the
   customer chooses to give an assistant.
5. **No agent metadata ships in any package.** Example topic and action metadata
   (`GenAiPlugin`, `GenAiFunction`) live in `examples/agentforce/`, outside every package
   directory in `sfdx-project.json`, for an administrator to deploy to their own Agentforce
   org or to copy in Agent Builder. If a packaged agent is wanted later, it is a separate
   optional extension package that depends on Core and requires Agentforce, with its own ADR.
6. **The packaged permission sets grant the four classes,** so no one adds Apex Class Access
   by hand (owner decision, 2026-10-13). BarnCRM Staff and BarnCRM Admin grant all four;
   BarnCRM Read Only grants Find People and Get Household Summary, because it reads people and
   households but not data jobs and creates nothing. The role groups (Program Staff,
   Volunteer Coordinator, Read Only, BarnCRM Admin Group) carry the grants through their
   sets. The actions run in user mode, so object and field access still decides what each user
   can do: the class grant lets an assistant call the action, never see or change more than
   the user could by hand. Record Inbound Gift is unchanged and still needs a grant by the
   administrator. A Flow calls the four without a grant.

## Alternatives considered

- **Rely on standard agent actions only.** Rejected: they do not know the membership mode,
  people stored as accounts, or how joining a household works, so an assistant would answer
  "which household" wrongly in junction mode and create duplicate households.
- **Ship `GenAiPlugin` and `GenAiFunction` in Core.** Rejected: Core would become an
  Agentforce package and could not install on the Platform-only org ADR-0013 requires.
- **An optional BarnCRM Agent extension package now.** Deferred: it needs an Agentforce
  packaging org and a release line of its own, and the examples folder gives an administrator
  the same topic in minutes. Nothing here prevents it.
- **Start an import from an action.** Rejected: an import needs a file, a template and a
  person reading the dry run; committing one from a sentence is the kind of mass change an
  assistant should not make.
- **One action per object with an "operation" input.** Rejected: an assistant chooses tools
  by their descriptions, and one tool that does four things is chosen and filled badly.
- **Leave the grant to each administrator.** Rejected by the owner (2026-10-13): a manual
  Setup step is easy to miss, and user-mode access already limits what any user can do
  through an action. An administrator who wants an assistant limited to looking things up
  assigns it a user with BarnCRM Read Only.

## Consequences

- Four more `global` classes, each with its request and result classes, are supported for the
  life of the package: optional variables can be added, none removed or renamed. ADR-0051's
  "four global classes and no more" was about Connect's inbound gift surface and is not
  changed.
- Create Person in junction mode saves the contact against the household it joins, the same
  shape merge, split and import already produce.
- `ImportBatchSelector.selectByIds` is added so a call naming many jobs reads them in one
  query.
- The admin guide page `using-barncrm-actions-with-ai.md` covers the Core actions, the Flow
  use, and the examples folder. The example metadata is not compiled or deployed by CI; an
  org with Agentforce must confirm it deploys (`sf project deploy start --source-dir
  examples/agentforce`) whenever an action's inputs change.
