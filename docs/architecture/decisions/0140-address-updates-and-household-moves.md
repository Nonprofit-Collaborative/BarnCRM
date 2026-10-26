# ADR-0140: Address Updates Has Three Choices, and a Household Can Be Moved on Purpose

**Status:** Accepted (owner decision, 2026-10-26)
**Date:** 2026-10-26
**Source:** owner decision AD1 (Brandon, 2026-10-26), approved as recommended "including the
default to everyone moves together". Amends plan Section 4.6 (household address with change
propagation to members) and the setting in Section 4.7, and canonical model rules R-AD3 and
R-AD5; adds R-AD9.

## Context

Until now one setting, `Contact_Address_Change_Behavior__c`, had two values. "Update
household" made a person's address edit the household's new primary address, so everyone
moved; "Create personal address" gave that person an address of their own. In both, every
household change (a new primary, a billing edit, the seasonal swap) reached every member with
no address of their own straight away (R-AD3).

Two things were missing. An organization whose staff edit addresses one person at a time, and
who check a move before mailing a whole household, had no way to stop a household change
reaching its members on its own. And there was no direct way back: making one person's own
address the household's address, or bringing everyone in a household onto its address again,
meant deleting records or retyping addresses.

## Decision

1. **One setting, three choices.** The field is kept, its two stored values stay valid, and a
   third is added. Its console label becomes **Address Updates** (a Settings title, so title
   case; the choices stay sentence case):
   - **Everyone in the household moves together** (`Update household`): the shipped choice and
     today's behaviour. A blank, or a value the console never offers, reads as this one, and
     the console shows it rather than an empty box.
   - **Only that person moves** (`Create personal address`): a person's edit becomes their own
     address; a household change still reaches members with no address of their own.
   - **Nobody moves until you choose** (`Manual`): a person's edit stays theirs, and a household
     change is written to the household only. It reaches the members when someone chooses
     **Update Everyone's Address**, and the seasonal swap still reaches members with no address
     of their own, because a swap the household asked for in advance is not a change anyone
     needs to check.
2. **Two buttons on the existing Addresses card** (no new component), offered in every
   setting:
   - **Use for Whole Household** on a person's own address makes a copy of it the household's
     primary address. In junction mode it targets the person's household (R-M3), and where
     they are a current member of several the user picks one. The person, if stored as a
     Contact, stops having a primary address of their own and follows the household again.
   - **Update Everyone's Address** on the household's primary address asks first: it lists the
     members who will change and those with an address of their own, who are left alone unless
     ticked.
3. **Like any other address write.** Both run as the user, in user mode, so a person who cannot
   edit addresses, the household or its people is refused. The service methods take many
   records at once. Nothing is deleted: a replaced primary stays on file as history (R-AD7).

## Consequences

- An org that chooses Manual sees a household's own address fields change while its people
  keep their old mailing address until someone presses Update Everyone's Address. The admin
  guide says so, and the confirmation lists exactly who moves.
- The seasonal swap marks its saves as a chosen move (`AddressService.chooseHouseholdMoves`), so
  it behaves the same in every setting.
- No object or field is added, and stored values need no migration.
