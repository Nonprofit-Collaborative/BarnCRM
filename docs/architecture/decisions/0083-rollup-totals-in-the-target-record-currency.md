# ADR-0083: Rollup totals are in the target record's currency

**Status:** Accepted (owner decision, 2026-10-12, rollup comparison recommendations)
**Date:** 2026-10-12
**Source:** rollup proposal slice S5; plan Section 4.10; ADR-0015 (the vendored engine this
replaces)

## Context

BarnCRM's own rollup engine (slice S5, `RollupEngine`) calculates SUM, COUNT, MIN, MAX and AVG
with grouped aggregate queries. In an org with multiple currencies, the SOQL reference says that
when a query has a `GROUP BY` clause, a currency value returned by an aggregate function such as
`SUM()` or `MAX()` is in the org's corporate currency, and `convertCurrency()` cannot be applied to
it. (To confirm in a multi-currency org; see Verification.) FIRST and LAST read rows, whose
currency values are in each row's own currency. Totals so far have added amounts as entered,
which is only right while every amount is in one currency.

Multi-currency was deferred in the proposal's feature set ("first multi-currency customer"). The
engine still has to do something defined when it meets such an org, because a total that mixes
corporate and entered amounts is wrong without any error.

## Decision

1. **Single-currency org:** amounts are aggregated as entered. Nothing is converted.
2. **Multi-currency org:** the engine works in the corporate currency throughout. Grouped
   answers already are; FIRST and LAST row values are divided by their row's conversion rate.
   When the target attribute is a currency attribute and the source attribute is a currency
   attribute, the result is multiplied by the rate of the target record's own currency
   (`CurrencyIsoCode`) before it is compared and written. A target that is a plain number keeps
   the corporate amount. COUNT and dates are never converted.
3. **Rates:** the org's static conversion rates (`CurrencyType`). Dated exchange rates are not
   applied; a total therefore changes when a rate changes and the next recalculation runs.
4. `CurrencyType` and `CurrencyIsoCode` are named as text and read dynamically
   (`RollupCurrency`), so Core still compiles and installs in a single-currency org.

## Alternatives considered

- **Add as entered everywhere.** Wrong in a multi-currency org: 100 EUR plus 100 USD is not 200.
- **Corporate currency everywhere.** Simpler, but a record in another currency would show its
  totals in a currency it does not display.
- **Dated exchange rates.** Needs one conversion per row by gift date, which grouped queries
  cannot do. Brought back when a customer needs it.

## Consequences

- The Rollup Builder (slice S11) shows these warnings in a multi-currency org:
  - On a currency total: "This org uses more than one currency. Totals are converted to each
    record's currency at today's rates, not the rate on the gift date."
  - On a currency total written to a number field: "This field is a number, not a currency, so
    the total is shown in the corporate currency."
  - On a rate change, in the help text: "After changing exchange rates, recalculate your money
    totals to bring them up to date."
- Verification: `RollupCurrencyTest` checks the arithmetic with test rates in every org, and its
  live test asserts conversion only when `UserInfo.isMultiCurrencyOrganization()` is true and
  asserts as-entered amounts otherwise. The first multi-currency test org confirms the corporate
  currency claim above.
