/**
 * The nightly seasonal address swap (C-18, R-AD4).
 *
 * A batch rather than one query and one save because the work scales with the org and because
 * every swap sets off the address automation, which writes the household's standard address
 * fields and every member's mailing address. A thousand snowbird households on one January
 * night is far more DML than one transaction may do.
 *
 * The chunk is small for the same reason. Each owner costs its own DML statement, on purpose:
 * a swap is a pair of writes and half of one leaves a household with no address in use at all
 * (see `SeasonalAddressWriter.save`). Fifteen owners is fifteen of those plus the automation's
 * own reads and writes, which stays inside the per-transaction limits with room to spare, and
 * still finishes an org of ten thousand seasonal addresses in a few minutes.
 *
 * Stateful because the counts are the point: they are the sentence the Hub shows afterwards.
 */
public with sharing class SeasonalAddressBatch implements Database.Batchable<SObject>, Database.Stateful {
    /** Owners per chunk. Each one costs a DML of its own plus the address automation's writes. */
    public static final Integer CHUNK_SIZE = 15;

    private static final String LOG_CONTEXT = 'Seasonal address swap';

    /** Carried across chunks so the finish method can record one run rather than many. */
    @TestVisible
    private SeasonalAddressService.RunSummary summary = new SeasonalAddressService.RunSummary();

    /**
     * The day the run is for. Held rather than read per chunk so a run that starts before
     * midnight and finishes after it swaps every owner onto the same day, instead of moving
     * half the org on one date and half on the next.
     */
    private Date runDate;

    /** Who pressed Run now, told when the swap ends; null for the nightly run (Q-04). */
    private Id notifyUserId = JobNotifier.starter();

    public SeasonalAddressBatch() {
        this(Date.today());
    }

    /** The same run against a named day, which is how the tests reach the boundary dates. */
    public SeasonalAddressBatch(Date runDate) {
        this.runDate = runDate == null ? Date.today() : runDate;
    }

    /** No work while the Addresses feature is off (ADR-0124): the locator then finds nothing. */
    public Database.QueryLocator start(Database.BatchableContext context) {
        if (!addressesOn()) {
            return Database.getQueryLocator(
                [SELECT Id FROM Address__c WHERE Id = NULL WITH SYSTEM_MODE]
            );
        }
        return new SeasonalAddressSelector().seasonalLocator();
    }

    private static Boolean addressesOn() {
        return FeatureSwitchService.isOn(FeatureSwitchService.ADDRESSES);
    }

    public void execute(Database.BatchableContext context, List<Address__c> scope) {
        if (!addressesOn()) {
            return;
        }
        try {
            Set<Id> ownerIds = new Set<Id>();
            for (Address__c address : scope) {
                Id ownerId = AddressService.ownerIdOf(address);
                if (ownerId != null) {
                    ownerIds.add(ownerId);
                }
            }
            this.summary.add(SeasonalAddressService.swapOwners(ownerIds, this.runDate));
        } catch (Exception chunkFailure) {
            // A chunk that cannot even be read must not stop the org's remaining chunks, and
            // must not disappear either: the run's own summary counts owner-level failures, and
            // this is the level above that.
            ErrorLogger.log(chunkFailure, LOG_CONTEXT);
        }
    }

    /**
     * Records the run whatever happened in it, including a run that swapped nothing. "The job
     * ran and had nothing to do" and "the job did not run" are different facts and an
     * administrator needs to be able to tell them apart (R-AD8).
     */
    public void finish(Database.BatchableContext context) {
        SeasonalAddressService.recordRun(this.summary, System.now());
        JobNotifier.aboutSettings(
            this.notifyUserId,
            System.Label.Core_JobNotice_SeasonalAddress,
            false,
            this.summary.text(),
            JobNotifier.SECTION_ADDRESSES
        );
    }

    /** What this run came to, for a caller or a test that wants the counts rather than the text. */
    public SeasonalAddressService.RunSummary runSummary() {
        return this.summary;
    }
}
