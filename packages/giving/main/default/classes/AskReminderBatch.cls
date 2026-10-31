/**
 * The nightly ask reminder pass: creates a task for the owner of every donor whose Next Ask Date
 * has arrived and who has not been reminded for that date (R-AC3).
 *
 * It runs over accounts first and chains to contacts, so one run covers organizations,
 * households and people, and records one summary at the end. Safe to run twice on one day:
 * a donor already stamped for its date is skipped, so the second run creates nothing.
 */
public with sharing class AskReminderBatch implements Database.Batchable<SObject>, Database.Stateful {
    @TestVisible
    private static final String ACCOUNTS = 'Account';
    @TestVisible
    private static final String CONTACTS = 'Contact';
    /** Task inserts and stamps per chunk: two DML statements however many donors are in it. */
    public static final Integer CHUNK_SIZE = 200;

    private final String scopeObject;
    private final Date today;
    private Integer created = 0;
    private Integer failed = 0;

    /** A run that starts with accounts and chains to contacts. */
    public AskReminderBatch() {
        this(ACCOUNTS, System.today(), 0, 0);
    }

    @TestVisible
    private AskReminderBatch(String scopeObject, Date today, Integer created, Integer failed) {
        this.scopeObject = scopeObject;
        this.today = today;
        this.created = created;
        this.failed = failed;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        Date earliest = AskReminderService.earliestDate(today);
        return ACCOUNTS.equals(scopeObject)
            ? AskReminderSelector.accountLocator(earliest, today)
            : AskReminderSelector.contactLocator(earliest, today);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        try {
            AskReminderService.Outcome outcome = AskReminderService.remindChunk(scope, today);
            created += outcome.created;
            failed += outcome.failed;
        } catch (Exception chunkFailure) {
            // One bad chunk must not stop the rest of the org being reminded.
            failed += scope.size();
            ErrorLogger.log(chunkFailure, 'AskReminderBatch.' + scopeObject);
        }
    }

    public void finish(Database.BatchableContext context) {
        try {
            if (ACCOUNTS.equals(scopeObject)) {
                if (!Test.isRunningTest()) {
                    Database.executeBatch(
                        new AskReminderBatch(CONTACTS, today, created, failed),
                        CHUNK_SIZE
                    );
                }
                return;
            }
            AskReminderService.recordRun(System.now(), created, failed);
        } catch (Exception finishFailure) {
            ErrorLogger.log(finishFailure, 'AskReminderBatch.finish');
        }
    }

    /** How many reminders this run created, for a test or a caller that wants to know. */
    public Integer remindersCreated() {
        return created;
    }
}
