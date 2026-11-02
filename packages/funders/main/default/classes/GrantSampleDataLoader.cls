/**
 * Builds and removes the Funders sample data set (C-10, canonical model 29ZH): three grants
 * flagged `Sample_Data__c` to Core's sample organizations, one at each point of the pipeline
 * (Prospect, Applied, Awarded), owned by the person loading them, and three requirements on the
 * award (29ZI). Every record is saved in user
 * mode through the grant rules, as an administrator's would be.
 *
 * Removal deletes the sample grants, one chunk per call; their requirements go with them.
 */
public with sharing class GrantSampleDataLoader {
    /** Records deleted per removeNext() call. Tests lower it. */
    @TestVisible
    private static Integer removeChunkSize = 200;

    // ------------------------------------------------------------------------- load

    /**
     * The three grants. Nothing when Core's sample organizations are not there, or when the
     * person loading has no Funders set yet (the access sync has not reached them), so one module
     * never breaks the whole load.
     */
    public static void loadGrants() {
        if (!Schema.SObjectType.Grant__c.isCreateable()) {
            return;
        }
        Id organizationType = AccountKinds.organizationRecordTypeId();
        List<Account> funders = [
            SELECT Id
            FROM Account
            WHERE Sample_Data__c = TRUE AND RecordTypeId = :organizationType
            WITH USER_MODE
            ORDER BY Name
            LIMIT 3
        ];
        if (funders.isEmpty()) {
            return;
        }
        Date today = Date.today();
        Grant__c prospect = grant(
            'Capacity Building Grant',
            funders[0].Id,
            GrantService.STAGE_PROSPECT,
            10000
        );
        prospect.Application_Deadline__c = today.addDays(30);
        prospect.Next_Step__c = 'Call the program officer about fit';

        Grant__c applied = grant(
            'Community Literacy Grant',
            funders[Math.mod(1, funders.size())].Id,
            GrantService.STAGE_APPLIED,
            25000
        );
        applied.Application_Deadline__c = today.addDays(-20);
        applied.Submitted_Date__c = today.addDays(-21);
        applied.Decision_Date__c = today.addDays(40);
        applied.Purpose__c = 'Reading support for 120 students in grades 3 to 5.';

        Grant__c awarded = grant(
            'Youth Programs Award',
            funders[Math.mod(2, funders.size())].Id,
            GrantService.STAGE_AWARDED,
            40000
        );
        awarded.Amount_Awarded__c = 35000;
        awarded.Application_Deadline__c = today.addDays(-120);
        awarded.Submitted_Date__c = today.addDays(-121);
        awarded.Decision_Date__c = today.addDays(-60);
        awarded.Award_Start_Date__c = today.addDays(-30);
        awarded.Award_End_Date__c = today.addDays(334);
        awarded.Purpose__c = 'General support for after-school programs for one year.';

        Database.insert(new List<Grant__c>{ prospect, applied, awarded }, AccessLevel.USER_MODE);
        loadRequirements(awarded.Id, today);
    }

    /**
     * F-02: what the award asks for, one requirement done, one coming due and one later. They go
     * with their grant when the sample data is removed.
     */
    private static void loadRequirements(Id grantId, Date today) {
        if (!Schema.SObjectType.Grant_Requirement__c.isCreateable()) {
            return;
        }
        Database.insert(
            new List<Grant_Requirement__c>{
                requirement(grantId, 'Site visit', 'Site Visit', today.addDays(-10), 'Accepted'),
                requirement(
                    grantId,
                    'Quarter 1 financial report',
                    'Financial Report',
                    today.addDays(10),
                    'In Progress'
                ),
                requirement(
                    grantId,
                    'Interim narrative report',
                    'Narrative Report',
                    today.addDays(75),
                    'Not Started'
                )
            },
            AccessLevel.USER_MODE
        );
    }

    private static Grant_Requirement__c requirement(
        Id grantId,
        String name,
        String type,
        Date due,
        String status
    ) {
        return new Grant_Requirement__c(
            Grant__c = grantId,
            Name = name,
            Type__c = type,
            Due_Date__c = due,
            Status__c = status
        );
    }

    // ------------------------------------------------------------------------- status card

    /** The sample grants in the org. */
    public static Integer countSampleGrants() {
        if (!Schema.SObjectType.Grant__c.isAccessible()) {
            return 0;
        }
        return [SELECT COUNT() FROM Grant__c WHERE Sample_Data__c = TRUE WITH USER_MODE];
    }

    // ------------------------------------------------------------------------- removal

    /** How many removeNext() calls clear every Funders sample record. */
    public static Integer removeStageCount() {
        return (countSampleGrants() + removeChunkSize - 1) / removeChunkSize;
    }

    /** Deletes the next chunk of sample grants and returns how many went, 0 once none are left. */
    public static Integer removeNext() {
        if (!Schema.SObjectType.Grant__c.isDeletable()) {
            return 0;
        }
        List<Grant__c> grants = [
            SELECT Id
            FROM Grant__c
            WHERE Sample_Data__c = TRUE
            WITH USER_MODE
            LIMIT :removeChunkSize
        ];
        if (!grants.isEmpty()) {
            Database.delete(grants, AccessLevel.USER_MODE);
        }
        return grants.size();
    }

    // ------------------------------------------------------------------------- helpers

    private static Grant__c grant(String name, Id funderId, String stage, Decimal requested) {
        return new Grant__c(
            Name = name,
            Funder__c = funderId,
            Stage__c = stage,
            Amount_Requested__c = requested,
            Sample_Data__c = true
        );
    }
}
