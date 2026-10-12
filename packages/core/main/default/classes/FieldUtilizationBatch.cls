/**
 * One run of the field utilization count (canonical model Section 29D).
 *
 * The start reads each object's record count by record type and lists one item per field.
 * Each item costs one count query, so a chunk of 25 stays far inside the 200 query limit and
 * keeps one chunk's wall time short on a large object. Stateful for the totals the start read
 * and the counts the summary reports.
 */
public with sharing class FieldUtilizationBatch implements Database.Batchable<Object>, Database.Stateful {
    /** Fields per chunk: one count query each. */
    public static final Integer CHUNK_SIZE = 25;

    private static final String LOG_CONTEXT = 'Field utilization count';

    private List<String> objectNames;
    private Datetime takenAt;
    private Map<String, Map<String, Integer>> totals = new Map<String, Map<String, Integer>>();
    private List<String> skipped = new List<String>();
    private Set<String> objectsCounted = new Set<String>();
    private Integer fieldsCounted = 0;
    private Integer fieldsFailed = 0;

    /** Narrows a test run to the named fields, so a test does not depend on the org's fields. */
    @TestVisible
    private Set<String> onlyFields;

    /** A run over the objects saved on the Field Utilization page. */
    public FieldUtilizationBatch() {
        this(FieldUtilizationService.trackedObjects());
    }

    /** A run over the named objects. */
    public FieldUtilizationBatch(List<String> objectNames) {
        this.objectNames = objectNames == null ? new List<String>() : objectNames;
        this.takenAt = System.now();
    }

    public Iterable<Object> start(Database.BatchableContext context) {
        List<Object> items = new List<Object>();
        try {
            FieldUtilizationService.Plan planned = FieldUtilizationService.plan(
                this.objectNames,
                this.onlyFields
            );
            this.totals = planned.totals;
            this.skipped = planned.skipped;
            items.addAll(planned.items);
        } catch (Exception planFailure) {
            ErrorLogger.log(planFailure, LOG_CONTEXT);
        }
        return items;
    }

    public void execute(Database.BatchableContext context, List<Object> scope) {
        List<Field_Utilization_Snapshot__c> rows = new List<Field_Utilization_Snapshot__c>();
        Integer chunkCounted = 0;
        for (Object entry : scope) {
            FieldUtilizationService.Item item = (FieldUtilizationService.Item) entry;
            try {
                rows.addAll(
                    FieldUtilizationService.count(
                        item,
                        this.totals.get(item.objectName),
                        this.takenAt
                    )
                );
                chunkCounted++;
                this.objectsCounted.add(item.objectName);
            } catch (Exception fieldFailure) {
                this.fieldsFailed++;
                ErrorLogger.log(
                    fieldFailure,
                    LOG_CONTEXT + ': ' + item.objectName + '.' + item.fieldName
                );
            }
        }
        try {
            FieldUtilizationService.save(rows);
            this.fieldsCounted += chunkCounted;
        } catch (Exception saveFailure) {
            this.fieldsFailed += chunkCounted;
            ErrorLogger.log(saveFailure, LOG_CONTEXT);
        }
    }

    /** Ages out old rows and records the run, including a run that counted nothing (R-FU8). */
    public void finish(Database.BatchableContext context) {
        Datetime now = System.now();
        try {
            FieldUtilizationService.purgeOld(now);
        } catch (Exception purgeFailure) {
            ErrorLogger.log(purgeFailure, LOG_CONTEXT);
        }
        FieldUtilizationService.recordRun(
            now,
            FieldUtilizationService.summary(
                this.fieldsCounted,
                this.objectsCounted.size(),
                this.fieldsFailed,
                this.skipped
            )
        );
    }

    /** When this run's rows say they were taken. */
    public Datetime takenAt() {
        return this.takenAt;
    }
}
