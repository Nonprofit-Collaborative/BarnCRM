/**
 * Re-places every donor on the ladder: the nightly pass, and the Recalculate now button on the
 * Donor Levels page, which are the same job (R-DL6).
 *
 * A save announces a changed giving total, so real time assignment covers almost everything. Two
 * things announce nothing and are the whole reason this batch exists: a fiscal year turning over,
 * which changes what "giving this year" means without touching a single record, and a ladder an
 * administrator edited yesterday, which changes what every total earns.
 *
 * It runs over accounts first and chains to contacts, so one run covers households, organizations,
 * people held as accounts, and people held as contacts. Only the records that actually move are
 * written, so a normal night reads broadly and writes very little.
 */
public with sharing class DonorLevelBatch implements Database.Batchable<SObject>, Database.Stateful {
    @TestVisible
    private static final String ACCOUNTS = 'Account';
    @TestVisible
    private static final String CONTACTS = 'Contact';
    /** The settings console section the Donor Levels page is in. */
    private static final String GIVING_SECTION = 'Giving';

    private final String scopeObject;
    private Integer moved = 0;
    /** Who pressed Recalculate now, told when the run ends; null for the nightly run (Q-04). */
    private Id notifyUserId;

    /** A run that starts with accounts and chains to contacts. */
    public DonorLevelBatch() {
        this(ACCOUNTS, JobNotifier.starter(), 0);
    }

    @TestVisible
    private DonorLevelBatch(String scopeObject) {
        this(scopeObject, JobNotifier.starter(), 0);
    }

    /** A pass that carries who to tell and what the passes before it moved. */
    private DonorLevelBatch(String scopeObject, Id notifyUserId, Integer moved) {
        this.scopeObject = scopeObject;
        this.notifyUserId = notifyUserId;
        this.moved = moved;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        return ACCOUNTS.equals(scopeObject)
            ? DonorLevelSelector.accountLocator()
            : DonorLevelSelector.contactLocator();
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        try {
            DonorLevelService.clearCache();
            List<SObject> changed = DonorLevelService.assignAll(scope);
            DonorLevelWriter.save(changed);
            moved += changed.size();
        } catch (Exception chunkFailure) {
            // One bad chunk must not stop the rest of the org being re-placed.
            ErrorLogger.log(chunkFailure, 'DonorLevelBatch.' + scopeObject);
        }
    }

    public void finish(Database.BatchableContext context) {
        try {
            if (ACCOUNTS.equals(scopeObject)) {
                if (!Test.isRunningTest()) {
                    Database.executeBatch(new DonorLevelBatch(CONTACTS, notifyUserId, moved), 200);
                }
                return;
            }
            DonorLevelService.recordRecalculation(System.now());
        } catch (Exception finishFailure) {
            ErrorLogger.log(finishFailure, 'DonorLevelBatch.finish');
        }
        // The contacts pass is the end of the run, so the one notification goes from there.
        JobNotifier.aboutSettings(
            notifyUserId,
            Label.Giving_JobNotice_DonorLevels,
            false,
            String.format(
                Label.Giving_JobNotice_DonorLevelsBody,
                new List<Object>{ moved.format() }
            ),
            GIVING_SECTION
        );
    }
}
