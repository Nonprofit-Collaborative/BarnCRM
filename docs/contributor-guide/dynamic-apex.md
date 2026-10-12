# Dynamic Apex conventions

How Open Impact reaches an object, field or class that a subscriber org may not have. Every
rule here is one the code on `main` already follows; each names the class to copy. Plan
Section 4.2 sets the requirement, ADR-0009 and ADR-0013 the Platform-only floor, ADR-0017
the cross-package mechanisms.

Why it matters: a static reference to something an org lacks is a compile error, and one
compile error refuses the whole package. Dynamic code compiles everywhere and asks the org
at runtime.

## 1. What must be dynamic

| Reached from | Target | Example | Decision |
| --- | --- | --- | --- |
| Connect | Campaign (and later Opportunity, Gift Transaction) | `CampaignSyncService`, `CampaignSyncSelector` | ADR-0056 |
| Core | Person Account fields (`PersonEmail`, `PersonMailingPostalCode`, `...__pc`) | `ImportMatcher`, `ImportRowProcessor.storedName` | ADR-0013 |
| Core | Giving behaviour (classes) | `ImportEntityProcessors`, `SampleDataModules`, `HealthCheckExtensions`, `SetupAssistantExtensions` | ADR-0017, ADR-0057, ADR-0059 |
| Core | Industries, NPSP, Sales Cloud detection | `OrgShapeDetector` | ADR-0013 |

The shape, from `CampaignSyncService`:

```apex
// detection-only: Campaign is resolved through describe so Connect installs without it
private static final String CAMPAIGN_OBJECT = 'Campaign';

public static Schema.SObjectType campaignType() {
    if (!typeResolved) {
        resolvedType = Schema.getGlobalDescribe().get(CAMPAIGN_OBJECT);
        typeResolved = true;
    }
    return resolvedType; // null on a Platform-only org: the feature does nothing
}
```

Rules:

- The name is a `String` constant. Records are `SObject`, read with `get` and written with
  `put`. Never `Campaign`, `Account.PersonEmail` or `Receipt__c.Status__c` as tokens.
- Field names come from the org's own describe before use. `ImportRowProcessor.personFieldFor`
  returns `getDescribe().getName()` of a field it found, never a name it assembled.
- Absent means "feature off", not an error: return empty, `null`, or `available = false`
  (a result whose `available` is false), and let the caller say nothing rather than zero.
- When the logic is another package's rule, not one field comparison, do not re-derive it
  dynamically; call the package through a discovered class (section 3). ADR-0057 records why.

## 2. How CI enforces it

| Gate | Catches | Misses |
| --- | --- | --- |
| `check-standard-objects.sh` (denylist) | Opportunity, Campaign, Lead, Case, `PersonAccount`, `IsPersonAccount`, `GiftTransaction`, `__dlm`, and the Nonprofit Cloud objects, in Core, Giving, Volunteers, Programs and Funders | Anything not on its list; any file in `packages/connect`; Person Account fields other than `IsPersonAccount` |
| `check-object-allowlist.py` (allowlist, every package including Connect and the vendor tree) | Any standard object not listed, in `new X(`, `List<X>`, `X.SObjectType`, `FROM X` | Plain declarations (`Campaign c;`), field tokens (`Account.PersonEmail`) |
| Offline Apex compile (`check:apex`) | Nothing about org shape: it compiles against a schema that has everything | |

A `String` constant naming a denied object is exempted by a trailing marker on that line
only (details in [ci.md](ci.md), "Detection-only exemptions"):

```apex
private static final String PERSON_ACCOUNT_FIELD = 'IsPersonAccount'; // detection-only: field map key
```

Neither gate sees a static Person Account field token such as `Account.PersonEmail`. Review
is the only guard: hold those names as strings, as `ImportMatcher` does.

## 3. Discovering a class in another package (`Type.forName`)

Core defines an interface; a dependent package implements it under a known class name; Core
looks the class up at runtime. Four resolvers share one shape (`ImportEntityProcessors`,
`HealthCheckExtensions`, `SampleDataModules`, `SetupAssistantExtensions`), and
`TriggerDispatcher` uses it for registry handlers.

```apex
private static HealthCheckExtension resolve() {
    String prefix = NamespaceUtil.prefix();
    Type found = Type.forName(String.isBlank(prefix) ? null : prefix.removeEnd('__'), CLASS_NAME);
    if (found == null) {
        found = Type.forName(CLASS_NAME); // no namespace: today, and unmanaged deploys
    }
    if (found == null) {
        return null; // package not installed: the ordinary case
    }
    Object candidate;
    try {
        candidate = found.newInstance();
    } catch (Exception cannotBuild) {
        ErrorLogger.log(cannotBuild, 'HealthCheckExtensions.resolve');
        return null;
    }
    return candidate instanceof HealthCheckExtension ? (HealthCheckExtension) candidate : null;
}
```

Rules:

