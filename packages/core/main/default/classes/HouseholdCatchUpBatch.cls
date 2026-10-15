/**
 * The household catch-up (ADR-0124, feature switches): when household upkeep is turned on, gives
 * a household to every contact added while it was off, exactly as the Contact trigger would have
 * on insert (R-H1, R-H2). `FeatureSwitchService.turnOn` queues it once, the moment the feature
 * goes on.
 *
 * The membership mode is read per chunk, so the work follows the mode in force: in contact mode
 * `HouseholdService.ensureHouseholds` makes the households and this batch points each contact at
 * its own, then names it the household's Primary Contact; in junction mode
 * `HouseholdService.createHouseholdsForNewContacts` makes the household and the membership row.
 * Both honour the Create households automatically setting, and both skip a person who already
 * has a household, so a run that overlaps ordinary saves creates no second one. The selection is
 * `HouseholdOrphanSelector`'s, so an erased person is never given a household.
 *
 * A household whose contact could not be pointed at it (a validation rule, or a preferred email
 * whose address is empty) is removed again, so the catch-up leaves no empty household behind;
 * the refusal is in the Error Log. People stored as accounts are not caught up here.
 */
public with sharing class HouseholdCatchUpBatch implements Database.Batchable<SObject> {
    /** Contacts per chunk: one household insert, one contact update and their upkeep. */
    public static final Integer CHUNK_SIZE = 100;

    private static final String LOG_CONTEXT = 'HouseholdCatchUpBatch';

    /** Test seam: a chunk large enough for a bulk test to run in the one chunk tests allow. */
    @TestVisible
    private static Integer chunkSize = CHUNK_SIZE;

    /** Queues the catch-up. Never throws: turning the feature on must not fail because of it. */
    public static Id enqueue() {
        try {
            return Database.executeBatch(new HouseholdCatchUpBatch(), chunkSize);
        } catch (Exception e) {
            ErrorLogger.log(e, LOG_CONTEXT);
            return null;
        }
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        if (!runs()) {
            return Database.getQueryLocator(
                [SELECT Id FROM Contact WHERE Id = NULL WITH SYSTEM_MODE]
            );
        }
        if (HouseholdService.isJunctionMode()) {
            // A contact linked straight to a household is in it by the simple link, and a
            // person account's own contact is the account's to settle (R-M4).
            Set<Id> excluded = new Set<Id>(OrgShapeDetector.personRecordTypeIds());
            Id householdType = HouseholdService.householdRecordTypeId();
            if (householdType != null) {
                excluded.add(householdType);
            }
            return HouseholdOrphanSelector.contactsWithoutMembershipLocator(excluded);
        }
        return HouseholdOrphanSelector.contactsWithoutAccountLocator();
    }

    public void execute(Database.BatchableContext context, List<Contact> scope) {
        if (!runs()) {
            return;
        }
        try {
            if (HouseholdService.isJunctionMode()) {
                HouseholdService.createHouseholdsForNewContacts(scope);
            } else {
                linkToNewHouseholds(scope);
            }
        } catch (Exception e) {
            ErrorLogger.log(e, LOG_CONTEXT);
        }
    }

    public void finish(Database.BatchableContext context) {
        // Nothing to record: each refusal was logged as it happened.
        return;
    }

    private static Boolean runs() {
        return FeatureSwitchService.isOn(FeatureSwitchService.HOUSEHOLD_UPKEEP) &&
            HouseholdService.automaticCreationEnabled();
    }

    /**
     * Contact mode: `ensureHouseholds` creates the households and sets each contact's
     * `AccountId` in memory, as it does before insert; the contacts are then saved with it.
     */
    private static void linkToNewHouseholds(List<Contact> scope) {
        HouseholdService.ensureHouseholds(scope);
        List<Contact> links = new List<Contact>();
        for (Contact person : scope) {
            if (person.AccountId != null) {
                links.add(new Contact(Id = person.Id, AccountId = person.AccountId));
            }
        }
        List<Database.SaveResult> saves = HouseholdWriter.linkContactsToHouseholds(links);
        List<Contact> linked = new List<Contact>();
        List<Account> unused = new List<Account>();
        for (Integer i = 0; i < saves.size(); i++) {
            if (saves[i].isSuccess()) {
                linked.add(links[i]);
            } else {
                unused.add(new Account(Id = links[i].AccountId));
            }
        }
        HouseholdService.seedPrimaryContactsOfNewHouseholds(linked);
        HouseholdWriter.deleteHouseholds(unused);
    }
}
