/**
 * Works out computed indicators' results (L-03; ADR-0158 `0158-indicator-sources.md`; canonical
 * model R-IN5 and R-IN6), one indicator per run, then starts the run for the next.
 *
 * The indicator's Find saved query is compiled as the running user (`IndicatorSourceService`,
 * so an object or field they cannot read stops the run), then its records whose date falls
 * between the earliest start and the latest end of the indicator's started periods are read in
 * chunks, and each record is counted in every period whose dates hold it. The finish writes each
 * started period's Result Value, the indicator's Computed At, and clears Source Status; a failure
 * writes Source Status and changes no result.
 *
 * Without sharing on purpose: the records are read in system mode so the result is the
 * organization's figure, not the share of records the person who pressed Refresh Results or
 * scheduled the nightly job can see (ADR-0158 decision 6). Only numbers are written, and only
 * Logic Models Admin can define what is counted.
 */
public without sharing class IndicatorResultsBatch implements Database.Batchable<SObject>, Database.Stateful {
    /** Records per chunk. */
    @TestVisible
    private static final Integer CHUNK_SIZE = 2000;
    /** The share of the heap a Count Unique may fill before it stops (R-IN6). */
    private static final Decimal HEAP_SHARE = 0.8;
    private static final String ERROR_CONTEXT = 'IndicatorResultsBatch';

    private final Id indicatorId;
    private final List<Id> waiting;
    private IndicatorSourceService.Definition definition;
    private List<Bucket> buckets = new List<Bucket>();
    /** True when the indicator is gone or no longer computed: nothing is written. */
    private Boolean skip = false;
    /** What stopped the run, in plain words, or null. */
    private String problem;
    /** The source query's bind values, with the periods' dates. */
    private Map<String, Object> binds;

    /** One started period and what has been counted in it. */
    private class Bucket {
        Id periodId;
        Date startDate;
        Date endDate;
        Decimal total = 0;
        Set<String> seen = new Set<String>();
    }

    /**
     * @param indicatorIds the indicators to work out, the first now and the rest after it
     */
    public IndicatorResultsBatch(List<Id> indicatorIds) {
        waiting = new List<Id>(indicatorIds);
        indicatorId = waiting.isEmpty() ? null : waiting.remove(0);
    }

    /**
     * Starts the run for the first indicator; each run starts the next.
     *
     * @param indicatorIds the computed indicators to work out
     * @return the batch job's Id, or null when there is nothing to do
     */
    public static Id run(List<Id> indicatorIds) {
        if (indicatorIds == null || indicatorIds.isEmpty()) {
            return null;
        }
        return Database.executeBatch(new IndicatorResultsBatch(indicatorIds), CHUNK_SIZE);
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        try {
            String soql = sourceQuery();
            if (soql != null) {
                return Database.getQueryLocatorWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
            }
        } catch (LogicModelService.BuilderException refused) {
            problem = refused.getMessage();
        } catch (Exception failed) {
            ErrorLogger.log(failed, ERROR_CONTEXT);
            problem = Label.LogicModels_Source_RefreshFailed;
        }
        return Database.getQueryLocatorWithBinds(
            'SELECT Id FROM Indicator__c WHERE Id = :nothing',
            new Map<String, Object>{ 'nothing' => null },
            AccessLevel.SYSTEM_MODE
        );
    }

    /** The query of the source records, or null when there is nothing to read. */
    private String sourceQuery() {
        List<Indicator__c> found = [
            SELECT
                Id,
                Source__c,
                Source_Query__c,
                Source_Query__r.Query_JSON__c,
                Source_Definition__c
            FROM Indicator__c
            WHERE Id = :indicatorId
            WITH SYSTEM_MODE
        ];
        if (found.isEmpty() || found[0].Source__c != IndicatorSourceService.COMPUTED) {
            skip = true;
            return null;
        }
        Indicator__c indicator = found[0];
        if (indicator.Source_Query__c == null) {
            throw new LogicModelService.BuilderException(Label.LogicModels_Source_QueryMissing);
        }
        definition = IndicatorSourceService.parse(indicator.Source_Definition__c);
        if (definition == null) {
            throw new LogicModelService.BuilderException(Label.LogicModels_Source_Invalid);
        }
        Date today = Date.today();
        Date earliest;
        Date latest;
        for (Indicator_Period__c period : [
            SELECT Id, Start_Date__c, End_Date__c
            FROM Indicator_Period__c
            WHERE Indicator__c = :indicatorId AND Start_Date__c <= :today
            WITH SYSTEM_MODE
            ORDER BY Start_Date__c
        ]) {
            Bucket bucket = new Bucket();
            bucket.periodId = period.Id;
            bucket.startDate = period.Start_Date__c;
            bucket.endDate = period.End_Date__c;
            buckets.add(bucket);
            earliest = earliest == null ||
                bucket.startDate < earliest
                ? bucket.startDate
                : earliest;
            latest = latest == null || bucket.endDate > latest ? bucket.endDate : latest;
        }
        if (buckets.isEmpty()) {
            return null;
        }
        QueryCompiler.Compiled compiled = IndicatorSourceService.compile(
            indicator.Source_Query__r.Query_JSON__c
        );
        IndicatorSourceService.check(compiled.objectName, definition);
        Boolean dateTimeField =
            QueryCompiler.resolve(compiled.objectName, definition.dateField).getType() ==
            Schema.DisplayType.DATETIME;

        binds = new Map<String, Object>(compiled.binds);
        binds.remove('rowLimit');
        if (dateTimeField) {
            binds.put('periodsFrom', Datetime.newInstance(earliest, Time.newInstance(0, 0, 0, 0)));
            binds.put(
                'periodsTo',
                Datetime.newInstance(latest.addDays(1), Time.newInstance(0, 0, 0, 0))
            );
        } else {
            binds.put('periodsFrom', earliest);
            binds.put('periodsTo', latest.addDays(1));
        }
        Set<String> columns = new Set<String>{ 'id', definition.dateField.toLowerCase() };
        String selected = 'SELECT Id, ' + definition.dateField;
        if (definition.field != null && columns.add(definition.field.toLowerCase())) {
            selected += ', ' + definition.field;
        }
        // Every name was checked by QueryCompiler.resolve (letters, digits, underscores and dots).
        return selected +
            compiled.fromWhere +
            (compiled.fromWhere.contains(' WHERE ') ? ' AND ' : ' WHERE ') +
            definition.dateField +
            ' >= :periodsFrom AND ' +
            definition.dateField +
            ' < :periodsTo';
    }

    public void execute(Database.BatchableContext context, List<SObject> records) {
        if (problem != null || skip || definition == null) {
            return;
        }
        for (SObject record : records) {
            Date day = dayOf(valueAt(record, definition.dateField));
            if (day == null) {
                continue;
            }
            Object measured = definition.field == null ? null : valueAt(record, definition.field);
            for (Bucket bucket : buckets) {
                if (day < bucket.startDate || day > bucket.endDate) {
                    continue;
                }
                if (definition.function == IndicatorSourceService.COUNT) {
                    bucket.total += 1;
                } else if (definition.function == IndicatorSourceService.SUM) {
                    bucket.total += measured == null
                        ? 0
                        : Decimal.valueOf(String.valueOf(measured));
                } else if (measured != null) {
                    bucket.seen.add(String.valueOf(measured));
                }
            }
        }
        if (Limits.getHeapSize() > Limits.getLimitHeapSize() * HEAP_SHARE) {
            problem = Label.LogicModels_Source_TooManyUnique;
            for (Bucket bucket : buckets) {
                bucket.seen.clear();
            }
        }
    }

    public void finish(Database.BatchableContext context) {
        try {
            write();
        } catch (Exception failed) {
            ErrorLogger.log(failed, ERROR_CONTEXT);
        }
        if (!waiting.isEmpty() && !Test.isRunningTest()) {
            try {
                run(waiting);
            } catch (Exception failed) {
                ErrorLogger.log(failed, ERROR_CONTEXT);
            }
        }
    }

    private void write() {
        if (skip) {
            return;
        }
        Indicator__c indicator = new Indicator__c(Id = indicatorId);
        List<SObject> changes = new List<SObject>();
        if (problem != null) {
            indicator.Source_Status__c = problem.abbreviate(255);
        } else {
            for (Bucket bucket : buckets) {
                Decimal result = definition.function == IndicatorSourceService.UNIQUE
                    ? Decimal.valueOf(bucket.seen.size())
                    : bucket.total;
                changes.add(
                    new Indicator_Period__c(
                        Id = bucket.periodId,
                        Result_Value__c = result.setScale(2, RoundingMode.HALF_UP)
                    )
                );
            }
            indicator.Computed_At__c = Datetime.now();
            indicator.Source_Status__c = null;
        }
        changes.add(indicator);
        for (Database.SaveResult saved : Database.update(changes, false, AccessLevel.SYSTEM_MODE)) {
            for (Database.Error error : saved.getErrors()) {
                // A period or the indicator deleted while the run read its records.
                if (error.getStatusCode() != StatusCode.ENTITY_IS_DELETED) {
                    ErrorLogger.logMessage(
                        error.getMessage(),
                        ERROR_CONTEXT,
                        ErrorLogger.SEVERITY_WARNING
                    );
                }
            }
        }
    }

    /** A date, or a date-time's date in the running user's time zone, or null. */
    private static Date dayOf(Object value) {
        if (value instanceof Datetime) {
            return ((Datetime) value).date();
        }
        return value instanceof Date ? (Date) value : null;
    }

    /** The value at a field path such as `Service__r.Date__c`, or null. */
    @TestVisible
    private static Object valueAt(SObject record, String path) {
        List<String> names = path.split('\\.');
        SObject current = record;
        for (Integer index = 0; index < names.size() - 1; index++) {
            current = current == null ? null : current.getSObject(names[index]);
        }
        return current == null ? null : current.get(names[names.size() - 1]);
    }
}