- **Namespace first, then none.** A class name is not an API name: it takes no `__` suffix.
- **Look up once per transaction** (`looked` flag in `ImportEntityProcessors.find`).
- **A class that cannot be built, or is the wrong shape, is absent.** A build failure is
  logged; `HealthCheckExtensions` also logs a wrong shape. The caller must not fail over a
  module it can do without.
- **Isolate the call.** `HealthCheckService.run()` turns an extension that throws into one
  `check_failed_...` finding; the rest of the report stands.
- **Only names the package owns reach `Type.forName`**: a constant, a registry row, or an
  allowlisted map (`ReceiptRendererFactory.PERMITTED_RENDERERS`). Never user input.
- **Test seams:** `@TestVisible` overrides (`overrides`, `processorOverride`,
  `moduleOverride`, `noneForTest`) let Core test installed, absent and throwing without the
  other package.

### What the implementing class needs

- `public` (not `global`, ADR-0017), `@NamespaceAccessible`, a public no-argument
  constructor, and the interface. See `GivingHealthCheckExtension`, `GiftImportProcessor`,
  `GivingSampleData`.
- Every Core member a dependent package calls is `@NamespaceAccessible`: the class, the
  method, the inner class and its constructor. Annotate what is reached, not ahead of need
  (`HealthCheckService` header lists exactly which members).

### `@AuraEnabled` fields cannot also be `@NamespaceAccessible`

The platform rejects both on one field (compile error). So `HealthCheckService.Finding`'s
fields are `@AuraEnabled` only. A test in another package reads them the way Lightning does,
through JSON (`GivingHealthCheckExtensionTest`):

```apex
private static Map<String, Object> asMap(HealthCheckService.Finding finding) {
    return (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(finding));
}
```

If a registered namespace later shows production code cannot read such a field, add an
`@NamespaceAccessible` getter for that field.

## 4. The namespace is empty today

`sfdx-project.json` has no namespace (ADR-0001). Never write a prefix; `check-namespace.sh`
fails the build. Never assume there is none either:

- Packaged API names in dynamic code go through `NamespaceUtil.qualify(...)`
  (`ImportEntityProcessors`, for a field it looks up by name). Values matched on are data and
  are never qualified.
- Names from metadata rows, which carry no prefix, resolve with
  `SettingsService.typeByName`, which tries the exact name and then the part after a
  namespace.
- Class lookups use `NamespaceUtil.prefix()` without the trailing `__` (section 3).
- Lightning components never build these names; Apex returns them.

## 5. Describe once, never in a loop

Describe calls are cached per transaction in a static map and read outside row loops.

```apex
// ImportRowProcessor
private static Map<Schema.SObjectType, Map<String, Schema.SObjectField>> fieldMaps = new Map<Schema.SObjectType, Map<String, Schema.SObjectField>>();

private static Map<String, Schema.SObjectField> fieldsOf(Schema.SObjectType type) {
    if (!fieldMaps.containsKey(type)) {
        fieldMaps.put(type, type.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap());
    }
    return fieldMaps.get(type);
}
```

- `Schema.getGlobalDescribe()` once per transaction per question: `OrgShapeDetector`
  (`cachedShape`), `CampaignSyncService.campaignType()` (`typeResolved`).
- `getDescribe(SObjectDescribeOptions.DEFERRED)` for object describes; field describes are
  taken only for the fields used.
- Derived answers are cached too (`ImportRowProcessor.storedNames`,
  `SettingsService.cachedFields`).
- Field map keys are lower case: `fields.get(name.toLowerCase())`.

## 6. CRUD, FLS and sharing in dynamic code

Default: `with sharing` and user mode, as for all Apex (plan Sections 4.13 and 7.2).

| Mode | When | Example |
| --- | --- | --- |
| User mode (`AccessLevel.USER_MODE`, `WITH USER_MODE`) | Every read that reaches a user, and every write of data the package does not own | `CampaignSyncSelector`, `CampaignSyncService` writes (ADR-0056 decision 3) |
| System mode, `without sharing` | Only the ADR-0021 writers, for package-owned data | `SettingsWriter`, `HouseholdWriter`, `ErrorLogWriter` |
| System mode read reaching a user | Only the one exception ADR-0057 amends into ADR-0021 | `HealthCheckGivingSelector`, gated inside itself by `canManageSettings()` |

A new `without sharing` or `SYSTEM_MODE` read that reaches a user needs its own ADR; it
cannot cite ADR-0057.

### Check before a user-mode query

A user-mode query naming a field the user cannot read throws, and fails the whole chunk or
check. So check the object **and every field the query names** first:

```apex
// The Receipt__c count Core took before C-29 moved it to Giving (ADR-0059)
DescribeSObjectResult receipt = receiptType.getDescribe(SObjectDescribeOptions.DEFERRED);
if (!receipt.isAccessible()) {
    return result;
}
if (!isReadable(fields, statusField) || !isReadable(fields, reasonField)) {
    return result;
}
```

`ErrorLogCountSelector.isReadable` records why the field check matters: checking the object
alone turned missing field access into a failed Health Check.

- For writes, check `isCreateable()` on insert and `isUpdateable()` on update, per field
  (`ImportRowProcessor`).
