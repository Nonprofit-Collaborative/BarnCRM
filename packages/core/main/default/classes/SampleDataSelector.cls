/**
 * All SOQL for the sample data loader (C-10). No other class in this feature issues a
 * query directly (plan Section 9.3).
 */
public with sharing class SampleDataSelector {
    /**
     * The batch class that runs every sample data load, Core's and each module's (a module's
     * stages run in Core's SampleDataStageBatch too), so one name covers the whole load.
     */
    private static final Set<String> LOAD_JOB_CLASS_NAMES = new Set<String>{
        'SampleDataStageBatch'
    };

    /** The batch class that runs every removal, Core's stages and each module's. */
    private static final Set<String> REMOVE_JOB_CLASS_NAMES = new Set<String>{
        'SampleDataRemoveBatch'
    };

    /** AsyncApexJob statuses that mean a job has not finished yet. */
    private static final Set<String> RUNNING_JOB_STATUSES = new Set<String>{
        'Queued',
        'Preparing',
        'Processing',
        'Holding'
    };

    /**
     * The SampleData static resource, or null when it has not been deployed. Callers use
     * the Body field's toString() to get the JSON text.
     */
    public StaticResource getSampleDataResource() {
        List<StaticResource> resources = [
            SELECT Body
            FROM StaticResource
            WHERE Name = 'SampleData'
            WITH USER_MODE
            LIMIT 1
        ];
        return resources.isEmpty() ? null : resources[0];
    }

    public Integer countSampleHouseholds() {
        return [
            SELECT COUNT()
            FROM Account
            WHERE Sample_Data__c = TRUE AND RecordType.DeveloperName = 'Household'
            WITH USER_MODE
        ];
    }

    public Integer countSampleOrganizations() {
        return [
            SELECT COUNT()
            FROM Account
            WHERE Sample_Data__c = TRUE AND RecordType.DeveloperName = 'Organization'
            WITH USER_MODE
        ];
    }

    public Integer countSampleContacts() {
        return [SELECT COUNT() FROM Contact WHERE Sample_Data__c = TRUE WITH USER_MODE];
    }

    public List<Id> getSampleAccountIds() {
        List<Id> ids = new List<Id>();
        for (Account acct : [SELECT Id FROM Account WHERE Sample_Data__c = TRUE WITH USER_MODE]) {
            ids.add(acct.Id);
        }
        return ids;
    }

    public List<Id> getSampleContactIds() {
        List<Id> ids = new List<Id>();
        for (Contact con : [SELECT Id FROM Contact WHERE Sample_Data__c = TRUE WITH USER_MODE]) {
            ids.add(con.Id);
        }
        return ids;
    }

    /**
     * How many sample connections there are, as the admin guide counts them: one for each
     * pair of people, not one for each side. The loader flags both sides of a connection it
     * made (the other side is built by the relationship automation), so a pair whose two sides
     * are both flagged is counted once, and a side standing alone still counts as one.
     */
    public Integer countSampleRelationships() {
        Integer sides = [
            SELECT COUNT()
            FROM Relationship__c
            WHERE Sample_Data__c = TRUE
            WITH USER_MODE
        ];
        Integer pairedSides = [
            SELECT COUNT()
            FROM Relationship__c
            WHERE Sample_Data__c = TRUE AND Reciprocal_Relationship__r.Sample_Data__c = TRUE
            WITH USER_MODE
        ];
        return sides - pairedSides / 2;
    }

    public Integer countSampleAffiliations() {
        return [SELECT COUNT() FROM Affiliation__c WHERE Sample_Data__c = TRUE WITH USER_MODE];
    }

    public List<Id> getSampleRelationshipIds() {
        List<Id> ids = new List<Id>();
        for (Relationship__c row : [
            SELECT Id
            FROM Relationship__c
            WHERE Sample_Data__c = TRUE
            WITH USER_MODE
        ]) {
            ids.add(row.Id);
        }
        return ids;
    }

    public List<Id> getSampleAffiliationIds() {
        List<Id> ids = new List<Id>();
        for (Affiliation__c row : [
            SELECT Id
            FROM Affiliation__c
            WHERE Sample_Data__c = TRUE
            WITH USER_MODE
        ]) {
            ids.add(row.Id);
        }
        return ids;
    }

    /**
     * The other side of each of these relationships, where the relationship automation built
     * it and it is not flagged as sample data yet.
     */
    public List<Id> getMirrorRelationshipIds(Set<Id> relationshipIds) {
        List<Id> ids = new List<Id>();
        for (Relationship__c row : [
            SELECT Id
            FROM Relationship__c
            WHERE Reciprocal_Relationship__c IN :relationshipIds AND Sample_Data__c = FALSE
            WITH USER_MODE
        ]) {
            ids.add(row.Id);
        }
        return ids;
    }

    /**
     * Every sample person by the key the generator gave them, which is how a module sample
     * set (Giving) and the connection stage find the person a record belongs to.
     */
    public Map<String, Id> getSampleContactIdsByKey() {
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

    /** Every sample household and organization by its generator key. */
    public Map<String, Id> getSampleAccountIdsByKey() {
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
     * True while any stage of the sample data load chain is still queued or running, so
     * the status card can keep polling instead of reporting a partial load as finished,
     * and load and remove can refuse to run against an in-flight chain.
     */
    public Boolean hasRunningLoadJob() {
        return hasRunningJob(LOAD_JOB_CLASS_NAMES);
    }

    /** True while the sample data removal's batch (SampleDataRemoveBatch) is queued or running. */
    public Boolean hasRunningRemoveJob() {
        return hasRunningJob(REMOVE_JOB_CLASS_NAMES);
    }

    private Boolean hasRunningJob(Set<String> classNames) {
        Set<String> runningStatuses = RUNNING_JOB_STATUSES;
        return ![
                SELECT Id
                FROM AsyncApexJob
                WHERE ApexClass.Name IN :classNames AND Status IN :runningStatuses
                WITH USER_MODE
                LIMIT 1
            ]
            .isEmpty();
    }
}
