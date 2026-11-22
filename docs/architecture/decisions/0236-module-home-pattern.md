# ADR-0236: Every module app opens on one Module Home pattern

**Status:** Accepted (owner decision)
**Date:** 2026-11-21
**Source:** Brandon, plan D-219 (OD-16, release 1.34): one "Module Home" pattern for every
module home tab. Builds on ADR-0223 (module apps), ADR-0093 and its Amendment A1 (record reads
through Lightning Data Service, queries built from schema imports), ADR-0164 (help text in
JSON) and D-135 (Error Log is the last tab).

## Context

The module apps opened on pages with uneven names and shapes: Events Home, Projects Home,
Volunteers Home and Fundraising Home, but Programs Dashboard, Board Dashboard (the Grants app),
Corporate Hub and Scholarships and Grants. The Forms, Memberships and Portal Builder apps had no
home at all and opened on a record list. Every existing home already used `c-barn-page-shell`,
so the gap was names, the regions on the page and the three missing homes, not the shell.

## Decision

1. **The first tab of each module app is its home, labelled `<Module> Home`** in title case,
   where `<Module>` is the app's label without "BarnCRM". The page title in the shell is the
   same words. Tab API names stay, so links, permission sets and the module catalog keep
   working:

   | App | Home tab (API name) | Label |
   |---|---|---|
   | BarnCRM Corporate Hub | `Corporate_Hub` | Corporate Hub Home |
   | BarnCRM Events | `Events_Home` | Events Home |
   | BarnCRM Forms | `Forms_Home` (new) | Forms Home |
   | BarnCRM Fundraising | `Fundraising_Home` | Fundraising Home |
   | BarnCRM Grants | `Funders_Board` | Grants Home |
   | BarnCRM Memberships | `Memberships_Home` (new) | Memberships Home |
   | BarnCRM Portal Builder | `Portal_Builder_Home` (new) | Portal Builder Home |
   | BarnCRM Programs | `Programs_Dashboard` | Programs Home |
   | BarnCRM Projects | `Projects_Home` | Projects Home |
   | BarnCRM Scholarships | `Scholarships` | Scholarships Home |
   | BarnCRM Volunteers | `Volunteers_Home` | Volunteers Home |

   Not module homes: the four Core apps (BarnCRM opens on the suite Home hub, the admin apps on
   Settings) and BarnCRM Connector, a one-tool app that opens on Super Connector.
2. **One shell, one order of regions.** A home is `c-barn-page-shell` (title, About This Tool
   help from the package's help catalog, the tab's icon from `c/barnIcons`), then top to
   bottom:
   - **Quick actions** in the shell's `actions` slot: New for the module's main record, shown
     only to someone who may create it, and the module's own tools.
   - **Notices:** one `c-barn-notice` for a load failure.
   - **KPI row:** two to four `c-barn-stat-tile` figures in the Visual Standard's tile row, each
     a link to the list behind it.
   - **Lists or charts** the module's daily work needs, each a section with an `h2`; an empty
     section shows `c-barn-empty-state size="compact"` with its next step.
   - **First run:** when the module has no records at all, one `c-barn-empty-state` with
     `illustration="setup"` and the first action replaces the lists.
3. **Only data the module already stores or computes.** A home adds no object, field or job. A
   flat read of records, as the user, uses the GraphQL wire adapter built from
   `@salesforce/schema` imports (ADR-0093 A1), and a count uses the query's `totalCount`, so
   a new home needs no Apex. Apex stays only for aggregates and logic the module already
   computes there (the Grants, Programs and Scholarships figures). The existing homes keep
   their controllers.
4. **Access follows the module's role sets.** A new home tab is visible in the module's Staff
   set (so the generated Admin and Read Only sets carry it; Portal Builder: its Admin set), sits
   first in the module app with Error Log still last, and joins the module's catalog row
   (`Staff_Tabs__c`, or `Admin_Tabs__c` for Portal Builder) so the BarnCRM apps list it too.
   Field security and sharing decide what each figure and list shows; New appears only when
   the object is createable for the user.
5. **Help and titles in the help catalog.** Page titles, section headings, tile labels and
   empty-state text are entries in the package's `BarnHelp_<Package>.json`, so a home adds no
   custom label (the label budget is full); column headers come from the objects' own field
   labels.

## Alternatives Considered

- **One shared `barnModuleHome` component in Core, fed a config per module.** One more
  cross-package contract for three small pages whose lists differ, and a Core change for every
  module tweak. The shell and the kit parts already make the pages look alike.
- **Keep Dashboard and Hub names where the page is figures only.** The app switcher then reads
  three different words for the same place; Brandon asked for one.
- **Apex controllers for the new homes.** Brings back the per-page controllers ADR-0093 moved
  away from, with their class access in every set, for reads LDS already does as the user.

## Consequences

- Tab labels change in the app nav and in the BarnCRM apps; API names do not, so nothing
  links differently. Guides name the new labels.
- The GraphQL queries cannot be checked offline (the Jest stub ignores the query text); a
  deploy and a look at each new home in a real org confirm them.
- Existing homes keep the regions they have. Each is checked against decision 2 in its next
  pre-batch review rather than rebuilt here.
- A new module app ships its home as its first tab under this pattern.
