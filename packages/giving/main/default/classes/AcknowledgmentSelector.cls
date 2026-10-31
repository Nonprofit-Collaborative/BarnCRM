/**
 * Every query the acknowledgment feature makes on behalf of a person (feature G-12).
 *
 * All of it runs `WITH USER_MODE`, so what a screen shows and what a send picks up is what the
 * running user's sharing and field level security allow. The one exception is the settings read,
 * which is a hierarchy custom setting and carries no sharing of its own.
 */
public with sharing class AcknowledgmentSelector {
    /** The largest queue this class will read in one go, so a page load is bounded. */
    public static final Integer QUEUE_LIMIT = 2000;

    /** The active rules in the order they are considered: lowest Order first, then by name. */
    public static List<Acknowledgment_Rule__c> activeRules() {
        return [
            SELECT
                Id,
                Name,
                Active__c,
                Order__c,
                Channel__c,
                Email_Template__c,
                Minimum_Amount__c,
                Maximum_Amount__c,
                Gift_Type__c,
                Appeal__c,
                First_Gift_Only__c
            FROM Acknowledgment_Rule__c
            WHERE Active__c = TRUE
            WITH USER_MODE
            ORDER BY Order__c ASC NULLS LAST, Name ASC
            LIMIT 500
        ];
    }

    /** Every rule, active or not, for the page that lists them. */
    public static List<Acknowledgment_Rule__c> allRules() {
        return [
            SELECT
                Id,
                Name,
                Active__c,
                Order__c,
                Channel__c,
                Email_Template__c,
                Minimum_Amount__c,
                Maximum_Amount__c,
                Gift_Type__c,
                Appeal__c,
                Appeal__r.Name,
                First_Gift_Only__c
            FROM Acknowledgment_Rule__c
            WITH USER_MODE
            ORDER BY Order__c ASC NULLS LAST, Name ASC
            LIMIT 500
        ];
    }

    /**
     * The gifts waiting to be thanked for: everything the queue could send, with the donor fields
     * a message and a merge row need.
     *
     * The filter is the whole of R-AK8. A gift that is not Received, or whose amount is not
     * positive, is not here, so no caller has to remember to exclude a refund.
     */
    public static List<Gift__c> queuedGifts(Integer maximum) {
        Integer cap = maximum == null || maximum > QUEUE_LIMIT ? QUEUE_LIMIT : maximum;
        return [
            SELECT
                Id,
                Name,
                Amount__c,
                Gift_Date__c,
                Type__c,
                Status__c,
                Appeal__c,
                Appeal__r.Name,
                Acknowledgment_Status__c,
                Donor_Contact__c,
                Donor_Contact__r.Name,
                Donor_Contact__r.FirstName,
                Donor_Contact__r.Email,
                Donor_Contact__r.MailingStreet,
                Donor_Contact__r.MailingCity,
                Donor_Contact__r.MailingState,
                Donor_Contact__r.MailingPostalCode,
                Donor_Contact__r.MailingCountry,
                Donor_Account__c,
                Donor_Account__r.Name,
                Donor_Account__r.Primary_Contact__c,
                Donor_Account__r.Household_Informal_Greeting__c,
                Donor_Account__r.BillingStreet,
                Donor_Account__r.BillingCity,
                Donor_Account__r.BillingState,
                Donor_Account__r.BillingPostalCode,
                Donor_Account__r.BillingCountry,
                Household__c,
                Household__r.Household_Informal_Greeting__c
            FROM Gift__c
            WHERE
                Acknowledgment_Status__c = :AcknowledgmentRuleService.STATUS_TO_ACKNOWLEDGE
                AND Status__c = 'Received'
                AND Amount__c > 0
                AND Id NOT IN (SELECT Gift__c FROM Acknowledgment__c WHERE Gift_Key__c != NULL)
            WITH USER_MODE
            ORDER BY Gift_Date__c ASC NULLS LAST, Id ASC
            LIMIT :cap
        ];
    }

    /**
     * The same queue as a query locator, for the batch. It selects the same fields as
     * `queuedGifts` and applies the same filter, because a batch that picked up a different set
     * from the one the page counted would be the defect nobody could reproduce.
     */
    public static Database.QueryLocator queuedGiftsLocator() {
        return Database.getQueryLocator(
            [
                SELECT
                    Id,
                    Name,
                    Amount__c,
                    Gift_Date__c,
                    Type__c,
                    Status__c,
                    Appeal__c,
                    Acknowledgment_Status__c,
                    Donor_Contact__c,
                    Donor_Contact__r.Email,
                    Donor_Account__c,
                    Donor_Account__r.Primary_Contact__c,
                    Household__c
                FROM Gift__c
                WHERE
                    Acknowledgment_Status__c = :AcknowledgmentRuleService.STATUS_TO_ACKNOWLEDGE
                    AND Status__c = 'Received'
                    AND Amount__c > 0
                    AND Id NOT IN (
                        SELECT Gift__c
                        FROM Acknowledgment__c
                        WHERE Gift_Key__c != NULL
                    )
                WITH USER_MODE
                ORDER BY Gift_Date__c ASC NULLS LAST, Id ASC
            ]
        );
    }

    /** The contacts a message can be addressed to, by contact id. */
    public static Map<Id, Contact> contactsById(Set<Id> contactIds) {
        if (contactIds == null || contactIds.isEmpty()) {
            return new Map<Id, Contact>();
        }
        return new Map<Id, Contact>(
            [
                SELECT Id, Name, FirstName, Email
                FROM Contact
                WHERE Id IN :contactIds
                WITH USER_MODE
            ]
        );
    }

    /**
     * Which of these contacts have Email Opt Out set (R-AK13, ADR-0144).
     *
     * Read in system mode and returned as Ids only: whether a donor is emailed must not depend on
     * whether the person pressing Send has field access to Email Opt Out, and nothing read here is
     * shown to them. The Ids come from gifts the caller already read in user mode.
     */
    public static Set<Id> optedOutOfEmail(Set<Id> contactIds) {
        Set<Id> optedOut = new Set<Id>();
        if (contactIds == null || contactIds.isEmpty()) {
            return optedOut;
        }
        for (Contact person : [
            SELECT Id
            FROM Contact
            WHERE Id IN :contactIds AND HasOptedOutOfEmail = TRUE
            WITH SYSTEM_MODE
        ]) {
            optedOut.add(person.Id);
        }
        return optedOut;
    }

    /** The acknowledgments a run produced, whatever their status. */
    public static List<Acknowledgment__c> forRun(Id runId) {
        return [
            SELECT Id, Gift__c, Channel__c, Status__c, Gift_Key__c
            FROM Acknowledgment__c
            WHERE Run__c = :runId
            WITH USER_MODE
            LIMIT 10000
        ];
    }

    /** The standing acknowledgments for these gifts: the rows holding the claim key (R-AK7). */
    public static List<Acknowledgment__c> claimsFor(Set<Id> giftIds) {
        List<String> keys = new List<String>();
        for (Id giftId : giftIds) {
            keys.add(String.valueOf(giftId));
        }
        return [
            SELECT Id, Gift__c, Gift_Key__c, Status__c
            FROM Acknowledgment__c
            WHERE Gift_Key__c IN :keys
            WITH USER_MODE
            LIMIT 10000
        ];
    }

    /** The most recent runs, for the page. */
    public static List<Acknowledgment_Run__c> recentRuns(Integer howMany) {
        Integer cap = howMany == null || howMany < 1 ? 5 : howMany;
        return [
            SELECT
                Id,
                Name,
                Channel__c,
                Status__c,
                Started__c,
                Finished__c,
                Gifts_Processed__c,
                Acknowledgments_Sent__c,
                Errors__c,
                Merge_File_Document_Id__c
            FROM Acknowledgment_Run__c
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :cap
        ];
    }

    /** One run. */
    public static Acknowledgment_Run__c runById(Id runId) {
        List<Acknowledgment_Run__c> runs = [
            SELECT
                Id,
                Name,
                Channel__c,
                Status__c,
                Started__c,
                Finished__c,
                Gifts_Processed__c,
                Acknowledgments_Sent__c,
                Errors__c,
                Merge_File_Document_Id__c
            FROM Acknowledgment_Run__c
            WHERE Id = :runId
            WITH USER_MODE
            LIMIT 1
        ];
        return runs.isEmpty() ? null : runs[0];
    }

    /**
     * The email templates this org has, so the page can show a rule's template by its label and
     * an administrator can copy the developer name a rule wants.
     *
     * A rule names a template by developer name because no custom lookup to a template is
     * possible (ADR-0032), which makes this list the only way to see the two names together.
     */
    public static List<EmailTemplate> activeTemplates() {
        return [
            SELECT Id, Name, DeveloperName
            FROM EmailTemplate
            WHERE IsActive = TRUE
            WITH USER_MODE
            ORDER BY Name ASC
            LIMIT 200
        ];
    }
}
