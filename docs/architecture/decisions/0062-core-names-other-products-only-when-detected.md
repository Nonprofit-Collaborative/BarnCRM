# ADR-0062: Core shows nonprofit wording and other products' names only where they apply

**Status:** Accepted
**Date:** 2026-10-12
**Source:** product owner decision (Brandon, 2026-10-12); amends ADR-0059 decision 5; builds
on ADR-0046

## Context

ADR-0046 made Core alone the Community Suite, for organizations that are not nonprofits, and
said nonprofit-only modules are never offered to it. ADR-0059 decision 5 made Core's wording
neutral but kept the names of Salesforce products Core coexists with (NPSP, Nonprofit Cloud,
Agentforce Nonprofit, Gift Transaction) as an exception, without saying when they may show.
An audit of Core after C-29 found that several screens every org sees still named those
products or spoke of gifts:

- Setup Assistant step one and the settings console always offered "Agentforce Nonprofit
  coexistence", and the step-one description said "as Nonprofit Cloud orgs do".
- Setup Assistant step six listed Giving and Funders to every org, with "Learn more" links to
  the product plan, a document written for nonprofits.
- The import wizard, with no module installed, offered "Gift: amount (kept with the row, not
  loaded yet)" and four similar columns.
- Core seeded the "Nonprofit Cloud: person accounts" and NPSP contacts import templates into
  every org.
- A post-install Error Log warning named the Nonprofit Admin role and Nonprofit Settings.
- The admin guide, which the in-app help links open, used nonprofit and gift wording on Core
  pages and had two Core pages named `nonprofit-hub.md` and `nonprofit-settings.md`.

The Nonprofit Edition choice that would let Core tell a nonprofit from any other organization
(C-30, roadmap v0.8) does not exist yet. Today Core can tell only two things: whether a module
such as Giving is installed, and what `OrgShapeDetector` finds in the org (`hasNpsp`,
`hasIndustriesNonprofit`, `hasPersonAccounts`).

## Decision

1. **Core shows no nonprofit wording where a Community Suite user can see it.** No label,
   help text, option, message, seeded record or admin-guide page of Core says "nonprofit" or
   uses nonprofit-only vocabulary (gift, donor, donation, grant, fundraising, receipt, pledge,
   appeal). Admin-guide pages count, because the in-app help links open them. Four exceptions:
   - text that appears only when Giving (or another module) is installed;
   - the names of Salesforce products (NPSP, Nonprofit Cloud, Gift Transaction), shown only
     when Core detects that product in the org;
   - import column aliases that only match file headers and are never displayed;
   - the Nonprofit Edition choice itself (C-30), when it is built.
   This replaces the exceptions in ADR-0059 decision 5. An admin-guide page about Giving or a
   detected product may stay in the guide; on a Core page such a passage is marked as applying
   only with Giving, or only when that product is in the org.
2. **"Agentforce Nonprofit" is called "Nonprofit Cloud" again**, in labels, help, docs and
   option names. The coexistence modes are "Standalone", "NPSP coexistence" and "Nonprofit
   Cloud coexistence". The stored value of the third mode is renamed on a later branch.
3. **Coexistence modes are offered by what Core detects.** Standalone is always offered. NPSP
   coexistence is offered only when NPSP is detected, and Nonprofit Cloud coexistence only
   when Nonprofit Cloud objects are detected. The mode already saved is always shown, so a
   saved choice is never hidden. Setup Assistant step one and the BarnCRM Settings console
   show the same filtered list. The recommendation is Nonprofit Cloud coexistence when
   Nonprofit Cloud objects are found, otherwise NPSP coexistence when NPSP is found,
   otherwise Standalone. An org with Person Accounts and no Nonprofit Cloud is recommended
   Standalone; BarnCRM still proposes junction membership (one membership record per person)
   for it, because Person Accounts need it, and never overwrites an administrator's existing
   choice of membership.
4. **Setup Assistant step six offers only what fits.** Until C-30 exists, an org without
   Giving sees Core and Volunteers, plus any other module already installed; an org with
   Giving sees all six (Core, Giving, Volunteers, Programs, Funders, Connect). Each "Learn
   more" link opens that package's README (`packages/<name>/README.md` on GitHub).
5. **The import wizard offers gift columns only when a module that loads gifts is
   installed.** Without one, a column for an amount, a date or anything else only a module
   could load is suggested as "Do not load"; the "Gift: ... (kept with the row, not loaded
   yet)" options are removed. The staged row still keeps the whole original line.
6. **The Nonprofit Cloud and NPSP migration templates ship with Giving.** "Nonprofit Cloud:
   person accounts" and the NPSP contacts template are created only in an org that has
   Giving. Detection is the wrong gate here: a migration usually goes into a fresh org where
   the old product is not installed.
7. **Nothing is gated on an edition choice until C-30 exists.** Every gate in Core is either
   "Giving (or another module) is installed" or a detected org shape from `OrgShapeDetector`
   (`hasNpsp`, `hasIndustriesNonprofit`, `hasPersonAccounts`).
8. **Core's sample data is neutral and loaded only on purpose.** It is loaded only by an
   explicit administrator action after install (the Sample data panel in BarnCRM Settings or
   the Setup Assistant) or by test and scratch-org scripts, never by a post-install script, a
   Setup Assistant default or a scheduled job.

## Alternatives considered

- **Keep ADR-0059's product-name exception as it was.** Rejected: "Agentforce Nonprofit
  coexistence" and "as Nonprofit Cloud orgs do" were shown to every org, including ones that
  have never had a nonprofit product, which the owner's rule rules out.
- **Rename the Person Accounts mode after the shape ("Person Accounts and Nonprofit Cloud
  coexistence") and offer it always.** Rejected: it still names a nonprofit product to every
  org, and Person Accounts alone do not need a coexistence mode; junction membership already
  covers them.
- **Gate the migration templates on detecting NPSP or Nonprofit Cloud.** Rejected for the
  reason in decision 6: the target org of a migration usually has neither.
- **Keep neutral "kept with the row" import columns** ("Amount (kept with the row, not
  loaded)"). Rejected: the staged row already keeps the whole original line, so the options
  add nothing a Community Suite org can use.
- **Wait for C-30 and gate on the edition.** Rejected: C-30 is planned for v0.8, and these
  screens are seen now.

## Consequences

- `docs/admin-guide/nonprofit-hub.md` and `nonprofit-settings.md` are renamed
  `barncrm-app.md` and `barncrm-settings.md`. Core admin-guide pages are neutral, with Giving
  and detected-product passages marked.
- Canonical model Section 2 rule 5 states this rule; Section 12 records which coexistence
  modes are offered when; Section 15 lists the Nonprofit Cloud and NPSP templates as Giving.
- The post-install Error Log warning names the BarnCRM Admin role and BarnCRM Settings, and
  the Import Template field "Donation Matching" is labelled "Payment Matching" (API name
  unchanged until the name pass).
- Giving ships its own Import Template Default rows for the two migration templates. An org
  without Giving that wants to migrate from NPSP or Nonprofit Cloud installs Giving first, or
  maps the columns by hand with the generic contact list.
- When C-30 is built, an edition choice becomes a third kind of gate, and this ADR's
  exceptions are revisited in that feature's ADR.
