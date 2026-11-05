# ADR-NEXT: A household pair from the org's duplicate rules is shown only with household evidence

**Status:** Accepted (owner QA, Brandon, 2026-11-05)
**Date:** 2026-11-05
**Narrows:** ADR-0050

## Context

ADR-0050 shows whatever pairs the org's own Account duplicate rules find. The standard
Account matching rule compares the account name and the billing city. Households are named
from a pattern ("The X Family") and many households in one city share it, so in QA two
households were proposed as duplicates when only their city and state matched.

## Decision

- A pair of households found by the org's rules is kept only when the two share household
  evidence: the same street with the same city or postal code, the same phone, or the same
  name with the same postal code.
- Organization accounts and contacts are unchanged; the org's rules still decide them.
- The filter applies wherever pairs are shown: the nightly scan and the suggestions on a
  record.
- BarnCRM still ships no matching or duplicate rule (ADR-0050 unchanged otherwise).

## Consequences

- No false pairs from a shared city and a pattern name.
- A real duplicate household with no shared street, phone or postal code is not proposed;
  staff can still merge it by hand.
