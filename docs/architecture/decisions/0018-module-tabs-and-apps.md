# ADR-0018: Each module ships its own Lightning app; the Hub links to the module apps

**Status:** Accepted
**Date:** 2026-09-07
**Source:** builder decision under plan Section 9.3 (platform limitation blocking plan Section 4.8), affecting plan Sections 2.3, 4.1 and 4.8

## Context

Plan Section 4.8 specifies one **Nonprofit Hub** Lightning app with tabs for Home,
Households, Contacts, Organizations, **Gifts (from Giving)**, Import, Reports and
Nonprofit Settings. The Hub is a Core component, and Core installs alone. Gifts, Funds and
Appeals belong to the Giving package, which installs later and may never be installed at
all (Principle 3: a module that is off leaves nothing behind).

The platform does not let the later package finish the sentence. A `CustomApplication` is
one metadata component owning an ordered list of tab references. A second-generation
managed package cannot add a member to a component another package owns, which is the same
constraint ADR-0014 and ADR-0017 record for fields on `Nonprofit_Settings__c` and for
handlers on another package's trigger. A subscriber cannot patch around it either:
components that arrive in a managed package are not editable in the subscriber org, they
can only be cloned, and a clone stops receiving upgrades.

So the Hub app, as installed, cannot list a Gifts tab. Three ways out were available, and
the choice matters because plan Section 2.3 sets the bar: every setting and every routine
navigation change happens in the app, and Maria never opens Setup.

Two further platform facts constrain the answer, both checked against Salesforce
documentation while writing this ADR:

- Users can personalize the navigation bar of an app themselves, adding items from the
  pencil menu, up to a 50 item ceiling, unless the app disables personalization. What a
  user adds is theirs alone: it is not org configuration and it does not reach the next
  person who logs in.
- A dashboard cannot be embedded in a packaged Lightning page by name. The Lightning page
  dashboard component stores the dashboard's record identifier, and a package cannot ship
  a record identifier (plan Section 4.13, no hard-coded IDs). The standing request to
  reference the dashboard by API name instead is an open Salesforce idea, not a shipped
  capability.

## Decision

**Every module package ships its own small Lightning app, and Core's Hub points at the
module apps rather than absorbing their tabs.**

1. **Giving ships the `Fundraising` Lightning app.** Its navigation is Quick Gift Entry (a
   Lightning app page on a custom tab), Gifts, Funds, Appeals, Dashboards and Reports.
   Volunteers, Programs and Funders follow the same pattern when they are built, each with
   a short, task-shaped navigation rather than a list of every object it owns.
2. **The Nonprofit Hub stays Core's app** and keeps its Core tabs. Core's Hub home page
   (C-03) gains a **Modules** tile listing the module apps that are installed, each as a
   link that opens that app. The tile is Core's to build; the request from Giving is
   recorded in `packages/giving/integration/g-03-g-06.permissions.md`. The tile detects
   installed modules the way the Module Manager already does (plan Section 4.8, describe
   based detection), so it lists Fundraising only when Giving is present and adds nothing
   to an org that never installs a module.
3. **Module apps do not disable navigation personalization.** A user who lives in one app
   can pin the tabs they want from the pencil menu. This is a convenience on top of the
   design, never the mechanism the design depends on.
4. **A packaged dashboard is reached through the standard Dashboards tab**, from its
   packaged folder, not through an embedded dashboard component on a packaged Lightning
   page. The Giving admin guide names the folder and the dashboard, and the app carries the
   Dashboards and Reports tabs so the path is two taps from the app launcher.

## Alternatives considered

- **Tell users to add the module's tabs to the Hub themselves through the pencil menu.**
  Zero build cost, and it fails the acceptance bar: the change is per user, so Maria cannot
  do it once for her team, and a five person office repeats it five times and re-repeats it
  for every new hire. Kept as a convenience, rejected as the mechanism.
- **An app page in Core that dynamically lists the tabs of installed modules.** Core would
  own a component that discovers module tabs by describe and renders them as links inside
  one Hub tab. It works, it is more code than a tab list is worth, and it produces a page of
  links that behaves like navigation without being navigation: no browser history, no
  keyboard tab order a user recognizes, no personalization, and no favourites. The Modules
  tile in point 2 is the small version of this idea, and it is enough.
- **Move Gifts, Funds and Appeals into Core so the Hub can carry them.** Rejected by
  ADR-0003: an org that does not fundraise would carry the Giving schema.
- **One app for the whole suite, shipped by Core, with every module's tabs listed and
  hidden when the module is absent.** A `CustomApplication` cannot reference a tab that does
  not exist at install time, so Core could not even be deployed with the list. Rejected as
  impossible rather than undesirable.
- **Ask Maria to clone the Hub app and add the tabs.** This is what an implementation
  partner would do, and it is exactly the Setup work Principle 1 exists to remove. It also
  breaks upgrades: the clone never receives the Hub's later tabs.

## Consequences

- The app launcher gains one entry per installed module. That is the visible cost, and it
  reads as a benefit for David and Priya, who each live in one app rather than sharing a
  crowded one. Tom and Maria cross between apps, which the Hub's Modules tile makes a single
  click.
- Each module now owns navigation as a design surface and must keep it short. The rule for
  a module app is at most six navigation items, task-shaped: the screens someone uses daily,
  not every object the package ships.
- The Modules tile is a dependency running from Giving's documentation to Core's C-03 home
  page. Until C-03 ships it, the app launcher is the path between apps, and the Giving admin
  guide says so in plain words.
- A packaged dashboard has to say who it reads as, and it cannot name a subscriber's user.
  (Amended 2026-11-13 by ADR-NEXT: dashboards now ship as `SpecifiedUser`; the text below
  is the original decision.)
  `Giving_Overview` therefore ships with `dashboardType` set to `LoggedInUser`, so it reads
  as whoever opens it and arrives working with no post-install step. The cost is that
  dashboards of this kind are capped per edition; an org that has used its allowance sets a
  specific running user instead, and the Giving admin guide says how.
- If Salesforce later allows a package to contribute a tab to another package's app, or
  allows a Lightning page to reference a dashboard by API name, this ADR is worth revisiting:
  the first would let the Hub carry module tabs directly, and the second would let the
  Giving dashboard live on a packaged page instead of behind the Dashboards tab.
