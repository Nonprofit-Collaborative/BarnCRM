/**
 * Sync all appeals (feature X-02, R-CS6): runs the Campaign sync copy over every appeal the
 * person who started it can see, as that person, in chunks.
 *
 * Two passes. The first copies every appeal, oldest first, so a parent usually has its Campaign
 * before its children are copied. The second copies again only the linked child appeals, which
 * puts a child under a parent whose Campaign was made later in the first pass. A copy that
 * finds nothing changed writes nothing, so the second pass costs one read per chunk.
 *
 * What was done is written to the Error Log at Info when the run ends, and every appeal that
 * could not be copied has its own Warning there already.
 */
public with sharing class CampaignSyncBatch implements Database.Batchable<SObject>, Database.Stateful {
    public static final String CLASS_NAME = 'CampaignSyncBatch';
    @TestVisible
    private static final Integer CHUNK_SIZE = 200;
    private static final String LOG_CONTEXT = 'Campaign sync: Sync all appeals';
    // Core's constant for this severity is not namespace accessible, so its value is repeated.
    private static final String SEVERITY_INFO = 'Info';

    /** Off in tests, where only one batch may run: the second pass is started by hand there. */
    @TestVisible
    private static Boolean chainSecondPass = true;

    private final Boolean childrenOnly;
    private final CampaignSyncService.Result totals = new CampaignSyncService.Result();

    public CampaignSyncBatch() {
        this(false);
    }

    @TestVisible
    private CampaignSyncBatch(Boolean childrenOnly) {
        this.childrenOnly = childrenOnly == true;
    }

    /** Starts the first pass and returns its job id. */
    public static Id start() {
        return Database.executeBatch(new CampaignSyncBatch(), CHUNK_SIZE);
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator(
            CampaignSyncSelector.allAppealsQuery(childrenOnly),
            AccessLevel.USER_MODE
        );
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        totals.add(CampaignSyncService.syncSaved((List<Appeal__c>) scope));
    }

    public void finish(Database.BatchableContext context) {
        if (!childrenOnly && chainSecondPass) {
            Database.executeBatch(new CampaignSyncBatch(true), CHUNK_SIZE);
        }
        ErrorLogger.logMessage(
            String.format(
                Label.Mirror_CampaignSync_LogRunSummary,
                new List<Object>{
                    childrenOnly ? 2 : 1,
                    totals.created,
                    totals.updated,
                    totals.unchanged,
                    totals.failed
                }
            ),
            LOG_CONTEXT,
            SEVERITY_INFO
        );
    }
}
