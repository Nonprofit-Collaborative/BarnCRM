/**
 * All SOQL for the Giving sample data set (C-10). No other class in this feature issues a
 * query directly (plan Section 9.3).
 *
 * The sample people and households are Core's records, found by the key Core's loader wrote
 * to `Sample_Data_Key__c`. Four hundred and forty people and two hundred and twenty five
 * accounts are read once per chunk, which is a fraction of the query row limit and cheaper
 * than carrying a map of that size from one queued job to the next.
 */
public with sharing class GivingSampleDataSelector {
    /**
     * The GivingSampleData static resource, or null when it has not been deployed.
     */
    public StaticResource getSampleDataResource() {
        List<StaticResource> resources = [
            SELECT Body
            FROM StaticResource
            WHERE Name = 'GivingSampleData'
            WITH USER_MODE
            LIMIT 1
        ];
        return resources.isEmpty() ? null : resources[0];
    }

    /** Every sample person by the key the generator gave them. */
    public Map<String, Id> samplePeopleByKey() {
        Map<String, Id> byKey = new Map<String, Id>();
        for (Contact person : [
            SELECT Id, Sample_Data_Key__c
            FROM Contact
            WHERE Sample_Data__c = TRUE AND Sample_Data_Key__c != NULL
            WITH USER_MODE
        ]) {
            byKey.put(person.Sample_Data_Key__c, person.Id);
        }
        return byKey;
    }

    /** Every sample household and organization by the key the generator gave them. */
    public Map<String, Id> sampleAccountsByKey() {
        Map<String, Id> byKey = new Map<String, Id>();
        for (Account account : [
            SELECT Id, Sample_Data_Key__c
            FROM Account
            WHERE Sample_Data__c = TRUE AND Sample_Data_Key__c != NULL
            WITH USER_MODE
        ]) {
            byKey.put(account.Sample_Data_Key__c, account.Id);
        }
        return byKey;
    }

    /**
     * The sample gifts carrying these external ids, so a negative gift in a later chunk can
     * still find the gift it reverses.
     */
    public Map<String, Id> giftIdsByExternalId(Set<String> externalIds) {
        Map<String, Id> byExternalId = new Map<String, Id>();
        for (Gift__c gift : [
            SELECT Id, External_Id__c
            FROM Gift__c
            WHERE Sample_Data__c = TRUE AND External_Id__c IN :externalIds
            WITH USER_MODE
        ]) {
            byExternalId.put(gift.External_Id__c, gift.Id);
        }
        return byExternalId;
    }

    /**
     * The number of sample gifts, or 0 for someone who cannot read the field (only Giving Admin
     * grants it). The status card asks this of every Core administrator, and a query the user
     * cannot run threw, which failed the whole status read.
     */
    public Integer countSampleGifts() {
        if (
            !Schema.SObjectType.Gift__c.isAccessible() ||
            !Schema.SObjectType.Gift__c.fields.Sample_Data__c.isAccessible()
        ) {
            return 0;
        }
        return [SELECT COUNT() FROM Gift__c WHERE Sample_Data__c = TRUE WITH USER_MODE];
    }

    public List<Id> sampleGiftIds() {
        List<Id> ids = new List<Id>();
        for (Gift__c gift : [SELECT Id FROM Gift__c WHERE Sample_Data__c = TRUE WITH USER_MODE]) {
            ids.add(gift.Id);
        }
        return ids;
    }

    /**
     * The sample refunds and write-offs: the negative gifts that point back at an original. They
     * go before the rest, because a gift a reversal points at refuses to be deleted.
     */
    public List<Id> sampleReversalIds() {
        List<Id> ids = new List<Id>();
        for (Gift__c gift : [
            SELECT Id
            FROM Gift__c
            WHERE Sample_Data__c = TRUE AND Original_Gift__c != NULL
            WITH USER_MODE
        ]) {
            ids.add(gift.Id);
        }
        return ids;
    }

    public List<Id> sampleAskIds() {
        List<Id> ids = new List<Id>();
        for (Ask__c ask : [SELECT Id FROM Ask__c WHERE Sample_Data__c = TRUE WITH USER_MODE]) {
            ids.add(ask.Id);
        }
        return ids;
    }

    public List<Id> sampleCommitmentIds() {
        List<Id> ids = new List<Id>();
        for (Commitment__c commitment : [
            SELECT Id
            FROM Commitment__c
            WHERE Sample_Data__c = TRUE
            WITH USER_MODE
        ]) {
            ids.add(commitment.Id);
        }
        return ids;
    }

    public List<Id> sampleAppealIds() {
        List<Id> ids = new List<Id>();
        for (Appeal__c appeal : [
            SELECT Id
            FROM Appeal__c
            WHERE Sample_Data__c = TRUE
            WITH USER_MODE
        ]) {
            ids.add(appeal.Id);
        }
        return ids;
    }

    public List<Id> sampleFundIds() {
        List<Id> ids = new List<Id>();
        for (Fund__c fund : [SELECT Id FROM Fund__c WHERE Sample_Data__c = TRUE WITH USER_MODE]) {
            ids.add(fund.Id);
        }
        return ids;
    }
}
