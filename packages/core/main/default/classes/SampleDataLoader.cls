/**
 * Loads and removes the C-10 sample data set: 200 households, 440 contacts, 25
 * organizations, 60 connections between people and 80 affiliations, read from the
 * SampleData static resource, plus whatever a module sample set adds to it (the Giving
 * gifts, appeals, funds, pledges and tributes). See data/sample/README.md for the JSON
 * format and docs/admin-guide/sample-data.md for the admin-facing behavior.
 *
 * The set loads in either membership mode. People are joined to their households through
 * HouseholdService, which knows what joining means in the mode the org is in, so this
 * feature never writes a membership row itself. The people are contacts either way,
 * because Core cannot create person accounts.
 *
 * load() is idempotent: it throws SampleDataException when sample data is already
 * present, and refuses to start while a load is still running. Because a synchronous
 * transaction cannot safely insert every household, organization, and contact (the
 * household naming and greeting triggers run on every contact insert), load() only
 * starts the stage batch (SampleDataStageBatch over SampleDataLoadStages) and returns
 * immediately; call status() to track progress.
 * remove() runs synchronously; a few hundred deletes are well within limits for one
 * transaction, and it too refuses while a load is running so the chain cannot insert
 * contacts against households that have just been deleted.
 *
 * Errors are thrown, not logged here: SampleDataController logs once at the LWC
 * boundary, and the queueables log their own async failures.
 */
