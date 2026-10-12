# ADR-0024: The receipt lock survives the automation switch, and lifting it is a deliberate act in Setup

**Status:** Accepted
**Date:** 2026-09-08
**Source:** owner decision, escalated under ADR-0010 and plan Section 11.4

## Context

ADR-0010 says a gift's amount does not change after a receipt has been issued against it,
and that "anything touching receipt immutability or gift amount mutability is an escalation
to Brandon, not a builder decision".

An access review found that the lock was, in practice, a setting. `GiftService.enforceReceiptLock`
and `GiftService.preventLossOfHistory` are the only enforcement, they run from
`GiftTriggerHandler`, and that handler is registered in `Automation_Registry__mdt` as an
ordinary switchable automation. `TriggerDispatcher.run` returns early when an automation is
bypassed, when it is disabled, or when all automation is paused. So anyone holding
`Manage_Nonprofit_Settings` could open the Automation page, turn off "Gift: household, date
and default allocation" or pause everything for a few hours, edit the amount, date or donor
of a receipted gift, or delete it outright, and switch the automation back on. The residue
was one `Setting_Change__c` row saying an automation had been toggled.

That is not a hole in the code. It is the automation framework working exactly as designed,
applied to a rule that should never have been in its scope. The framework exists so an
administrator can stop BarnCRM filling things in while they load or correct data in
bulk. Receipt immutability is not a convenience of that kind: it is what a gift record
means, and a pause aimed at a bulk import silently opened it for every user in the org.

The escalation ADR-0010 called for was therefore made, and the owner decided.

## Decision

- **Receipt enforcement always runs.** It is moved out of the switchable handler into
  `GiftReceiptLockHandler`, registered with `Always_Runs__c` set. `TriggerDispatcher` does
  not consult the bypass, the enabled flag, or the global pause for an automation marked
  that way.
- **`Always_Runs__c` is a general capability, not a receipt special case.** Any automation
  that enforces a rule rather than providing a convenience can carry it. It is set on the
  shipped record and is not editable by a subscriber, because the whole point is that it
  cannot be turned off from inside the app.
- **The Automation page still lists such an automation**, with its switch shown off and
  disabled and a line saying why. An administrator who came looking for the receipt lock
  finds it and finds out why it will not move, rather than toggling the wrong row and
  concluding the product is broken.
- **The escape hatch is a custom permission, `Override_Receipt_Lock`, granted to nobody.**
  It ships on no permission set and in no permission set group. Lifting the lock therefore
  means an administrator deliberately assigning a permission in Salesforce Setup, making the
  change, and removing it again.
- **Every override is written to the Error Log** at Warning severity, naming the gift, its
  receipt number, and which values changed. An override that nobody recorded is the thing
  an auditor cannot reconstruct, so the package records it whether or not anyone remembers
  to.

## Alternatives considered

- **Leave it switchable and document the risk.** Rejected: ADR-0010 makes the amount
  immutable as a matter of what the record means, and a rule an administrator can suspend
  for the whole org with a two-click pause is not immutable. The documentation would have
  been a warning that the product does not do what it says.
- **A setting in the Nonprofit Settings console, defaulting to locked.** Rejected for the
  same reason the pause was rejected: it puts lifting the lock one click from the person
  most likely to be under pressure to make a number look right, and the console is where
  conveniences live. The project rule that every admin setting belongs in the console
  (plan Section 4) is about settings; this is deliberately not one.
- **No escape hatch at all.** Tempting, and it is what ADR-0010 read like on its own. Rejected
  because a real org will eventually hold a receipted gift that is wrong in a way void and
  reissue cannot reach, for example a receipt number issued against the wrong donor before
  G-13 ships the void path. Refusing every route leaves the administrator editing the record
  through the API or the Data Loader with the trigger disabled from Setup, which is the same
  act with none of the logging. An escape hatch that is hard, deliberate and recorded is
  safer than one people build for themselves.
- **Require two people to lift it.** Rejected as more machinery than a package this size can
  justify. A permission that is assigned to nobody, has to be granted in Setup, and writes to
  the Error Log when used is already several deliberate steps, and the small nonprofits this
  serves often have one administrator, so a second approver would mean the same person
  holding both roles.

## Consequences

- The receipt lock is no longer suspended by "Pause all automation", which changes what that
  button does. `automation-control.md` says so: the pause stops BarnCRM filling things
  in, and never stops it refusing something.
- Package code that legitimately writes to gifts inside `AutomationControl.bypass` is now
  subject to the lock. That is correct, and nothing in Giving edits a receipted gift's
  amount, date or donor: `GiftService.refund` and `writeOff` change only `Status__c` on the
  original and insert a linked negative gift, which is the ADR-0010 model and is untouched
  by the lock.
- A subscriber cannot mark their own automation `Always_Runs__c`, because the field lives on
  a protected custom metadata type. That is intended: it is a statement the package makes
  about its own rules, not a configuration surface.
- **The override reaches receipt immutability and nothing else.** R-G3's separate refusal, that
  a gift with a linked reversal is not deletable, stays absolute. `Gift__c.Original_Gift__c` is a
  lookup with `SetNull`, so lifting that one would leave a negative gift standing with nothing to
  say what it reverses: a wrong total with no trace of why. The two rules are enforced next door
  to each other and are not the same rule.
- `Override_Receipt_Lock` is a permission an org can misuse by simply leaving it assigned.
  Health Check should report it as a finding when anyone holds it, which is recorded as
  follow-up work rather than shipped here. **Shipped 2026-09-09** under C-11: the
  `override_receipt_lock` finding names the active people holding it, at Warning severity, with
  a fix that opens Custom Permissions in Setup. Core does not compile against Giving to do it:
  `CustomPermissionSelector` matches the permission on `DeveloperName` through
  `CustomPermission` and `SetupEntityAccess`, which are platform setup objects every org has,
  so an org without Giving answers "nobody" rather than failing (ADR-0009, ADR-0013).
- **Unverified in an org.** No Apex test in this repository has been executed, so the
  behaviour above is reasoned from the code and enforced by tests that have been written
  and not run.
