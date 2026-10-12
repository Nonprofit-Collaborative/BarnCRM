/**
 * The scan that finds the duplicates that were already there (C-20, canonical model R-DP3).
 *
 * A duplicate rule runs only when somebody saves a record, so the day BarnCRM is installed
 * the platform has never compared last year's imported spreadsheet with itself. The platform's
 * answer, a duplicate job, exists only in the two largest editions. This batch asks the
 * platform to evaluate the org's own active rules against records that already exist, fifty at
 * a time, which is the most one call accepts: people first, then households.
 *
 * It writes nothing but the platform's own duplicate record sets, changes nothing about the
 * records it examines, and merges nothing (R-DP4). It runs as the person who started it, so it
 * sees and records only what they can.
 */
public with sharing class DuplicateScanBatch implements Database.Batchable<SObject>, Database.Stateful {
    /** The Error Log context the scan's summary is written under, and the panel reads. */
    public static final String LOG_CONTEXT = 'Duplicate scan';

    private static final String CONTACT_QUERY = 'SELECT Id FROM Contact';
    private static final String CONTACT_QUERY_WITHOUT_PERSON_ACCOUNTS = 'SELECT Id FROM Contact WHERE IsPersonAccount = false'; // detection-only: used only after isPersonAccountOrg found person accounts, to leave their contact half out of the people pass

    private final String objectName;
    private final List<String> remaining;
    private final Map<String, Id> ruleIdsByName;
    private final List<String> scanned;
    @TestVisible
    private Integer written = 0;
    @TestVisible
    private Integer failedChunks = 0;

    public DuplicateScanBatch(String objectName, List<String> remaining) {
        this(objectName, remaining, new List<String>(), 0, 0);
    }

    /** A later pass, carrying what the passes before it found, so one summary covers the scan. */
    private DuplicateScanBatch(
        String objectName,
        List<String> remaining,
        List<String> scanned,
        Integer written,
        Integer failedChunks
    ) {
        this.objectName = objectName;
        this.remaining = remaining == null ? new List<String>() : remaining;
        this.ruleIdsByName = DuplicateSelector.activeRuleIdsByName(new Set<String>{ objectName });
        this.scanned = scanned;
        this.scanned.add(objectName);
        this.written = written;
        this.failedChunks = failedChunks;
    }

    /**
     * Starts a scan of every reviewed object that has an active duplicate rule, and answers
     * with the job started, or null when no rule is active for any of them: with nothing to
     * evaluate, a clean result would be a lie rather than an answer.
     */
    public static Id start() {
        Set<String> active = DuplicateSelector.objectsWithActiveRules(
            new Set<String>(DuplicateSelector.REVIEWED_OBJECTS)
        );
        List<String> toScan = new List<String>();
        for (String objectName : DuplicateSelector.REVIEWED_OBJECTS) {
            if (active.contains(objectName)) {
                toScan.add(objectName);
            }
        }
        if (toScan.isEmpty()) {
            return null;
        }
        String first = toScan.remove(0);
        return Database.executeBatch(
            new DuplicateScanBatch(first, toScan),
            DuplicateService.MAX_RECORDS_PER_CALL
        );
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocatorWithBinds(
            queryFor(objectName),
            new Map<String, Object>{ 'householdType' => HouseholdService.householdRecordTypeId() },
            AccessLevel.USER_MODE
        );
    }

    /**
     * Identifiers only: the matcher reads the records itself. Accounts are households only
     * (R-DP2). A person stored as an account is kept out of both passes, because the platform
     * refuses a whole call that includes one when no person account rule is active. In an org
     * with person accounts their contact half is filtered out by name in the query string, so
     * nothing here refers to the field where it does not exist (ADR-0013).
     */
    @TestVisible
    private static String queryFor(String objectName) {
        if (objectName == 'Account') {
            return 'SELECT Id FROM Account WHERE RecordTypeId = :householdType';
        }
        return HouseholdService.isPersonAccountOrg()
            ? CONTACT_QUERY_WITHOUT_PERSON_ACCOUNTS
            : CONTACT_QUERY;
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        Integer failuresBefore = DuplicateService.failureCount;
        written += scanChunk(scope, ruleIdsByName);
        if (DuplicateService.failureCount > failuresBefore) {
            failedChunks++;
        }
    }

    /** One chunk: ask, keep what is new and actionable, write it down. */
    public static Integer scanChunk(List<SObject> scope, Map<String, Id> ruleIdsByName) {
        List<Id> recordIds = new List<Id>();
        for (SObject record : scope) {
            recordIds.add(record.Id);
        }
        List<DuplicateService.Pair> candidates = DuplicateService.pairsToRecord(
            DuplicateService.matchesFor(recordIds),
            DuplicateService.pairsAlreadySuggested(new Set<Id>(recordIds))
        );
        return DuplicateService.recordPairs(
            DuplicateService.withoutDismissed(DuplicateService.actionablePairs(candidates)),
            ruleIdsByName
        );
    }

    /**
     * Starts the next object, or, after the last one, writes one summary of the whole scan. A
     * scan that found nothing says so, because "ran and found nothing" and "never ran" are
     * different facts; and a scan with a chunk it could not check says that at Warning,
     * because otherwise it would read as a clean result.
     */
    public void finish(Database.BatchableContext context) {
        if (!remaining.isEmpty()) {
            List<String> next = remaining.clone();
            String objectToScan = next.remove(0);
            Database.executeBatch(
                new DuplicateScanBatch(objectToScan, next, scanned, written, failedChunks),
                DuplicateService.MAX_RECORDS_PER_CALL
            );
            return;
        }
        logSummary();
    }

    @TestVisible
    private void logSummary() {
        List<String> values = new List<String>{
            String.join(scanned, ', '),
            String.valueOf(written),
            String.valueOf(failedChunks)
        };
        if (failedChunks > 0) {
            ErrorLogger.logMessage(
                String.format(Label.Core_Duplicates_ScanFinishedWithFailures, values),
                LOG_CONTEXT,
                ErrorLogger.SEVERITY_WARNING
            );
        } else {
            ErrorLogger.logMessage(
                String.format(Label.Core_Duplicates_ScanFinished, values),
                LOG_CONTEXT,
                ErrorLogger.SEVERITY_INFO
            );
        }
    }
}