public with sharing class SampleDataLoader {
    /** Contacts inserted per contact stage (see SampleDataLoadStages). */
    public static final Integer CONTACT_CHUNK_SIZE = 100;

    /** Injected by the tests in place of the static resource body. */
    @TestVisible
    private static String jsonOverride;

    /**
     * Injected by the tests in place of the AsyncApexJob query, so the refusal paths can
     * be asserted without an org that can hold a queued job. Null in production.
     */
    @TestVisible
    private static Boolean runningJobOverride;

    /** One module sample set's own number, as the status card shows it. */
    public class ModuleCount {
        /** The module's stable name, for example 'Giving'. */
        @AuraEnabled
        public String name;
        /** The module's own wording for what the number counts, for example 'Gifts'. */
        @AuraEnabled
        public String label;
        @AuraEnabled
        public Integer recordCount;
    }

    public class Counts {
        @AuraEnabled
        public Integer householdCount;
        @AuraEnabled
        public Integer organizationCount;
        @AuraEnabled
        public Integer contactCount;
        @AuraEnabled
        public Integer relationshipCount;
        @AuraEnabled
        public Integer affiliationCount;
        /**
         * One entry per installed module sample set, empty in an org that has only Core.
         * The card renders whatever is here, so a module shipping its own sample data does
         * not need a change in this component (C-10, ADR-0017).
         */
        @AuraEnabled
        public List<ModuleCount> moduleCounts = new List<ModuleCount>();
        @AuraEnabled
        public Boolean loaded;
        @AuraEnabled
        public Boolean loading;
        /**
         * True when this org keeps household membership in household member records. The
         * load works either way; the card uses this to say how the sample people will be
         * joined to their households, and that they arrive as contacts.
         */
        @AuraEnabled
        public Boolean junctionMembership;
    }

    /**
     * Starts loading the sample data set. Throws SampleDataException when a load is
     * already running, when sample data is already present, or when the static resource is
     * missing or does not hold a usable payload.
     *
     * Both membership modes are loaded: the load stage asks HouseholdService to join each
     * person to their household, so in contact mode the join is the contact's household
     * field and in junction mode it is a household member record. Membership mode is
     * therefore not a reason to refuse.
     *
     * The sample people are contacts in either mode. Core cannot create person accounts
     * (plan Section 4, ADR-0013), so an org that stores its own people as accounts gets a
     * sample set of contacts in household member records rather than one of person
     * accounts. That is a difference the admin guide states, not a refusal: the households,
     * the names, the greetings, the counts and the panels all behave as they will with the
     * org's own data.
     */
    public static void load() {
        if (hasRunningLoadJob()) {
            throw new SampleDataException(Label.Core_SampleData_LoadInProgress);
        }
        SampleDataSelector selector = new SampleDataSelector();
        if (selector.countSampleHouseholds() > 0 || selector.countSampleOrganizations() > 0) {
            throw new SampleDataException(Label.Core_SampleData_AlreadyLoaded);
        }
        // Parsed here so a malformed payload fails in front of the admin, with a readable
        // message, instead of inside a batch the card can only report as "not loaded".
        SampleDataSet.parse(getSampleDataJson());
        SampleDataStageBatch.start(new SampleDataLoadStages());
    }

    /**
     * Whether the load may run past its first stage. An Apex test may run only one execute
     * of a batch, so there the stage batch runs the first stage alone, and each stage and
     * hand-off is tested by calling it directly. Everywhere else every stage runs.
     */
    public static Boolean mayQueueNextStage() {
        return !Test.isRunningTest();
    }

    /**
     * Deletes every record flagged Sample_Data__c, and returns the counts that were
     * removed: each installed module's own records first (a gift points at a person and a
     * household), then connections and affiliations, then contacts, then the accounts, so
     * nothing is ever left pointing at a record that has just gone.
     *
     * Everything the loader creates is either flagged itself or a detail of something that
     * is, which is what keeps this to "delete only what the loader created". Records an
     * administrator entered have the box clear and are never in these lists.
     *
     * In junction mode the membership rows the load created go with the households: the
     * Household field on a household member record is a required lookup that cascades, so
     * deleting a household flagged Sample_Data__c takes its own membership rows with it.
     * The account ids are read after the contacts are gone, so a household that upkeep has
     * already tidied away is not asked for a second time.
     */
    public static Counts remove() {
        if (hasRunningLoadJob()) {
            throw new SampleDataException(Label.Core_SampleData_LoadInProgress);
        }
        SampleDataSelector selector = new SampleDataSelector();
        Counts result = new Counts();
        result.contactCount = selector.countSampleContacts();
        result.householdCount = selector.countSampleHouseholds();
        result.organizationCount = selector.countSampleOrganizations();
        result.relationshipCount = selector.countSampleRelationships();
        result.affiliationCount = selector.countSampleAffiliations();
        result.moduleCounts = SampleDataModules.counts();

        // Modules first: a gift points at a household and a person, and a lookup that is
        // cleared by a deleted parent would leave the gift behind with nothing on it.
        SampleDataModules.removeAll();

        List<Id> relationshipIds = selector.getSampleRelationshipIds();
        if (!relationshipIds.isEmpty()) {
            Database.delete(relationshipIds, AccessLevel.USER_MODE);
        }
        List<Id> affiliationIds = selector.getSampleAffiliationIds();
        if (!affiliationIds.isEmpty()) {
            Database.delete(affiliationIds, AccessLevel.USER_MODE);
        }
        List<Id> contactIds = selector.getSampleContactIds();
        if (!contactIds.isEmpty()) {
            Database.delete(contactIds, AccessLevel.USER_MODE);
        }
        List<Id> accountIds = selector.getSampleAccountIds();
        if (!accountIds.isEmpty()) {
            Database.delete(accountIds, AccessLevel.USER_MODE);
        }

        result.loaded = false;
        result.loading = false;
        result.junctionMembership = HouseholdService.isJunctionMode();
        return result;
    }

    /**
     * Current counts of flagged records, and whether a load is still in progress. A user
     * who cannot read the Sample Data field gets zeros rather than an error, so the
     * read-only card still renders for them.
     */
    public static Counts status() {
        Counts result = new Counts();
        if (!canReadSampleDataFields()) {
            result.householdCount = 0;
            result.organizationCount = 0;
            result.contactCount = 0;
            result.relationshipCount = 0;
            result.affiliationCount = 0;
            result.loading = false;
            result.loaded = false;
            result.junctionMembership = HouseholdService.isJunctionMode();
            return result;
        }

        SampleDataSelector selector = new SampleDataSelector();
        result.householdCount = selector.countSampleHouseholds();
        result.organizationCount = selector.countSampleOrganizations();
        result.contactCount = selector.countSampleContacts();
        result.relationshipCount = selector.countSampleRelationships();
        result.affiliationCount = selector.countSampleAffiliations();
        result.moduleCounts = SampleDataModules.counts();
        result.loading = hasRunningLoadJob();
        result.loaded =
            !result.loading && (result.householdCount > 0 || result.organizationCount > 0);
        result.junctionMembership = HouseholdService.isJunctionMode();
        return result;
    }

    /** True while any stage of the sample data load chain is queued or running. */
    public static Boolean hasRunningLoadJob() {
        if (runningJobOverride != null) {
            return runningJobOverride;
        }
        return new SampleDataSelector().hasRunningLoadJob();
    }

    /** The sample data JSON body, from the injected override or the static resource. */
    public static String getSampleDataJson() {
        if (jsonOverride != null) {
            return jsonOverride;
        }
        StaticResource resource = new SampleDataSelector().getSampleDataResource();
        if (resource == null) {
            throw new SampleDataException(Label.Core_SampleData_ResourceMissing);
        }
        return resource.Body.toString();
    }

    private static Boolean canReadSampleDataFields() {
        return Schema.SObjectType.Account.fields.Sample_Data__c.isAccessible() &&
            Schema.SObjectType.Contact.fields.Sample_Data__c.isAccessible();
    }
}
