/**
 * The household catch-up (ADR-0124, feature switches): when household upkeep is turned on, gives
 * a household to every person added while it was off, exactly as the triggers would have on
 * insert (R-H1, R-H2). `FeatureSwitchService.turnOn` queues it once, the moment the feature
 * goes on.
 *
 * It runs as two jobs over two objects, because one batch reads one object. The contact job
 * always runs. The person account job is queued only in an org that stores people as accounts,
 * so an org without them queues exactly the one job it always did (ADR-0013); the two jobs
 * never touch the same person, because the contact job leaves out the contact behind a person
 * account (R-M4).
 *
 * The membership mode is read per chunk, so the work follows the mode in force: in contact mode
 * `HouseholdService.ensureHouseholds` makes the households and this batch points each contact at
 * its own, then names it the household's Primary Contact; in junction mode
 * `HouseholdService.createHouseholdsForNewContacts` makes the household and the membership row.
 * A person stored as an account is given a household and a membership row in junction mode, by
 * `HouseholdService.catchUpPersonAccounts`, the creation pass a new person account goes through
 * (`AccountTriggerHandler`); in contact mode a person account is given nothing, as on insert.
 * Every path honours the Create households automatically setting, and skips a person who
 * already has a household, so a run that overlaps ordinary saves creates no second one. The
 * selection is `HouseholdOrphanSelector`'s, so an erased person is never given a household.
 *
 * A household whose contact could not be pointed at it (a validation rule, or a preferred email
 * whose address is empty) is removed again, so the catch-up leaves no empty household behind;
 * the refusal is in the Error Log.
 */
public with sharing class HouseholdCatchUpBatch implements Database.Batchable<SObject> {
    /** People per chunk: one household insert, one contact or membership write and their upkeep. */
    public static final Integer CHUNK_SIZE = 100;

    private static final String LOG_CONTEXT = 'HouseholdCatchUpBatch';

    /** Test seam: a chunk large enough for a bulk test to run in the one chunk tests allow. */
    @TestVisible
    private static Integer chunkSize = CHUNK_SIZE;

    /** True for the job over people stored as accounts, false for the job over contacts. */
    private final Boolean personAccounts;

    public HouseholdCatchUpBatch() {
        this(false);
    }

    @TestVisible
    private HouseholdCatchUpBatch(Boolean personAccounts) {
        this.personAccounts = personAccounts == true;
    }

    /**
     * Queues the catch-up: the contact job, and the person account job where the org stores
     * people as accounts. Never throws: turning the feature on must not fail because of it.
     * Answers the contact job's id.
     */
    public static Id enqueue() {
        Id contactJob = enqueue(false);
        try {
            if (HouseholdService.isPersonAccountOrg()) {
                enqueue(true);
            }
        } catch (Exception e) {
            ErrorLogger.log(e, LOG_CONTEXT);
        }
        return contactJob;
    }

    private static Id enqueue(Boolean personAccounts) {
        try {
            return Database.executeBatch(new HouseholdCatchUpBatch(personAccounts), chunkSize);
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
        if (personAccounts) {
            return HouseholdOrphanSelector.personAccountsWithoutMembershipLocator(
                OrgShapeDetector.personRecordTypeIds()
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

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        if (!runs()) {
            return;
        }
        try {
            if (personAccounts) {
                HouseholdService.catchUpPersonAccounts(new Map<Id, SObject>(scope).keySet());
            } else if (HouseholdService.isJunctionMode()) {
                HouseholdService.createHouseholdsForNewContacts((List<Contact>) scope);
            } else {
                linkToNewHouseholds((List<Contact>) scope);
            }
        } catch (Exception e) {
            ErrorLogger.log(e, LOG_CONTEXT);
        }
    }

    public void finish(Database.BatchableContext context) {
        // Nothing to record: each refusal was logged as it happened.
        return;
    }

    /**
     * Whether this job has anything to do now. The person account job also needs junction
     * mode and an org that stores people as accounts, as the Account trigger does.
     */
    private Boolean runs() {
        Boolean upkeepOn =
            FeatureSwitchService.isOn(FeatureSwitchService.HOUSEHOLD_UPKEEP) &&
            HouseholdService.automaticCreationEnabled();
        if (!upkeepOn || !personAccounts) {
            return upkeepOn;
        }
        return HouseholdService.isPersonAccountOrg() && HouseholdService.isJunctionMode();
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