- **Name what was skipped.** A field left out for access is reported by its label, never
  dropped silently: `ImportMatcher.unreadableFields()` feeds the import run log
  (`Core_Import_LogMatchFieldNoAccess`), and `ImportRowProcessor.noAccessNote` does the same
  for writes.
- What a person cannot see is told to them as nothing, never as a fault
  (`ErrorLogCountSelector`). Where a zero would read as "none failed", say "unknown"
  instead (a result whose `available` is false).

## 7. Dynamic SOQL

- **Bind every value.** Use `Database.queryWithBinds` or `Database.countQueryWithBinds` with
  an explicit `AccessLevel`:

  ```apex
  Database.queryWithBinds(
      'SELECT ' + CAMPAIGN_FIELDS + ' FROM ' + String.escapeSingleQuotes(campaignObject) +
      ' WHERE Id IN :campaignIds',
      new Map<String, Object>{ 'campaignIds' => campaignIds },
      AccessLevel.USER_MODE
  );
  ```

- **Identifiers come from describe or constants**, never from user text (ADR-0021 condition
  2). Binds cannot carry an identifier, so an object name may be wrapped in
  `String.escapeSingleQuotes` as defence in depth (`CampaignSyncSelector`, `ImportUndoBatch`).
- **`String.escapeSingleQuotes` on a value only where a bind is impossible**, such as a filter
  string handed to the rollup engine (`RollupFilterParser`). On a bind it corrupts the value
  (`HouseholdSelector.searchHouseholds`: it "would lose every O'Brien").
- **Escape LIKE wildcards** in a bound search term (`\`, `%`, `_`), as `searchHouseholds` does.
- **Keep the query string testable.** Build it in a separate `@TestVisible` method, so a test
  in an org without the other package still asserts what Core would ask.

### Cap every count and read

- Never an uncapped `COUNT()` over data that grows. Read `cap + 1` and report "more than cap"
  (`ErrorLogCountSelector.countNewUpTo`, `HealthCheckHouseholdChecks.countCap`,
  `HealthCheckGivingChecks`).
- A bulk lookup carries a row cap and notes when it was hit (`ImportMatcher.rowCap`,
  `noteCutOff`), and slices large key sets (`MAX_KEYS_PER_QUERY`).
- **Query-row headroom:** before a read that can spend many rows, size it from what is left:

  ```apex
  // ErrorDigestService: two reads spend up to the cap each; keep a margin for the rest.
  Integer room = (Limits.getLimitQueryRows() - Limits.getQueryRows() - QUERY_ROW_MARGIN) / 2;
  ```

## 8. Trigger paths: headroom and bulk logging

A trigger handler shares its transaction with every other automation, and a large Apex
insert runs it once per 200 records.

- **Check headroom before the work, skip and log once if there is none.**
  `CampaignSyncService.hasHeadroom` checks queries, DML statements and DML rows against
  what one copy costs plus `SAFETY_MARGIN`; a save too large to copy is left for Sync all
  appeals with one Warning per transaction (ADR-0056 decision 8).
- **Seams for the limits:** `@TestVisible simulatedQueriesUsed` and
  `simulatedDmlStatementsUsed` let a test show a nearly spent transaction.
- **One log write per call.** Queue messages and write them with
  `ErrorLogger.logMessages(messages, recordIds, context, severity)`, one statement however
  many records failed (`CampaignSyncService.flushLog`).
- **Once-per-transaction warnings** use a static flag (`noAccessLogged`, `noHeadroomLogged`),
  so edits do not flood the log.
- **Partial success on writes to objects the package does not own**, so a refused Campaign
  never refuses the appeal.

## 9. Testing dynamic code

- **Both branches assert.** A test that depends on a feature asserts the absent branch too,
  not a bare `return`. `CampaignSyncServiceTest`:

  ```apex
  if (!CampaignSyncService.isAvailable()) {
      Assert.isNull(saved.Campaign_Id__c, 'Without Campaign the sync does nothing.');
      return;
  }
  Assert.isNotNull(saved.Campaign_Id__c, 'The Campaign is linked in the same save (R-CS3).');
  ```

  Where the absent branch has nothing to assert, the skip must be the first statement and
  the present branch must assert something real (`ImportPersonAccountTest`, guarded by
  `orgHasPersonAccounts()`).
- **Force the other shape with seams**, not with the org: `OrgShapeDetector.overrideShape`,
  `CustomPermissionSelector.holdersOverride`, the resolver overrides in section 3.
- **Test orgs:** `oi-test` and `oi-pa` both have Person Accounts and the Sales Cloud objects
  (see [ci.md](ci.md)). Every feature-present branch runs on them; no feature-absent branch
  does.
- **Known gap:** no org runs the Platform-only shape. ADR-0013 records that a scratch org
  cannot remove the standard objects, and plan Section 7.3's four-shape matrix does not run
  (ci.md, opening section). Absent-object paths are covered only by the seams above and by
  the static gates in section 2. A manual check on a real Platform-license org is scheduled for the
  v0.10 hardening iteration (ADR-0013).
