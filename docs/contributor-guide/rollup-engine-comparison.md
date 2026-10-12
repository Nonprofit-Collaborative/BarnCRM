# Rollup engine comparison

Since slice S8, every rollup run uses BarnCRM's own engine. The vendored apex-rollup tree
(`packages/core/vendor/apex-rollup`), `RollupAdapter`, `Rollup__mdt` and `RollupCalcItem__c` stay
in the repository, reached by no run, until this comparison is clean
(`docs/architecture/decisions/NEXT-barncrm-owns-its-rollup-engine.md`, rollup proposal D9 and
Section 6 step 5). Slice S9 deletes them after that.

`RollupEngineComparison` calculates the same target records with both engines and lists every
value where they differ.

## What it does

For each active definition:

1. It picks the target records: the ones you name, or a sample of up to 200 records of the
   definition's target entity, taken in Id order. Either way it keeps only records the definition's
   target filter admits.
2. It reads the value stored on each record now.
3. It runs BarnCRM's engine for that definition and those records, reads the values back, and rolls
   back to a savepoint.
4. It runs the vendored engine the same way (the single-record recalculation entry point, which
   calculates in the same transaction), reads the values back, and rolls back.
5. It compares the two answers. Numbers are compared as numbers, so `3` and `3.0` are equal.
   Zero and blank are not equal.

Nothing is saved. Every registered automation is bypassed during the run, so a save by either
engine starts nothing else. If the vendored engine starts a background job anyway, which a rollback
does not take back, the run throws and the whole transaction is discarded. The error message holds
the report, so you still see the result. Compare fewer records or fewer definitions when that happens.

## Running it

Use a test org with sample data loaded (BarnCRM Settings, then Sample data), never a production org.
You need the Author Apex permission, which Anonymous Apex requires anyway. Run this in the Developer
Console (Debug, Open Execute Anonymous Window) or with `sf apex run`:

```apex
System.debug(LoggingLevel.ERROR, RollupEngineComparison.run(null, 50).summary());
```

- `run(keys, sample)` compares the active definitions with these `Definition_Key__c` values (null
  compares every active definition) over a sample of up to `sample` records each (null takes 50, at
  most 200).
- `compare(recordIds, keys)` compares over the records you name, which is how you check a donor whose
  totals look wrong.

```apex
System.debug(
    LoggingLevel.ERROR,
    RollupEngineComparison.compare(
        new Set<Id>{ '001XXXXXXXXXXXXXXX' },
        new Set<String>{ 'Account_Gift_Count' }
    ).summary()
);
```

A run stops before it nears a governor limit and names the definitions it did not reach. Run it again
with those keys. Running every definition in groups of five to ten keeps each run small.

## Reading the report

The first line gives the totals. Then one line per difference: the definition, the attribute, the
record, the stored value, BarnCRM's answer and the vendored answer. Then each definition that was not
compared, with the reason.

Differences the comparison is expected to find, each to be confirmed rather than assumed:

- **Definitions the vendored engine cannot run.** It refuses a definition that reads an attribute
  through a relationship (gift allocation and soft credit totals read the gift's status and date) or
  reaches its target through a household token. These show as "The vendored engine failed". BarnCRM's
  answer for them is judged by the Giving regression suite, not by this comparison.
- **Zero against blank.** A sum or count with nothing to count is zero in BarnCRM's engine. If the
  vendored engine leaves a record blank, or resets it in a separate background job, the line shows
  zero against blank.
- **Target filters.** Each definition is compared only over records its target filter admits, so the
  vendored engine's habit of writing records the filter excludes (proposal bug 2) does not show here.
  `RollupRegressionTargetsTest` covers it.

Freshness stamps (`Rollups_Last_Calculated__c`, `Last_Calculated__c`) are not compared: only
BarnCRM's engine writes them.

## The gate

Record each run's summary on the S9 pull request. S9 may delete the vendored tree when every
difference left is one of the expected kinds above, or has its own explanation in that pull request.
