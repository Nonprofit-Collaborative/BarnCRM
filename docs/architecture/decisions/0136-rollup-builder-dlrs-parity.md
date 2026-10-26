# ADR-0136: The Rollup Builder Offers Standard Objects Through Describe, and Closes the Gaps to DLRS

**Status:** Accepted (owner decision, Brandon, 2026-10-26: "Please close the gaps to bring Rollup
Builder up to or above parity with DLRS. Adding standard objects as options is approved." The
owner also agreed with the list of DLRS features not to copy.)
**Date:** 2026-10-26
**Source:** owner decision 2026-10-26; the Rollup Builder and DLRS gap analysis of 2026-10-26;
amends ADR-0082 (its deferred list and its "one `global` method" statement); applies ADR-0013
to data-driven definitions; builds on ADR-0125

## Context

The Rollup Builder offered only Account, Contact and custom objects as the record that shows a
total and as the records counted (`RollupBuilderController`, `STANDARD_ENTITIES`). The engine
itself never cared: a definition names its entities as text (canonical model R-R7) and every
query is built from describe. So the most common rollup in Declarative Lookup Rollup Summaries
(DLRS), closed won opportunity amounts onto an Account, could not be built, and could not be
moved over from DLRS either.

ADR-0013 makes the Platform-only org the floor of the product: Core and the modules may not
depend on Opportunity, Campaign, Lead, Case or the Industries objects, and
`check-standard-objects.sh` fails any source file in those packages that names them. A
definition that counts Opportunities in an org that has them is not such a dependency: nothing
is compiled or deployed against the object, and an org without it simply has no such option.
ADR-0013 does not say this, so it is recorded here.

ADR-0082 also deferred several things DLRS has: top N, moving definitions from sandbox to
production, and Task or Event paths, and it said the engine adds one `global` method only (the
generated trigger's entry point).

## Decision

1. **Standard objects are offered through describe only.** The Builder lists, as targets and as
   sources, every object the org's describe returns that the running user can read, that can be
   queried, and (for a target) updated: Account, Contact, the org's own objects, and standard
   objects. Custom settings, the platform's companion objects (sharing, history, feed and change
   event objects), objects marked deprecated and BarnCRM's own bookkeeping objects are left out.
   A standard object outside a short "common" list must also be one people create and search
   (describe's createable and searchable), which leaves out logs and system records; a source
   is offered only through a reference attribute that can be filtered and grouped on, because
   the engine's aggregate query does both.
2. **A short common list, by name, detection-only.** The objects most nonprofits roll up from or
   to (Opportunity, Opportunity Product, Case, Campaign, Campaign Member, Lead, Task, Event,
   Asset, Order, Order Product, Contract) are shown first, with Account, Contact and the org's
   own objects; every other object is found by searching. The names sit in one String constant
   in `RollupBuilderController`, marked `// detection-only:` for `check-standard-objects.sh`,
   resolved through describe, and skipped when the org lacks the object. No Apex, metadata,
   label or test in a package outside Mirror names one of these objects as a reference.
3. **Instant only where a trigger exists.** A total is instant only when its source object has a
   rollup trigger: a packaged registration of `RollupTriggerHandler` in the Automation Registry
   today, a generated trigger later (ADR-0082 amendment A2, slice S16). Until then, a rollup that
   counts any other object is recalculated in the background: the Builder says so plainly when
   such a source is chosen ("Instant totals are not available yet for ..."), does not offer
   **Instantly** on its own for it, and its save and the rollup list's mode change refuse
   **Instantly** alone with what to choose instead. **Both** and **Every night** are allowed;
   with the Recalculate rollups Flow template, **Both** is still instant.
4. **The DLRS gaps are closed in the Rollup Builder module, in small pull requests.** Row limit
   (top N) with an order, order direction, a parent record's fields in the filter builder, more
   delimiters (Pipe, Custom), picklist targets for First and Last, counting deleted and archived
   records, a per-rollup bypass custom permission, a Flow action that recalculates one record's
   totals, the nightly run's hour as a setting in BarnCRM Settings, a `global` Apex entry point
   for developers, export and import of definitions as a file keyed on Definition Key, and
   Delete in the rollup list. Each new attribute is specified in the canonical model first.
   Two of them carry rules of their own:
   - **Parent-field criteria** go one lookup deep in the Builder (a lookup to one object; the
     filter parser and Find still allow two). A change to the parent's field is instant only
     where the parent has a rollup trigger; otherwise the nightly run and Recalculate catch
     it, and step 4 says so.
   - **Picklist targets** take First and Last only. A source picklist with active values the
     target lacks is refused on save; at run time a value is matched to the target's values
     ignoring letter case, and a value the target lacks is left out and logged as a Warning
     rather than failing the write, so a picklist never collects values it does not list.
5. **Deferrals of ADR-0082 lifted:** top N, moving definitions between orgs (export and import,
   not a deploy), and Task or Event sources. Grandchild and hierarchy paths, dated currency
   rates and failure emails stay deferred.
6. **More than one `global` surface.** ADR-0082 said the generated trigger's entry point would
   be the engine's only `global` method. The Flow action that recalculates one record's totals
   and the developer entry point are `global` too, for the same reason `RollupRecalcAction` is:
   a subscriber can call nothing else across the namespace. Each is kept minimal, because a
   released `global` signature is permanent.
7. **Not copied from DLRS** (owner agreed): totals calculated in the saving user's sharing
   mode, SOQL typed by an administrator and lists of criteria fields, editable test code,
   regenerating a trigger per rollup, definitions as custom metadata, a separate scheduled
   items object, and Developer as a distinct mode.

## Alternatives considered

- **Keep the Builder to Account, Contact and custom objects.** Fails the owner's parity goal and
  leaves the most common DLRS rollup unbuildable.
- **Move standard-object rollups into Mirror**, the one package allowed to name these objects.
  Nothing about them is Mirror's: the engine is generic, and the only name the Builder needs is
  for ordering a list. A second engine entry point in Mirror would duplicate the module.
- **No curated list**, every standard object alphabetically. Correct but hard to use: a full
  org has hundreds of objects, and the handful people actually want would be lost among them.
- **Offer Instantly for every object** and let a rollup with no trigger silently never update
  between nightly runs. Rejected: a total that looks instant and is not is the failure
  Principle 2 forbids.

## Consequences

- An org with Sales or Service Cloud objects can build, preview and recalculate rollups on them
  today, nightly or on demand; instant needs the Flow template until the generated trigger
  ships. A Platform-only org sees none of these objects and behaves as before.
- A rollup on an administrator's own object that was set to **Instantly** alone keeps working
  as saved; the next time it is edited in the Builder it has to be **Both** or **Every night**.
- `check-standard-objects.sh` lists the new detection-only line on every run, so a reviewer
  sees it.
- `AutomationRegistrySelector` becomes `@NamespaceAccessible` so the module can ask which
  objects have a rollup trigger.
- Canonical model: R-R7 says how standard objects are offered, R-R12 what the Builder does for
  a source with no trigger, and each later parity pull request adds its attributes and rules.
