/**
 * Test data for the Giving package's own objects. Core's TestDataFactory builds households,
 * contacts and organizations; this builds the giving records on top of them, so a test reads
 * as a story about David and Maria rather than as a pile of field assignments.
 */
@IsTest
@NamespaceAccessible
public class GivingTestDataFactory {
    /**
     * A fund. Pass isDefault true for the one that undesignated gifts should go to.
     */
    public static Fund__c buildFund(String name, Boolean isDefault) {
        return new Fund__c(
            Name = name,
            Active__c = true,
            Restricted__c = false,
            Is_Default__c = isDefault
        );
    }

    /**
     * An inserted default fund named "General", which is what most organizations call it and
     * what the admin guide walks David through creating.
     */
    public static Fund__c insertDefaultFund() {
        Fund__c fund = buildFund('General', true);
        insert fund;
        return fund;
    }

    /**
     * Cancels the Giving jobs the org already has scheduled (the three nightly jobs and the
     * acknowledgment send). Scheduled jobs are visible to tests, so a test that counts them or
     * expects none starts by clearing the ones an administrator switched on.
     */
    @NamespaceAccessible
    public static void clearOrgGivingJobs() {
        for (CronTrigger job : [
            SELECT Id
            FROM CronTrigger
            WHERE
                CronJobDetail.Name LIKE 'BarnCRM Giving%'
                OR CronJobDetail.Name = :AcknowledgmentScheduler.JOB_NAME
            WITH SYSTEM_MODE
        ]) {
            System.abortJob(job.Id);
        }
        ScheduledJobSelector.forget();
    }

    /**
     * The default fund, inserted only if the org has no active default fund yet. A gift saves
     * only when there is a default fund to allocate it to, so any test that inserts gifts
     * without choosing funds itself calls this first.
     */
    @NamespaceAccessible
    public static Fund__c ensureDefaultFund() {
        List<Fund__c> existing = [
            SELECT Id, Name, Active__c, Is_Default__c
            FROM Fund__c
            WHERE Is_Default__c = TRUE AND Active__c = TRUE
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return existing.isEmpty() ? insertDefaultFund() : existing[0];
    }

    /**
     * An appeal, active, with no goal unless the test sets one.
     */
    @NamespaceAccessible
    public static Appeal__c buildAppeal(String name) {
        return new Appeal__c(Name = name, Active__c = true, Start_Date__c = Date.today());
    }

    /**
     * A gift from a contact, ready to insert.
     */
    @NamespaceAccessible
    public static Gift__c buildGift(Id donorContactId, Decimal amount) {
        return new Gift__c(
            Donor_Contact__c = donorContactId,
            Amount__c = amount,
            Type__c = 'Check',
            Status__c = 'Received',
            Acknowledgment_Status__c = 'To acknowledge'
        );
    }

    /**
     * A gift from an account: an organization, a household giving in its own name, or a person
     * held as an account.
     */
    @NamespaceAccessible
    public static Gift__c buildAccountGift(Id donorAccountId, Decimal amount) {
        return new Gift__c(
            Donor_Account__c = donorAccountId,
            Amount__c = amount,
            Type__c = 'Check',
            Status__c = 'Received',
            Acknowledgment_Status__c = 'To acknowledge'
        );
    }

    /**
     * Many gifts from one donor, for the bulk tests that prove one save of two hundred records
     * stays inside the platform's limits (plan Section 7.2).
     */
    @NamespaceAccessible
    public static List<Gift__c> buildGifts(Id donorContactId, Integer howMany, Decimal amount) {
        List<Gift__c> gifts = new List<Gift__c>();
        for (Integer i = 0; i < howMany; i++) {
            gifts.add(buildGift(donorContactId, amount));
        }
        return gifts;
    }

    /**
     * Closes the books through a date, as Maria does on the Accounting Periods page (G-20), and
     * clears the lock's once per transaction answer about the override, so the next save asks.
     */
    public static void closeBooksThrough(Date lastClosedDay) {
        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        if (settings.Id == null) {
            settings.SetupOwnerId = UserInfo.getOrganizationId();
        }
        settings.Books_Closed_Through__c = lastClosedDay;
        upsert settings;
        GiftPostingLock.overrideHeld = null;
    }

    /**
     * An allocation of part of a gift to a fund.
     */
    public static Gift_Allocation__c buildAllocation(Id giftId, Id fundId, Decimal amount) {
        return new Gift_Allocation__c(Gift__c = giftId, Fund__c = fundId, Amount__c = amount);
    }

    /**
     * A household account and a contact in it, named for the persona a test is about. Returns
     * the contact, whose AccountId is the household.
     */
    @NamespaceAccessible
    public static Contact insertHouseholdContact(
        String householdName,
        String firstName,
        String lastName
    ) {
        // The record type is set rather than left to the running user's default, because the
        // household on a gift is derived only from an account of the Household record type.
        Account household = new Account(
            Name = householdName,
            RecordTypeId = HouseholdService.householdRecordTypeId()
        );
        insert household;
        Contact person = new Contact(
            FirstName = firstName,
            LastName = lastName,
            AccountId = household.Id
        );
        insert person;
        return person;
    }

    /**
     * An organization account, for the donor path where no household is derived.
     */
    @NamespaceAccessible
    public static Account insertOrganization(String name) {
        Account organization = new Account(Name = name);
        insert organization;
        return organization;
    }

    /**
     * Fails with what the org can say about a rollup run when a total the engine should have
     * written is still blank. A bulk or background save leaves the totals to a queued job whose
     * errors are caught by its own finalizer, so a blank total otherwise arrives with no cause
     * attached. Nothing is
     * asserted about a value that was written: the caller's own assertions do that.
     */
    public static void assertRollupWrote(Object total) {
        if (total != null) {
            return;
        }
        List<String> facts = new List<String>();
        for (AsyncApexJob job : [
            SELECT ApexClass.Name, JobType, Status, ExtendedStatus, NumberOfErrors
            FROM AsyncApexJob
            ORDER BY CreatedDate
            LIMIT 20
        ]) {
            facts.add(
                job.ApexClass?.Name +
                    ' ' +
                    job.JobType +
                    ' ' +
                    job.Status +
                    ' errors ' +
                    job.NumberOfErrors +
                    ' ' +
                    job.ExtendedStatus
            );
        }
        for (Error_Log__c entry : [
            SELECT Context__c, Message__c, Technical_Detail__c
            FROM Error_Log__c
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
            LIMIT 20
        ]) {
            facts.add(entry.Context__c + ': ' + entry.Technical_Detail__c);
        }
        Assert.fail(
            'The rollup engine wrote nothing to the total. Jobs and Error Log: ' +
            String.join(facts, ' | ')
        );
    }
}
